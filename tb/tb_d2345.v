`timescale 1ns/1ps

module tb_d2345 #(
    parameter TEST_ID = 2,
    parameter CORE0_FILE = "d2_core0.mem",
    parameter CORE1_FILE = "d2_core1.mem"
);
    reg clk = 1'b0;
    reg rst_n = 1'b0;
    wire [31:0] c0_wb_data, c1_wb_data;
    top_multicore #(.CORE0_INIT_FILE(CORE0_FILE), .CORE1_INIT_FILE(CORE1_FILE)) dut (
        .clk(clk), .rst_n(rst_n),
        .out_core0_wb_data(c0_wb_data), .out_core1_wb_data(c1_wb_data)
    );

    integer errors = 0;
    integer c0_stores = 0, c1_stores = 0;
    integer c0_loads = 0, c1_loads = 0;
    integer evict_a = 0, evict_b = 0, data_flushes = 0;
    reg [3:0] c0_store_mask = 0, c1_store_mask = 0;
    reg [3:0] c0_load_mask = 0, c1_load_mask = 0;
    reg invalidation_seen = 0;
    reg shared_seen = 0;
    reg final_ram_seen = 0;

    wire [31:0] c0_instr = dut.core_0.dp.Instr;
    wire [31:0] c1_instr = dut.core_1.dp.Instr;

    always #10 clk = ~clk;

    function [31:0] expected_store;
        input integer scenario;
        input integer core_id;
        input [31:0] addr;
        input integer ordinal;
        begin
            expected_store = 32'hxxxxxxxx;
            if (scenario == 2 && core_id == 0) begin
                case (addr)
                    0: expected_store = 32'h00000135;
                    4: expected_store = 32'h00000246;
                    64: expected_store = 32'h00000357;
                endcase
            end else if (scenario == 3) begin
                if (core_id == 0 && addr == 0) expected_store = 32'h00000135;
                if (core_id == 1 && addr == 8) expected_store = 32'h00000246;
            end else if (scenario == 4 && core_id == 0) begin
                if (addr == 0) expected_store = ordinal < 2 ? 32'h00000135 : 32'h00000357;
                if (addr == 4) expected_store = ordinal < 2 ? 32'h00000246 : 32'h00000468;
            end else if (scenario == 5) begin
                if (core_id == 0 && addr == 0) expected_store = 32'h00000135;
                if (core_id == 0 && addr == 4) expected_store = 32'h00000246;
                if (core_id == 1 && addr == 12) expected_store = 32'h00000357;
            end
        end
    endfunction

    function [31:0] expected_load;
        input integer scenario;
        input integer core_id;
        input [31:0] addr;
        begin
            expected_load = 32'hxxxxxxxx;
            if (scenario == 2 && core_id == 0) begin
                if (addr == 0) expected_load = 32'h00000135;
                if (addr == 4) expected_load = 32'h00000246;
            end else if (scenario == 3) begin
                if (addr == 0) expected_load = 32'h00000135;
                if (addr == 8) expected_load = 32'h00000246;
            end else if (scenario == 4) begin
                if (core_id == 0 && addr == 0) expected_load = 32'h00000357;
                if (core_id == 0 && addr == 4) expected_load = 32'h00000468;
                if (core_id == 1 && addr == 0) expected_load = 32'h00000135;
                if (core_id == 1 && addr == 4) expected_load = 32'h00000246;
            end else if (scenario == 5 && core_id == 1 && addr == 12)
                expected_load = 32'h00000357;
        end
    endfunction

    task check_load;
        input integer core_id;
        input [31:0] addr;
        input [31:0] data;
        reg [31:0] exp;
        reg [31:0] expected_addr;
        integer ord;
        begin
            exp = expected_load(TEST_ID, core_id, addr);
            ord = core_id == 0 ? c0_loads : c1_loads;
            expected_addr = 32'hxxxxxxxx;
            if (TEST_ID == 2 && core_id == 0) expected_addr = ord == 0 ? 0 : 4;
            if (TEST_ID == 3) expected_addr = ord == 0 ? 0 : 8;
            if (TEST_ID == 4) expected_addr = ord == 0 ? 0 : 4;
            if (TEST_ID == 5 && core_id == 1) expected_addr = 12;
            if (addr !== expected_addr) begin
                errors = errors + 1;
                $display("[D%0d] FAIL C%0d load sequence index=%0d expected addr=%08h actual=%08h", TEST_ID, core_id, ord, expected_addr, addr);
            end
            if (exp === 32'hxxxxxxxx || data !== exp) begin
                errors = errors + 1;
                $display("[D%0d] FAIL C%0d load addr=%08h expected=%08h actual=%08h", TEST_ID, core_id, addr, exp, data);
            end
            if (core_id == 0) begin
                c0_loads = c0_loads + 1;
                if (addr[3:2] > 3 || c0_load_mask[addr[3:2]]) errors = errors + 1;
                else c0_load_mask[addr[3:2]] = 1'b1;
            end else begin
                c1_loads = c1_loads + 1;
                if (addr[3:2] > 3 || c1_load_mask[addr[3:2]]) errors = errors + 1;
                else c1_load_mask[addr[3:2]] = 1'b1;
            end
        end
    endtask

    task check_store;
        input integer core_id;
        input [31:0] addr;
        input [31:0] data;
        reg [31:0] exp;
        integer ord;
        begin
            if (core_id == 0) begin c0_stores = c0_stores + 1; ord = c0_stores - 1; end
            else begin c1_stores = c1_stores + 1; ord = c1_stores - 1; end
            exp = expected_store(TEST_ID, core_id, addr, ord);
            begin : store_address_check
                reg [31:0] exp_addr;
                exp_addr = 32'hxxxxxxxx;
                if (TEST_ID == 2 && core_id == 0) begin
                    case (ord) 0: exp_addr=0; 1: exp_addr=4; 2: exp_addr=64; endcase
                end
                if (TEST_ID == 3 && core_id == 0 && ord == 0) exp_addr=0;
                if (TEST_ID == 3 && core_id == 1 && ord == 0) exp_addr=8;
                if (TEST_ID == 4 && core_id == 0) begin
                    case (ord) 0: exp_addr=0; 1: exp_addr=4; 2: exp_addr=0; 3: exp_addr=4; endcase
                end
                if (TEST_ID == 5 && core_id == 0) begin
                    case (ord) 0: exp_addr=0; 1: exp_addr=4; endcase
                end
                if (TEST_ID == 5 && core_id == 1 && ord == 0) exp_addr=12;
                if (addr !== exp_addr) begin
                    errors = errors + 1;
                    $display("[D%0d] FAIL C%0d store sequence index=%0d expected addr=%08h actual=%08h", TEST_ID, core_id, ord, exp_addr, addr);
                end
            end
            if (exp === 32'hxxxxxxxx || data !== exp) begin
                errors = errors + 1;
                $display("[D%0d] FAIL C%0d store addr=%08h expected=%08h actual=%08h", TEST_ID, core_id, addr, exp, data);
            end
        end
    endtask

    initial begin
        #35 rst_n = 1'b1;
        #100000;
        $display("[D%0d] FAIL timeout stores=%0d/%0d loads=%0d/%0d errors=%0d", TEST_ID, c0_stores, c1_stores, c0_loads, c1_loads, errors);
        $fatal(1, "D%0d timeout", TEST_ID);
    end

    always @(posedge clk) if (rst_n) begin
        if (dut.cache_ctrl_0.saved_wen && dut.c0_ctrl_we &&
            ((dut.cache_ctrl_0.state == 4'd2) ||
             (dut.cache_ctrl_0.state == 4'd3 && dut.c0_bus_grant) || dut.cache_ctrl_0.state == 4'd6))
            check_store(0, dut.cache_ctrl_0.saved_addr, dut.cache_ctrl_0.saved_wdata);
        if (dut.cache_ctrl_1.saved_wen && dut.c1_ctrl_we &&
            ((dut.cache_ctrl_1.state == 4'd2) ||
             (dut.cache_ctrl_1.state == 4'd3 && dut.c1_bus_grant) || dut.cache_ctrl_1.state == 4'd6))
            check_store(1, dut.cache_ctrl_1.saved_addr, dut.cache_ctrl_1.saved_wdata);

        if (dut.cache_ctrl_0.state == 4'd8 && dut.c0_cpu_ren && !dut.cache_ctrl_0.saved_wen)
            check_load(0, dut.cache_ctrl_0.saved_addr, dut.c0_cpu_rdata);
        if (dut.cache_ctrl_1.state == 4'd8 && dut.c1_cpu_ren && !dut.cache_ctrl_1.saved_wen)
            check_load(1, dut.cache_ctrl_1.saved_addr, dut.c1_cpu_rdata);

        if (TEST_ID == 2 && dut.cache_ctrl_0.state == 4'd10 && dut.c0_mem_ready && dut.cache_ctrl_0.evict_cnt == 2'd3) begin
            if (dut.c0_mem_addr[31:4] == 0) begin
                evict_a = evict_a + 1;
                if (dut.shared_mem.main_ram[0] !== 32'h135 || dut.shared_mem.main_ram[1] !== 32'h246) errors = errors + 1;
            end
            if (dut.c0_mem_addr[31:4] == 4) begin
                evict_b = evict_b + 1;
                if (dut.shared_mem.main_ram[16] !== 32'h357) errors = errors + 1;
            end
        end
        if (TEST_ID == 3 && c1_stores != 0 && dut.cache_array_0.mesi_array[0] == 2'b00)
            invalidation_seen = 1'b1;
        if (TEST_ID == 4 && dut.cache_array_0.mesi_array[0] == 2'b11 && dut.cache_array_1.mesi_array[0] == 2'b00)
            invalidation_seen = 1'b1;
        if (TEST_ID == 4 && dut.cache_array_0.mesi_array[0] == 2'b01 && dut.cache_array_1.mesi_array[0] == 2'b01)
            shared_seen = 1'b1;

        if (TEST_ID == 5 && dut.cache_ctrl_0.state == 4'd11 && dut.c0_mem_ready &&
            dut.cache_ctrl_0.flush_cnt == 2'd3 && dut.cache_ctrl_0.latched_snoop_addr[31:4] === 28'h0 &&
            dut.cache_ctrl_0.latched_snoop_cmd == 3'b010) begin
            data_flushes = data_flushes + 1;
            if (dut.shared_mem.main_ram[0] !== 32'h135 || dut.shared_mem.main_ram[1] !== 32'h246 ||
                dut.shared_mem.main_ram[2] !== 0 || dut.shared_mem.main_ram[3] !== 0) errors = errors + 1;
            else final_ram_seen = 1'b1;
        end

        if (c0_instr == 32'h0000006f && c1_instr == 32'h0000006f) begin
            if (errors != 0) $fatal(1, "D%0d data checker errors=%0d", TEST_ID, errors);
            case (TEST_ID)
                2: if (c0_stores != 3 || c0_loads != 2 || evict_a != 1 || evict_b != 1 || c0_load_mask[1:0] != 2'b11 || dut.shared_mem.main_ram[16] !== 32'h357 || dut.cache_array_0.mesi_array[0] !== 2'b10 || dut.cache_array_1.mesi_array[0] !== 2'b00) $fatal(1,"D2 acceptance failed");
                3: if (c0_stores != 1 || c1_stores != 1 || c0_loads != 2 || c1_loads != 2 || !invalidation_seen || dut.cache_array_0.mesi_array[0] !== 2'b01 || dut.cache_array_1.mesi_array[0] !== 2'b01) $fatal(1,"D3 acceptance failed");
                4: if (c0_stores != 4 || c0_loads != 2 || c1_loads != 2 || !shared_seen || !invalidation_seen || dut.cache_array_0.mesi_array[0] !== 2'b11 || dut.cache_array_1.mesi_array[0] !== 2'b00) $fatal(1,"D4 acceptance failed");
                5: if (c0_stores != 2 || c1_stores != 1 || c1_loads != 1 || data_flushes != 1 || !final_ram_seen || dut.cache_array_0.mesi_array[0] !== 2'b00 || dut.cache_array_1.mesi_array[0] !== 2'b11) $fatal(1,"D5 acceptance failed");
                default: $fatal(1,"invalid TEST_ID");
            endcase
            $display("[D%0d] PASS: data, transaction counts, and coherence checks passed.", TEST_ID);
            $finish;
        end
    end
endmodule
