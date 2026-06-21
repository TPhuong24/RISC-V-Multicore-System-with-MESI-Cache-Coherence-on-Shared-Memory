`timescale 1ns/1ps

module tb_top;

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
        $display("\n[TIMEOUT] Mo phong ket thuc do het thoi gian.");
        $stop;
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
    
    reg check_c0_pending, check_c1_pending;
    reg check_c0_hit_pending, check_c1_hit_pending;
    
    reg [1:0] c0_hit_curr, c1_hit_curr;
    reg [1:0] c0_hit_exp, c1_hit_exp;

    integer tc_counter = 1;

    wire [1:0] c0_actual_mesi = dut.cache_array_0.mesi_array[checked_addr[5:4]]; 
    wire [1:0] c1_actual_mesi = dut.cache_array_1.mesi_array[checked_addr[5:4]];

    // Tín hiệu bắt TRỰC TIẾP dữ liệu lưu bên trong mảng RAM của CACHE
    wire [31:0] c0_cache_data = dut.cache_array_0.data_array[checked_addr[5:4]][checked_addr[3:2]];
    wire [31:0] c1_cache_data = dut.cache_array_1.data_array[checked_addr[5:4]][checked_addr[3:2]];

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
                $display("-> Flushed Data    : 0x%08h", dut.bus_arb.mem_wdata);
                $display("-> Status          : Memory synchronized successfully.");
                $display("---------------------------------------------------------------------------------------------------\n");
            end
        end
    end

    always @(posedge clk) begin
        if (!rst_n) begin
            prev_c0_grant <= 0; prev_c1_grant <= 0;
            check_c0_pending <= 0; check_c1_pending <= 0;
            check_c0_hit_pending <= 0; check_c1_hit_pending <= 0;
            prev_c0_state <= 0; prev_c1_state <= 0;
            c0_mem_instr <= 32'h00000013; c0_mem_pc <= 0; 
            c1_mem_instr <= 32'h00000013; c1_mem_pc <= 0; 
            tc_counter <= 1;
        end else begin
            if (c0_instr == 32'h0000006f && c1_instr == 32'h0000006f && !check_c0_pending && !check_c1_pending) begin
                $display("\n=======================================================================================================");
                $display("   [END OF SIMULATION] BOTH CORES COMPLETE THE PROGRAM ");
                $display("=======================================================================================================");
                $stop;
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
            // 1. MONITOR CACHE HITS
            // =========================================================================
            if (c0_state == 4'd2 && prev_c0_state != 4'd2) begin
                 c0_hit_curr = dut.cache_ctrl_0.ctrl_mesi_out; 
                 if (c0_mem_instr[6:0] == 7'b0100011) c0_hit_exp = 2'b11; // SW
                 else c0_hit_exp = c0_hit_curr; // LW
                 checked_addr = dut.c0_cpu_addr; 

                 $display("-------------------------------------------------------------------------------------------------------");
                 $display("[TC %0d: CACHE HIT START] CORE 0 INTERNAL ACTION (TIME: %t)", tc_counter, $time);
                 $display("-> Description     : TEST CASE: CACHE HIT - Executed silently without Bus.");
                 $display("-> Target Address  : 0x%08h", checked_addr);
                 if (c0_mem_instr[6:0] == 7'b0100011) 
                     $display("-> Action (SW)     : Core 0 is writing Data = 0x%08h", dut.c0_cpu_wdata);
                 $display("-> Expected MESI   : Core 0 -> [%0s] | Core 1 -> [%0s]", mesi_char(c0_hit_exp), mesi_char(dut.cache_ctrl_1.ctrl_mesi_out));
                 
                 check_c0_hit_pending <= 1; 
            end

            if (check_c0_hit_pending && c0_state != 4'd2) begin
                 $display(".......................................................................................................");
                 $display("[TC %0d: CACHE HIT END] TIME: %t", tc_counter, $time);
                 $display("-> Actual MESI     : Core 0 = [%0s] | Core 1 = [%0s]", mesi_char(c0_actual_mesi), mesi_char(c1_actual_mesi));
                 $display("-> Cached Data     : 0x%08h", c0_cache_data);
                 
                 if (c0_actual_mesi == c0_hit_exp)
                     $display("-> FINAL VERDICT   : PASS - Silent transition computed and written perfectly!");
                 else
                     $display("-> FINAL VERDICT   : FAIL - Expected [%0s] but got [%0s]!", mesi_char(c0_hit_exp), mesi_char(c0_actual_mesi));
                 $display("-------------------------------------------------------------------------------------------------------\n");
                 check_c0_hit_pending <= 0; tc_counter <= tc_counter + 1;
            end

            if (c1_state == 4'd2 && prev_c1_state != 4'd2) begin
                 c1_hit_curr = dut.cache_ctrl_1.ctrl_mesi_out;
                 if (c1_mem_instr[6:0] == 7'b0100011) c1_hit_exp = 2'b11; 
                 else c1_hit_exp = c1_hit_curr; 
                 checked_addr = dut.c1_cpu_addr;

                 $display("-------------------------------------------------------------------------------------------------------");
                 $display("[TC %0d: CACHE HIT START] CORE 1 INTERNAL ACTION (TIME: %t)", tc_counter, $time);
                 $display("-> Description     : TEST CASE: CACHE HIT - Executed silently without Bus.");
                 $display("-> Target Address  : 0x%08h", checked_addr);
                 if (c1_mem_instr[6:0] == 7'b0100011) 
                     $display("-> Action (SW)     : Core 1 is writing Data = 0x%08h", dut.c1_cpu_wdata);
                 $display("-> Expected MESI   : Core 0 -> [%0s] | Core 1 -> [%0s]", mesi_char(dut.cache_ctrl_0.ctrl_mesi_out), mesi_char(c1_hit_exp));
                 
                 check_c1_hit_pending <= 1;
            end

            if (check_c1_hit_pending && c1_state != 4'd2) begin
                 $display(".......................................................................................................");
                 $display("[TC %0d: CACHE HIT END] TIME: %t", tc_counter, $time);
                 $display("-> Actual MESI     : Core 0 = [%0s] | Core 1 = [%0s]", mesi_char(c0_actual_mesi), mesi_char(c1_actual_mesi));
                 $display("-> Cached Data     : 0x%08h", c1_cache_data);
                 
                 if (c1_actual_mesi == c1_hit_exp)
                     $display("-> FINAL VERDICT   : PASS - Silent transition computed and written perfectly!");
                 else
                     $display("-> FINAL VERDICT   : FAIL - Expected [%0s] but got [%0s]!", mesi_char(c1_hit_exp), mesi_char(c1_actual_mesi));
                 $display("-------------------------------------------------------------------------------------------------------\n");
                 check_c1_hit_pending <= 0; tc_counter <= tc_counter + 1;
            end

            // =========================================================================
            // 2. MONITOR CORE 0 BUS TRANSACTIONS
            // =========================================================================
            if (c0_grant_edge && dut.bus_arb.c0_bus_cmd != 3'b000) begin
                // [FIX LỖI MÙ MÀU ĐỊA CHỈ]: Đọc thẳng từ tín hiệu CPU phát ra, không đọc từ arbiter bị trễ
                checked_addr = (dut.bus_arb.c0_bus_cmd == 3'b100) ? {dut.cache_ctrl_0.ctrl_tag_out, dut.c0_cpu_addr[5:4], 4'b0000} : dut.bus_arb.c0_bus_addr;
                
                case (dut.bus_arb.c0_bus_cmd)
                    3'b001: begin 
                        if (dut.cache_ctrl_1.ctrl_mesi_out == 2'b00) begin 
                            c0_exp_char = "E"; c1_exp_char = "I"; 
                        end else begin                 
                            c0_exp_char = "S"; c1_exp_char = "S"; 
                        end
                    end
                    3'b010, 3'b011: begin c0_exp_char = "M"; c1_exp_char = "I"; end
                    3'b100: begin c0_exp_char = "E"; c1_exp_char = "I"; end
                    default: begin c0_exp_char = "I"; c1_exp_char = "I"; end
                endcase
                check_c0_pending <= 1;

                $display("=======================================================================================================");
                $display("[TC %0d: BUS TRANSACTION START] REQUESTING: CORE 0 | TIME: %t", tc_counter, $time);
                $display("-> Description     : %0s", get_tc_desc(dut.bus_arb.c0_bus_cmd, dut.cache_ctrl_1.ctrl_mesi_out));
                $display("-> Executing Instr : %0s (PC = 0x%08h)", decode_instr(c0_mem_instr), c0_mem_pc);
                $display("-> Target Address  : 0x%08h", checked_addr);
                if (c0_mem_instr[6:0] == 7'b0100011)
                    $display("-> Write Data      : 0x%08h", dut.c0_cpu_wdata);
                    
                $display("-> Issued Bus Cmd  : %0s", get_bus_cmd_str(dut.bus_arb.c0_bus_cmd));
                $display("-> Current MESI    : Core 0 = %0s | Core 1 = %0s", mesi_decode(dut.cache_ctrl_0.ctrl_mesi_out), mesi_decode(dut.cache_ctrl_1.ctrl_mesi_out));
                $display("-> Expected MESI   : Core 0 -> [%0s] | Core 1 -> [%0s]", c0_exp_char, c1_exp_char);
            end

            if (c0_grant_fall && check_c0_pending) begin
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
                end else begin
                    verdict = "FAIL - Hardware logic error detected!";
                end

                $display(".......................................................................................................");
                $display("[TC %0d: BUS TRANSACTION END] TIME: %t", tc_counter, $time);
                $display("-> Actual MESI     : Core 0 = [%0s] | Core 1 = [%0s]", mesi_char(c0_actual_mesi), mesi_char(c1_actual_mesi));
                $display("-> Cached Data     : 0x%08h (Data now sitting in Core 0 Cache)", c0_cache_data);
                $display("-> FINAL VERDICT   : %0s", verdict);
                $display("=======================================================================================================\n");
                check_c0_pending <= 0; tc_counter <= tc_counter + 1;
            end

            // =========================================================================
            // 3. MONITOR CORE 1 BUS TRANSACTIONS
            // =========================================================================
            if (c1_grant_edge && dut.bus_arb.c1_bus_cmd != 3'b000) begin
                // [FIX LỖI MÙ MÀU ĐỊA CHỈ]: Đọc thẳng từ tín hiệu CPU Core 1 phát ra
                checked_addr = (dut.bus_arb.c1_bus_cmd == 3'b100) ? {dut.cache_ctrl_1.ctrl_tag_out, dut.c1_cpu_addr[5:4], 4'b0000} : dut.bus_arb.c1_bus_addr;
                
                case (dut.bus_arb.c1_bus_cmd)
                    3'b001: begin
                        if (dut.cache_ctrl_0.ctrl_mesi_out == 2'b00) begin
                            c0_exp_char = "I"; c1_exp_char = "E";
                        end else begin
                            c0_exp_char = "S"; c1_exp_char = "S";
                        end
                    end
                    3'b010, 3'b011: begin c0_exp_char = "I"; c1_exp_char = "M"; end
                    3'b100: begin c0_exp_char = "I"; c1_exp_char = "E"; end 
                    default: begin c0_exp_char = "I"; c1_exp_char = "I"; end
                endcase
                check_c1_pending <= 1;

                $display("=======================================================================================================");
                $display("[TC %0d: BUS TRANSACTION START] REQUESTING: CORE 1 | TIME: %t", tc_counter, $time);
                $display("-> Description     : %0s", get_tc_desc(dut.bus_arb.c1_bus_cmd, dut.cache_ctrl_0.ctrl_mesi_out));
                $display("-> Executing Instr : %0s (PC = 0x%08h)", decode_instr(c1_mem_instr), c1_mem_pc);
                $display("-> Target Address  : 0x%08h", checked_addr);
                if (c1_mem_instr[6:0] == 7'b0100011)
                    $display("-> Write Data      : 0x%08h", dut.c1_cpu_wdata);
                    
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
                end else begin
                    verdict = "FAIL - Hardware logic error detected!";
                end

                $display(".......................................................................................................");
                $display("[TC %0d: BUS TRANSACTION END] TIME: %t", tc_counter, $time);
                $display("-> Actual MESI     : Core 0 = [%0s] | Core 1 = [%0s]", mesi_char(c0_actual_mesi), mesi_char(c1_actual_mesi));
                $display("-> Cached Data     : 0x%08h (Data now sitting in Core 1 Cache)", c1_cache_data);
                $display("-> FINAL VERDICT   : %0s", verdict);
                $display("=======================================================================================================\n");
                check_c1_pending <= 0; tc_counter <= tc_counter + 1;
            end
        end
    end
endmodule