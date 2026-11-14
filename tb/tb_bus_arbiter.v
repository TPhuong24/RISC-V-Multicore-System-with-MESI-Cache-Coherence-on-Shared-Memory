`timescale 1ns/1ps

module tb_bus_arbiter;
    reg clk=0, rst_n=0;
    reg [2:0] c0_bus_cmd=0, c1_bus_cmd=0;
    reg [31:0] c0_bus_addr=0, c1_bus_addr=0, c0_bus_wdata=0, c1_bus_wdata=0;
    reg c0_bus_req=0, c1_bus_req=0;
    wire c0_bus_grant, c1_bus_grant;
    reg c0_snoop_hit=0, c1_snoop_hit=0;
    reg [31:0] c0_snoop_wdata_out=0, c1_snoop_wdata_out=0;
    reg c0_snoop_busy=0, c1_snoop_busy=0;
    wire [2:0] c0_snoop_cmd, c1_snoop_cmd;
    wire [31:0] c0_snoop_addr, c1_snoop_addr;
    wire c0_other_has_copy, c1_other_has_copy;
    wire [31:0] c0_other_flush_data, c1_other_flush_data;
    reg [31:0] c0_mem_addr=0, c1_mem_addr=0, c0_mem_wdata=0, c1_mem_wdata=0;
    reg c0_mem_wen=0, c0_mem_ren=0, c1_mem_wen=0, c1_mem_ren=0;
    wire c0_mem_ready, c1_mem_ready;
    wire [31:0] mem_addr, mem_wdata, mem_rdata;
    wire mem_wen, mem_ren, mem_ready;
    integer accepted_ram_writes=0;
    integer errors=0;

    bus_arbiter dut (
        .clk(clk), .rst_n(rst_n),
        .c0_bus_cmd(c0_bus_cmd), .c0_bus_addr(c0_bus_addr), .c0_bus_wdata(c0_bus_wdata),
        .c0_bus_req(c0_bus_req), .c0_bus_grant(c0_bus_grant), .c0_snoop_hit(c0_snoop_hit),
        .c0_snoop_wdata_out(c0_snoop_wdata_out), .c0_snoop_busy(c0_snoop_busy),
        .c1_bus_cmd(c1_bus_cmd), .c1_bus_addr(c1_bus_addr), .c1_bus_wdata(c1_bus_wdata),
        .c1_bus_req(c1_bus_req), .c1_bus_grant(c1_bus_grant), .c1_snoop_hit(c1_snoop_hit),
        .c1_snoop_wdata_out(c1_snoop_wdata_out), .c1_snoop_busy(c1_snoop_busy),
        .c0_snoop_cmd(c0_snoop_cmd), .c0_snoop_addr(c0_snoop_addr),
        .c0_other_has_copy(c0_other_has_copy), .c0_other_flush_data(c0_other_flush_data),
        .c1_snoop_cmd(c1_snoop_cmd), .c1_snoop_addr(c1_snoop_addr),
        .c1_other_has_copy(c1_other_has_copy), .c1_other_flush_data(c1_other_flush_data),
        .c0_mem_addr(c0_mem_addr), .c0_mem_wdata(c0_mem_wdata), .c0_mem_wen(c0_mem_wen),
        .c0_mem_ren(c0_mem_ren), .c0_mem_ready(c0_mem_ready),
        .c1_mem_addr(c1_mem_addr), .c1_mem_wdata(c1_mem_wdata), .c1_mem_wen(c1_mem_wen),
        .c1_mem_ren(c1_mem_ren), .c1_mem_ready(c1_mem_ready),
        .mem_addr(mem_addr), .mem_wdata(mem_wdata), .mem_wen(mem_wen), .mem_ren(mem_ren),
        .mem_ready(mem_ready), .mem_rdata(mem_rdata)
    );

    shared_memory #(.MEM_SIZE(16), .INIT_FILE("tb_shared_memory_init.mem")) ram (
        .clk(clk), .rst_n(rst_n), .mem_addr(mem_addr), .mem_wdata(mem_wdata),
        .mem_wen(mem_wen), .mem_ren(mem_ren), .mem_rdata(mem_rdata), .mem_ready(mem_ready)
    );

    always #5 clk=~clk;
    always @(posedge clk) if (rst_n && mem_wen && !mem_ready) accepted_ram_writes=accepted_ram_writes+1;

    task wait_c0_owner;
        integer n;
        begin
            n=0;
            while (dut.c0_bus_grant_q !== 1'b1 && n<8) begin @(posedge clk); #1; n=n+1; end
            if (dut.c0_bus_grant_q !== 1'b1) begin errors=errors+1; $display("[BUS] FAIL Core0 grant timeout"); end
        end
    endtask
    task wait_c1_owner;
        integer n;
        begin
            n=0;
            while (dut.c1_bus_grant_q !== 1'b1 && n<8) begin @(posedge clk); #1; n=n+1; end
            if (dut.c1_bus_grant_q !== 1'b1) begin errors=errors+1; $display("[BUS] FAIL Core1 grant timeout"); end
        end
    endtask
    task release_bus;
        begin
            @(negedge clk);
            c0_bus_req=0; c1_bus_req=0; c0_mem_ren=0; c1_mem_ren=0;
            c0_mem_wen=0; c1_mem_wen=0; c0_snoop_busy=0; c1_snoop_busy=0;
            repeat(3) begin @(posedge clk); #1; end
        end
    endtask

    initial begin
        repeat(2) @(posedge clk);
        @(negedge clk); rst_n=1;

        // Establish a known previous read value so the busy windows can prove
        // that an owner cannot consume stale RAM data as a completed response.
        @(negedge clk);
        c0_bus_req=1; c0_bus_cmd=3'b001; c0_bus_addr=4;
        c0_mem_addr=4; c0_mem_ren=1;
        wait_c0_owner();
        begin : prime_read_data
            integer n; n=0;
            while (c0_mem_ready !== 1'b1 && n<8) begin @(posedge clk); #1; n=n+1; end
            if (c0_mem_ready !== 1'b1 || mem_rdata !== 32'h11223344) begin
                errors=errors+1; $display("[BUS] FAIL could not prime known previous RAM data");
            end
        end
        release_bus();

        // Core 0 owns the bus. Core 1 busy must block the owner's RAM read/ready.
        @(negedge clk);
        c0_bus_req=1; c0_bus_cmd=3'b001; c0_bus_addr=0;
        c0_mem_addr=0; c0_mem_ren=1; c1_snoop_busy=1;
        wait_c0_owner();
        repeat(3) begin
            @(posedge clk); #1;
            if (mem_ren !== 1'b0 || c0_mem_ready !== 1'b0) begin
                errors=errors+1; $display("[BUS] FAIL C0 owner was not stalled by C1 snoop_busy");
            end
        end
        if (mem_rdata !== 32'h11223344) begin
            errors=errors+1; $display("[BUS] FAIL stale/unknown RAM data while C1 busy: %08h",mem_rdata);
        end
        c1_snoop_busy=0;
        begin : wait_c0_read
            integer n; n=0;
            while (c0_mem_ready !== 1'b1 && n<8) begin @(posedge clk); #1; n=n+1; end
            if (c0_mem_ready !== 1'b1 || mem_rdata !== 32'h01020304) begin
                errors=errors+1; $display("[BUS] FAIL C0 read did not complete with current RAM data=%08h",mem_rdata);
            end
        end
        release_bus();

        // Reverse direction: Core 1 owner is blocked by Core 0 snoop_busy.
        @(negedge clk);
        c1_bus_req=1; c1_bus_cmd=3'b001; c1_bus_addr=4;
        c1_mem_addr=4; c1_mem_ren=1; c0_snoop_busy=1;
        wait_c1_owner();
        repeat(3) begin
            @(posedge clk); #1;
            if (mem_ren !== 1'b0 || c1_mem_ready !== 1'b0) begin
                errors=errors+1; $display("[BUS] FAIL C1 owner was not stalled by C0 snoop_busy");
            end
        end
        if (mem_rdata !== 32'h01020304) begin
            errors=errors+1; $display("[BUS] FAIL stale/unknown RAM data while C0 busy: %08h",mem_rdata);
        end
        c0_snoop_busy=0;
        begin : wait_c1_read
            integer n; n=0;
            while (c1_mem_ready !== 1'b1 && n<8) begin @(posedge clk); #1; n=n+1; end
            if (c1_mem_ready !== 1'b1 || mem_rdata !== 32'h11223344) begin
                errors=errors+1; $display("[BUS] FAIL C1 read did not complete with current RAM data=%08h",mem_rdata);
            end
        end
        release_bus();

        // Non-owner Core 1 write-back must reach RAM while Core 0 owns the bus;
        // the owner stays blocked throughout the other controller's busy period.
        @(negedge clk);
        c0_bus_req=1; c0_bus_cmd=3'b001; c0_bus_addr=0;
        wait_c0_owner();
        @(negedge clk);
        c1_snoop_busy=1; c1_mem_addr=32'h18; c1_mem_wdata=32'hC0DEC001; c1_mem_wen=1;
        begin : wait_c1_writeback
            integer n;
            integer before_count;
            n=0;
            before_count=accepted_ram_writes;
            while (c1_mem_ready !== 1'b1 && n<8) begin @(posedge clk); #1; n=n+1; end
            if (c1_mem_ready !== 1'b1 || c0_mem_ready !== 1'b0 || ram.main_ram[6] !== 32'hC0DEC001) begin
                errors=errors+1;
                $display("[BUS] FAIL C1 write-back under C0 owner ready0=%b ready1=%b RAM=%08h",c0_mem_ready,c1_mem_ready,ram.main_ram[6]);
            end
            if ((accepted_ram_writes-before_count) != 1) begin
                errors=errors+1;
                $display("[BUS] FAIL C1 buffered write side effects expected=1 actual=%0d",accepted_ram_writes-before_count);
            end
        end
        release_bus();

        // Reverse non-owner write-back direction and check exactly one RAM side effect.
        @(negedge clk);
        c1_bus_req=1; c1_bus_cmd=3'b001; c1_bus_addr=0;
        wait_c1_owner();
        @(negedge clk);
        c0_snoop_busy=1; c0_mem_addr=32'h1C; c0_mem_wdata=32'hC0DEC002; c0_mem_wen=1;
        begin : wait_c0_writeback
            integer n;
            integer before_count;
            n=0;
            before_count=accepted_ram_writes;
            while (c0_mem_ready !== 1'b1 && n<8) begin @(posedge clk); #1; n=n+1; end
            if (c0_mem_ready !== 1'b1 || c1_mem_ready !== 1'b0 || ram.main_ram[7] !== 32'hC0DEC002) begin
                errors=errors+1;
                $display("[BUS] FAIL C0 write-back under C1 owner ready0=%b ready1=%b RAM=%08h",c0_mem_ready,c1_mem_ready,ram.main_ram[7]);
            end
            if ((accepted_ram_writes-before_count) != 1) begin
                errors=errors+1;
                $display("[BUS] FAIL C0 buffered write side effects expected=1 actual=%0d",accepted_ram_writes-before_count);
            end
        end
        release_bus();

        if (errors==0) begin
            $display("[BUS] PASS: owner gating both ways, ready/data freshness, and non-owner write-back both ways verified.");
            $finish;
        end else $fatal(1,"[BUS] %0d errors",errors);
    end

    initial begin
        #5000;
        $display("[BUS] FAIL timeout");
        $fatal(1,"[BUS] timeout");
    end
endmodule
