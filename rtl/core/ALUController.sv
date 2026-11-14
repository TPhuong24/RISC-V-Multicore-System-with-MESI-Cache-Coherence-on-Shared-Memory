`timescale 1ns / 1ps

module ALUController
(

    input logic [1:0] ALUOp, 
    input logic [6:0] Funct7,  
    input logic [2:0] Funct3,  
    input Branch,
    input Mem,OpI,AUIPC,

    output logic [3:0] Operation,   // Control signal that determines the ALU operation
    output logic Con_beq, Con_bnq, Con_blt, Con_bgt
);

    // Operation encoding is shared with alu.sv. Defaults are deterministic
    // for unsupported encodings and never infer latches.
    always_comb begin
        Operation = 4'b0010; // ADD (also the address operation for LW/SW)
        Con_beq = 1'b0;
        Con_bnq = 1'b0;
        Con_blt = 1'b0;
        Con_bgt = 1'b0;

        if (Branch) begin
            Con_beq = (Funct3 == 3'b000);
            Con_bnq = (Funct3 == 3'b001);
            Con_blt = (Funct3 == 3'b100) || (Funct3 == 3'b110);
            Con_bgt = (Funct3 == 3'b101) || (Funct3 == 3'b111);
        end

        case (ALUOp)
            2'b00: begin
                // Loads/stores and upper-immediate PC plumbing use ADD.
                if (OpI) begin
                    case (Funct3)
                        3'b000: Operation = 4'b0010; // ADDI
                        3'b010: Operation = 4'b1010; // SLTI
                        3'b011: Operation = 4'b0101; // SLTIU
                        3'b100: Operation = 4'b0011; // XORI
                        3'b110: Operation = 4'b0001; // ORI
                        3'b111: Operation = 4'b0000; // ANDI
                        3'b001: Operation = 4'b0100; // SLLI
                        3'b101: begin
                            if (Funct7[5])
                                Operation = 4'b1100; // SRAI
                            else
                                Operation = 4'b1000; // SRLI
                        end
                        default: Operation = 4'b0010;
                    endcase
                end
            end
            2'b01: begin
                // Branch decision itself is made from the source operands in
                // Datapath; SUB remains useful for the observable ALU result.
                Operation = 4'b0110;
            end
            2'b10: begin
                case (Funct3)
                    3'b000: begin
                        if (Funct7 == 7'b0100000)
                            Operation = 4'b0110; // SUB
                        else
                            Operation = 4'b0010; // ADD
                    end
                    3'b001: Operation = 4'b0100; // SLL
                    3'b010: Operation = 4'b1010; // SLT
                    3'b011: Operation = 4'b0101; // SLTU
                    3'b100: Operation = 4'b0011; // XOR
                    3'b101: begin
                        if (Funct7 == 7'b0100000)
                            Operation = 4'b1100; // SRA
                        else
                            Operation = 4'b1000; // SRL
                    end
                    3'b110: Operation = 4'b0001; // OR
                    3'b111: Operation = 4'b0000; // AND
                    default: Operation = 4'b0010;
                endcase
            end
            default: Operation = 4'b0010;
        endcase
    end

endmodule
