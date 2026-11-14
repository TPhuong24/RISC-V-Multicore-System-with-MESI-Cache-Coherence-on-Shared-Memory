`timescale 1ns / 1ps

module alu#(
        parameter DATA_WIDTH    = 32,
        parameter OPCODE_LENGTH = 4
        )
        (
        input logic [DATA_WIDTH-1:0]     SrcA,
        input logic [DATA_WIDTH-1:0]     SrcB,
        input logic [OPCODE_LENGTH-1:0]  Operation,

        output logic[DATA_WIDTH-1:0]     ALUResult,

        output logic Con_BLT, 
        output logic Con_BGT,
        output logic zero
        );

        always_comb begin
            ALUResult = '0;
            // Comparison flags are derived from operands, not from the sign
            // of a potentially-overflowed subtraction result.
            Con_BLT = ($signed(SrcA) < $signed(SrcB));
            Con_BGT = ($signed(SrcA) > $signed(SrcB));
            zero = (SrcA == SrcB);

            case (Operation)
                4'b0000: ALUResult = SrcA & SrcB; // AND
                4'b0001: ALUResult = SrcA | SrcB; // OR
                4'b0010: ALUResult = SrcA + SrcB; // ADD
                4'b0011: ALUResult = SrcA ^ SrcB; // XOR
                4'b0100: ALUResult = SrcA << SrcB[4:0]; // SLL
                4'b0101: ALUResult = ($unsigned(SrcA) < $unsigned(SrcB)); // SLTU
                4'b0110: ALUResult = SrcA - SrcB; // SUB
                4'b0111: ALUResult = SrcA - SrcB; // legacy unsigned SUB encoding
                4'b1000: ALUResult = SrcA >> SrcB[4:0]; // SRL
                4'b1010: ALUResult = ($signed(SrcA) < $signed(SrcB)); // SLT
                4'b1100: begin
                    if (SrcB[4:0] == 5'd0)
                        ALUResult = SrcA;
                    else if (SrcA[DATA_WIDTH-1] == 1'b1)
                        ALUResult = (SrcA >> SrcB[4:0])
                                  | ({DATA_WIDTH{1'b1}} << (DATA_WIDTH - SrcB[4:0]));
                    else
                        ALUResult = SrcA >> SrcB[4:0];
                end // SRA
                default: ALUResult = '0;
            endcase
        end
endmodule
