`timescale 1ns/1ps

module shared_memory #(
    parameter ADDR_WIDTH = 32,
    parameter DATA_WIDTH = 32,
    parameter MEM_SIZE   = 1024,  // 1024 words = 4 KB when DATA_WIDTH = 32
    parameter INIT_FILE  = ""     // Optional hexadecimal initialization file
)(
    input  wire                  clk,
    input  wire                  rst_n,
    
    // Giao tiếp Bus (Nhận duy nhất 1 luồng dữ liệu đã dồn kênh từ Arbiter)
    input  wire [ADDR_WIDTH-1:0] mem_addr,
    input  wire [DATA_WIDTH-1:0] mem_wdata,
    input  wire                  mem_wen,
    input  wire                  mem_ren,
    output reg  [DATA_WIDTH-1:0] mem_rdata,
    output reg                   mem_ready
);

    // Tự động tính số bit địa chỉ mảng (Index bits) dựa trên MEM_SIZE
    localparam INDEX_BITS = $clog2(MEM_SIZE);

    // Khai báo mảng bộ nhớ RAM (Single-port)
    // Thêm thuộc tính (* ramstyle = "M4K" *) để ép Quartus sử dụng Block RAM chuyên dụng thay vì dùng Register (Flip-flop)
    (* ramstyle = "M4K" *) reg [DATA_WIDTH-1:0] main_ram [0:MEM_SIZE-1];

    // Initialize every word to zero, then optionally load a memory image.
    integer init_idx;
    initial begin : init_main_ram
        for (init_idx = 0; init_idx < MEM_SIZE; init_idx = init_idx + 1) begin
            main_ram[init_idx] = {DATA_WIDTH{1'b0}};
        end

        if (INIT_FILE != "") begin
            $readmemh(INIT_FILE, main_ram);
        end
    end

    // Ready is a one-cycle pulse for each continuously-held request.
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            mem_ready <= 1'b0;
        end else begin
            mem_ready <= (mem_wen || mem_ren) && !mem_ready;
        end
    end

    // Perform read/write side effects only on the first request cycle,
    // when the current ready value is low.
    always @(posedge clk) begin
        if (mem_wen && !mem_ready) begin
            main_ram[mem_addr[INDEX_BITS+1:2]] <= mem_wdata;
        end

        if (mem_ren && !mem_ready) begin
            mem_rdata <= main_ram[mem_addr[INDEX_BITS+1:2]];
        end
    end

endmodule
