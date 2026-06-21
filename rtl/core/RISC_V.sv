`timescale 1ns / 1ps

module RISC_V#(
    parameter DATA_W = 32,
    parameter INIT_FILE = "default.mem" // NHẬN TÊN FILE 
    )
    (
    input  logic clk, reset,      // Clock and reset
    output logic [31:0] WB_Data,  // The ALU_Result

    // ====== [BỔ SUNG]: CÁC CHÂN PORT ĐỂ GIAO TIẾP VỚI HỆ THỐNG CACHE NGOẠI VI ======
    output logic [31:0] cpu_mem_addr,   // Địa chỉ đầy đủ từ CPU gửi tới Cache
    output logic [31:0] cpu_mem_wdata,  // Dữ liệu ghi từ CPU tới Cache
    output logic        cpu_mem_wen,    // Tín hiệu kích hoạt Ghi bộ nhớ (MemWrite)
    output logic        cpu_mem_ren,    // Tín hiệu kích hoạt Đọc bộ nhớ (MemRead)
    input  logic [31:0] cpu_mem_rdata,  // Dữ liệu đọc được từ Cache trả về cho CPU
    input  logic        cpu_stall       // Tín hiệu từ bộ điều khiển Cache ép CPU đứng hình (khi bị Miss)
    );

    logic [6:0] opcode;
    logic ALUSrc, MemtoReg, RegtoMem, RegWrite, MemRead, MemWrite, Con_Jalr;
    logic Con_beq, Con_bnq, Con_bgt, Con_blt, Con_Jal, Branch, Mem, OpI, AUIPC, LUI;

    logic [1:0] ALUop;
    logic [6:0] Funct7;
    logic [2:0] Funct3;
    logic [3:0] Operation; 
        
    // Giữ nguyên khối Controller theo đúng thiết kế gốc của bạn
    Controller c(opcode, ALUSrc, MemtoReg, RegtoMem, RegWrite, MemRead, MemWrite, Branch, ALUop, Con_Jalr, Con_Jal, Mem, OpI, AUIPC, LUI);

    // Giữ nguyên khối ALUController theo đúng thiết kế gốc của bạn
    ALUController ac(ALUop, Funct7, Funct3, Branch, Mem, OpI, AUIPC, Operation, Con_beq, Con_bnq, Con_blt, Con_bgt);

    // ====== [CẬP NHẬT CHUYÊN NGHIỆP]: KẾT NỐI VÀO DATAPATH THEO TÊN PORT ======
    // Việc gọi tên chân cụ thể giúp hệ thống không bao giờ bị nhận nhầm dây khi bạn thêm bớt cổng ngoại vi
    Datapath #(
        .INIT_FILE(INIT_FILE) // <--- TRUYỀN TIẾP TÊN FILE XUỐNG CHO DATAPATH
    ) dp (
        .clk(clk),
        .reset(reset),
        .RegWrite(RegWrite),
        .MemtoReg(MemtoReg),
        .RegtoMem(RegtoMem),
        .ALUsrc(ALUSrc),
        .MemWrite(MemWrite),
        .MemRead(MemRead),
        .Con_beq(Con_beq),
        .Con_bnq(Con_bnq),
        .Con_bgt(Con_bgt),
        .Con_blt(Con_blt),
        .Con_Jalr(Con_Jalr),
        .Jal(Con_Jal),
        .AUIPC(AUIPC),
        .LUI(LUI),
        .ALU_CC(Operation),
        .opcode(opcode),
        .Funct7(Funct7),
        .Funct3(Funct3),
        .ALU_Result(WB_Data),

        // Đấu nối 6 chân chức năng kết nối với tầng đệm Cache và điều khiển mạch Stall
        .cpu_mem_addr(cpu_mem_addr),
        .cpu_mem_wdata(cpu_mem_wdata),
        .cpu_mem_wen(cpu_mem_wen),
        .cpu_mem_ren(cpu_mem_ren),
        .cpu_mem_rdata(cpu_mem_rdata),
        .cpu_stall(cpu_stall)
    );

endmodule