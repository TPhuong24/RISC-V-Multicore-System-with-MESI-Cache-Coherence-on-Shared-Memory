`timescale 1ns/1ps

module tb_d1;
    reg clk;
    reg rst_n;
    wire [31:0] c0_wb_data;
    wire [31:0] c1_wb_data;

    top_multicore #(
        .CORE0_INIT_FILE("d1_core0.mem"),
        .CORE1_INIT_FILE("d1_core1.mem")
    ) dut (
        .clk(clk),
        .rst_n(rst_n),
        .out_core0_wb_data(c0_wb_data),
        .out_core1_wb_data(c1_wb_data)
    );

    reg [3:0] store_mask;
    reg [3:0] load_mask;
    integer store_count;
    integer load_count;
    integer flush_count;
    integer errors;
    reg flag_seen;
    integer i;

    wire [31:0] c0_instr = dut.core_0.dp.Instr;
    wire [31:0] c1_instr = dut.core_1.dp.Instr;

    function [31:0] expected_word;
        input [31:0] addr;
        begin
            case (addr)
                32'h00000000: expected_word = 32'h11223344;
                32'h00000004: expected_word = 32'h55667788;
                32'h00000008: expected_word = 32'hA1B2C3D4;
                32'h0000000C: expected_word = 32'hE5F60718;
                default:      expected_word = 32'hxxxxxxxx;
            endcase
        end
    endfunction

    initial begin
        clk = 1'b0;
        forever #10 clk = ~clk;
    end

    initial begin
        rst_n = 1'b0;
        store_mask = 4'b0;
        load_mask = 4'b0;
        store_count = 0;
        load_count = 0;
        flush_count = 0;
        errors = 0;
        flag_seen = 1'b0;
        #35 rst_n = 1'b1;

        #100000;
        $display("[D1] FAIL: timeout stores=%0d reads=%0d flushes=%0d errors=%0d",
                 store_count, load_count, flush_count, errors);
        $fatal(1, "D1 timed out");
    end

    always @(posedge clk) begin
        if (rst_n) begin
            // Count only accepted cache-array store commits, never CPU request cycles.
            if (dut.cache_ctrl_0.saved_wen && dut.c0_ctrl_we &&
                ((dut.cache_ctrl_0.state == 4'd2) ||
                 (dut.cache_ctrl_0.state == 4'd3 && dut.c0_bus_grant) ||
                 dut.cache_ctrl_0.state == 4'd6)) begin
                case (dut.cache_ctrl_0.saved_addr)
                    32'h00000000, 32'h00000004, 32'h00000008, 32'h0000000C: begin
                        if (dut.cache_ctrl_0.saved_wdata !== expected_word(dut.cache_ctrl_0.saved_addr)) begin
                            errors = errors + 1;
                            $display("[D1] FAIL C0 store addr=%08h expected=%08h actual=%08h",
                                     dut.cache_ctrl_0.saved_addr,
                                     expected_word(dut.cache_ctrl_0.saved_addr),
                                     dut.cache_ctrl_0.saved_wdata);
                        end
                        if (store_mask[dut.cache_ctrl_0.saved_addr[3:2]]) begin
                            errors = errors + 1;
                            $display("[D1] FAIL duplicate C0 store addr=%08h", dut.cache_ctrl_0.saved_addr);
                        end
                        store_mask[dut.cache_ctrl_0.saved_addr[3:2]] = 1'b1;
                        store_count = store_count + 1;
                    end
                    32'h00000010: begin
                        if (dut.cache_ctrl_0.saved_wdata !== 32'd1) begin
                            errors = errors + 1;
                            $display("[D1] FAIL completion flag data=%08h", dut.cache_ctrl_0.saved_wdata);
                        end
                    end
                    default: begin
                        errors = errors + 1;
                        $display("[D1] FAIL unexpected C0 store addr=%08h", dut.cache_ctrl_0.saved_addr);
                    end
                endcase
            end

            // Observe architectural load completion in S_DONE, comparing against
            // fixed constants rather than values copied from the DUT into a model.
            if (dut.cache_ctrl_1.state == 4'd8 && dut.c1_cpu_ren && !dut.cache_ctrl_1.saved_wen) begin
                if (dut.cache_ctrl_1.saved_addr == 32'h00000010) begin
                    if (dut.c1_cpu_rdata === 32'd1)
                        flag_seen = 1'b1;
                end else if (dut.cache_ctrl_1.saved_addr <= 32'h0000000C) begin
                    load_count = load_count + 1;
                    if (!flag_seen) begin
                        errors = errors + 1;
                        $display("[D1] FAIL C1 read began before completion flag");
                    end
                    if (dut.c1_cpu_rdata !== expected_word(dut.cache_ctrl_1.saved_addr)) begin
                        errors = errors + 1;
                        $display("[D1] FAIL C1 load addr=%08h expected=%08h actual=%08h",
                                 dut.cache_ctrl_1.saved_addr,
                                 expected_word(dut.cache_ctrl_1.saved_addr), dut.c1_cpu_rdata);
                    end
                    if (load_mask[dut.cache_ctrl_1.saved_addr[3:2]]) begin
                        errors = errors + 1;
                        $display("[D1] FAIL duplicate C1 load addr=%08h", dut.cache_ctrl_1.saved_addr);
                    end
                    load_mask[dut.cache_ctrl_1.saved_addr[3:2]] = 1'b1;
                end else begin
                    errors = errors + 1;
                    $display("[D1] FAIL unexpected C1 load addr=%08h", dut.cache_ctrl_1.saved_addr);
                end
            end

            // The snoop flush is complete on the final word's ready handshake.
            // Check the actual SRAM after the final word has been committed.
            if (dut.cache_ctrl_0.state == 4'd11 && dut.c0_mem_ready &&
                dut.cache_ctrl_0.flush_cnt == 2'd3 &&
                dut.cache_ctrl_0.latched_snoop_addr[31:4] === 28'h0000000) begin
                flush_count = flush_count + 1;
                if (dut.shared_mem.main_ram[0] !== expected_word(32'h00000000) ||
                    dut.shared_mem.main_ram[1] !== expected_word(32'h00000004) ||
                    dut.shared_mem.main_ram[2] !== expected_word(32'h00000008) ||
                    dut.shared_mem.main_ram[3] !== expected_word(32'h0000000C)) begin
                    errors = errors + 1;
                    $display("[D1] FAIL RAM after flush: %08h %08h %08h %08h",
                             dut.shared_mem.main_ram[0], dut.shared_mem.main_ram[1],
                             dut.shared_mem.main_ram[2], dut.shared_mem.main_ram[3]);
                end else begin
                    $display("[D1] RAM flush verified: %08h %08h %08h %08h",
                             dut.shared_mem.main_ram[0], dut.shared_mem.main_ram[1],
                             dut.shared_mem.main_ram[2], dut.shared_mem.main_ram[3]);
                end
            end

            if ((c0_instr == 32'h0000006f) && (c1_instr == 32'h0000006f)) begin
                if ((store_count != 4) || (store_mask !== 4'b1111) ||
                    (load_count != 4) || (load_mask !== 4'b1111) ||
                    (flush_count != 1) || !flag_seen || (errors != 0) ||
                    (dut.cache_array_0.mesi_array[0] !== 2'b01) ||
                    (dut.cache_array_1.mesi_array[0] !== 2'b01)) begin
                    $display("[D1] FAIL stores=%0d mask=%b reads=%0d mask=%b flushes=%0d flag=%b errors=%0d MESI=%b/%b",
                             store_count, store_mask, load_count, load_mask, flush_count,
                             flag_seen, errors, dut.cache_array_0.mesi_array[0],
                             dut.cache_array_1.mesi_array[0]);
                    $fatal(1, "D1 acceptance conditions failed");
                end else begin
                    $display("[D1] PASS: four fixed-value stores, four checked loads, four RAM words flushed; MESI S/S.");
                    $finish;
                end
            end
        end
    end
endmodule
