`timescale 1ns/1ps

module tb_u1 #(
    parameter integer TEST_ID = 1,
    parameter PROGRAM_FILE = "u1_alu.mem"
);
    reg clk = 1'b0;
    reg reset = 1'b1;
    wire [31:0] wb_data;
    wire [31:0] cpu_mem_addr;
    wire [31:0] cpu_mem_wdata;
    wire cpu_mem_wen;
    wire cpu_mem_ren;
    reg [31:0] cpu_mem_rdata = 32'b0;
    reg cpu_mem_ready = 1'b0;
    wire cpu_stall = (cpu_mem_wen || cpu_mem_ren) && !cpu_mem_ready;

    RISC_V #(.INIT_FILE(PROGRAM_FILE)) dut (
        .clk(clk), .reset(reset), .WB_Data(wb_data),
        .cpu_mem_addr(cpu_mem_addr), .cpu_mem_wdata(cpu_mem_wdata),
        .cpu_mem_wen(cpu_mem_wen), .cpu_mem_ren(cpu_mem_ren),
        .cpu_mem_rdata(cpu_mem_rdata), .cpu_stall(cpu_stall)
    );

    reg [31:0] data_ram [0:31];
    reg [31:0] held_regs [0:31];
    reg pending = 1'b0;
    reg pending_wen = 1'b0;
    reg pending_ren = 1'b0;
    reg [31:0] pending_addr = 32'b0;
    reg [31:0] pending_wdata = 32'b0;
    integer wait_count = 0;
    integer mem_reads = 0;
    integer mem_writes = 0;
    integer mem_tx_count = 0;
    integer mem_completions = 0;
    integer errors = 0;
    integer stall_cycles = 0;
    integer branch_count = 0;
    reg stall_active = 1'b0;
    reg [31:0] held_pc = 32'b0;
    reg completed = 1'b0;
    reg jump_checked = 1'b0;
    reg [31:0] halt_pc = 32'b0;
    integer init_i;
    integer check_i;
    reg [31:0] diag_pc, diag_instr, diag_reg1, diag_reg2, diag_imm;
    reg [31:0] diag_pcplus4, diag_pcplusimm, diag_pcjalr, diag_pcvalue;
    reg [31:0] diag_aluresult;
    reg [3:0] diag_operation;
    reg [4:0] diag_rd;
    reg diag_stall, diag_regwrite, diag_memwrite;
    integer branch_trace_count = 0;
    reg [31:0] branch_trace_pc, branch_trace_instr;
    reg branch_trace_taken;
    reg [31:0] branch_trace_selected, branch_trace_target;
    reg srai_diag_seen = 1'b0;
    reg srai_reg_logged = 1'b0;

    always #5 clk = ~clk;

    initial begin
        for (init_i=0; init_i<32; init_i=init_i+1)
            data_ram[init_i] = 32'b0;
        case (TEST_ID)
            1: halt_pc = 32'h00000068;
            2: halt_pc = 32'h00000084;
            3: halt_pc = 32'h0000001C;
            4: halt_pc = 32'h00000044;
            5: halt_pc = 32'h00000200;
            6: halt_pc = 32'h00000014;
            default: $fatal(1, "[U1] invalid TEST_ID=%0d", TEST_ID);
        endcase

        $display("[U1] START test=%0d image=%0s", TEST_ID, PROGRAM_FILE);
        // Release between the rising and falling edge so the first
        // instruction's falling-edge RegFile write precedes its PC update.
        #27 reset = 1'b0;
        #100000;
        $display("[U1][TEST %0d] FAIL timeout pc=%08h reads=%0d writes=%0d", TEST_ID, dut.dp.PC, mem_reads, mem_writes);
        $fatal(1, "U1 timeout");
    end

    // Small delayed memory model. A request is accepted once, its address and
    // payload must remain stable, and ready is returned as a one-cycle pulse.
    always @(posedge clk or posedge reset) begin
        if (reset) begin
            cpu_mem_ready <= 1'b0;
            cpu_mem_rdata <= 32'b0;
            pending <= 1'b0;
            pending_wen <= 1'b0;
            pending_ren <= 1'b0;
            pending_addr <= 32'b0;
            pending_wdata <= 32'b0;
            wait_count <= 0;
        end else begin
            cpu_mem_ready <= 1'b0;
            if ((cpu_mem_wen !== 1'b0 && cpu_mem_wen !== 1'b1) ||
                (cpu_mem_ren !== 1'b0 && cpu_mem_ren !== 1'b1)) begin
                $display("[U1][TEST %0d] FAIL X/Z on memory request controls", TEST_ID);
                $fatal(1, "U1 unknown request control");
            end

            if (pending) begin
                if (!(cpu_mem_wen || cpu_mem_ren) ||
                    cpu_mem_addr !== pending_addr ||
                    cpu_mem_wdata !== pending_wdata ||
                    cpu_mem_wen !== pending_wen ||
                    cpu_mem_ren !== pending_ren) begin
                    $display("[U1][TEST %0d] FAIL request changed before ready: saved=%b/%b %08h %08h actual=%b/%b %08h %08h",
                             TEST_ID, pending_wen, pending_ren, pending_addr, pending_wdata,
                             cpu_mem_wen, cpu_mem_ren, cpu_mem_addr, cpu_mem_wdata);
                    $fatal(1, "U1 unstable memory request");
                end
                if (cpu_mem_ready) begin
                    if (TEST_ID == 6 && pending_ren &&
                        cpu_mem_rdata !== 32'h11223344) begin
                        $display("[U1][MEM] FAIL read response expected=11223344 actual=%08h addr=%08h",
                                 cpu_mem_rdata, pending_addr);
                        $fatal(1, "U1 memory read-data mismatch");
                    end
                    pending <= 1'b0;
                    wait_count <= 0;
                    mem_completions <= mem_completions + 1;
                end else if (wait_count == 0) begin
                    cpu_mem_ready <= 1'b1;
                end else begin
                    wait_count <= wait_count - 1;
                end
            end else if (cpu_mem_wen || cpu_mem_ren) begin
                if (cpu_mem_wen && cpu_mem_ren) begin
                    $display("[U1][TEST %0d] FAIL simultaneous read/write request", TEST_ID);
                    $fatal(1, "U1 invalid memory request");
                end
                if (((^cpu_mem_addr) === 1'bx) || ((^cpu_mem_wdata) === 1'bx) || cpu_mem_addr[31:7] !== 0) begin
                    $display("[U1][TEST %0d] FAIL X/Z or out-of-range memory request addr=%08h wdata=%08h",
                             TEST_ID, cpu_mem_addr, cpu_mem_wdata);
                    $fatal(1, "U1 invalid memory address/data");
                end
                if (TEST_ID == 6)
                    check_mem_request(mem_tx_count, cpu_mem_wen, cpu_mem_ren,
                                      cpu_mem_addr, cpu_mem_wdata);
                mem_tx_count <= mem_tx_count + 1;
                pending <= 1'b1;
                pending_wen <= cpu_mem_wen;
                pending_ren <= cpu_mem_ren;
                pending_addr <= cpu_mem_addr;
                pending_wdata <= cpu_mem_wdata;
                wait_count <= 2;
                if (cpu_mem_wen) begin
                    data_ram[cpu_mem_addr[6:2]] <= cpu_mem_wdata;
                    mem_writes <= mem_writes + 1;
                end else begin
                    cpu_mem_rdata <= data_ram[cpu_mem_addr[6:2]];
                    mem_reads <= mem_reads + 1;
                end
            end
        end
    end

    // Assert that the PC holds on every stalled rising edge and that the
    // datapath suppresses register writes while stalled.
    always @(posedge clk) begin
        if (reset) begin
            stall_active = 1'b0;
        end else if (cpu_stall === 1'b1) begin
            stall_cycles = stall_cycles + 1;
            if (!stall_active)
                held_pc = dut.dp.PC;
            else if (dut.dp.PC !== held_pc) begin
                $display("[U1][TEST %0d] FAIL PC changed during stall: held=%08h actual=%08h", TEST_ID, held_pc, dut.dp.PC);
                $fatal(1, "U1 PC advanced while stalled");
            end
            if (dut.dp.actual_reg_write !== 1'b0) begin
                $display("[U1][TEST %0d] FAIL actual_reg_write=%b during cpu_stall", TEST_ID, dut.dp.actual_reg_write);
                $fatal(1, "U1 register write enabled while stalled");
            end
            stall_active = 1'b1;
            #0.001;
            if (dut.dp.PC !== held_pc) begin
                $display("[U1][TEST %0d] FAIL PC changed after stalled edge: held=%08h actual=%08h", TEST_ID, held_pc, dut.dp.PC);
                $fatal(1, "U1 PC advanced while stalled");
            end
        end else begin
            stall_active = 1'b0;
        end

        if (!reset && dut.dp.Instr[6:0] === 7'b1100011 && cpu_stall === 1'b0)
            branch_count = branch_count + 1;
    end

    // The register file writes on the falling edge. Snapshot all registers
    // before that edge's NBA updates and verify that a stall caused no write.
    always @(negedge clk) begin
        if (!reset && cpu_stall === 1'b1) begin
            if (dut.dp.actual_reg_write !== 1'b0) begin
                $display("[U1][TEST %0d] FAIL register write enable during falling-edge stall", TEST_ID);
                $fatal(1, "U1 unintended stalled register write");
            end
            for (check_i=0; check_i<32; check_i=check_i+1)
                held_regs[check_i] = dut.dp.rf.register_file[check_i];
            #0.001;
            for (check_i=0; check_i<32; check_i=check_i+1) begin
                if (dut.dp.rf.register_file[check_i] !== held_regs[check_i]) begin
                    $display("[U1][TEST %0d] FAIL x%0d changed during stall: before=%08h after=%08h",
                             TEST_ID, check_i, held_regs[check_i], dut.dp.rf.register_file[check_i]);
                    $fatal(1, "U1 unintended register update during stall");
                end
            end
        end
    end

    task check_reg;
        input integer regno;
        input [31:0] expected;
        reg [31:0] actual;
        begin
            actual = dut.dp.rf.register_file[regno];
            if (actual !== expected) begin
                errors = errors + 1;
                $display("[U1][TEST %0d] FAIL x%0d expected=%08h actual=%08h", TEST_ID, regno, expected, actual);
                $display("[U1][DIAG] last_retired PC=%08h Instr=%08h Funct3=%03b Operation=%04b Reg1=%08h Reg2=%08h ExtImm=%08h",
                         diag_pc, diag_instr, diag_instr[14:12], diag_operation, diag_reg1, diag_reg2, diag_imm);
                $display("[U1][DIAG] PCPlus4=%08h PCPlusImm=%08h PCJalr=%08h PCValue=%08h cpu_stall=%b",
                         diag_pcplus4, diag_pcplusimm, diag_pcjalr, diag_pcvalue, diag_stall);
                $display("[U1][DIAG] RegWrite=%b MemWrite=%b ALUResult=%08h rd=x%0d current_PC=%08h current_Instr=%08h",
                         diag_regwrite, diag_memwrite, diag_aluresult, diag_rd, dut.dp.PC, dut.dp.Instr);
            end
        end
    endtask

    // The MEM ROM must issue exactly SW 0, LW 0, then SW 4. Each is a
    // word access, so the byte address must be naturally aligned.
    task check_mem_request;
        input integer tx_index;
        input actual_wen;
        input actual_ren;
        input [31:0] actual_addr;
        input [31:0] actual_wdata;
        reg expected_wen;
        reg expected_ren;
        reg [31:0] expected_addr;
        reg [31:0] expected_wdata;
        begin
            expected_wen = 1'b0;
            expected_ren = 1'b0;
            expected_addr = 32'b0;
            expected_wdata = 32'b0;
            case (tx_index)
                0: begin expected_wen=1'b1; expected_addr=32'h00000000; expected_wdata=32'h11223344; end
                1: begin expected_ren=1'b1; expected_addr=32'h00000000; end
                2: begin expected_wen=1'b1; expected_addr=32'h00000004; expected_wdata=32'h11223344; end
                default: begin
                    $display("[U1][MEM] FAIL unexpected extra transaction index=%0d wen/ren=%b/%b addr=%08h wdata=%08h",
                             tx_index, actual_wen, actual_ren, actual_addr, actual_wdata);
                    $fatal(1, "U1 unexpected memory transaction");
                end
            endcase

            if (actual_wen !== expected_wen || actual_ren !== expected_ren ||
                actual_addr !== expected_addr) begin
                $display("[U1][MEM] FAIL transaction %0d expected wen/ren=%b/%b addr=%08h actual=%b/%b addr=%08h",
                         tx_index, expected_wen, expected_ren, expected_addr,
                         actual_wen, actual_ren, actual_addr);
                $fatal(1, "U1 memory type/address mismatch");
            end
            if (actual_addr[1:0] !== 2'b00) begin
                $display("[U1][MEM] FAIL transaction %0d unaligned word byte address=%08h", tx_index, actual_addr);
                $fatal(1, "U1 unaligned word access");
            end
            if (expected_wen && actual_wdata !== expected_wdata) begin
                $display("[U1][MEM] FAIL transaction %0d write data expected=%08h actual=%08h",
                         tx_index, expected_wdata, actual_wdata);
                $fatal(1, "U1 memory write-data mismatch");
            end
            if (expected_ren && data_ram[expected_addr[6:2]] !== 32'h11223344) begin
                $display("[U1][MEM] FAIL read transaction %0d expected RAM word=%08h actual=%08h",
                         tx_index, 32'h11223344, data_ram[expected_addr[6:2]]);
                $fatal(1, "U1 memory read-source mismatch");
            end
        end
    endtask

    task check_final_state;
        begin
            case (TEST_ID)
                1: begin
                    check_reg(0, 32'h00000000); check_reg(1, 32'h80000000);
                    check_reg(2, 32'hFFFFFFFF); check_reg(3, 32'h7FFFFFFF);
                    check_reg(4, 32'h80000001); check_reg(5, 32'h80000000);
                    check_reg(6, 32'hFFFFFFFF); check_reg(7, 32'h7FFFFFFF);
                    check_reg(8, 32'h00000001); check_reg(9, 32'h00000001);
                    check_reg(10,32'h00000001); check_reg(11,32'h00000001);
                    check_reg(12,32'h0000000F); check_reg(13,32'h00000120);
                    check_reg(14,32'hFFFFFFAA); check_reg(15,32'h00000900);
                    check_reg(16,32'h08000000); check_reg(17,32'hF8000000);
                    check_reg(18,32'h12345000); check_reg(19,32'h00001048);
                    check_reg(20,32'h00000007); check_reg(22,32'h00000020);
                    check_reg(23,32'h00000007); check_reg(24,32'h80000000);
                    check_reg(25,32'h80000000);
                    check_reg(26,32'h00000004); check_reg(27,32'hF8000000);
                end
                2: begin
                    check_reg(1,32'h80000000); check_reg(2,32'hFFFFFFFF);
                    check_reg(3,32'h7FFFFFFF); check_reg(20,32'h00000006);
                    check_reg(31,32'h00000000);
                    if (branch_count != 14) begin
                        errors=errors+1;
                        $display("[U1][BRANCH] FAIL branch count expected=14 actual=%0d", branch_count);
                    end
                end
                3: begin
                    check_reg(0,32'h00000000); check_reg(5,32'h00000004);
                    check_reg(6,32'h00000055); check_reg(9,32'h00000018);
                    check_reg(31,32'h00000000);
                end
                4: begin
                    check_reg(1,32'h00000041); check_reg(5,32'h00000008);
                    check_reg(6,32'h00000066); check_reg(31,32'h00000000);
                end
                5: begin
                    check_reg(0,32'h00000000); check_reg(1,32'h00000004);
                    if (dut.dp.PC !== 32'h00000200) begin
                        errors=errors+1;
                        $display("[U1][PC32] FAIL target expected=00000200 actual=%08h", dut.dp.PC);
                    end
                end
                6: begin
                    check_reg(0,32'h00000000); check_reg(1,32'h11223344);
                    check_reg(2,32'h11223344);
                    if (data_ram[0] !== 32'h11223344 || data_ram[1] !== 32'h11223344) begin
                        errors=errors+1;
                        $display("[U1][MEM] FAIL RAM expected[0..1]=11223344/11223344 actual=%08h/%08h",
                                 data_ram[0], data_ram[1]);
                    end
                    if (mem_reads != 1 || mem_writes != 2) begin
                        errors=errors+1;
                        $display("[U1][MEM] FAIL transaction counts expected R/W=1/2 actual=%0d/%0d", mem_reads, mem_writes);
                    end
                    if (mem_tx_count != 3 || mem_completions != 3) begin
                        errors=errors+1;
                        $display("[U1][MEM] FAIL accepted/completed transactions expected=3/3 actual=%0d/%0d",
                                 mem_tx_count, mem_completions);
                    end
                    if (stall_cycles < 6) begin
                        errors=errors+1;
                        $display("[U1][STALL] FAIL insufficient observed stall cycles=%0d", stall_cycles);
                    end
                end
            endcase

            if (dut.dp.rf.register_file[0] !== 32'h00000000) begin
                errors=errors+1;
                $display("[U1] FAIL x0 expected=00000000 actual=%08h", dut.dp.rf.register_file[0]);
            end
            if (errors == 0) begin
                case (TEST_ID)
                    1: $display("[U1][ALU] PASS: ALU, immediate ALU, shifts, LUI, AUIPC.");
                    2: $display("[U1][BRANCH] PASS: six branch conditions, taken/not-taken, equality, signed overflow.");
                    3: $display("[U1][JAL] PASS: targets, links, and x0 destination.");
                    4: $display("[U1][JALR] PASS: target bit clearing and link value.");
                    5: $display("[U1][PC32] PASS: jump target beyond 9 bits fetched from the 1024-word ROM.");
                    6: $display("[U1][MEM] PASS: LW/SW data, handshake, single side effects, PC/register stall checks.");
                endcase
                $display("[U1][TEST %0d] COUNTS reads=%0d writes=%0d stall_cycles=%0d",TEST_ID,mem_reads,mem_writes,stall_cycles);
                $finish;
            end else begin
                $display("[U1][TEST %0d] FAIL final errors=%0d",TEST_ID,errors);
                $fatal(1,"U1 final-state mismatch");
            end
        end
    endtask

    // Jumps are checked immediately after the PC's nonblocking update.
    always @(posedge clk) begin
        if (!reset && !jump_checked && TEST_ID == 4 &&
            dut.dp.PC === 32'h00000004 && dut.dp.Instr[6:0] === 7'b1100111) begin
            jump_checked = 1'b1;
            #0.001;
            if (dut.dp.PC !== 32'h00000040) begin
                $display("[U1][JALR] FAIL target expected=00000040 actual=%08h (rs1 has bit0=1)", dut.dp.PC);
                $fatal(1,"U1 JALR target mismatch");
            end
            if (dut.dp.rf.register_file[5] !== 32'h00000008) begin
                $display("[U1][JALR] FAIL link expected=00000008 actual=%08h", dut.dp.rf.register_file[5]);
                $fatal(1,"U1 JALR link mismatch");
            end
        end
        if (!reset && !jump_checked && TEST_ID == 5 &&
            dut.dp.PC === 32'h00000000 && dut.dp.Instr[6:0] === 7'b1101111) begin
            jump_checked = 1'b1;
            #0.001;
            if (dut.dp.PC !== 32'h00000200) begin
                $display("[U1][PC32] FAIL JAL target expected=00000200 actual=%08h", dut.dp.PC);
                $fatal(1,"U1 PC/JAL target truncated or miscomputed");
            end
            if (dut.dp.rf.register_file[1] !== 32'h00000004) begin
                $display("[U1][PC32] FAIL JAL link expected=00000004 actual=%08h", dut.dp.rf.register_file[1]);
                $fatal(1,"U1 PC32 link mismatch");
            end
        end
    end

    // Inspect SRAI while PC=0x40 after the instruction and combinational
    // decode have settled. The following negedge report confirms the actual
    // register-file write after its NBA update.
    always @(posedge clk) begin
        if (!reset && TEST_ID == 1 && !srai_diag_seen &&
            dut.dp.PC === 32'h0000003C) begin
            #0.001;
            if (dut.dp.PC === 32'h00000040) begin
                srai_diag_seen = 1'b1;
                $display("[U1][SRAI_DIAG][COMB] PC=%08h Instr=%08h opcode=%07b funct3=%03b bit30=%b Reg1=%08h Reg2=%08h SrcA=%08h SrcB=%08h ExtImm=%08h",
                         dut.dp.PC, dut.dp.Instr, dut.dp.Instr[6:0],
                         dut.dp.Instr[14:12], dut.dp.Instr[30], dut.dp.Reg1,
                         dut.dp.Reg2, dut.dp.alu_module.SrcA, dut.dp.SrcB,
                         dut.dp.ExtImm);
                $display("[U1][SRAI_DIAG][COMB] Operation=%04b ALUResult=%08h Result=%08h RegWrite=%b actual_reg_write=%b rd=x%0d rg_wrt_dest=x%0d rg_wrt_data=%08h cpu_stall=%b",
                         dut.Operation, dut.dp.ALUResult, dut.dp.Result,
                         dut.RegWrite, dut.dp.actual_reg_write,
                         dut.dp.Instr[11:7], dut.dp.rf.rg_wrt_dest,
                         dut.dp.rf.rg_wrt_data, cpu_stall);
            end
        end
    end

    always @(negedge clk) begin
        if (!reset && TEST_ID == 1 && srai_diag_seen && !srai_reg_logged &&
            dut.dp.PC === 32'h00000040) begin
            #0.001;
            $display("[U1][SRAI_DIAG][RF] x17_after_write=%08h expected=F8000000",
                     dut.dp.rf.register_file[17]);
            srai_reg_logged = 1'b1;
        end
    end

    // Bounded control-flow trace: the BRANCH image has exactly 14 branch
    // instructions. Capture the decision before the PC NBA, then report the
    // actual next PC after it settles.
    always @(posedge clk) begin
        if (!reset && TEST_ID == 2 && cpu_stall === 1'b0 &&
            dut.dp.Instr[6:0] === 7'b1100011) begin
            branch_trace_count = branch_trace_count + 1;
            branch_trace_pc = dut.dp.PC;
            branch_trace_instr = dut.dp.Instr;
            branch_trace_taken = dut.dp.branch_taken;
            branch_trace_selected = dut.dp.PCValue;
            branch_trace_target = dut.dp.PCPlusImm;
            #0.001;
            $display("[U1][BRANCH_TRACE] #%0d PC=%08h Instr=%08h funct3=%03b taken=%b target=%08h selected_PCValue=%08h actual_next=%08h",
                     branch_trace_count, branch_trace_pc, branch_trace_instr,
                     branch_trace_instr[14:12], branch_trace_taken,
                     branch_trace_target, branch_trace_selected, dut.dp.PC);
        end
    end

    // Keep a compact snapshot of the last instruction allowed to retire so
    // final-state mismatches include the datapath/control context that caused
    // the value under test.
    always @(posedge clk) begin
        if (!reset && cpu_stall === 1'b0) begin
            diag_pc = dut.dp.PC;
            diag_instr = dut.dp.Instr;
            diag_reg1 = dut.dp.Reg1;
            diag_reg2 = dut.dp.Reg2;
            diag_imm = dut.dp.ExtImm;
            diag_pcplus4 = dut.dp.PCPlus4;
            diag_pcplusimm = dut.dp.PCPlusImm;
            diag_pcjalr = dut.dp.PCJalr;
            diag_pcvalue = dut.dp.PCValue;
            diag_operation = dut.Operation;
            diag_aluresult = dut.dp.ALUResult;
            diag_rd = dut.dp.Instr[11:7];
            diag_stall = cpu_stall;
            diag_regwrite = dut.RegWrite;
            diag_memwrite = dut.MemWrite;
        end
    end

    always @(negedge clk) begin
        if (!reset && !completed && dut.dp.PC === halt_pc) begin
            completed = 1'b1;
            check_final_state;
        end
    end
endmodule
