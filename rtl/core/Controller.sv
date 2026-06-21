`timescale 1ns / 1ps

module Controller 
(
    // Input to Controller is the 7-bit opcode from instruction
    input  logic [6:0] Opcode, 

    // Output from Controller are the control signals
    output logic ALUSrc, 
    output logic MemtoReg, 
    output logic RegtoMem, 
    output logic RegWrite, 
    output logic MemRead, 
    output logic MemWrite, 
    output logic Branch,
    output logic [1:0] ALUOp,
    output logic Con_Jalr, Con_Jal, Mem, OpI, Con_AUIPC, Con_LUI
);

    // Biến tổ hợp tạm thời chứa 15 bit cấu hình
    logic [14:0] ctrl_bits;

    // Khối case tổ hợp - Chuẩn hóa mạch giải mã không bao giờ lo bị Latch
    always_comb begin
        case (Opcode)
            7'b0110011: ctrl_bits = 15'b000100010000000; // R_TYPE
            7'b0000011: ctrl_bits = 15'b110110000001000; // LW
            7'b0100011: ctrl_bits = 15'b101001000001000; // SW
            7'b0010011: ctrl_bits = 15'b100100000000100; // RI_TYPE
            7'b1100011: ctrl_bits = 15'b000000101000000; // BR_TYPE
            7'b1100111: ctrl_bits = 15'b000101000100000; // JALR
            7'b1101111: ctrl_bits = 15'b000100000010000; // JAL
            7'b0010111: ctrl_bits = 15'b000000000000010; // AUIPC
            7'b0110111: ctrl_bits = 15'b000000000000001; // LUI
            default:    ctrl_bits = 15'b000000000000000; // Tránh Latch tuyệt đối cho các Opcode lạ
        endcase
    end

    // Ánh xạ trực tiếp từ biến tạm ra các cổng Output của Controller
    assign ALUSrc    =  ctrl_bits[14];
    assign MemtoReg  =  ctrl_bits[13];
    assign RegtoMem  =  ctrl_bits[12];
    assign RegWrite  =  ctrl_bits[11];
    assign MemRead   =  ctrl_bits[10];
    assign MemWrite  =  ctrl_bits[9];
    assign Branch    =  ctrl_bits[8];
    assign ALUOp     =  ctrl_bits[7:6];
    assign Con_Jalr  =  ctrl_bits[5];
    assign Con_Jal   =  ctrl_bits[4];
    assign Mem       =  ctrl_bits[3];
    assign OpI       =  ctrl_bits[2];
    assign Con_AUIPC =  ctrl_bits[1];
    assign Con_LUI   =  ctrl_bits[0];

endmodule