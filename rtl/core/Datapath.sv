`timescale 1ns / 1ps

module Datapath#(
    parameter PC_W = 32,         // Program Counter Width
    parameter INS_W = 32,        // Instruction Width
    parameter RF_ADDRESS = 5,    // Register File Address
    parameter DATA_W = 32,       // Data WriteData
    parameter DM_ADDRESS = 9,    // Data Memory Address
    parameter ALU_CC_W = 4,      // ALU Control Code Width
    parameter INIT_FILE = "default.mem" //  Tham số nhận tên file từ RISC_V
    )
    (
    // Control Signals used to control the datapath modules
    input logic 
        clk ,                    // Global clock
        reset ,                  // Reset
        RegWrite ,               // RegFile write enable
        MemtoReg ,               // MUX Select : 1 = Load Data  , 0 = ALU Result
        RegtoMem,                // MUX Select : 1 = Store Data , 0 = RegFile ReadData2
        ALUsrc ,
        MemWrite ,               // Data Memory Write Enable
        MemRead ,                // Data Memory Read  Enable

    // Control signals used for branching, jumping, and ALU operations
    input logic Con_beq,         // Branch on equal condition signal. 
    input logic Con_bnq,         // Branch on not equal condition signal. 
    input logic Con_bgt,         // Branch on greater than condition signal. 
    input logic Con_blt,         // Branch on less than condition signal.
    input logic Con_Jalr,        // Jump and link register instruction signal.
    input logic Jal,             // Jump and link instruction signal. 
    input logic AUIPC, LUI,      // AUIPC and LUI instruction signals. 
    input logic [ALU_CC_W-1:0] ALU_CC,     // ALU Control Code 

    // Output signals that will carry information about the instruction being executed
    output logic [6:0] opcode,             // Instruction opcode
    output logic [6:0] Funct7,             // Instruction funct7
    output logic [2:0] Funct3,             // Instruction funct3 

    // Result of the ALU operation
    output logic [31:0] ALU_Result,        // Result of the ALU operation

    // ====== [CHỈNH SỬA 1]: CÁC CHÂN PORT ĐỂ KẾT NỐI RA CACHE NGOẠI VI ======
    output logic [31:0] cpu_mem_addr,     // Địa chỉ gửi tới Cache
    output logic [31:0] cpu_mem_wdata,    // Dữ liệu ghi tới Cache
    output logic        cpu_mem_wen,      // Tín hiệu kích hoạt Ghi tới Cache
    output logic        cpu_mem_ren,      // Tín hiệu kích hoạt Đọc tới Cache
    input  logic [31:0] cpu_mem_rdata,    // Dữ liệu đọc từ Cache trả về CPU
    input  logic        cpu_stall         // Tín hiệu ép CPU đứng hình từ Cache (khi Cache Miss)
    );

    // Defining the datapath signals (ports)
    logic [31:0] PC, PCPlus4, PCValue, BranchPC;
    logic [31:0] Instr, PCPlusImm, PCJalr, LD, ST, Store_data;
    logic [31:0] Result;
    logic [31:0] Reg1, Reg2;
    logic [31:0] ReadData;
    logic [31:0] SrcB, ALUResult;
    logic [31:0] ExtImm;
    logic [31:0] Read_Alu_Result, Jal_test, aui_data, lui_data;
    logic [1:0] PCSel;
    logic zero, Con_BLT, Con_BGT, Jalr, Branch, branch_taken;

    assign Branch = branch_taken || Jal;
    assign Jalr = Con_Jalr;

    // Extracting the instruction opcode, funct7, and funct3 from the instruction
    assign opcode = Instr[6:0];
    assign Funct7 = Instr[31:25];
    assign Funct3 = Instr[14:12];

    // All PC arithmetic, branch/jump destinations, and links are 32-bit.
    assign PCPlus4 = PC + 32'd4;
    assign PCPlusImm = PC + ExtImm;
    assign PCJalr = (Reg1 + ExtImm) & 32'hFFFF_FFFE;
    assign BranchPC = Branch ? PCPlusImm : PCPlus4;
    assign PCValue = Jalr ? PCJalr : BranchPC;

    // Branch predicates compare source operands directly. This avoids the
    // signed-overflow bug from using the sign of (Reg1 - Reg2).
    always_comb begin
        branch_taken = 1'b0;
        if (opcode == 7'b1100011) begin
            case (Funct3)
                3'b000: branch_taken = (Reg1 == Reg2); // BEQ
                3'b001: branch_taken = (Reg1 != Reg2); // BNE
                3'b100: branch_taken = ($signed(Reg1) < $signed(Reg2)); // BLT
                3'b101: branch_taken = ($signed(Reg1) >= $signed(Reg2)); // BGE
                3'b110: branch_taken = ($unsigned(Reg1) < $unsigned(Reg2)); // BLTU
                3'b111: branch_taken = ($unsigned(Reg1) >= $unsigned(Reg2)); // BGEU
                default: branch_taken = 1'b0;
            endcase
        end
    end

    // ====== [CHỈNH SỬA 2]: ĐIỀU KHIỂN THANH GHI PC DỪNG LẠI KHI BỊ STALL ======
    // Thay thế cục flopr cũ để PC không tự tăng khi hệ thống đang bận đợi Cache gánh Miss
    always_ff @(posedge clk or posedge reset) begin
        if (reset) 
            PC <= 32'b0;
        else if (!cpu_stall) // Chỉ cập nhật PCValue mới nếu CPU KHÔNG bị stall
            PC <= PCValue;
    end

    // Instruction ROM is indexed by addr[11:2] and accepts the full PC.
    instructionmemory #(
        .INIT_FILE(INIT_FILE)
    ) instr_mem (PC, Instr);

    // Use Instr(Instruction from instruction memory) and Reg2(Data from data memory) to extract the information and assign it to ST
    data_extract store_data_ex(Instr, Reg2, ST);

    // Store_data = RegtoMem ? ST : Reg2
    mux2 #(32) resmux_store(Reg2, ST, RegtoMem, Store_data);

    // ====== [CHỈNH SỬA 3]: BẢO VỆ THANH GHI CỦA TẬP THANH GHI (REGFILE) ======
    // Nếu đang bị stall do Cache Miss, ta phải khóa chân Write Enable lại, chặn không cho ghi đè dữ liệu sai chu kỳ vào RegFile
    logic actual_reg_write;
    assign actual_reg_write = RegWrite && !cpu_stall;

    /* Define register file (rf) */
    RegFile rf(clk, reset, actual_reg_write, Instr[11:7], Instr[19:15], Instr[24:20], Result, Reg1, Reg2);

    // Use Instr(Instruction from instruction memory) and ReadData(Data from data memory) to extract the information and assign it to LD
    data_extract load_data_ex(Instr, ReadData, LD);

    // Read_ALU_Result = MemtoReg ? LD : ALUResult
    mux2 #(32) resmux(ALUResult, LD, MemtoReg, Read_Alu_Result);

    // JAL/JALR link address is the full-width PC+4.
    mux2 #(32) resmux_jal(Read_Alu_Result, PCPlus4, (Jal||Jalr), Jal_test);

    // aui_data = AUIPC ? PCPlusImm : Jal_test
    mux2 #(32) resmux_auipc(Jal_test, PCPlusImm, AUIPC, aui_data);

    // Use Instr(Instruction) to generate ExtImm(Extended Immediate Operand)
    imm_Gen Ext_Imm (Instr, ExtImm);

    // SrcB = (ALUsrc OR Jal OR Jalr) ? ExtImm : Reg2
    mux2 #(32) srcbmux(Reg2, ExtImm, (ALUsrc||Jal||Jalr), SrcB);

    /* Define ALU (alu_module) */
    alu alu_module(Reg1, SrcB, ALU_CC, ALUResult, Con_BLT, Con_BGT, zero);

    // Result = LUI ? ExtImm : aui_data
    mux2 #(32) resmux_lui(aui_data, ExtImm, LUI, Result);

    assign ALU_Result = Result;

    // ====== [CHỈNH SỬA 4]: ÁNH XẠ CHÂN RA NGOẠI VI & XÓA BỎ RAM NỘI BỘ ======
    // Đổ toàn bộ dữ liệu điều khiển bộ nhớ ra các chân Port mới để chuyển thẳng cho Cache xử lý
    assign cpu_mem_addr   = ALUResult;    // Địa chỉ đầy đủ 32-bit cho Cache phân tách Tag/Index/Offset
    assign cpu_mem_wdata  = Store_data;
    assign cpu_mem_wen    = MemWrite;
    assign cpu_mem_ren    = MemRead;
    
    // Đón nhận dữ liệu từ Cache truyền ngược vào dây nội bộ ReadData
    assign ReadData       = cpu_mem_rdata;

endmodule
