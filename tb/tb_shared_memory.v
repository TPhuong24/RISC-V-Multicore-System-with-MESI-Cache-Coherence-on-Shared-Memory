`timescale 1ns/1ps

module tb_shared_memory;
    reg clk = 1'b0;
    reg rst_n = 1'b0;
    reg [31:0] mem_addr = 0;
    reg [31:0] mem_wdata = 0;
    reg mem_wen = 1'b0;
    reg mem_ren = 1'b0;
    wire [31:0] mem_rdata;
    wire mem_ready;
    integer errors = 0;
    integer accepted_writes = 0;

    shared_memory #(.MEM_SIZE(16), .INIT_FILE("tb_shared_memory_init.mem")) dut (
        .clk(clk), .rst_n(rst_n), .mem_addr(mem_addr), .mem_wdata(mem_wdata),
        .mem_wen(mem_wen), .mem_ren(mem_ren), .mem_rdata(mem_rdata), .mem_ready(mem_ready)
    );

    always #5 clk = ~clk;

    always @(posedge clk) begin
        if (rst_n && mem_wen && !mem_ready)
            accepted_writes = accepted_writes + 1;
    end

    task read_word;
        input [31:0] addr;
        input [31:0] expected;
        begin
            @(negedge clk);
            mem_addr = addr;
            mem_ren = 1'b1;
            mem_wen = 1'b0;
            begin : wait_read_ready
                integer cycles;
                cycles = 0;
                while (mem_ready !== 1'b1 && cycles < 5) begin
                    @(posedge clk); #1; cycles = cycles + 1;
                end
                if (mem_ready !== 1'b1) begin
                    errors = errors + 1;
                    $display("[SHM] FAIL read timeout addr=%08h", addr);
                end else if (mem_rdata !== expected) begin
                    errors = errors + 1;
                    $display("[SHM] FAIL read addr=%08h expected=%08h actual=%08h", addr, expected, mem_rdata);
                end
            end
            @(negedge clk); mem_ren = 1'b0; mem_addr = 0;
            @(posedge clk); #1;
            if (mem_ready !== 1'b0) begin
                errors = errors + 1;
                $display("[SHM] FAIL ready did not return low after read");
            end
        end
    endtask

    task write_word;
        input [31:0] addr;
        input [31:0] data;
        integer before_count;
        begin
            before_count = accepted_writes;
            @(negedge clk);
            mem_addr = addr; mem_wdata = data; mem_wen = 1'b1; mem_ren = 1'b0;
            begin : wait_write_ready
                integer cycles;
                cycles = 0;
                while (mem_ready !== 1'b1 && cycles < 5) begin
                    @(posedge clk); #1; cycles = cycles + 1;
                end
                if (mem_ready !== 1'b1) begin
                    errors = errors + 1;
                    $display("[SHM] FAIL write timeout addr=%08h", addr);
                end
            end
            if (dut.main_ram[addr[5:2]] !== data) begin
                errors = errors + 1;
                $display("[SHM] FAIL write mapping addr=%08h expected=%08h actual=%08h", addr, data, dut.main_ram[addr[5:2]]);
            end
            @(negedge clk); mem_wen = 1'b0; mem_addr = 0; mem_wdata = 0;
            @(posedge clk); #1;
            if ((accepted_writes - before_count) != 1) begin
                errors = errors + 1;
                $display("[SHM] FAIL write side effect count expected=1 actual=%0d", accepted_writes-before_count);
            end
        end
    endtask

    initial begin
        #1;
        if (dut.main_ram[0] !== 32'h01020304 || dut.main_ram[3] !== 32'hAABBCCDD ||
            dut.main_ram[7] !== 32'h0BADF00D || dut.main_ram[8] !== 32'h00000000 ||
            dut.main_ram[15] !== 32'hAA55AA55) begin
            errors = errors + 1;
            $display("[SHM] FAIL INIT_FILE contents or word order");
        end
        repeat (2) @(posedge clk);
        #1;
        if (mem_ready !== 1'b0) begin
            errors = errors + 1;
            $display("[SHM] FAIL ready not reset low");
        end
        @(negedge clk); rst_n = 1'b1;

        // Word index is byte address [5:2], including upper-address mapping.
        read_word(32'h00000000, 32'h01020304);
        read_word(32'h0000000C, 32'hAABBCCDD);
        read_word(32'h0000003C, 32'hAA55AA55);
        read_word(32'h00000020, 32'h00000000);
        write_word(32'h00000008, 32'hC001D00D);
        read_word(32'h00000008, 32'hC001D00D);

        // Keep request asserted while changing address immediately after ready.
        // Both adjacent writes must be accepted once and in order.
        begin : adjacent_requests
            integer before_count;
            integer cycles;
            before_count = accepted_writes;
            @(negedge clk);
            mem_addr = 32'h00000004; mem_wdata = 32'hA0A0A0A0; mem_wen = 1'b1;
            cycles = 0;
            while (mem_ready !== 1'b1 && cycles < 5) begin @(posedge clk); #1; cycles=cycles+1; end
            if (mem_ready !== 1'b1) begin errors=errors+1; $display("[SHM] FAIL first adjacent request timeout"); end
            @(negedge clk);
            mem_addr = 32'h00000010; mem_wdata = 32'hB1B1B1B1;
            @(posedge clk); #1;
            if (mem_ready !== 1'b0) begin errors=errors+1; $display("[SHM] FAIL ready pulse width between adjacent requests"); end
            cycles = 0;
            while (mem_ready !== 1'b1 && cycles < 5) begin @(posedge clk); #1; cycles=cycles+1; end
            if (mem_ready !== 1'b1) begin errors=errors+1; $display("[SHM] FAIL second adjacent request timeout"); end
            if (dut.main_ram[1] !== 32'hA0A0A0A0 || dut.main_ram[4] !== 32'hB1B1B1B1) begin
                errors=errors+1;
                $display("[SHM] FAIL adjacent request mapping/order word1=%08h word4=%08h",dut.main_ram[1],dut.main_ram[4]);
            end
            @(negedge clk); mem_wen=1'b0; mem_addr=0; mem_wdata=0;
            @(posedge clk); #1;
            if ((accepted_writes-before_count) != 2) begin
                errors=errors+1;
                $display("[SHM] FAIL adjacent side effects expected=2 actual=%0d",accepted_writes-before_count);
            end
        end

        // Reset clears handshake state but does not erase the initialized RAM.
        @(negedge clk); rst_n=1'b0;
        #1;
        if (mem_ready !== 1'b0 || dut.main_ram[4] !== 32'hB1B1B1B1) begin
            errors=errors+1;
            $display("[SHM] FAIL reset interaction ready=%b retained_word=%08h",mem_ready,dut.main_ram[4]);
        end
        if (errors == 0) begin
            $display("[SHM] PASS: init, pulse handshake, held request, adjacent requests, mapping, and reset checked.");
            $finish;
        end else $fatal(1,"[SHM] %0d errors",errors);
    end
endmodule
