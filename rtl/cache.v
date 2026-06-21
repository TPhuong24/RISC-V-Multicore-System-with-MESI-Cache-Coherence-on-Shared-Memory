// =============================================================================
// cache.v — Direct-mapped cache completely controlled by the cache_controller
// =============================================================================

module cache #(
    parameter SETS        = 4,
    parameter BLOCK_WORDS = 4,
    parameter ADDR_WIDTH  = 32,
    parameter DATA_WIDTH  = 32,
    parameter INDEX_BITS  = 2,
    parameter OFFSET_BITS = 2,
    parameter TAG_BITS    = ADDR_WIDTH - INDEX_BITS - OFFSET_BITS - 2
)(
    input  wire                 clk,
    input  wire                 rst_n,

    // CPU Port
    input  wire [ADDR_WIDTH-1:0] cpu_addr,
    input  wire [DATA_WIDTH-1:0] cpu_wdata,
    input  wire                 cpu_wen,
    input  wire                 cpu_ren,
    output reg  [DATA_WIDTH-1:0] cpu_rdata,
    output reg                  cpu_hit,

    // Controller Write/Control Ports
    input  wire [INDEX_BITS-1:0]  ctrl_index,
    input  wire [OFFSET_BITS-1:0] ctrl_offset,
    input  wire [TAG_BITS-1:0]    ctrl_tag_in,
    input  wire [DATA_WIDTH-1:0]  ctrl_wdata,
    input  wire                 ctrl_we,
    input  wire                 ctrl_tag_we,
    input  wire                 ctrl_dirty_we,
    input  wire                 ctrl_dirty_in,
    input  wire [1:0]             ctrl_mesi_in,
    input  wire                 ctrl_mesi_we,

    // Controller Readback Ports
    output wire [TAG_BITS-1:0]    ctrl_tag_out,
    output wire                 ctrl_valid_out,
    output wire                 ctrl_dirty_out,
    output wire [1:0]             ctrl_mesi_out,
    output wire [DATA_WIDTH-1:0]  ctrl_rdata,

    // Snoop Ports
    input  wire [INDEX_BITS-1:0]  snoop_index,
    output wire [TAG_BITS-1:0]    snoop_tag_out,
    output wire [1:0]             snoop_mesi_out,
    output wire                 snoop_valid_out,
    output wire                 snoop_dirty_out
);

    localparam INVALID = 2'b00;

    // Storage arrays
    reg [TAG_BITS-1:0]   tag_array   [0:SETS-1];
    reg                  valid_array [0:SETS-1];
    reg                  dirty_array [0:SETS-1];
    reg [1:0]            mesi_array  [0:SETS-1];
    reg [DATA_WIDTH-1:0] data_array  [0:SETS-1][0:BLOCK_WORDS-1];

    // Decode CPU address
    wire [OFFSET_BITS-1:0] cpu_offset = cpu_addr[OFFSET_BITS+1:2];
    wire [INDEX_BITS-1:0]  cpu_index  = cpu_addr[INDEX_BITS+OFFSET_BITS+1 : OFFSET_BITS+2];
    wire [TAG_BITS-1:0]    cpu_tag    = cpu_addr[ADDR_WIDTH-1 : INDEX_BITS+OFFSET_BITS+2];

    // Hit detection logic
    wire tag_match  = (tag_array[cpu_index] == cpu_tag);
    wire line_valid = valid_array[cpu_index];
    wire real_hit   = tag_match && line_valid && (mesi_array[cpu_index] != INVALID);

    // CPU read and hit combinational output
    always @(*) begin
        cpu_hit   = 1'b0;
        cpu_rdata = {DATA_WIDTH{1'b0}};
        
        if ((cpu_ren || cpu_wen) && real_hit) begin
            cpu_hit = 1'b1;
        end
        
        if (cpu_ren && real_hit) begin
            cpu_rdata = data_array[cpu_index][cpu_offset];
        end
    end

    // ====== [ĐÃ SỬA]: Đưa "integer i" vào trong làm biến cục bộ ======
    always @(posedge clk or negedge rst_n) begin : seq_write
        integer i; // KHÔNG CÒN BỊ LATCH NỮA
        
        if (!rst_n) begin
            for (i = 0; i < SETS; i = i + 1) begin
                valid_array[i] <= 1'b0;
                dirty_array[i] <= 1'b0;
                mesi_array[i]  <= INVALID;
                tag_array[i]   <= {TAG_BITS{1'b0}};
            end
        end else begin
            // Toàn bộ hoạt động ghi được điều phối tập trung bởi Controller
            if (ctrl_we)
                data_array[ctrl_index][ctrl_offset] <= ctrl_wdata;

            if (ctrl_tag_we) begin
                tag_array[ctrl_index]   <= ctrl_tag_in;
                valid_array[ctrl_index] <= 1'b1;
            end

            if (ctrl_dirty_we)
                dirty_array[ctrl_index] <= ctrl_dirty_in;

            if (ctrl_mesi_we)
                mesi_array[ctrl_index]  <= ctrl_mesi_in;
        end
    end

    // Controller continuous read assignments
    assign ctrl_tag_out   = tag_array  [ctrl_index];
    assign ctrl_valid_out = valid_array[ctrl_index];
    assign ctrl_dirty_out = dirty_array[ctrl_index];
    assign ctrl_mesi_out  = mesi_array [ctrl_index];
    assign ctrl_rdata     = data_array [ctrl_index][ctrl_offset];

    // Snoop continuous read assignments
    assign snoop_tag_out   = tag_array  [snoop_index];
    assign snoop_mesi_out  = mesi_array [snoop_index];
    assign snoop_valid_out = valid_array[snoop_index];
    assign snoop_dirty_out = dirty_array[snoop_index];

endmodule