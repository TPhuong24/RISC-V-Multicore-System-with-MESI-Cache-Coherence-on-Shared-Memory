`timescale 1ns / 1ps

module instructionmemory #(
    parameter ADDR_WIDTH = 32,
    parameter DATA_WIDTH = 32,
    parameter INIT_FILE  = ""
)(
    input  wire [ADDR_WIDTH-1:0] addr,
    output wire [DATA_WIDTH-1:0] instr
);
    // 1024 words (4KB ROM)
    reg [DATA_WIDTH-1:0] rom [0:1023];

    initial begin
        if (INIT_FILE != "") begin
            $readmemh(INIT_FILE, rom);
        end
    end

    // Dịch địa chỉ (Word-aligned)
    assign instr = rom[addr[11:2]]; 

endmodule