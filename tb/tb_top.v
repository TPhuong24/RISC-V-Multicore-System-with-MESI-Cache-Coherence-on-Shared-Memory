`timescale 1ns/1ps

module tb_top #(
    parameter NEGATIVE_SCOREBOARD_TEST = 0
);

    reg clk;
    reg rst_n;
    wire [31:0] out_core0_wb_data;
    wire [31:0] out_core1_wb_data;

    top_multicore dut (
        .clk(clk),
        .rst_n(rst_n),
        .out_core0_wb_data(out_core0_wb_data),
        .out_core1_wb_data(out_core1_wb_data)
    );

    initial begin
        clk = 0;
        forever #10 clk = ~clk;
    end

    initial begin
        $timeformat(-9, 2, " ns", 10);
        $display("\n=======================================================================================================");
        $display("   [COMPREHENSIVE REPORT] MULTI-CORE SYSTEM SIMULATION - MESI CACHE COHERENCE PROTOCOL");
        $display("=======================================================================================================");
        
        rst_n = 0;
        #45;       
        rst_n = 1; 
        
        $display("[%t] [SYSTEM] RESET RELEASED -> CORES START FETCHING INSTRUCTIONS.\n", $time);

        #20000;
        $display("\n[TIMEOUT] FAIL: system did not reach the program halt marker.");
        $display("[GOLDEN CHECKER] checks=%0d errors=%0d.", data_checks, checker_errors);
        $fatal(1, "integrated testbench timed out");
    end

    // =========================================================================
    // DECODER FUNCTIONS
    // =========================================================================
    function [255:0] decode_instr;
        input [31:0] instr;
        reg [6:0] opcode;
        begin
            opcode = instr[6:0];
            case (opcode)
                7'b0100011: decode_instr = "SW   (Store Word to Memory)";
                7'b0000011: decode_instr = "LW   (Load Word from Memory)";
                7'b1101111: decode_instr = "JAL  (Jump and Link - HALTING)";
                7'b0010011: decode_instr = "NOP  (ADDI x0, x0, 0)";
                default:    decode_instr = "UNKNOWN";
            endcase
        end
    endfunction

    function [127:0] mesi_decode;
        input [1:0] state;
        case(state)
            2'b00: mesi_decode = "INVALID (I)";
            2'b01: mesi_decode = "SHARED (S)";
            2'b10: mesi_decode = "EXCLUSIVE (E)";
            2'b11: mesi_decode = "MODIFIED (M)";
            default: mesi_decode = "UNKNOWN";
        endcase
    endfunction

    function [7:0] mesi_char;
        input [1:0] st;
        case(st)
            2'b00: mesi_char = "I";
            2'b01: mesi_char = "S";
            2'b10: mesi_char = "E";
            2'b11: mesi_char = "M";
            default: mesi_char = "?";
        endcase
    endfunction

    function [559:0] get_bus_cmd_str;
        input [2:0] cmd;
        case(cmd)
            3'b001: get_bus_cmd_str = "READ  (Read Miss -> Fetching from RAM)";
            3'b010: get_bus_cmd_str = "READX (Write Miss -> Fetching exclusive & Invalidating others)";
            3'b011: get_bus_cmd_str = "UPGR  (Write Hit -> Upgrading rights & Invalidating others)";
            3'b100: get_bus_cmd_str = "WRITE (Write-Back -> Evicting Dirty block to RAM)";
            default: get_bus_cmd_str ="NONE  (Bus Idle)";
        endcase
    endfunction

    function [799:0] get_tc_desc;
        input [2:0] cmd;
        input [1:0] other_state;
        begin
            if (cmd == 3'b001 && other_state == 2'b00) 
                get_tc_desc = "TEST CASE: READ MISS (I -> E) - Fetching data cleanly, No sharing.";
            else if (cmd == 3'b001 && other_state != 2'b00) 
                get_tc_desc = "TEST CASE: SNOOP READ (I -> S or M -> S) - Data is shared/flushed.";
            else if (cmd == 3'b010) 
                get_tc_desc = "TEST CASE: WRITE MISS (I -> M) - Snooping & Invalidating others.";
            else if (cmd == 3'b011) 
                get_tc_desc = "TEST CASE: WRITE UPGRADE (S -> M) - Upgrading from Shared to Modified.";
            else if (cmd == 3'b100)
                get_tc_desc = "TEST CASE: CONFLICT MISS & EVICTION - Writing dirty block back to RAM.";
            else 
                get_tc_desc = "TEST CASE: UNKNOWN BUS ACTION.";
        end
    endfunction

    // =========================================================================
    // HARDWARE WIRES & LOGIC
    // =========================================================================
    wire [31:0] c0_instr = dut.core_0.dp.Instr;
    wire [31:0] c0_pc    = dut.core_0.dp.PC;
    wire [31:0] c1_instr = dut.core_1.dp.Instr;
    wire [31:0] c1_pc    = dut.core_1.dp.PC;

    reg [31:0] c0_mem_instr, c0_mem_pc;
    reg [31:0] c1_mem_instr, c1_mem_pc;

    wire [3:0] c0_state = dut.cache_ctrl_0.state;
    wire [3:0] c1_state = dut.cache_ctrl_1.state;
    reg [3:0] prev_c0_state, prev_c1_state;

    reg prev_c0_grant, prev_c1_grant;
    wire c0_grant_edge = dut.bus_arb.c0_bus_grant & ~prev_c0_grant; 
    wire c1_grant_edge = dut.bus_arb.c1_bus_grant & ~prev_c1_grant;
    wire c0_grant_fall = ~dut.bus_arb.c0_bus_grant & prev_c0_grant; 
    wire c1_grant_fall = ~dut.bus_arb.c1_bus_grant & prev_c1_grant;

    reg [7:0]  c0_exp_char, c1_exp_char;
    reg [31:0] checked_addr;
    reg [799:0] verdict; 
    reg bus_mesi_pass;
    reg check_c0_pending, check_c1_pending;
    integer tc_counter = 1;
    reg [31:0] golden [0:1023];
    integer golden_init_idx;
    integer cache_set_idx;
    integer data_checks;
    integer checker_errors;
    reg negative_injected;
    reg [5:0] tc_pass_mask;
    reg tc2_commit_pending;
    reg tc4_commit_pending;
    reg tc5_stimulus_checked;
    reg tc5_stimulus_ok;
    reg [31:0] tc5_req_pc, tc5_req_instr, tc5_req_addr;
    integer tc5_load_completions;
    reg [2:0] c0_pending_cmd;
    reg [2:0] c1_pending_cmd;
    reg [31:0] c0_pending_addr;
    reg [31:0] c1_pending_addr;
    reg [3:0] tc3_flush_mask;
    reg [3:0] tc6_evict_mask;
    integer tc1_bus_count;
    integer tc3_bus_count;
    integer tc4_bus_count;
    integer tc6_bus_count;

    task mark_tc;
        input integer tc_id;
        input [799:0] description;
        begin
            if (tc_pass_mask[tc_id-1] !== 1'b1) begin
                tc_pass_mask[tc_id-1] = 1'b1;
                $display("[TC%0d] PASS: %0s", tc_id, description);
            end else begin
                checker_errors = checker_errors + 1;
                $display("[TC%0d] FAIL: duplicate completion marker", tc_id);
            end
        end
    endtask

    task check_ram_line_zero;
        input integer tc_id;
        begin
            if (dut.shared_mem.main_ram[0] !== golden[0] ||
                dut.shared_mem.main_ram[1] !== golden[1] ||
                dut.shared_mem.main_ram[2] !== golden[2] ||
                dut.shared_mem.main_ram[3] !== golden[3]) begin
                checker_errors = checker_errors + 1;
                $display("[TC%0d] FAIL RAM line 0 expected=%08h,%08h,%08h,%08h actual=%08h,%08h,%08h,%08h",
                         tc_id, golden[0], golden[1], golden[2], golden[3],
                         dut.shared_mem.main_ram[0], dut.shared_mem.main_ram[1],
                         dut.shared_mem.main_ram[2], dut.shared_mem.main_ram[3]);
            end
        end
    endtask

    // Cache index is address[5:4]; address[3:2] selects a word inside a block.
    wire [1:0] c0_actual_mesi = dut.cache_array_0.mesi_array[checked_addr[5:4]];
    wire [1:0] c1_actual_mesi = dut.cache_array_1.mesi_array[checked_addr[5:4]];

    // Tinh chỉnh lại thông báo Ghi RAM (Áp dụng chung cho Flush và Write-Back)
    reg prev_mem_wen;
    always @(posedge clk) begin
        if (!rst_n) begin
            prev_mem_wen <= 0;
        end else begin
            prev_mem_wen <= dut.bus_arb.mem_wen;
            if (dut.bus_arb.mem_wen && !prev_mem_wen) begin
                $display("-------------------------------------------------------------------------------------------------------");
                $display("[MEMORY WRITE DETECTED: SNOOP FLUSH / EVICTION] TIME: %t", $time);
                $display("-> Source Target   : Set %0d of Core Cache contains MODIFIED (Dirty) data.", dut.bus_arb.mem_addr[5:4]);
                $display("-> RAM Destination : Writing dirty data to RAM address 0x%08h.", dut.bus_arb.mem_addr);
                $display("-> Status          : Memory synchronized successfully.");
                $display("---------------------------------------------------------------------------------------------------\n");
            end
        end
    end

    always @(posedge clk) begin
        if (!rst_n) begin
            prev_c0_grant <= 0; prev_c1_grant <= 0;
            check_c0_pending <= 0; check_c1_pending <= 0;
            prev_c0_state <= 0; prev_c1_state <= 0;
            c0_mem_instr <= 32'h00000013; c0_mem_pc <= 0; 
            c1_mem_instr <= 32'h00000013; c1_mem_pc <= 0; 
            tc_counter <= 1;
            data_checks <= 0;
            checker_errors <= 0;
            negative_injected <= 1'b0;
            tc_pass_mask = 6'b0;
            tc2_commit_pending = 1'b0;
            tc4_commit_pending = 1'b0;
            tc5_stimulus_checked = 1'b0;
            tc5_stimulus_ok = 1'b0;
            tc5_req_pc = 32'b0;
            tc5_req_instr = 32'b0;
            tc5_req_addr = 32'b0;
            tc5_load_completions = 0;
            c0_pending_cmd = 3'b000;
            c1_pending_cmd = 3'b000;
            c0_pending_addr = 32'b0;
            c1_pending_addr = 32'b0;
            tc3_flush_mask = 4'b0;
            tc6_evict_mask = 4'b0;
            tc1_bus_count = 0;
            tc3_bus_count = 0;
            tc4_bus_count = 0;
            tc6_bus_count = 0;
            for (golden_init_idx = 0; golden_init_idx < 1024; golden_init_idx = golden_init_idx + 1)
                golden[golden_init_idx] = 32'b0;
        end else begin
            if (c0_instr == 32'h0000006f && c1_instr == 32'h0000006f && !check_c0_pending && !check_c1_pending) begin
                $display("\n=======================================================================================================");
                $display("   [END OF SIMULATION] CA 2 CORE DA HOAN THANH CHUONG TRINH VA VAO TRANG THAI HALT.");
                if (NEGATIVE_SCOREBOARD_TEST && !negative_injected) begin
                    $display("[NEGATIVE TEST] FAIL: no eligible store was found for expectation perturbation.");
                    $fatal(1, "negative scoreboard injection was not reached");
                end
                if (!NEGATIVE_SCOREBOARD_TEST && (tc_pass_mask !== 6'b111111)) begin
                    $display("[TC COVERAGE] FAIL: completed mask=%06b expected=111111", tc_pass_mask);
                    if (!tc_pass_mask[4])
                        $display("[TC5] FAIL missing required load: expected PC=00000024 Instr=01002083 EA=00000010 data=00000000; actual stimulus_seen=%b ok=%b PC=%08h Instr=%08h EA=%08h last_data=%08h cache_state=%0d saved_EA=%08h MESI(set1)=%b/%b completions=%0d",
                                 tc5_stimulus_checked, tc5_stimulus_ok,
                                 tc5_req_pc, tc5_req_instr, tc5_req_addr,
                                 dut.c0_cpu_rdata, c0_state, dut.cache_ctrl_0.saved_addr,
                                 dut.cache_array_0.mesi_array[1], dut.cache_array_1.mesi_array[1],
                                 tc5_load_completions);
                    $fatal(1, "TB_TOP did not complete every TC1-TC6 check");
                end
                if ((data_checks > 0) && (checker_errors == 0))
                    $display("[GOLDEN CHECKER] PASS: %0d load completions checked; no data/coherence/X errors; TC1-TC6 mask=%06b.", data_checks, tc_pass_mask);
                else begin
                    $display("[GOLDEN CHECKER] FAIL: checks=%0d errors=%0d.", data_checks, checker_errors);
                    $fatal(1, "G0.5 golden checker did not pass");
                end
                $display("=======================================================================================================");
                $finish;
            end

            // Complete delayed architectural store checks after the cache's
            // nonblocking array write has taken effect.
            if (tc2_commit_pending) begin
                if ((dut.cache_array_0.data_array[0][0] !== 32'h00000000) ||
                    (dut.cache_array_0.mesi_array[0] !== 2'b11)) begin
                    checker_errors = checker_errors + 1;
                    $display("[TC2] FAIL E-to-M store expected addr=00000000 data=00000000 state=M; actual data=%08h state=%b",
                             dut.cache_array_0.data_array[0][0], dut.cache_array_0.mesi_array[0]);
                end else begin
                    mark_tc(2, "C0 store hit in E committed fixed data 00000000 and transitioned to M without a bus request.");
                end
                tc2_commit_pending = 1'b0;
            end
            // Count each committed word of the M-to-S snoop flush and dirty
            // eviction. mem_ready is low on the one side-effect cycle.
            if (c0_state == 4'd11 && dut.c0_mem_wen && !dut.shared_mem.mem_ready &&
                dut.cache_ctrl_0.latched_snoop_addr[31:4] == 28'h0) begin
                cache_set_idx = dut.cache_ctrl_0.flush_cnt;
                if (dut.c0_mem_addr !== (cache_set_idx * 4) ||
                    dut.c0_mem_wdata !== golden[cache_set_idx]) begin
                    checker_errors = checker_errors + 1;
                    $display("[TC3] FAIL flush word=%0d expected addr=%08h data=%08h actual addr=%08h data=%08h",
                             cache_set_idx, cache_set_idx * 4, golden[cache_set_idx],
                             dut.c0_mem_addr, dut.c0_mem_wdata);
                end
                if (tc3_flush_mask[cache_set_idx]) begin
                    checker_errors = checker_errors + 1;
                    $display("[TC3] FAIL duplicate snoop-flush word=%0d", cache_set_idx);
                end
                tc3_flush_mask[cache_set_idx] = 1'b1;
            end
            if (c0_state == 4'd10 && dut.c0_mem_wen && !dut.shared_mem.mem_ready &&
                dut.c0_mem_addr[31:4] == 28'h0) begin
                cache_set_idx = dut.cache_ctrl_0.evict_cnt;
                if (dut.c0_mem_addr !== (cache_set_idx * 4) ||
                    dut.c0_mem_wdata !== golden[cache_set_idx]) begin
                    checker_errors = checker_errors + 1;
                    $display("[TC6] FAIL eviction word=%0d expected addr=%08h data=%08h actual addr=%08h data=%08h",
                             cache_set_idx, cache_set_idx * 4, golden[cache_set_idx],
                             dut.c0_mem_addr, dut.c0_mem_wdata);
                end
                if (tc6_evict_mask[cache_set_idx]) begin
                    checker_errors = checker_errors + 1;
                    $display("[TC6] FAIL duplicate eviction word=%0d", cache_set_idx);
                end
                tc6_evict_mask[cache_set_idx] = 1'b1;
            end

            // Commit each architectural store once, at the cache-array write
            // enable in S_HIT, granted S_UPGR_ARBWAIT, or S_FILL_DONE.
            if ((c0_state == 4'd2 ||
                 (c0_state == 4'd3 && dut.c0_bus_grant) ||
                 c0_state == 4'd6) && dut.cache_ctrl_0.saved_wen && dut.c0_ctrl_we)
                golden[dut.cache_ctrl_0.saved_addr[11:2]] = dut.cache_ctrl_0.saved_wdata;
            if ((c1_state == 4'd2 ||
                 (c1_state == 4'd3 && dut.c1_bus_grant) ||
                 c1_state == 4'd6) && dut.cache_ctrl_1.saved_wen && dut.c1_ctrl_we)
                golden[dut.cache_ctrl_1.saved_addr[11:2]] = dut.cache_ctrl_1.saved_wdata;

            if (dut.cache_ctrl_0.state == 4'd2 && dut.cache_ctrl_0.saved_wen &&
                dut.cache_ctrl_0.saved_addr == 32'h0 && dut.c0_ctrl_we && !tc_pass_mask[1]) begin
                if ((dut.cache_ctrl_0.saved_wdata !== 32'h0) || (dut.c0_bus_cmd !== 3'b000) ||
                    (dut.cache_array_0.mesi_array[0] !== 2'b10)) begin
                    checker_errors = checker_errors + 1;
                    $display("[TC2] FAIL expected E-to-M silent store addr=00000000 data=00000000; actual addr=%08h data=%08h cmd=%b MESI=%b",
                             dut.cache_ctrl_0.saved_addr, dut.cache_ctrl_0.saved_wdata,
                             dut.c0_bus_cmd, dut.cache_array_0.mesi_array[0]);
                end else tc2_commit_pending = 1'b1;
            end
            if (dut.cache_ctrl_0.state == 4'd3 && dut.c0_bus_grant && dut.c0_ctrl_we &&
                dut.cache_ctrl_0.saved_wen && dut.cache_ctrl_0.saved_addr == 32'h0 && !tc_pass_mask[3])
                tc4_commit_pending = 1'b1;

            // Verify that the ROM really presents TC5's intended load. The
            // original word at PC 0x24 is checked as an instruction/address
            // stimulus; it must not be inferred from a cache-state observation.
            if (!tc5_stimulus_checked && c0_pc == 32'h00000024) begin
                tc5_stimulus_checked = 1'b1;
                tc5_req_pc = c0_pc;
                tc5_req_instr = c0_instr;
                tc5_req_addr = dut.c0_cpu_addr;
                tc5_stimulus_ok = (c0_instr === 32'h01002083) &&
                                  (dut.c0_cpu_ren === 1'b1) &&
                                  (dut.c0_cpu_addr === 32'h00000010);
                if (!tc5_stimulus_ok) begin
                    checker_errors = checker_errors + 1;
                    $display("[TC5] FAIL stimulus expected PC=00000024 Instr=01002083 (LW x1,16(x0)) EA=00000010 read=1 data=00000000; actual PC=%08h Instr=%08h EA=%08h read=%b data=%08h cache_state=%0d MESI(actual set)=%b/%b X/Z=%b",
                             c0_pc, c0_instr, dut.c0_cpu_addr, dut.c0_cpu_ren, dut.c0_cpu_rdata,
                             c0_state,
                             dut.cache_array_0.mesi_array[dut.c0_cpu_addr[5:4]],
                             dut.cache_array_1.mesi_array[dut.c0_cpu_addr[5:4]],
                             ((^c0_pc === 1'bx) || (^c0_instr === 1'bx) ||
                              (^dut.c0_cpu_addr === 1'bx) || (dut.c0_cpu_ren === 1'bx)));
                end
            end

            // Deliberately corrupt one committed expectation only in the dedicated
            // negative run. The normal checker path and its comparisons are unchanged.
            if (NEGATIVE_SCOREBOARD_TEST && !negative_injected &&
                dut.cache_ctrl_0.saved_wen && dut.c0_ctrl_we &&
                (c0_state == 4'd2 ||
                 (c0_state == 4'd3 && dut.c0_bus_grant) ||
                 c0_state == 4'd6) &&
                dut.cache_ctrl_0.saved_addr[11:2] == 0) begin
                golden[0] = golden[0] ^ 32'h00000001;
                negative_injected = 1'b1;
                $display("[NEGATIVE TEST] INJECTED: golden[0] intentionally corrupted after store commit.");
            end

            // A load retires in S_DONE, after the cache has supplied its word.
            if (c0_state == 4'd8 && dut.c0_cpu_ren && !dut.cache_ctrl_0.saved_wen) begin
                data_checks = data_checks + 1;
                if (dut.c0_cpu_rdata !== golden[dut.cache_ctrl_0.saved_addr[11:2]]) begin
                    checker_errors = checker_errors + 1;
                    $display("[GOLDEN CHECKER] FAIL C0 addr=%08h expected=%08h actual=%08h",
                             dut.cache_ctrl_0.saved_addr, golden[dut.cache_ctrl_0.saved_addr[11:2]], dut.c0_cpu_rdata);
                end
                if (dut.cache_ctrl_0.saved_addr == 32'h0 && !tc_pass_mask[0]) begin
                    if ((dut.c0_cpu_rdata === golden[0]) &&
                        (dut.cache_array_0.mesi_array[0] === 2'b10) &&
                        (dut.cache_array_1.mesi_array[0] === 2'b00) && (tc1_bus_count == 1))
                        mark_tc(1, "C0 READ miss at 00000000 returned golden data with E/I ownership.");
                    else begin
                        checker_errors = checker_errors + 1;
                        $display("[TC1] FAIL load/ownership/bus-count addr=%08h data=%08h MESI=%b/%b READs=%0d",
                                 dut.cache_ctrl_0.saved_addr, dut.c0_cpu_rdata,
                                 dut.cache_array_0.mesi_array[0], dut.cache_array_1.mesi_array[0], tc1_bus_count);
                    end
                end
                if (dut.cache_ctrl_0.saved_addr == 32'h10) begin
                    tc5_load_completions = tc5_load_completions + 1;
                    $display("[TC5][LOAD_COMPLETE] PC=%08h Instr=%08h expected_EA=00000010 actual_saved_EA=%08h cpu_EA=%08h expected_data=00000000 actual_data=%08h state=%0d MESI=%b/%b",
                             c0_pc, c0_instr, dut.cache_ctrl_0.saved_addr,
                             dut.c0_cpu_addr, dut.c0_cpu_rdata, c0_state,
                             dut.cache_array_0.mesi_array[1], dut.cache_array_1.mesi_array[1]);
                    if (!tc_pass_mask[4] && tc5_stimulus_ok && (tc5_load_completions == 1) &&
                        (dut.cache_ctrl_0.saved_addr === 32'h10) &&
                        (dut.c0_cpu_rdata === 32'h00000000) &&
                        (dut.c0_cpu_rdata === golden[4]))
                        mark_tc(5, "C0 load at 00000010 matched the independent zero-initialized golden word.");
                    else begin
                        checker_errors = checker_errors + 1;
                        $display("[TC5] FAIL completion expected PC=00000024 Instr=01002083 EA=00000010 data=00000000 count=1; actual PC=%08h Instr=%08h saved_EA=%08h cpu_EA=%08h data=%08h count=%0d state=%0d MESI=%b/%b",
                                 c0_pc, c0_instr, dut.cache_ctrl_0.saved_addr,
                                 dut.c0_cpu_addr, dut.c0_cpu_rdata,
                                 tc5_load_completions, c0_state,
                                 dut.cache_array_0.mesi_array[1], dut.cache_array_1.mesi_array[1]);
                    end
                end
                if (dut.cache_ctrl_0.saved_addr == 32'h40 && !tc_pass_mask[5]) begin
                    check_ram_line_zero(6);
                if ((dut.c0_cpu_rdata === golden[16]) && (tc6_evict_mask === 4'b1111) &&
                        (dut.cache_array_0.mesi_array[0] === 2'b10) &&
                        (dut.cache_array_1.mesi_array[0] === 2'b00) && (tc6_bus_count == 1) &&
                    (tc6_evict_mask === 4'b1111) &&
                    (dut.shared_mem.main_ram[0] === golden[0]) &&
                    (dut.shared_mem.main_ram[1] === golden[1]) &&
                    (dut.shared_mem.main_ram[2] === golden[2]) &&
                    (dut.shared_mem.main_ram[3] === golden[3]))
                        mark_tc(6, "Dirty conflict eviction wrote all four fixed-expected words to RAM before the new line load completed.");
                    else begin
                        checker_errors = checker_errors + 1;
                        $display("[TC6] FAIL conflict/load data=%08h mask=%b MESI=%b/%b WB_count=%0d",
                                 dut.c0_cpu_rdata, tc6_evict_mask,
                                 dut.cache_array_0.mesi_array[0], dut.cache_array_1.mesi_array[0], tc6_bus_count);
                    end
                end
            end
            if (c1_state == 4'd8 && dut.c1_cpu_ren && !dut.cache_ctrl_1.saved_wen) begin
                data_checks = data_checks + 1;
                if (dut.c1_cpu_rdata !== golden[dut.cache_ctrl_1.saved_addr[11:2]]) begin
                    checker_errors = checker_errors + 1;
                    $display("[GOLDEN CHECKER] FAIL C1 addr=%08h expected=%08h actual=%08h",
                             dut.cache_ctrl_1.saved_addr, golden[dut.cache_ctrl_1.saved_addr[11:2]], dut.c1_cpu_rdata);
                end
                if (dut.cache_ctrl_1.saved_addr == 32'h0 && !tc_pass_mask[2]) begin
                    check_ram_line_zero(3);
                    if ((dut.c1_cpu_rdata === golden[0]) && (tc3_bus_count == 1) &&
                        (tc3_flush_mask === 4'b1111) &&
                        (dut.cache_array_0.mesi_array[0] === 2'b01) &&
                        (dut.cache_array_1.mesi_array[0] === 2'b01) &&
                        (dut.shared_mem.main_ram[0] === golden[0]) &&
                        (dut.shared_mem.main_ram[1] === golden[1]) &&
                        (dut.shared_mem.main_ram[2] === golden[2]) &&
                        (dut.shared_mem.main_ram[3] === golden[3]))
                        mark_tc(3, "C1 READ of C0's M line returned golden data; all four words flushed and both copies ended Shared.");
                    else begin
                        checker_errors = checker_errors + 1;
                        $display("[TC3] FAIL snoop-read data=%08h flush_mask=%b MESI=%b/%b READ_count=%0d",
                                 dut.c1_cpu_rdata, tc3_flush_mask,
                                 dut.cache_array_0.mesi_array[0], dut.cache_array_1.mesi_array[0], tc3_bus_count);
                    end
                end
            end

            // Check the MESI invariant and returned-data knownness every cycle.
            for (cache_set_idx = 0; cache_set_idx < 4; cache_set_idx = cache_set_idx + 1) begin
                if ((dut.cache_array_0.mesi_array[cache_set_idx] == 2'b11) &&
                    (dut.cache_array_1.mesi_array[cache_set_idx] == 2'b11) &&
                    (dut.cache_array_0.tag_array[cache_set_idx] == dut.cache_array_1.tag_array[cache_set_idx])) begin
                    checker_errors = checker_errors + 1;
                    $display("[COHERENCE CHECKER] FAIL: both caches hold M for set %0d tag %08h",
                             cache_set_idx, dut.cache_array_0.tag_array[cache_set_idx]);
                end
            end
            if (!dut.c0_cpu_stall && ((^dut.c0_cpu_rdata) === 1'bx)) begin
                checker_errors = checker_errors + 1;
                $display("[X CHECKER] FAIL: Core 0 returned X while unstalled at %t", $time);
            end
            if (!dut.c1_cpu_stall && ((^dut.c1_cpu_rdata) === 1'bx)) begin
                checker_errors = checker_errors + 1;
                $display("[X CHECKER] FAIL: Core 1 returned X while unstalled at %t", $time);
            end

            prev_c0_grant <= dut.bus_arb.c0_bus_grant;
            prev_c1_grant <= dut.bus_arb.c1_bus_grant;
            prev_c0_state <= c0_state;
            prev_c1_state <= c1_state;

            if (c0_instr[6:0] == 7'b0000011 || c0_instr[6:0] == 7'b0100011) begin
                c0_mem_instr <= c0_instr; c0_mem_pc <= c0_pc;
            end
            if (c1_instr[6:0] == 7'b0000011 || c1_instr[6:0] == 7'b0100011) begin
                c1_mem_instr <= c1_instr; c1_mem_pc <= c1_pc;
            end

            // =========================================================================
            // 1. MONITOR CACHE HITS (observation only; entry is not a PASS)
            // =========================================================================
            if (c0_state == 4'd2 && prev_c0_state != 4'd2) begin
                 $display("-------------------------------------------------------------------------------------------------------");
                 $display("[OBS %0d: CACHE HIT / SILENT TRANSITION] CORE 0 INTERNAL ACTION (TIME: %t)", tc_counter, $time);
                 $display("-> Description     : TEST CASE: WRITE/READ HIT (E->M or M->M) - Executed silently without Bus.");
                 $display("-> Executing Instr : %0s (PC = 0x%08h)", decode_instr(c0_mem_instr), c0_mem_pc);
                 $display("-> Core 0 MESI     : Updated / Kept securely in cache controller.");
                 $display("-> Observation     : entered S_HIT; architectural data is checked at load completion.");
                 $display("-------------------------------------------------------------------------------------------------------\n");
                 tc_counter <= tc_counter + 1;
            end

            if (c1_state == 4'd2 && prev_c1_state != 4'd2) begin
                 $display("-------------------------------------------------------------------------------------------------------");
                 $display("[OBS %0d: CACHE HIT / SILENT TRANSITION] CORE 1 INTERNAL ACTION (TIME: %t)", tc_counter, $time);
                 $display("-> Description     : TEST CASE: WRITE/READ HIT (E->M or M->M) - Executed silently without Bus.");
                 $display("-> Executing Instr : %0s (PC = 0x%08h)", decode_instr(c1_mem_instr), c1_mem_pc);
                 $display("-> Core 1 MESI     : Updated / Kept securely in cache controller.");
                 $display("-> Observation     : entered S_HIT; architectural data is checked at load completion.");
                 $display("-------------------------------------------------------------------------------------------------------\n");
                 tc_counter <= tc_counter + 1;
            end

            // =========================================================================
            // 2. MONITOR CORE 0 BUS TRANSACTIONS
            // =========================================================================
            if (c0_grant_edge && dut.bus_arb.c0_bus_cmd != 3'b000) begin
                c0_pending_cmd = dut.bus_arb.c0_bus_cmd;
                c0_pending_addr = dut.bus_arb.c0_bus_addr;
                if (dut.bus_arb.c0_bus_cmd == 3'b001 && dut.bus_arb.c0_bus_addr == 32'h0)
                    tc1_bus_count = tc1_bus_count + 1;
                if (dut.bus_arb.c0_bus_cmd == 3'b011 && dut.bus_arb.c0_bus_addr == 32'h0)
                    tc4_bus_count = tc4_bus_count + 1;
                if (dut.bus_arb.c0_bus_cmd == 3'b100 && dut.bus_arb.c0_bus_addr == 32'h0)
                    tc6_bus_count = tc6_bus_count + 1;
                checked_addr = dut.bus_arb.c0_bus_addr;
                case (dut.bus_arb.c0_bus_cmd)
                    3'b001: begin 
                        if (dut.cache_ctrl_1.ctrl_mesi_out == 2'b00) begin 
                            c0_exp_char = "E"; c1_exp_char = "I"; 
                        end else begin                  
                            c0_exp_char = "S"; c1_exp_char = "S"; 
                        end
                    end
                    3'b010: begin c0_exp_char = "M"; c1_exp_char = "I"; end
                    3'b011: begin c0_exp_char = "M"; c1_exp_char = "I"; end
                    3'b100: begin c0_exp_char = "E"; c1_exp_char = "I"; end // <--- ĐÃ SỬA THÀNH KỲ VỌNG [E] | [I] CHUẨN XÁC
                    default: begin c0_exp_char = "I"; c1_exp_char = "I"; end
                endcase
                check_c0_pending <= 1;

                $display("=======================================================================================================");
                $display("[OBS %0d: BUS TRANSACTION START] REQUESTING: CORE 0 | TIME: %t", tc_counter, $time);
                $display("-> Description     : %0s", get_tc_desc(dut.bus_arb.c0_bus_cmd, dut.cache_ctrl_1.ctrl_mesi_out));
                $display("-> Executing Instr : %0s (PC = 0x%08h)", decode_instr(c0_mem_instr), c0_mem_pc);
                $display("-> Target Address  : 0x%08h", checked_addr);
                $display("-> Issued Bus Cmd  : %0s", get_bus_cmd_str(dut.bus_arb.c0_bus_cmd));
                $display("-> Current MESI    : Core 0 = %0s | Core 1 = %0s", mesi_decode(dut.cache_ctrl_0.ctrl_mesi_out), mesi_decode(dut.cache_ctrl_1.ctrl_mesi_out));
                $display("-> Expected MESI   : Core 0 -> [%0s] | Core 1 -> [%0s]", c0_exp_char, c1_exp_char);
            end

            if (c0_grant_fall && check_c0_pending) begin
                // Áp dụng luật kiểm tra cứng cho toàn bộ các lệnh Bus (Đã bỏ ngoại lệ Eviction)
                if (((c0_exp_char == "E" && c0_actual_mesi == 2'b10) ||
                     (c0_exp_char == "M" && c0_actual_mesi == 2'b11) ||
                     (c0_exp_char == "S" && c0_actual_mesi == 2'b01) ||
                     (c0_exp_char == "I" && c0_actual_mesi == 2'b00)) 
                    && 
                    ((c1_exp_char == "E" && c1_actual_mesi == 2'b10) ||
                     (c1_exp_char == "M" && c1_actual_mesi == 2'b11) ||
                     (c1_exp_char == "S" && c1_actual_mesi == 2'b01) ||
                     (c1_exp_char == "I" && c1_actual_mesi == 2'b00))) begin
                    verdict = "PASS - MESI hardware FSM logic is PERFECT!";
                    bus_mesi_pass = 1'b1;
                end else begin
                    verdict = "FAIL - Hardware logic error detected!";
                    bus_mesi_pass = 1'b0;
                end

                $display(".......................................................................................................");
                $display("[OBS %0d: BUS TRANSACTION END] TIME: %t", tc_counter, $time);
                $display("-> Actual MESI     : Core 0 = [%0s] | Core 1 = [%0s]", mesi_char(c0_actual_mesi), mesi_char(c1_actual_mesi));
                $display("-> FINAL VERDICT   : %0s", verdict);
                if (bus_mesi_pass !== 1'b1) begin
                    checker_errors = checker_errors + 1;
                    $display("[TC BUS] FAIL: owner Core 0 command=%b addr=%08h expected MESI=%0s/%0s actual=%0s/%0s",
                             c0_pending_cmd, c0_pending_addr, c0_exp_char, c1_exp_char,
                             mesi_char(c0_actual_mesi), mesi_char(c1_actual_mesi));
                end
                if (c0_pending_cmd == 3'b011 && c0_pending_addr == 32'h0 && tc4_commit_pending) begin
                    if ((dut.cache_array_0.data_array[0][0] === 32'h00000000) &&
                        (dut.cache_array_0.mesi_array[0] === 2'b11) &&
                        (dut.cache_array_1.mesi_array[0] === 2'b00) &&
                        (tc4_bus_count == 1) && (bus_mesi_pass === 1'b1)) begin
                        mark_tc(4, "C0 Shared-to-Modified upgrade completed with data 00000000 and C1 invalidated.");
                    end else begin
                        checker_errors = checker_errors + 1;
                        $display("[TC4] FAIL upgrade completion expected cmd=UPGR addr=00000000 data=00000000 MESI=M/I bus_count=1; actual cmd=%b addr=%08h data=%08h MESI=%b/%b bus_count=%0d bus_mesi_pass=%b time=%t",
                                 c0_pending_cmd, c0_pending_addr,
                                 dut.cache_array_0.data_array[0][0],
                                 dut.cache_array_0.mesi_array[0], dut.cache_array_1.mesi_array[0],
                                 tc4_bus_count, bus_mesi_pass, $time);
                    end
                    tc4_commit_pending = 1'b0;
                end
                $display("=======================================================================================================\n");
                check_c0_pending <= 0; tc_counter <= tc_counter + 1;
            end

            // =========================================================================
            // 3. MONITOR CORE 1 BUS TRANSACTIONS
            // =========================================================================
            if (c1_grant_edge && dut.bus_arb.c1_bus_cmd != 3'b000) begin
                c1_pending_cmd = dut.bus_arb.c1_bus_cmd;
                c1_pending_addr = dut.bus_arb.c1_bus_addr;
                if (dut.bus_arb.c1_bus_cmd == 3'b001 && dut.bus_arb.c1_bus_addr == 32'h0)
                    tc3_bus_count = tc3_bus_count + 1;
                checked_addr = dut.bus_arb.c1_bus_addr;
                case (dut.bus_arb.c1_bus_cmd)
                    3'b001: begin
                        if (dut.cache_ctrl_0.ctrl_mesi_out == 2'b00) begin
                            c0_exp_char = "I"; c1_exp_char = "E";
                        end else begin
                            c0_exp_char = "S"; c1_exp_char = "S";
                        end
                    end
                    3'b010: begin c0_exp_char = "I"; c1_exp_char = "M"; end
                    3'b011: begin c0_exp_char = "I"; c1_exp_char = "M"; end
                    3'b100: begin c0_exp_char = "I"; c1_exp_char = "E"; end // <--- ĐÃ SỬA THÀNH KỲ VỌNG [I] | [E] CHUẨN XÁC
                    default: begin c0_exp_char = "I"; c1_exp_char = "I"; end
                endcase
                check_c1_pending <= 1;

                $display("=======================================================================================================");
                $display("[OBS %0d: BUS TRANSACTION START] REQUESTING: CORE 1 | TIME: %t", tc_counter, $time);
                $display("-> Description     : %0s", get_tc_desc(dut.bus_arb.c1_bus_cmd, dut.cache_ctrl_0.ctrl_mesi_out));
                $display("-> Executing Instr : %0s (PC = 0x%08h)", decode_instr(c1_mem_instr), c1_mem_pc);
                $display("-> Target Address  : 0x%08h", checked_addr);
                $display("-> Issued Bus Cmd  : %0s", get_bus_cmd_str(dut.bus_arb.c1_bus_cmd));
                $display("-> Current MESI    : Core 0 = %0s | Core 1 = %0s", mesi_decode(dut.cache_ctrl_0.ctrl_mesi_out), mesi_decode(dut.cache_ctrl_1.ctrl_mesi_out));
                $display("-> Expected MESI   : Core 0 -> [%0s] | Core 1 -> [%0s]", c0_exp_char, c1_exp_char);
            end

            if (c1_grant_fall && check_c1_pending) begin
                if (((c1_exp_char == "E" && c1_actual_mesi == 2'b10) ||
                     (c1_exp_char == "M" && c1_actual_mesi == 2'b11) ||
                     (c1_exp_char == "S" && c1_actual_mesi == 2'b01) ||
                     (c1_exp_char == "I" && c1_actual_mesi == 2'b00))
                    &&
                    ((c0_exp_char == "E" && c0_actual_mesi == 2'b10) ||
                     (c0_exp_char == "M" && c0_actual_mesi == 2'b11) ||
                     (c0_exp_char == "S" && c0_actual_mesi == 2'b01) ||
                     (c0_exp_char == "I" && c0_actual_mesi == 2'b00))) begin
                    verdict = "PASS - MESI hardware FSM logic is PERFECT!";
                    bus_mesi_pass = 1'b1;
                end else begin
                    verdict = "FAIL - Hardware logic error detected!";
                    bus_mesi_pass = 1'b0;
                end

                $display(".......................................................................................................");
                $display("[OBS %0d: BUS TRANSACTION END] TIME: %t", tc_counter, $time);
                $display("-> Actual MESI     : Core 0 = [%0s] | Core 1 = [%0s]", mesi_char(c0_actual_mesi), mesi_char(c1_actual_mesi));
                $display("-> FINAL VERDICT   : %0s", verdict);
                if (bus_mesi_pass !== 1'b1) begin
                    checker_errors = checker_errors + 1;
                    $display("[TC BUS] FAIL: owner Core 1 command=%b addr=%08h expected MESI=%0s/%0s actual=%0s/%0s",
                             c1_pending_cmd, c1_pending_addr, c0_exp_char, c1_exp_char,
                             mesi_char(c0_actual_mesi), mesi_char(c1_actual_mesi));
                end
                $display("=======================================================================================================\n");
                check_c1_pending <= 0; tc_counter <= tc_counter + 1;
            end
        end
    end
endmodule
