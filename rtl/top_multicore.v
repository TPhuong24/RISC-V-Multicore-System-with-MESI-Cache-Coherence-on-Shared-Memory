// =============================================================================
// top_multicore.v — TOP MODULE HOÀN CHỈNH KẾT NỐI HỆ THỐNG ĐA LÕI ĐA CACHE MESI
// =============================================================================
`timescale 1ns/1ps

module top_multicore (
    input  wire clk,
    input  wire rst_n,
    
    // ====== [CHỈNH SỬA QUAN TRỌNG]: THÊM OUTPUT ĐỂ QUARTUS KHÔNG XÓA MẠCH ======
    output wire [31:0] out_core0_wb_data,
    output wire [31:0] out_core1_wb_data
);
    // -------------------------------------------------------------------------
    // CÁC ĐƯỜNG DÂY LIÊN KẾT LIÊN NHÂN (CORE <--> CACHE CONTROLLER)
    // -------------------------------------------------------------------------
    // Core 0
    wire [31:0] c0_cpu_addr, c0_cpu_wdata, c0_cpu_rdata;
    wire        c0_cpu_wen, c0_cpu_ren, c0_cpu_stall;
    // Core 1
    wire [31:0] c1_cpu_addr, c1_cpu_wdata, c1_cpu_rdata;
    wire        c1_cpu_wen, c1_cpu_ren, c1_cpu_stall;

    // Tín hiệu nội bộ giữa Cache Controller và Mảng Cache lưu trữ (Cache Array)
    // Core 0 Cache internal wires
    wire [1:0]  c0_ctrl_index, c0_ctrl_offset; wire [25:0] c0_ctrl_tag_in, c0_ctrl_tag_out;
    wire [31:0] c0_ctrl_wdata, c0_ctrl_rdata; wire [1:0]  c0_ctrl_mesi_in, c0_ctrl_mesi_out;
    wire        c0_ctrl_we, c0_ctrl_tag_we, c0_ctrl_dirty_we, c0_ctrl_mesi_we;
    wire        c0_ctrl_valid_out, c0_ctrl_dirty_out, c0_ctrl_dirty_in;
    wire [1:0]  c0_snoop_index; wire [1:0]  c0_snoop_mesi_out;
    
    wire [25:0] c0_snoop_tag_out;
    wire        c0_snoop_valid_out, c0_snoop_dirty_out;
    wire        c0_cache_hit;

    // Core 1 Cache internal wires
    wire [1:0]  c1_ctrl_index, c1_ctrl_offset; wire [25:0] c1_ctrl_tag_in, c1_ctrl_tag_out;
    wire [31:0] c1_ctrl_wdata, c1_ctrl_rdata; wire [1:0]  c1_ctrl_mesi_in, c1_ctrl_mesi_out;
    wire        c1_ctrl_we, c1_ctrl_tag_we, c1_ctrl_dirty_we, c1_ctrl_mesi_we;
    wire        c1_ctrl_valid_out, c1_ctrl_dirty_out, c1_ctrl_dirty_in;
    wire [1:0]  c1_snoop_index; wire [1:0]  c1_snoop_mesi_out;
    
    wire [25:0] c1_snoop_tag_out;
    wire        c1_snoop_valid_out, c1_snoop_dirty_out;
    wire        c1_cache_hit;

    // -------------------------------------------------------------------------
    // CÁC ĐƯỜNG DÂY LIÊN KẾT HỆ THỐNG BUS VÀ TRUY XUẤT RAM
    // -------------------------------------------------------------------------
    wire [2:0]  c0_bus_cmd;   wire [31:0] c0_bus_addr, c0_bus_wdata; wire c0_bus_req, c0_bus_grant;
    wire [2:0]  c0_snoop_cmd; wire [31:0] c0_snoop_addr; wire c0_snoop_hit, c0_other_has_copy;
    wire [31:0] c0_snoop_wdata_out, c0_other_flush_data;
    wire [31:0] c0_mem_addr, c0_mem_wdata, c0_mem_rdata; wire c0_mem_wen, c0_mem_ren, c0_mem_ready;

    wire [2:0]  c1_bus_cmd;   wire [31:0] c1_bus_addr, c1_bus_wdata; wire c1_bus_req, c1_bus_grant;
    wire [2:0]  c1_snoop_cmd; wire [31:0] c1_snoop_addr; wire c1_snoop_hit, c1_other_has_copy;
    wire [31:0] c1_snoop_wdata_out, c1_other_flush_data;
    wire [31:0] c1_mem_addr, c1_mem_wdata, c1_mem_rdata; wire c1_mem_wen, c1_mem_ren, c1_mem_ready;

    // ====== ĐƯỜNG DÂY BUS CHÍNH (MASTER BUS) SAU KHI QUA ARBITER ======
    wire [31:0] bus_mem_addr, bus_mem_wdata, bus_mem_rdata;
    wire        bus_mem_wen, bus_mem_ren, bus_mem_ready;

    assign c0_mem_rdata = bus_mem_rdata;
    assign c1_mem_rdata = bus_mem_rdata;

    // -------------------------------------------------------------------------
    // LÕI XỬ LÝ SỐ 0 (CORE 0) VÀ KHỐI L1 CACHE 0
    // -------------------------------------------------------------------------
    RISC_V #(
        .INIT_FILE("core0_test.mem")
    ) core_0 (
        .clk(clk), .reset(~rst_n),
        .cpu_mem_addr(c0_cpu_addr), .cpu_mem_wdata(c0_cpu_wdata),
        .cpu_mem_wen(c0_cpu_wen), .cpu_mem_ren(c0_cpu_ren),
        .cpu_mem_rdata(c0_cpu_rdata), .cpu_stall(c0_cpu_stall),
        .WB_Data(out_core0_wb_data) // KHÔNG ĐƯỢC BỎ TRỐNG CỔNG NÀY NỮA
    );

    cache_controller cache_ctrl_0 (
        .clk(clk), .rst_n(rst_n),
        .cpu_addr(c0_cpu_addr), .cpu_wdata(c0_cpu_wdata), .cpu_wen(c0_cpu_wen), .cpu_ren(c0_cpu_ren),
        .cpu_stall(c0_cpu_stall), .cpu_done(),
        
        .ctrl_index(c0_ctrl_index), .ctrl_offset(c0_ctrl_offset), .ctrl_rdata(c0_ctrl_rdata),
        .ctrl_wdata(c0_ctrl_wdata), .ctrl_we(c0_ctrl_we), .ctrl_tag_in(c0_ctrl_tag_in),
        .ctrl_tag_out(c0_ctrl_tag_out), .ctrl_tag_we(c0_ctrl_tag_we), .ctrl_valid_out(c0_ctrl_valid_out),
        .ctrl_dirty_in(c0_ctrl_dirty_in), .ctrl_dirty_out(c0_ctrl_dirty_out), .ctrl_dirty_we(c0_ctrl_dirty_we),
        .ctrl_mesi_in(c0_ctrl_mesi_in), .ctrl_mesi_out(c0_ctrl_mesi_out), .ctrl_mesi_we(c0_ctrl_mesi_we),
        .cache_hit(c0_cache_hit),
        
        .snoop_index(c0_snoop_index), 
        .snoop_tag_out(c0_snoop_tag_out), 
        .snoop_mesi_out(c0_snoop_mesi_out), 
        .snoop_valid_out(c0_snoop_valid_out), 
        .snoop_dirty_out(c0_snoop_dirty_out),
        
        .snoop_cmd(c0_snoop_cmd), .snoop_addr(c0_snoop_addr), .snoop_hit(c0_snoop_hit),
        .snoop_wdata_out(c0_snoop_wdata_out), .snoop_ack(),
        .other_has_copy(c0_other_has_copy), .other_flush_data(c0_other_flush_data),
        
        .bus_cmd(c0_bus_cmd), .bus_addr(c0_bus_addr), .bus_wdata(c0_bus_wdata),
        .bus_req(c0_bus_req), .bus_grant(c0_bus_grant),
        
        .mem_addr(c0_mem_addr), .mem_wdata(c0_mem_wdata), .mem_rdata(c0_mem_rdata),
        .mem_wen(c0_mem_wen), .mem_ren(c0_mem_ren), .mem_ready(c0_mem_ready)
    );

    cache cache_array_0 (
        .clk(clk), .rst_n(rst_n),
        .cpu_addr(c0_cpu_addr), .cpu_wdata(c0_cpu_wdata), .cpu_wen(c0_cpu_wen), .cpu_ren(c0_cpu_ren),
        .cpu_rdata(c0_cpu_rdata), .cpu_hit(c0_cache_hit),
        
        .ctrl_index(c0_ctrl_index), .ctrl_offset(c0_ctrl_offset), .ctrl_wdata(c0_ctrl_wdata),
        .ctrl_we(c0_ctrl_we), .ctrl_tag_in(c0_ctrl_tag_in), .ctrl_tag_we(c0_ctrl_tag_we),
        .ctrl_dirty_in(c0_ctrl_dirty_in), .ctrl_dirty_we(c0_ctrl_dirty_we), .ctrl_mesi_in(c0_ctrl_mesi_in),
        .ctrl_mesi_we(c0_ctrl_mesi_we), .ctrl_tag_out(c0_ctrl_tag_out), .ctrl_valid_out(c0_ctrl_valid_out),
        .ctrl_dirty_out(c0_ctrl_dirty_out), .ctrl_mesi_out(c0_ctrl_mesi_out), .ctrl_rdata(c0_ctrl_rdata),
        
        .snoop_index(c0_snoop_index), 
        .snoop_tag_out(c0_snoop_tag_out), 
        .snoop_mesi_out(c0_snoop_mesi_out),
        .snoop_valid_out(c0_snoop_valid_out), 
        .snoop_dirty_out(c0_snoop_dirty_out)
    );

    // -------------------------------------------------------------------------
    // LÕI XỬ LÝ SỐ 1 (CORE 1) VÀ KHỐI L1 CACHE 1
    // -------------------------------------------------------------------------
    RISC_V #(
        .INIT_FILE("core1_test.mem")
    ) core_1 (
        .clk(clk), .reset(~rst_n),
        .cpu_mem_addr(c1_cpu_addr), .cpu_mem_wdata(c1_cpu_wdata),
        .cpu_mem_wen(c1_cpu_wen), .cpu_mem_ren(c1_cpu_ren),
        .cpu_mem_rdata(c1_cpu_rdata), .cpu_stall(c1_cpu_stall),
        .WB_Data(out_core1_wb_data) // KHÔNG ĐƯỢC BỎ TRỐNG CỔNG NÀY NỮA
    );

    cache_controller cache_ctrl_1 (
        .clk(clk), .rst_n(rst_n),
        .cpu_addr(c1_cpu_addr), .cpu_wdata(c1_cpu_wdata), .cpu_wen(c1_cpu_wen), .cpu_ren(c1_cpu_ren),
        .cpu_stall(c1_cpu_stall), .cpu_done(),
        
        .ctrl_index(c1_ctrl_index), .ctrl_offset(c1_ctrl_offset), .ctrl_rdata(c1_ctrl_rdata),
        .ctrl_wdata(c1_ctrl_wdata), .ctrl_we(c1_ctrl_we), .ctrl_tag_in(c1_ctrl_tag_in),
        .ctrl_tag_out(c1_ctrl_tag_out), .ctrl_tag_we(c1_ctrl_tag_we), .ctrl_valid_out(c1_ctrl_valid_out),
        .ctrl_dirty_in(c1_ctrl_dirty_in), .ctrl_dirty_out(c1_ctrl_dirty_out), .ctrl_dirty_we(c1_ctrl_dirty_we),
        .ctrl_mesi_in(c1_ctrl_mesi_in), .ctrl_mesi_out(c1_ctrl_mesi_out), .ctrl_mesi_we(c1_ctrl_mesi_we),
        .cache_hit(c1_cache_hit),
        
        .snoop_index(c1_snoop_index), 
        .snoop_tag_out(c1_snoop_tag_out), 
        .snoop_mesi_out(c1_snoop_mesi_out), 
        .snoop_valid_out(c1_snoop_valid_out), 
        .snoop_dirty_out(c1_snoop_dirty_out),
        
        .snoop_cmd(c1_snoop_cmd), .snoop_addr(c1_snoop_addr), .snoop_hit(c1_snoop_hit),
        .snoop_wdata_out(c1_snoop_wdata_out), .snoop_ack(),
        .other_has_copy(c1_other_has_copy), .other_flush_data(c1_other_flush_data),
        
        .bus_cmd(c1_bus_cmd), .bus_addr(c1_bus_addr), .bus_wdata(c1_bus_wdata),
        .bus_req(c1_bus_req), .bus_grant(c1_bus_grant),
        
        .mem_addr(c1_mem_addr), .mem_wdata(c1_mem_wdata), .mem_rdata(c1_mem_rdata),
        .mem_wen(c1_mem_wen), .mem_ren(c1_mem_ren), .mem_ready(c1_mem_ready)
    );

    cache cache_array_1 (
        .clk(clk), .rst_n(rst_n),
        .cpu_addr(c1_cpu_addr), .cpu_wdata(c1_cpu_wdata), .cpu_wen(c1_cpu_wen), .cpu_ren(c1_cpu_ren),
        .cpu_rdata(c1_cpu_rdata), .cpu_hit(c1_cache_hit),
        
        .ctrl_index(c1_ctrl_index), .ctrl_offset(c1_ctrl_offset), .ctrl_wdata(c1_ctrl_wdata),
        .ctrl_we(c1_ctrl_we), .ctrl_tag_in(c1_ctrl_tag_in), .ctrl_tag_we(c1_ctrl_tag_we),
        .ctrl_dirty_in(c1_ctrl_dirty_in), .ctrl_dirty_we(c1_ctrl_dirty_we), .ctrl_mesi_in(c1_ctrl_mesi_in),
        .ctrl_mesi_we(c1_ctrl_mesi_we), .ctrl_tag_out(c1_ctrl_tag_out), .ctrl_valid_out(c1_ctrl_valid_out),
        .ctrl_dirty_out(c1_ctrl_dirty_out), .ctrl_mesi_out(c1_ctrl_mesi_out), .ctrl_rdata(c1_ctrl_rdata),
        
        .snoop_index(c1_snoop_index), 
        .snoop_tag_out(c1_snoop_tag_out), 
        .snoop_mesi_out(c1_snoop_mesi_out),
        .snoop_valid_out(c1_snoop_valid_out), 
        .snoop_dirty_out(c1_snoop_dirty_out)
    );

    // -------------------------------------------------------------------------
    // KHỞI TẠO BỘ PHÂN XỬ BUS VÀ BỘ NHỚ DÙNG CHUNG CHÍNH (SHARED MAIN RAM)
    // -------------------------------------------------------------------------
    bus_arbiter bus_arb (
        .clk(clk), .rst_n(rst_n),
        
        .c0_bus_cmd(c0_bus_cmd), .c0_bus_addr(c0_bus_addr), .c0_bus_wdata(c0_bus_wdata),
        .c0_bus_req(c0_bus_req), .c0_bus_grant(c0_bus_grant), .c0_snoop_hit(c0_snoop_hit),
        .c0_snoop_wdata_out(c0_snoop_wdata_out),
        
        .c1_bus_cmd(c1_bus_cmd), .c1_bus_addr(c1_bus_addr), .c1_bus_wdata(c1_bus_wdata),
        .c1_bus_req(c1_bus_req), .c1_bus_grant(c1_bus_grant), .c1_snoop_hit(c1_snoop_hit),
        .c1_snoop_wdata_out(c1_snoop_wdata_out),
        
        .c0_snoop_cmd(c0_snoop_cmd), .c0_snoop_addr(c0_snoop_addr),
        .c0_other_has_copy(c0_other_has_copy), .c0_other_flush_data(c0_other_flush_data),
        
        .c1_snoop_cmd(c1_snoop_cmd), .c1_snoop_addr(c1_snoop_addr),
        .c1_other_has_copy(c1_other_has_copy), .c1_other_flush_data(c1_other_flush_data),

        .c0_mem_addr(c0_mem_addr), .c0_mem_wdata(c0_mem_wdata),
        .c0_mem_wen(c0_mem_wen), .c0_mem_ren(c0_mem_ren), .c0_mem_ready(c0_mem_ready),

        .c1_mem_addr(c1_mem_addr), .c1_mem_wdata(c1_mem_wdata),
        .c1_mem_wen(c1_mem_wen), .c1_mem_ren(c1_mem_ren), .c1_mem_ready(c1_mem_ready),

        .mem_addr(bus_mem_addr),
        .mem_wdata(bus_mem_wdata),
        .mem_wen(bus_mem_wen),
        .mem_ren(bus_mem_ren),
        .mem_ready(bus_mem_ready),
        .mem_rdata(bus_mem_rdata)
    );

    shared_memory shared_mem (
        .clk(clk), 
        .rst_n(rst_n),
        
        .mem_addr(bus_mem_addr), 
        .mem_wdata(bus_mem_wdata), 
        .mem_wen(bus_mem_wen), 
        .mem_ren(bus_mem_ren),
        .mem_rdata(bus_mem_rdata), 
        .mem_ready(bus_mem_ready)
    );

endmodule