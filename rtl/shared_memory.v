`timescale 1ns/1ps

module shared_memory #(
    parameter ADDR_WIDTH = 32,
    parameter DATA_WIDTH = 32,
    parameter MEM_SIZE   = 1024   // Kích thước RAM: 1024 từ mã (Words) tương đương 4KB
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

    // ==========================================================
    // KHỞI TẠO DỮ LIỆU MỒI CHO RAM (CHỈ DÙNG TRONG MÔ PHỎNG)
    // ==========================================================
    integer i;
    initial begin
        for (i = 0; i < MEM_SIZE; i = i + 1) begin
            // Nạp giá trị ban đầu: 0xAABBCCDD cộng thêm offset là địa chỉ i
            // VD: Ô nhớ 0 chứa AABBCCDD, ô 1 chứa AABBCCDE, ô 2 chứa AABBCCDF,...
            main_ram[i] = 32'hAABBCCDD + i; 
        end
    end
    // ==========================================================

    // Khối 1: Xử lý tín hiệu điều khiển Ready (Cần reset bất đồng bộ để tránh treo mạch lúc khởi động)
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            mem_ready <= 1'b0;
        end else begin
            if (mem_wen || mem_ren) begin
                mem_ready <= 1'b1; // Báo hiệu đã xử lý xong yêu cầu RAM
            end else begin
                mem_ready <= 1'b0; // Hạ ready xuống nếu không có yêu cầu đọc/ghi
            end
        end
    end

    // Khối 2: Đọc/Ghi dữ liệu RAM tuần tự (KHÔNG ĐƯỢC chứa rst_n để Quartus hiểu đây là Block RAM thật)
    always @(posedge clk) begin
        if (mem_wen) begin
            main_ram[mem_addr[INDEX_BITS+1 : 2]] <= mem_wdata; 
        end
        if (mem_ren) begin
            mem_rdata <= main_ram[mem_addr[INDEX_BITS+1 : 2]];
        end
    end

endmodule