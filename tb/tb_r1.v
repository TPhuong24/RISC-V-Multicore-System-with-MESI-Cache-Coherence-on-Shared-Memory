`timescale 1ns/1ps

module tb_r1;
    localparam [31:0] R1_SEED_C0 = 32'hD1A20001;
    localparam [31:0] R1_SEED_C1 = 32'hD1A20002;
    localparam integer OPS_PER_CORE = 2000;

    reg clk=0, rst_n=0;
    wire [31:0] c0_wb_data, c1_wb_data;
    top_multicore #(.CORE0_INIT_FILE("r1_core0.mem"), .CORE1_INIT_FILE("r1_core1.mem")) dut (
        .clk(clk), .rst_n(rst_n),
        .out_core0_wb_data(c0_wb_data), .out_core1_wb_data(c1_wb_data)
    );

    integer errors=0;
    integer c0_init_count=0, c1_init_count=0;
    integer c0_ops=0, c1_ops=0;
    reg [7:0] c0_init_mask=0, c1_init_mask=0;
    reg c0_stopped=0, c1_stopped=0;
    integer set_idx;
    reg [31:0] expected_addr[0:31];
    reg expected_store[0:31];
    integer perm[0:7];
    integer core_idx, sched_idx, swap_idx, temp_slot, addr_slot, try_count;
    integer sched_base;
    reg [31:0] random_state;
    reg candidate_store, accepted_candidate;
    wire [31:0] c0_instr=dut.core_0.dp.Instr;
    wire [31:0] c1_instr=dut.core_1.dp.Instr;

    always #10 clk=~clk;

    task print_core1_pc_trace;
    input [8*12-1:0] phase;
        begin
            $display("[R1][PC_TRACE][%0s] time=%0t c1_ops=%0d c1_init_count=%0d PC=%03h Instr=%08h Branch=%b Jal=%b ExtImm=%08h PCPlusImm=%08h PCPlus4=%03h PCValue=%03h cpu_stall=%b",
                     phase,$time,c1_ops,c1_init_count,dut.core_1.dp.PC,dut.core_1.dp.Instr,
                     dut.core_1.dp.Branch,dut.core_1.dp.Jal,dut.core_1.dp.ExtImm,
                     dut.core_1.dp.PCPlusImm,dut.core_1.dp.PCPlus4,dut.core_1.dp.PCValue,
                     dut.c1_cpu_stall);
        end
    endtask

// Trace every selected Core 1 PC on each rising edge, independent of c1_ops.
// The delayed sample is taken 1 ps after the edge, after NBA updates settle.
    always @(posedge clk) begin
    if (rst_n &&
        (((dut.core_1.dp.PC >= 9'h0B0) &&
          (dut.core_1.dp.PC <= 9'h1FC)) ||
         dut.core_1.dp.PC===9'h000 ||
         dut.core_1.dp.PC===9'h080 ||
         dut.core_1.dp.PC===9'h190)) begin
            print_core1_pc_trace("PRE_EDGE");
        #0.001;
        print_core1_pc_trace("POST_SAMPLE");
        end
    end

    function [31:0] addr_for_slot;
        input integer slot;
        begin
            case(slot)
                0:addr_for_slot=32'h00000000;
                1:addr_for_slot=32'h00000004;
                2:addr_for_slot=32'h00000040;
                3:addr_for_slot=32'h00000044;
                4:addr_for_slot=32'h00000080;
                5:addr_for_slot=32'h00000084;
                6:addr_for_slot=32'h00000088;
                7:addr_for_slot=32'h0000008C;
                default:addr_for_slot=32'hxxxxxxxx;
            endcase
        end
    endfunction

    function [31:0] value_for_addr;
        input [31:0] addr;
        begin
            case(addr)
                32'h00000000:value_for_addr=32'h00000135;
                32'h00000004:value_for_addr=32'h00000246;
                32'h00000040:value_for_addr=32'h00000357;
                32'h00000044:value_for_addr=32'h00000468;
                32'h00000080:value_for_addr=32'h00000579;
                32'h00000084:value_for_addr=32'h0000068A;
                32'h00000088:value_for_addr=32'h000005AB;
                32'h0000008C:value_for_addr=32'h000006BC;
                default:value_for_addr=32'hxxxxxxxx;
            endcase
        end
    endfunction

    function [31:0] xorshift32;
        input [31:0] seed;
        reg [31:0] value;
        begin
            value=seed ^ (seed << 13);
            value=value ^ (value >> 17);
            value=value ^ (value << 5);
            xorshift32=value;
        end
    endfunction

    task mismatch;
        input [8*120-1:0] reason;
        begin
            errors=errors+1;
            $display("[R1] FAIL %0s",reason);
            $fatal(1,"R1 data/sequence mismatch");
        end
    endtask

    task stop_core0_requests;
        begin
            if(!c0_stopped) begin
                force dut.c0_cpu_wen=1'b0;
                force dut.c0_cpu_ren=1'b0;
                c0_stopped=1'b1;
            end
        end
    endtask
    task stop_core1_requests;
        begin
            if(!c1_stopped) begin
                force dut.c1_cpu_wen=1'b0;
                force dut.c1_cpu_ren=1'b0;
                c1_stopped=1'b1;
            end
        end
    endtask

    initial begin
        $display("[R1] Fixed seeds Core0=%08h Core1=%08h; each core executes 125 x 16 = %0d checked LW/SW operations.",R1_SEED_C0,R1_SEED_C1,OPS_PER_CORE);
        for(core_idx=0;core_idx<2;core_idx=core_idx+1) begin
            random_state=(core_idx==0) ? R1_SEED_C0 : R1_SEED_C1;
            for(sched_idx=0;sched_idx<8;sched_idx=sched_idx+1) perm[sched_idx]=sched_idx;
            // Seeded Fisher-Yates permutation ensures every word is loaded.
            for(sched_idx=7;sched_idx>0;sched_idx=sched_idx-1) begin
                random_state=xorshift32(random_state);
                swap_idx=random_state%(sched_idx+1);
                temp_slot=perm[sched_idx]; perm[sched_idx]=perm[swap_idx]; perm[swap_idx]=temp_slot;
            end
            sched_base=core_idx*16;
            for(sched_idx=0;sched_idx<8;sched_idx=sched_idx+1) begin
                expected_addr[sched_base+sched_idx]=addr_for_slot(perm[sched_idx]);
                expected_store[sched_base+sched_idx]=1'b0;
            end
            // Four seeded writes plus four additional seeded load/store choices.
            for(sched_idx=8;sched_idx<12;sched_idx=sched_idx+1) begin
                random_state=xorshift32(random_state);
                expected_addr[sched_base+sched_idx]=addr_for_slot(random_state%8);
                expected_store[sched_base+sched_idx]=1'b1;
            end
            for(sched_idx=12;sched_idx<16;sched_idx=sched_idx+1) begin
                accepted_candidate=1'b0; try_count=0;
                while(!accepted_candidate && try_count<64) begin
                    random_state=xorshift32(random_state); addr_slot=random_state%8;
                    random_state=xorshift32(random_state); candidate_store=random_state[0];
                    if(sched_idx==15 && addr_slot==perm[0] && !candidate_store) begin
                        // Avoid repeating the exact transaction at the loop boundary.
                        try_count=try_count+1;
                    end else if(sched_idx>0 && addr_slot==((expected_addr[sched_base+sched_idx-1]==32'h0)?0:
                               (expected_addr[sched_base+sched_idx-1]==32'h4)?1:
                               (expected_addr[sched_base+sched_idx-1]==32'h40)?2:
                               (expected_addr[sched_base+sched_idx-1]==32'h44)?3:
                               (expected_addr[sched_base+sched_idx-1]==32'h80)?4:
                               (expected_addr[sched_base+sched_idx-1]==32'h84)?5:
                               (expected_addr[sched_base+sched_idx-1]==32'h88)?6:7) &&
                               candidate_store==expected_store[sched_base+sched_idx-1]) begin
                        try_count=try_count+1;
                    end else begin
                        expected_addr[sched_base+sched_idx]=addr_for_slot(addr_slot);
                        expected_store[sched_base+sched_idx]=candidate_store;
                        accepted_candidate=1'b1;
                    end
                end
                if(!accepted_candidate) $fatal(1,"R1 schedule generation failed");
            end
        end
        #35 rst_n=1'b1;
        #20000000;
        $display("[R1] FAIL timeout operations C0=%0d C1=%0d init=%0d/%0d",c0_ops,c1_ops,c0_init_count,c1_init_count);
        $fatal(1,"R1 timeout");
    end

    always @(posedge clk) if(rst_n) begin : monitor_ops
        integer ordinal;
        reg [31:0] addr,data,exp_addr,exp_data;

        // Count only accepted cache-array stores, at the same commit points as tb_top.
        if(dut.cache_ctrl_0.saved_wen && dut.c0_ctrl_we &&
           (dut.cache_ctrl_0.state==4'd2 ||
            (dut.cache_ctrl_0.state==4'd3 && dut.c0_bus_grant) ||
            dut.cache_ctrl_0.state==4'd6)) begin
            addr=dut.cache_ctrl_0.saved_addr; data=dut.cache_ctrl_0.saved_wdata;
            if(c0_init_count<8) begin
                exp_addr=addr_for_slot(c0_init_count); exp_data=value_for_addr(exp_addr);
                if(addr!==exp_addr || data!==exp_data) mismatch("Core0 initialization store address/data mismatch");
                c0_init_mask[c0_init_count]=1'b1; c0_init_count=c0_init_count+1;
            end else begin
                ordinal=c0_ops; exp_addr=expected_addr[ordinal%16]; exp_data=value_for_addr(exp_addr);
                if(!expected_store[ordinal%16] || addr!==exp_addr || data!==exp_data)
                    mismatch("Core0 workload store type/address/data mismatch");
                c0_ops=c0_ops+1;
                if(c0_ops>OPS_PER_CORE) mismatch("Core0 exceeded exactly 2000 operations");
                if(c0_ops==OPS_PER_CORE) stop_core0_requests();
            end
        end

        if(dut.cache_ctrl_1.saved_wen && dut.c1_ctrl_we &&
           (dut.cache_ctrl_1.state==4'd2 ||
            (dut.cache_ctrl_1.state==4'd3 && dut.c1_bus_grant) ||
            dut.cache_ctrl_1.state==4'd6)) begin
            addr=dut.cache_ctrl_1.saved_addr; data=dut.cache_ctrl_1.saved_wdata;
            if(c1_init_count<8) begin
                exp_addr=addr_for_slot(c1_init_count); exp_data=value_for_addr(exp_addr);
                if(addr!==exp_addr || data!==exp_data) begin
                    $display("[R1][DIAG] Core1 initialization mismatch: c1_init_count=%0d slot=%0d",c1_init_count,c1_init_count);
                    $display("[R1][DIAG] expected addr=%08h data=%08h; actual saved_addr=%08h saved_wdata=%08h",exp_addr,exp_data,addr,data);
                    $display("[R1][DIAG] PC=%08h Instr=%08h",dut.core_1.dp.PC,dut.core_1.dp.Instr);
                    $display("[R1][DIAG] c1_cpu_addr=%08h c1_cpu_wdata=%08h c1_cpu_wen=%b",dut.c1_cpu_addr,dut.c1_cpu_wdata,dut.c1_cpu_wen);
                    $display("[R1][DIAG] saved_addr=%08h saved_wdata=%08h saved_wen=%b state=%0d c1_ctrl_we=%b",dut.cache_ctrl_1.saved_addr,dut.cache_ctrl_1.saved_wdata,dut.cache_ctrl_1.saved_wen,dut.cache_ctrl_1.state,dut.c1_ctrl_we);
                    $display("[R1][DIAG] RegFile x10..x17: %08h %08h %08h %08h %08h %08h %08h %08h",
                             dut.core_1.dp.rf.register_file[10],dut.core_1.dp.rf.register_file[11],
                             dut.core_1.dp.rf.register_file[12],dut.core_1.dp.rf.register_file[13],
                             dut.core_1.dp.rf.register_file[14],dut.core_1.dp.rf.register_file[15],
                             dut.core_1.dp.rf.register_file[16],dut.core_1.dp.rf.register_file[17]);
                    $display("[R1][DIAG] X/Z flags exp_addr=%b exp_data=%b actual_addr=%b actual_data=%b PC=%b Instr=%b cpu_addr=%b cpu_wdata=%b cpu_wen=%b saved_addr=%b saved_wdata=%b saved_wen=%b state=%b ctrl_we=%b",
                             ((^exp_addr)===1'bx),((^exp_data)===1'bx),((^addr)===1'bx),((^data)===1'bx),
                             ((^dut.core_1.dp.PC)===1'bx),((^dut.core_1.dp.Instr)===1'bx),
                             ((^dut.c1_cpu_addr)===1'bx),((^dut.c1_cpu_wdata)===1'bx),((dut.c1_cpu_wen!==1'b0)&&(dut.c1_cpu_wen!==1'b1)),
                             ((^dut.cache_ctrl_1.saved_addr)===1'bx),((^dut.cache_ctrl_1.saved_wdata)===1'bx),
                             ((dut.cache_ctrl_1.saved_wen!==1'b0)&&(dut.cache_ctrl_1.saved_wen!==1'b1)),
                             ((^dut.cache_ctrl_1.state)===1'bx),((dut.c1_ctrl_we!==1'b0)&&(dut.c1_ctrl_we!==1'b1)));
                    $display("[R1][DIAG] X/Z flags RegFile x10..x17=%b%b%b%b%b%b%b%b",
                             ((^dut.core_1.dp.rf.register_file[10])===1'bx),
                             ((^dut.core_1.dp.rf.register_file[11])===1'bx),
                             ((^dut.core_1.dp.rf.register_file[12])===1'bx),
                             ((^dut.core_1.dp.rf.register_file[13])===1'bx),
                             ((^dut.core_1.dp.rf.register_file[14])===1'bx),
                             ((^dut.core_1.dp.rf.register_file[15])===1'bx),
                             ((^dut.core_1.dp.rf.register_file[16])===1'bx),
                             ((^dut.core_1.dp.rf.register_file[17])===1'bx));
                    mismatch("Core1 initialization store address/data mismatch");
                end
                c1_init_mask[c1_init_count]=1'b1; c1_init_count=c1_init_count+1;
            end else begin
                ordinal=c1_ops; exp_addr=expected_addr[16+(ordinal%16)]; exp_data=value_for_addr(exp_addr);
                if(!expected_store[16+(ordinal%16)] || addr!==exp_addr || data!==exp_data) begin
                    $display("[R1][DIAG] Core1 workload store mismatch: c1_ops=%0d schedule_iteration=%0d slot=%0d c1_init_count=%0d",
                             c1_ops,ordinal/16,ordinal%16,c1_init_count);
                    $display("[R1][DIAG] expected_type=%s actual_type=SW (saved_wen=%b cpu_wen=%b cpu_ren=%b)",
                             expected_store[16+(ordinal%16)] ? "SW" : "LW",dut.cache_ctrl_1.saved_wen,dut.c1_cpu_wen,dut.c1_cpu_ren);
                    $display("[R1][DIAG] expected addr=%08h data=%08h; actual addr=%08h data=%08h",
                             exp_addr,exp_data,addr,data);
                    $display("[R1][DIAG] PC=%08h Instr=%08h c1_cpu_addr=%08h c1_cpu_wdata=%08h c1_cpu_wen=%b",
                             dut.core_1.dp.PC,dut.core_1.dp.Instr,dut.c1_cpu_addr,dut.c1_cpu_wdata,dut.c1_cpu_wen);
                    $display("[R1][DIAG] saved_addr=%08h saved_wdata=%08h saved_wen=%b state=%0d c1_ctrl_we=%b",
                             dut.cache_ctrl_1.saved_addr,dut.cache_ctrl_1.saved_wdata,dut.cache_ctrl_1.saved_wen,dut.cache_ctrl_1.state,dut.c1_ctrl_we);
                    $display("[R1][DIAG] datapath Reg1=%08h Reg2=%08h Store_data=%08h",
                             dut.core_1.dp.Reg1,dut.core_1.dp.Reg2,dut.core_1.dp.Store_data);
                    $display("[R1][DIAG] checker expected_store=%b expected_addr=%08h schedule_index=%0d expected[0..15] types=%b%b%b%b%b%b%b%b%b%b%b%b%b%b%b%b",
                             expected_store[16+(ordinal%16)],expected_addr[16+(ordinal%16)],ordinal%16,
                             expected_store[16],expected_store[17],expected_store[18],expected_store[19],
                             expected_store[20],expected_store[21],expected_store[22],expected_store[23],
                             expected_store[24],expected_store[25],expected_store[26],expected_store[27],
                             expected_store[28],expected_store[29],expected_store[30],expected_store[31]);
                    $display("[R1][DIAG] scheduler state sched_base=%0d sched_idx=%0d core_idx=%0d random_state=%08h perm=%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d",
                             sched_base,sched_idx,core_idx,random_state,perm[0],perm[1],perm[2],perm[3],perm[4],perm[5],perm[6],perm[7]);
                    $display("[R1][DIAG] X/Z flags expected_type=%b expected_addr=%b expected_data=%b actual_addr=%b actual_data=%b PC=%b Instr=%b cpu_addr=%b cpu_wdata=%b cpu_wen=%b cpu_ren=%b saved_addr=%b saved_wdata=%b saved_wen=%b state=%b ctrl_we=%b Reg1=%b Reg2=%b Store_data=%b",
                             ((expected_store[16+(ordinal%16)]!==1'b0)&&(expected_store[16+(ordinal%16)]!==1'b1)),
                             ((^exp_addr)===1'bx),((^exp_data)===1'bx),((^addr)===1'bx),((^data)===1'bx),
                             ((^dut.core_1.dp.PC)===1'bx),((^dut.core_1.dp.Instr)===1'bx),
                             ((^dut.c1_cpu_addr)===1'bx),((^dut.c1_cpu_wdata)===1'bx),
                             ((dut.c1_cpu_wen!==1'b0)&&(dut.c1_cpu_wen!==1'b1)),
                             ((dut.c1_cpu_ren!==1'b0)&&(dut.c1_cpu_ren!==1'b1)),
                             ((^dut.cache_ctrl_1.saved_addr)===1'bx),((^dut.cache_ctrl_1.saved_wdata)===1'bx),
                             ((dut.cache_ctrl_1.saved_wen!==1'b0)&&(dut.cache_ctrl_1.saved_wen!==1'b1)),
                             ((^dut.cache_ctrl_1.state)===1'bx),
                             ((dut.c1_ctrl_we!==1'b0)&&(dut.c1_ctrl_we!==1'b1)),
                             ((^dut.core_1.dp.Reg1)===1'bx),((^dut.core_1.dp.Reg2)===1'bx),
                             ((^dut.core_1.dp.Store_data)===1'bx));
                    mismatch("Core1 workload store type/address/data mismatch");
                end
                c1_ops=c1_ops+1;
                if(c1_ops>OPS_PER_CORE) mismatch("Core1 exceeded exactly 2000 operations");
                if(c1_ops==OPS_PER_CORE) stop_core1_requests();
            end
        end

        // Loads complete in S_DONE; compare data using fixed constants, never DUT stores.
        if(dut.cache_ctrl_0.state==4'd8 && dut.c0_cpu_ren && !dut.cache_ctrl_0.saved_wen) begin
            addr=dut.cache_ctrl_0.saved_addr; data=dut.c0_cpu_rdata;
            if(c0_init_count!=8) mismatch("Core0 load occurred before all eight initial stores");
            ordinal=c0_ops; exp_addr=expected_addr[ordinal%16]; exp_data=value_for_addr(exp_addr);
            if(expected_store[ordinal%16] || addr!==exp_addr || data!==exp_data)
                mismatch("Core0 workload load type/address/data mismatch or X/Z");
            c0_ops=c0_ops+1;
            if(c0_ops>OPS_PER_CORE) mismatch("Core0 exceeded exactly 2000 operations");
            if(c0_ops==OPS_PER_CORE) stop_core0_requests();
        end

        if(dut.cache_ctrl_1.state==4'd8 && dut.c1_cpu_ren && !dut.cache_ctrl_1.saved_wen) begin
            addr=dut.cache_ctrl_1.saved_addr; data=dut.c1_cpu_rdata;
            if(c1_init_count!=8) mismatch("Core1 load occurred before all eight initial stores");
            ordinal=c1_ops; exp_addr=expected_addr[16+(ordinal%16)]; exp_data=value_for_addr(exp_addr);
            if(expected_store[16+(ordinal%16)] || addr!==exp_addr || data!==exp_data)
                mismatch("Core1 workload load type/address/data mismatch or X/Z");
            c1_ops=c1_ops+1;
            if(c1_ops>OPS_PER_CORE) mismatch("Core1 exceeded exactly 2000 operations");
            if(c1_ops==OPS_PER_CORE) stop_core1_requests();
        end

        for(set_idx=0;set_idx<4;set_idx=set_idx+1) begin
            if(dut.cache_array_0.mesi_array[set_idx]===2'b11 &&
               dut.cache_array_1.mesi_array[set_idx]===2'b11 &&
               dut.cache_array_0.tag_array[set_idx]===dut.cache_array_1.tag_array[set_idx])
                mismatch("both caches hold Modified for one line");
        end

        if(c0_ops==OPS_PER_CORE && c1_ops==OPS_PER_CORE && c0_stopped && c1_stopped) begin
            if(c0_init_mask!==8'hFF || c1_init_mask!==8'hFF)
                mismatch("initialization store missing or duplicated");
            $display("[R1] PASS: seed=%08h/%08h; both cores completed exactly 2000 checked LW/SW operations over the same eight words on three conflicting lines.",R1_SEED_C0,R1_SEED_C1);
            $finish;
        end
    end
endmodule
