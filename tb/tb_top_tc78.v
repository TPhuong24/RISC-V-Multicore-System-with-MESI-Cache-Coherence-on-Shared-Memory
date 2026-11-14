`timescale 1ns/1ps

// New G0.5 system tests. These supplement the historical six event sequence
// exercised by tb_top; no original instruction images are modified.
module tb_top_tc78 #(
    parameter integer TEST_ID = 7
);
    localparam CORE0_IMAGE = (TEST_ID == 7) ? "tc7_core0.mem" : "tc8_core0.mem";
    localparam CORE1_IMAGE = (TEST_ID == 7) ? "tc7_core1.mem" : "tc8_core1.mem";

    reg clk;
    reg rst_n;
    wire [31:0] c0_wb;
    wire [31:0] c1_wb;
    reg prev_c0_grant;
    reg prev_c1_grant;
    reg tc7_readx_seen;
    reg tc7_readx_checked;
    reg tc8_upgrade_seen;
    reg tc8_upgrade_checked;
    reg [3:0] flush_mask;
    integer c0_reads;
    integer c1_reads;
    integer c1_readx_count;
    integer c0_upgrade_count;
    integer c0_bus_tx_count;
    integer c1_bus_tx_count;
    integer c0_loads;
    integer c1_loads;
    integer stores;
    integer errors;
    reg finished;
    integer word_index;

    top_multicore #(
        .CORE0_INIT_FILE(CORE0_IMAGE),
        .CORE1_INIT_FILE(CORE1_IMAGE)
    ) dut (
        .clk(clk),
        .rst_n(rst_n),
        .out_core0_wb_data(c0_wb),
        .out_core1_wb_data(c1_wb)
    );

    function [31:0] expected_data;
        input [31:0] addr;
        input integer load_number;
        begin
            if (TEST_ID == 7) begin
                if ((addr == 32'h0) && (load_number == 0))
                    expected_data = 32'h0;
                else
                    expected_data = 32'h00000055;
            end else begin
                if ((addr == 32'h0) && (load_number == 0))
                    expected_data = 32'h0;
                else
                    expected_data = 32'h00000066;
            end
        end
    endfunction

    initial begin
        clk = 1'b0;
        forever #10 clk = ~clk;
    end

    initial begin
        rst_n = 1'b0;
        prev_c0_grant = 1'b0;
        prev_c1_grant = 1'b0;
        tc7_readx_seen = 1'b0;
        tc7_readx_checked = 1'b0;
        tc8_upgrade_seen = 1'b0;
        tc8_upgrade_checked = 1'b0;
        flush_mask = 4'b0000;
        c0_reads = 0;
        c1_reads = 0;
        c1_readx_count = 0;
        c0_upgrade_count = 0;
        c0_bus_tx_count = 0;
        c1_bus_tx_count = 0;
        c0_loads = 0;
        c1_loads = 0;
        stores = 0;
        errors = 0;
        finished = 1'b0;
        #45 rst_n = 1'b1;
        #20000;
        if (!finished) begin
            $display("[TC%0d] FAIL timeout c0_loads=%0d c1_loads=%0d stores=%0d flush=%b errors=%0d",
                     TEST_ID, c0_loads, c1_loads, stores, flush_mask, errors);
            $fatal(1, "TC%0d timed out", TEST_ID);
        end
    end

    always @(posedge clk) begin
        if (!rst_n) begin
            prev_c0_grant = 1'b0;
            prev_c1_grant = 1'b0;
        end else if (!finished) begin
            if (dut.c0_bus_grant && !prev_c0_grant && dut.c0_bus_cmd != 3'b000) begin
                c0_bus_tx_count = c0_bus_tx_count + 1;
                if (dut.c0_bus_addr !== 32'h00000000) begin
                    errors = errors + 1;
                    $display("[TC%0d] FAIL C0 bus address cmd=%b addr=%08h", TEST_ID,
                             dut.c0_bus_cmd, dut.c0_bus_addr);
                end
                if (TEST_ID == 8 && dut.c0_bus_cmd == 3'b011) begin
                    c0_upgrade_count = c0_upgrade_count + 1;
                    if ((dut.cache_array_0.mesi_array[0] !== 2'b01) ||
                        (dut.cache_array_1.mesi_array[0] !== 2'b01)) begin
                        errors = errors + 1;
                        $display("[TC8] FAIL upgrade precondition: MESI=%b/%b",
                                 dut.cache_array_0.mesi_array[0], dut.cache_array_1.mesi_array[0]);
                    end
                    tc8_upgrade_seen = 1'b1;
                end
                if (dut.c0_bus_cmd == 3'b001) begin
                    if (TEST_ID == 8 && c0_reads == 0 &&
                        ((dut.cache_array_0.mesi_array[0] !== 2'b00) ||
                         (dut.cache_array_1.mesi_array[0] !== 2'b10))) begin
                        errors = errors + 1;
                        $display("[TC8] FAIL C0 shared-read precondition: MESI=%b/%b",
                                 dut.cache_array_0.mesi_array[0], dut.cache_array_1.mesi_array[0]);
                    end
                    if (TEST_ID == 7 && c0_reads == 0 &&
                        ((dut.cache_array_0.mesi_array[0] !== 2'b00) ||
                         (dut.cache_array_1.mesi_array[0] !== 2'b00))) begin
                        errors = errors + 1;
                        $display("[TC7] FAIL initial C0 READ precondition: MESI=%b/%b",
                                 dut.cache_array_0.mesi_array[0], dut.cache_array_1.mesi_array[0]);
                    end
                    if (TEST_ID == 7 && c0_reads == 1 &&
                        ((dut.cache_array_0.mesi_array[0] !== 2'b00) ||
                         (dut.cache_array_1.mesi_array[0] !== 2'b11))) begin
                        errors = errors + 1;
                        $display("[TC7] FAIL C0 reload precondition: MESI=%b/%b",
                                 dut.cache_array_0.mesi_array[0], dut.cache_array_1.mesi_array[0]);
                    end
                    c0_reads = c0_reads + 1;
                end
            end

            if (dut.c1_bus_grant && !prev_c1_grant && dut.c1_bus_cmd != 3'b000) begin
                c1_bus_tx_count = c1_bus_tx_count + 1;
                if (dut.c1_bus_addr !== 32'h00000000) begin
                    errors = errors + 1;
                    $display("[TC%0d] FAIL C1 bus address cmd=%b addr=%08h", TEST_ID,
                             dut.c1_bus_cmd, dut.c1_bus_addr);
                end
                if (TEST_ID == 7 && dut.c1_bus_cmd == 3'b010) begin
                    c1_readx_count = c1_readx_count + 1;
                    if ((dut.cache_array_0.mesi_array[0] !== 2'b10) ||
                        (dut.cache_array_1.mesi_array[0] !== 2'b00)) begin
                        errors = errors + 1;
                        $display("[TC7] FAIL READX precondition: MESI=%b/%b",
                                 dut.cache_array_0.mesi_array[0], dut.cache_array_1.mesi_array[0]);
                    end
                    tc7_readx_seen = 1'b1;
                end
                if (TEST_ID == 8 && dut.c1_bus_cmd == 3'b001) begin
                    if (c1_reads == 1 &&
                        ((dut.cache_array_0.mesi_array[0] !== 2'b11) ||
                         (dut.cache_array_1.mesi_array[0] !== 2'b00))) begin
                        errors = errors + 1;
                        $display("[TC8] FAIL final C1 READ precondition: MESI=%b/%b",
                                 dut.cache_array_0.mesi_array[0], dut.cache_array_1.mesi_array[0]);
                    end
                    c1_reads = c1_reads + 1;
                end
            end

            if (TEST_ID == 7 && prev_c1_grant && !dut.c1_bus_grant &&
                tc7_readx_seen && !tc7_readx_checked) begin
                if ((dut.cache_array_0.mesi_array[0] !== 2'b00) ||
                    (dut.cache_array_1.mesi_array[0] !== 2'b11)) begin
                    errors = errors + 1;
                    $display("[TC7] FAIL READX result: MESI=%b/%b",
                             dut.cache_array_0.mesi_array[0], dut.cache_array_1.mesi_array[0]);
                end
                tc7_readx_checked = 1'b1;
            end
            if (TEST_ID == 8 && prev_c0_grant && !dut.c0_bus_grant &&
                tc8_upgrade_seen && !tc8_upgrade_checked) begin
                if ((dut.cache_array_0.mesi_array[0] !== 2'b11) ||
                    (dut.cache_array_1.mesi_array[0] !== 2'b00)) begin
                    errors = errors + 1;
                    $display("[TC8] FAIL upgrade result: MESI=%b/%b",
                             dut.cache_array_0.mesi_array[0], dut.cache_array_1.mesi_array[0]);
                end
                tc8_upgrade_checked = 1'b1;
            end

            if ((dut.cache_ctrl_0.saved_wen && dut.c0_ctrl_we &&
                 ((dut.cache_ctrl_0.state == 4'd2) ||
                  (dut.cache_ctrl_0.state == 4'd3 && dut.c0_bus_grant) ||
                  (dut.cache_ctrl_0.state == 4'd6))) ||
                (dut.cache_ctrl_1.saved_wen && dut.c1_ctrl_we &&
                 ((dut.cache_ctrl_1.state == 4'd2) ||
                  (dut.cache_ctrl_1.state == 4'd3 && dut.c1_bus_grant) ||
                  (dut.cache_ctrl_1.state == 4'd6)))) begin
                stores = stores + 1;
                if (TEST_ID == 7) begin
                    if ((dut.cache_ctrl_1.saved_addr !== 32'h0) ||
                        (dut.cache_ctrl_1.saved_wdata !== 32'h55)) begin
                        errors = errors + 1;
                        $display("[TC7] FAIL committed store expected addr=00000000 data=00000055 actual addr=%08h data=%08h",
                                 dut.cache_ctrl_1.saved_addr, dut.cache_ctrl_1.saved_wdata);
                    end
                end else begin
                    if ((dut.cache_ctrl_0.saved_addr !== 32'h0) ||
                        (dut.cache_ctrl_0.saved_wdata !== 32'h66)) begin
                        errors = errors + 1;
                        $display("[TC8] FAIL committed store expected addr=00000000 data=00000066 actual addr=%08h data=%08h",
                                 dut.cache_ctrl_0.saved_addr, dut.cache_ctrl_0.saved_wdata);
                    end
                end
            end

            if (TEST_ID == 7 && dut.cache_ctrl_1.state == 4'd11 &&
                dut.c1_mem_wen && !dut.shared_mem.mem_ready) begin
                word_index = dut.cache_ctrl_1.flush_cnt;
                if (dut.c1_mem_addr !== (word_index * 4) ||
                    dut.c1_mem_wdata !== ((word_index == 0) ? 32'h55 : 32'h0)) begin
                    errors = errors + 1;
                    $display("[TC7] FAIL flush word=%0d expected addr=%08h data=%08h actual addr=%08h data=%08h",
                             word_index, word_index * 4, (word_index == 0) ? 32'h55 : 32'h0,
                             dut.c1_mem_addr, dut.c1_mem_wdata);
                end
                if (flush_mask[word_index]) begin
                    errors = errors + 1;
                    $display("[TC7] FAIL duplicate flush word=%0d", word_index);
                end
                flush_mask[word_index] = 1'b1;
            end

            if (TEST_ID == 8 && dut.cache_ctrl_0.state == 4'd11 &&
                dut.c0_mem_wen && !dut.shared_mem.mem_ready) begin
                word_index = dut.cache_ctrl_0.flush_cnt;
                if (dut.c0_mem_addr !== (word_index * 4) ||
                    dut.c0_mem_wdata !== ((word_index == 0) ? 32'h66 : 32'h0)) begin
                    errors = errors + 1;
                    $display("[TC8] FAIL flush word=%0d expected addr=%08h data=%08h actual addr=%08h data=%08h",
                             word_index, word_index * 4, (word_index == 0) ? 32'h66 : 32'h0,
                             dut.c0_mem_addr, dut.c0_mem_wdata);
                end
                if (flush_mask[word_index]) begin
                    errors = errors + 1;
                    $display("[TC8] FAIL duplicate flush word=%0d", word_index);
                end
                flush_mask[word_index] = 1'b1;
            end

            if (dut.cache_ctrl_0.state == 4'd8 && dut.c0_cpu_ren && !dut.cache_ctrl_0.saved_wen) begin
                if ((dut.cache_ctrl_0.saved_addr !== 32'h0) ||
                    (dut.c0_cpu_rdata !== expected_data(dut.cache_ctrl_0.saved_addr, c0_loads))) begin
                    errors = errors + 1;
                    $display("[TC%0d] FAIL C0 load #%0d expected addr=00000000 data=%08h actual addr=%08h data=%08h",
                             TEST_ID, c0_loads, expected_data(dut.cache_ctrl_0.saved_addr, c0_loads),
                             dut.cache_ctrl_0.saved_addr, dut.c0_cpu_rdata);
                end
                c0_loads = c0_loads + 1;
            end
            if (dut.cache_ctrl_1.state == 4'd8 && dut.c1_cpu_ren && !dut.cache_ctrl_1.saved_wen) begin
                if ((dut.cache_ctrl_1.saved_addr !== 32'h0) ||
                    (dut.c1_cpu_rdata !== ((TEST_ID == 7) ? 32'h55 : expected_data(dut.cache_ctrl_1.saved_addr, c1_loads)))) begin
                    errors = errors + 1;
                    $display("[TC%0d] FAIL C1 load #%0d expected addr=00000000 data=%08h actual addr=%08h data=%08h",
                             TEST_ID, c1_loads, ((TEST_ID == 7) ? 32'h55 : expected_data(dut.cache_ctrl_1.saved_addr, c1_loads)),
                             dut.cache_ctrl_1.saved_addr, dut.c1_cpu_rdata);
                end
                c1_loads = c1_loads + 1;
            end

            prev_c0_grant = dut.c0_bus_grant;
            prev_c1_grant = dut.c1_bus_grant;

            if (dut.core_0.dp.Instr == 32'h0000006f && dut.core_1.dp.Instr == 32'h0000006f) begin
                if (TEST_ID == 7) begin
                    if ((c0_reads != 2) || (c0_bus_tx_count != 2) || (c1_bus_tx_count != 1) ||
                        (c1_readx_count != 1) || !tc7_readx_seen ||
                        !tc7_readx_checked || (stores != 1) ||
                        (c0_loads != 2) || (c1_loads != 1) || (flush_mask !== 4'b1111) ||
                        (dut.cache_array_0.mesi_array[0] !== 2'b01) ||
                        (dut.cache_array_1.mesi_array[0] !== 2'b01) ||
                        (dut.shared_mem.main_ram[0] !== 32'h55) ||
                        (dut.shared_mem.main_ram[1] !== 32'h0) ||
                        (dut.shared_mem.main_ram[2] !== 32'h0) ||
                        (dut.shared_mem.main_ram[3] !== 32'h0) ||
                        (dut.core_0.dp.rf.register_file[2] !== 32'h55) ||
                        (dut.core_1.dp.rf.register_file[11] !== 32'h55) || (errors != 0)) begin
                        $display("[TC7] FAIL reads=%0d READX=%b stores=%0d loads=%0d/%0d flush=%b MESI=%b/%b RAM=%08h,%08h,%08h,%08h errors=%0d",
                                 c0_reads, tc7_readx_seen, stores, c0_loads, c1_loads, flush_mask,
                                 dut.cache_array_0.mesi_array[0], dut.cache_array_1.mesi_array[0],
                                 dut.shared_mem.main_ram[0], dut.shared_mem.main_ram[1],
                                 dut.shared_mem.main_ram[2], dut.shared_mem.main_ram[3], errors);
                        $fatal(1, "TC7 failed");
                    end
                    $display("[TC7] PASS: C1 READX invalidated C0 E; fixed store/read data and four-word M-to-S flush verified.");
                end else begin
                    if (!tc8_upgrade_seen || !tc8_upgrade_checked || (c0_reads != 1) ||
                        (c0_upgrade_count != 1) || (c0_bus_tx_count != 2) ||
                        (c1_reads != 2) || (c1_bus_tx_count != 2) || (stores != 1) ||
                        (c0_loads != 2) || (c1_loads != 2) || (flush_mask !== 4'b1111) ||
                        (dut.cache_array_0.mesi_array[0] !== 2'b01) ||
                        (dut.cache_array_1.mesi_array[0] !== 2'b01) ||
                        (dut.shared_mem.main_ram[0] !== 32'h66) ||
                        (dut.shared_mem.main_ram[1] !== 32'h0) ||
                        (dut.shared_mem.main_ram[2] !== 32'h0) ||
                        (dut.shared_mem.main_ram[3] !== 32'h0) ||
                        (dut.core_0.dp.rf.register_file[2] !== 32'h66) ||
                        (dut.core_1.dp.rf.register_file[11] !== 32'h66) || (errors != 0)) begin
                        $display("[TC8] FAIL READS=%0d UPGR=%b stores=%0d loads=%0d/%0d flush=%b MESI=%b/%b RAM=%08h,%08h,%08h,%08h errors=%0d",
                                 c1_reads, tc8_upgrade_seen, stores, c0_loads, c1_loads, flush_mask,
                                 dut.cache_array_0.mesi_array[0], dut.cache_array_1.mesi_array[0],
                                 dut.shared_mem.main_ram[0], dut.shared_mem.main_ram[1],
                                 dut.shared_mem.main_ram[2], dut.shared_mem.main_ram[3], errors);
                        $fatal(1, "TC8 failed");
                    end
                    $display("[TC8] PASS: S-to-M upgrade invalidated C1; fixed-value reload and four-word M-to-S flush verified.");
                end
                finished = 1'b1;
                $finish;
            end
        end
    end
endmodule
