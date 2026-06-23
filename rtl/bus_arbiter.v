`timescale 1ns/1ps

module bus_arbiter #(
    parameter ADDR_WIDTH = 32,
    parameter DATA_WIDTH = 32
)(
    input wire clk,
    input wire rst_n,
    
    // Giao tiếp phía Core 0 Cache Controller (Bus & Snoop)
    input  wire [2:0]            c0_bus_cmd,
    input  wire [ADDR_WIDTH-1:0] c0_bus_addr,
    input  wire [DATA_WIDTH-1:0] c0_bus_wdata,
    input  wire                  c0_bus_req,
    output reg                   c0_bus_grant,
    input  wire                  c0_snoop_hit,
    input  wire [DATA_WIDTH-1:0] c0_snoop_wdata_out,
    
    // Giao tiếp phía Core 1 Cache Controller (Bus & Snoop)
    input  wire [2:0]            c1_bus_cmd,
    input  wire [ADDR_WIDTH-1:0] c1_bus_addr,
    input  wire [DATA_WIDTH-1:0] c1_bus_wdata,
    input  wire                  c1_bus_req,
    output reg                   c1_bus_grant,
    input  wire                  c1_snoop_hit,
    input  wire [DATA_WIDTH-1:0] c1_snoop_wdata_out,
    
    // Cổng phát tín hiệu Snoop tới ngược lại Core 0
    output reg [2:0]            c0_snoop_cmd,
    output reg [ADDR_WIDTH-1:0] c0_snoop_addr,
    output wire                 c0_other_has_copy,
    output wire [DATA_WIDTH-1:0] c0_other_flush_data,
    
    // Cổng phát tín hiệu Snoop tới ngược lại Core 1
    output reg [2:0]            c1_snoop_cmd,
    output reg [ADDR_WIDTH-1:0] c1_snoop_addr,
    output wire                 c1_other_has_copy,
    output wire [DATA_WIDTH-1:0] c1_other_flush_data,

    // Giao tiếp giao lộ RAM của Core 0
    input  wire [ADDR_WIDTH-1:0] c0_mem_addr,
    input  wire [DATA_WIDTH-1:0] c0_mem_wdata,
    input  wire                  c0_mem_wen,
    input  wire                  c0_mem_ren,
    output reg                   c0_mem_ready,

    // Giao tiếp giao lộ RAM của Core 1
    input  wire [ADDR_WIDTH-1:0] c1_mem_addr,
    input  wire [DATA_WIDTH-1:0] c1_mem_wdata,
    input  wire                  c1_mem_wen,
    input  wire                  c1_mem_ren,
    output reg                   c1_mem_ready,

    // Kết nối đi thẳng tới RAM chung
    output reg  [ADDR_WIDTH-1:0] mem_addr,
    output reg  [DATA_WIDTH-1:0] mem_wdata,
    output reg                   mem_wen,
    output reg                   mem_ren,
    input  wire                  mem_ready,
    input  wire [DATA_WIDTH-1:0] mem_rdata
);

    reg last_grant; 
    reg c0_bus_grant_q, c1_bus_grant_q;

    // Các thanh ghi lưu vết (Latch) phản hồi snoop
    reg                  c0_other_has_copy_reg;
    reg [DATA_WIDTH-1:0] c0_other_flush_data_reg;
    reg                  c1_other_has_copy_reg;
    reg [DATA_WIDTH-1:0] c1_other_flush_data_reg;

    // Bộ đệm giữ lệnh ghi bộ nhớ
    reg                  wb_active;
    reg [ADDR_WIDTH-1:0] wb_addr;
    reg [DATA_WIDTH-1:0] wb_wdata;

    // 1. Khối phân xử cấp quyền Bus (Cơ chế Lock & Round-Robin)
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            c0_bus_grant <= 1'b0;
            c1_bus_grant <= 1'b0;
            last_grant   <= 1'b0;
        end else begin
            if (c0_bus_grant && c0_bus_req) begin
                c0_bus_grant <= 1'b1;
                c1_bus_grant <= 1'b0;
            end 
            else if (c1_bus_grant && c1_bus_req) begin
                c0_bus_grant <= 1'b0;
                c1_bus_grant <= 1'b1;
            end 
            else begin
                c0_bus_grant <= 1'b0;
                c1_bus_grant <= 1'b0;
                
                if (c0_bus_req && c1_bus_req) begin
                    if (last_grant == 1'b1) begin
                        c0_bus_grant <= 1'b1;
                        last_grant   <= 1'b0;
                    end else begin
                        c1_bus_grant <= 1'b1;
                        last_grant   <= 1'b1;
                    end
                end 
                else if (c0_bus_req) begin
                    c0_bus_grant <= 1'b1;
                    last_grant   <= 1'b0; // FIX BUG: Cập nhật last_grant khi Core 0 xin Bus
                end 
                else if (c1_bus_req) begin
                    c1_bus_grant <= 1'b1;
                    last_grant   <= 1'b1; // FIX BUG: Cập nhật last_grant khi Core 1 xin Bus
                end
            end
        end
    end

    wire c0_grant_edge = c0_bus_grant & ~c0_bus_grant_q;
    wire c1_grant_edge = c1_bus_grant & ~c1_bus_grant_q;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            c0_bus_grant_q <= 1'b0;
            c1_bus_grant_q <= 1'b0;
        end else begin
            c0_bus_grant_q <= c0_bus_grant;
            c1_bus_grant_q <= c1_bus_grant;
        end
    end

    // 2. MẠCH CHỐT SNOOP HIT
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            c0_other_has_copy_reg   <= 1'b0;
            c0_other_flush_data_reg <= 0;
        end else if (c0_grant_edge) begin
            c0_other_has_copy_reg   <= 1'b0;
            c0_other_flush_data_reg <= 0;
        end else if (c1_snoop_hit) begin 
            c0_other_has_copy_reg   <= 1'b1;
            c0_other_flush_data_reg <= c1_snoop_wdata_out;
        end
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            c1_other_has_copy_reg   <= 1'b0;
            c1_other_flush_data_reg <= 0;
        end else if (c1_grant_edge) begin
            c1_other_has_copy_reg   <= 1'b0;
            c1_other_flush_data_reg <= 0;
        end else if (c0_snoop_hit) begin 
            c1_other_has_copy_reg   <= 1'b1;
            c1_other_flush_data_reg <= c0_snoop_wdata_out;
        end
    end

    assign c0_other_has_copy   = c0_other_has_copy_reg | c1_snoop_hit;
    assign c0_other_flush_data = c1_snoop_hit ? c1_snoop_wdata_out : c0_other_flush_data_reg;
    assign c1_other_has_copy   = c1_other_has_copy_reg | c0_snoop_hit;
    assign c1_other_flush_data = c0_snoop_hit ? c0_snoop_wdata_out : c1_other_flush_data_reg;


    // 3. Khối điều khiển bộ đệm lệnh Ghi bộ nhớ (Snoop Writeback)
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            wb_active <= 1'b0;
            wb_addr   <= 0;
            wb_wdata  <= 0;
        end else begin
            if (!wb_active) begin
                if (c0_bus_grant_q && c1_mem_wen) begin
                    wb_active <= 1'b1; wb_addr <= c1_mem_addr; wb_wdata <= c1_mem_wdata;
                end
                else if (c1_bus_grant_q && c0_mem_wen) begin
                    wb_active <= 1'b1; wb_addr <= c0_mem_addr; wb_wdata <= c0_mem_wdata;
                end
            end else begin
                if (mem_ready) wb_active <= 1'b0;
            end
        end
    end

    // 4. Logic định tuyến chéo lệnh lệnh Snoop
    always @(*) begin
        c0_snoop_cmd = 3'b000; c0_snoop_addr = 0;
        c1_snoop_cmd = 3'b000; c1_snoop_addr = 0;
        
        if (c0_bus_grant) begin
            c1_snoop_cmd  = c0_bus_cmd; c1_snoop_addr = c0_bus_addr;
        end else if (c1_bus_grant) begin
            c0_snoop_cmd  = c1_bus_cmd; c0_snoop_addr = c1_bus_addr;
        end
    end

    // 5. CỤM GIAO LỘ ĐIỀU HƯỚNG RAM (Memory Multiplexing)
    always @(*) begin
        mem_addr     = 0; mem_wdata    = 0;
        mem_wen      = 1'b0; mem_ren      = 1'b0;
        c0_mem_ready = 1'b0; c1_mem_ready = 1'b0;

        if (wb_active) begin
            mem_addr  = wb_addr; mem_wdata = wb_wdata;
            mem_wen   = 1'b1;    mem_ren   = 1'b0;
            c0_mem_ready = mem_ready; c1_mem_ready = mem_ready;
        end 
        else if (c0_bus_grant_q && c1_mem_wen) begin
            mem_addr     = c1_mem_addr; mem_wdata    = c1_mem_wdata;
            mem_wen      = 1'b1;        mem_ren      = 1'b0;
            c0_mem_ready = 1'b0;        c1_mem_ready = mem_ready;
        end 
        else if (c1_bus_grant_q && c0_mem_wen) begin
            mem_addr     = c0_mem_addr; mem_wdata    = c0_mem_wdata;
            mem_wen      = 1'b1;        mem_ren      = 1'b0;
            c0_mem_ready = mem_ready;   c1_mem_ready = 1'b0; 
        end 
        else begin
            if (c0_bus_grant_q) begin
                mem_addr     = c0_mem_addr; mem_wdata    = c0_mem_wdata;
                mem_wen      = c0_mem_wen;  mem_ren      = c0_mem_ren;
                c0_mem_ready = mem_ready;   c1_mem_ready = 1'b0;
            end 
            else if (c1_bus_grant_q) begin
                mem_addr     = c1_mem_addr; mem_wdata    = c1_mem_wdata;
                mem_wen      = c1_mem_wen;  mem_ren      = c1_mem_ren;
                c0_mem_ready = 1'b0;        c1_mem_ready = mem_ready;
            end 
            else begin
                c0_mem_ready = mem_ready; c1_mem_ready = mem_ready;
            end
        end
    end
endmodule
