// =============================================================================
// cache_controller.v — Fixed & Optimized Version (Includes Write-Back/Eviction)
// =============================================================================

module cache_controller #(
    parameter SETS        = 4,
    parameter BLOCK_WORDS = 4,
    parameter ADDR_WIDTH  = 32,
    parameter DATA_WIDTH  = 32,
    parameter INDEX_BITS  = 2,
    parameter OFFSET_BITS = 2,
    parameter TAG_BITS    = ADDR_WIDTH - INDEX_BITS - OFFSET_BITS - 2, 
    parameter MEM_LATENCY = 2
)(
    input  wire                  clk,
    input  wire                  rst_n,

    // CPU
    input  wire [ADDR_WIDTH-1:0]   cpu_addr,
    input  wire [DATA_WIDTH-1:0]   cpu_wdata,
    input  wire                  cpu_wen,
    input  wire                  cpu_ren,
    output reg                   cpu_stall,
    output reg                   cpu_done,

    // Cache SRAM control
    output reg  [INDEX_BITS-1:0]   ctrl_index,
    output reg  [OFFSET_BITS-1:0]  ctrl_offset,
    output reg  [TAG_BITS-1:0]     ctrl_tag_in,
    output reg  [DATA_WIDTH-1:0]   ctrl_wdata,
    output reg                   ctrl_we,
    output reg                   ctrl_tag_we,
    output reg                   ctrl_dirty_we,
    output reg                   ctrl_dirty_in,
    output reg  [1:0]              ctrl_mesi_in,
    output reg                   ctrl_mesi_we,

    // Cache SRAM readback
    input  wire [TAG_BITS-1:0]     ctrl_tag_out,
    input  wire                  ctrl_valid_out,
    input  wire                  ctrl_dirty_out,
    input  wire [1:0]              ctrl_mesi_out,
    input  wire [DATA_WIDTH-1:0]   ctrl_rdata,
    input  wire                  cache_hit,

    // Snoop port
    output reg  [INDEX_BITS-1:0]   snoop_index,
    input  wire [TAG_BITS-1:0]     snoop_tag_out,
    input  wire [1:0]              snoop_mesi_out,
    input  wire                  snoop_valid_out,
    input  wire                  snoop_dirty_out,

    // Bus arbiter
    output reg  [2:0]              bus_cmd,
    output reg  [ADDR_WIDTH-1:0]   bus_addr,
    output reg  [DATA_WIDTH-1:0]   bus_wdata,
    output reg                   bus_req,
    input  wire                  bus_grant,

    // Snoop from arbiter
    input  wire [2:0]              snoop_cmd,
    input  wire [ADDR_WIDTH-1:0]   snoop_addr,
    output reg                   snoop_ack,
    output reg                   snoop_hit,
    output reg  [DATA_WIDTH-1:0]   snoop_wdata_out,

    // Memory
    output reg  [ADDR_WIDTH-1:0]   mem_addr,
    output reg  [DATA_WIDTH-1:0]   mem_wdata,
    output reg                   mem_wen,
    output reg                   mem_ren,
    input  wire [DATA_WIDTH-1:0]   mem_rdata,
    input  wire                  mem_ready,

    // From arbiter
    input  wire                  other_has_copy,
    input  wire [DATA_WIDTH-1:0]   other_flush_data
);

    // MESI States
    localparam INVALID   = 2'b00;
    localparam SHARED    = 2'b01;
    localparam EXCLUSIVE = 2'b10;
    localparam MODIFIED  = 2'b11;

    // Bus commands
    localparam BUS_NONE  = 3'b000;
    localparam BUS_READ  = 3'b001;
    localparam BUS_READX = 3'b010;
    localparam BUS_UPGR  = 3'b011;
    localparam BUS_WB    = 3'b100; // Thêm lệnh Write-Back

    // Snoop commands
    localparam SNOOP_NONE  = 3'b000;
    localparam SNOOP_READ  = 3'b001;
    localparam SNOOP_READX = 3'b010;
    localparam SNOOP_UPGR  = 3'b011;

    // FSM States
    localparam S_IDLE         = 4'd0;
    localparam S_CHECK        = 4'd1;
    localparam S_HIT          = 4'd2;
    localparam S_UPGR_ARBWAIT = 4'd3;
    localparam S_MISS_ARBWAIT = 4'd4;
    localparam S_FETCH        = 4'd5;
    localparam S_FILL_DONE    = 4'd6;
    localparam S_SNOOP_HANDLE = 4'd7;
    localparam S_DONE         = 4'd8;
    localparam S_EVICT_ARBWAIT= 4'd9;  // Chờ Bus để ghi trả
    localparam S_EVICT        = 4'd10; // Xả data xuống RAM

    reg [3:0] state;

    reg [ADDR_WIDTH-1:0] saved_addr;
    reg [DATA_WIDTH-1:0] saved_wdata;
    reg                  saved_wen;

    reg [2:0] latched_snoop_cmd;
    reg [ADDR_WIDTH-1:0] latched_snoop_addr;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            latched_snoop_cmd  <= SNOOP_NONE;
            latched_snoop_addr <= 0;
        end else if (snoop_cmd != SNOOP_NONE) begin
            latched_snoop_cmd  <= snoop_cmd;
            latched_snoop_addr <= snoop_addr;
        end
    end

    wire use_latched = (state == S_SNOOP_HANDLE) && (snoop_cmd == SNOOP_NONE);
    wire [2:0] cur_snoop_cmd = use_latched ? latched_snoop_cmd : snoop_cmd;
    wire [ADDR_WIDTH-1:0] cur_snoop_addr = use_latched ? latched_snoop_addr : snoop_addr;

    wire [ADDR_WIDTH-1:0] active_addr = (state == S_IDLE) ? cpu_addr : saved_addr;
    wire [OFFSET_BITS-1:0] a_offset = active_addr[OFFSET_BITS+1:2];
    wire [INDEX_BITS-1:0]  a_index  = active_addr[INDEX_BITS+OFFSET_BITS+1:OFFSET_BITS+2];
    wire [TAG_BITS-1:0]    a_tag    = active_addr[ADDR_WIDTH-1:INDEX_BITS+OFFSET_BITS+2];

    wire [OFFSET_BITS-1:0] snp_offset = cur_snoop_addr[OFFSET_BITS+1:2];
    wire [INDEX_BITS-1:0]  snp_index  = cur_snoop_addr[INDEX_BITS+OFFSET_BITS+1:OFFSET_BITS+2];
    wire [TAG_BITS-1:0]    snp_tag    = cur_snoop_addr[ADDR_WIDTH-1:INDEX_BITS+OFFSET_BITS+2];

    reg [OFFSET_BITS-1:0] fill_cnt;
    reg [OFFSET_BITS-1:0] evict_cnt; // Đếm số word đã đẩy về RAM

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state       <= S_IDLE;
            saved_addr  <= 0;
            saved_wdata <= 0;
            saved_wen   <= 0;
            fill_cnt    <= 0;
            evict_cnt   <= 0;
        end else begin
            if (snoop_cmd != SNOOP_NONE && state != S_SNOOP_HANDLE) begin
                state <= S_SNOOP_HANDLE;
            end else begin
                case (state)
                    S_IDLE: begin
                        if (cpu_ren || cpu_wen) begin
                            saved_addr  <= cpu_addr;
                            saved_wdata <= cpu_wdata;
                            saved_wen   <= cpu_wen;
                            state       <= S_CHECK;
                        end
                    end

                    S_CHECK: begin
                        if (cache_hit) begin
                            if (saved_wen && ctrl_mesi_out == SHARED)
                                state <= S_UPGR_ARBWAIT;
                            else
                                state <= S_HIT;
                        end else begin
                            // Kiểm tra nếu block cũ đang bị bẩn (Dirty/Modified) -> Cần Evict
                            if (ctrl_valid_out && ctrl_mesi_out == MODIFIED) begin
                                state <= S_EVICT_ARBWAIT;
                            end else begin
                                state <= S_MISS_ARBWAIT;
                            end
                        end
                    end

                    S_HIT: state <= S_DONE;

                    S_UPGR_ARBWAIT: if (bus_grant) state <= S_DONE;

                    S_EVICT_ARBWAIT: begin
                        if (bus_grant) begin
                            evict_cnt <= 0;
                            state     <= S_EVICT;
                        end
                    end

                    S_EVICT: begin
                        if (mem_ready) begin
                            if (evict_cnt == BLOCK_WORDS - 1)
                                state <= S_MISS_ARBWAIT;
                            else
                                evict_cnt <= evict_cnt + 1;
                        end
                    end

                    S_MISS_ARBWAIT: begin
                        if (bus_grant) begin
                            fill_cnt <= 0;
                            state    <= S_FETCH;
                        end
                    end

                    S_FETCH: begin
                        if (mem_ready) begin
                            if (fill_cnt == BLOCK_WORDS - 1)
                                state <= S_FILL_DONE;
                            else
                                fill_cnt <= fill_cnt + 1;
                        end
                    end

                    S_FILL_DONE: state <= S_DONE;
                    S_DONE: state <= S_IDLE;
                    S_SNOOP_HANDLE: state <= S_IDLE; 
                    default: state <= S_IDLE;
                endcase
            end
        end
    end

    always @(*) begin
        cpu_done        = 1'b0;
        bus_req         = 1'b0;
        bus_cmd         = BUS_NONE;
        bus_addr        = saved_addr;
        bus_wdata       = 0;
        mem_addr        = 0;
        mem_wdata       = 0;
        mem_wen         = 0;
        mem_ren         = 0;
        cpu_stall       = (state != S_DONE && state != S_IDLE) || (state == S_IDLE && (cpu_ren || cpu_wen)) || (cur_snoop_cmd != SNOOP_NONE);

        if ((state == S_SNOOP_HANDLE) || (cur_snoop_cmd != SNOOP_NONE)) begin
            ctrl_index  = snp_index;
            ctrl_offset = snp_offset;
            ctrl_tag_in = snp_tag;      
            snoop_index = snp_index;
        end else if (state == S_EVICT) begin
            ctrl_index  = a_index;
            ctrl_offset = evict_cnt; // Đọc tuần tự các word để hất văng
            ctrl_tag_in = a_tag;
            snoop_index = a_index;
        end else begin
            ctrl_index  = a_index;
            ctrl_offset = a_offset;
            ctrl_tag_in = a_tag;        
            snoop_index = a_index;
        end

        ctrl_wdata      = 0;
        ctrl_we         = 0;
        ctrl_tag_we     = 0;
        ctrl_dirty_we   = 0;
        ctrl_dirty_in   = 0;
        ctrl_mesi_in    = INVALID;
        ctrl_mesi_we    = 0;
        snoop_ack       = 0;
        snoop_hit       = 0;
        snoop_wdata_out = 0;

        // BUS LOCK LOGIC
        if (state == S_MISS_ARBWAIT || state == S_FETCH || state == S_FILL_DONE) begin
            bus_req  = 1'b1;
            bus_cmd  = saved_wen ? BUS_READX : BUS_READ;
            bus_addr = saved_addr;
        end else if (state == S_UPGR_ARBWAIT) begin
            bus_req  = 1'b1;
            bus_cmd  = BUS_UPGR;
            bus_addr = saved_addr;
        end else if (state == S_EVICT_ARBWAIT || state == S_EVICT) begin
            bus_req  = 1'b1;
            bus_cmd  = BUS_WB;
            // Địa chỉ eviction dựa trên block cũ
            bus_addr = {ctrl_tag_out, a_index, 4'b0000}; 
        end

        case (state)
            S_HIT: begin
                if (cur_snoop_cmd == SNOOP_NONE) begin
                    if (saved_wen) begin
                        ctrl_index    = a_index;
                        ctrl_offset   = a_offset;
                        ctrl_wdata    = saved_wdata;
                        ctrl_we       = 1'b1;
                        ctrl_dirty_we = 1'b1;
                        ctrl_dirty_in = 1'b1;
                        ctrl_mesi_in  = MODIFIED;
                        ctrl_mesi_we  = 1'b1;
                    end
                end
            end
            S_UPGR_ARBWAIT: begin
                if (cur_snoop_cmd == SNOOP_NONE && bus_grant) begin
                    ctrl_index    = a_index;
                    ctrl_offset   = a_offset;
                    ctrl_wdata    = saved_wdata;
                    ctrl_we       = 1'b1;
                    ctrl_dirty_we = 1'b1;
                    ctrl_dirty_in = 1'b1;
                    ctrl_mesi_in  = MODIFIED;
                    ctrl_mesi_we  = 1'b1;
                end
            end
            S_EVICT: begin
                mem_addr  = {ctrl_tag_out, a_index, evict_cnt, 2'b00};
                mem_wdata = ctrl_rdata;
                mem_wen   = 1'b1;
            end
            S_FETCH: begin
                mem_addr  = {saved_addr[ADDR_WIDTH-1:4], fill_cnt, 2'b00};
                mem_ren   = 1'b1;
                if (mem_ready) begin
                    ctrl_index  = a_index;
                    ctrl_offset = fill_cnt;
                    ctrl_wdata  = mem_rdata;
                    ctrl_we     = 1'b1;
                end
            end
            S_FILL_DONE: begin
                ctrl_index    = a_index;
                ctrl_tag_in   = a_tag;
                ctrl_tag_we   = 1'b1;
                ctrl_dirty_we = 1'b1;
                ctrl_mesi_we  = 1'b1; 
                if (saved_wen) begin
                    ctrl_offset   = a_offset;
                    ctrl_wdata    = saved_wdata;
                    ctrl_we       = 1'b1;
                    ctrl_dirty_in = 1'b1;
                    ctrl_mesi_in  = MODIFIED;
                end else begin
                    ctrl_dirty_in = 1'b0;
                    ctrl_mesi_in  = other_has_copy ? SHARED : EXCLUSIVE;
                end
            end
            S_DONE: begin
                if (cur_snoop_cmd == SNOOP_NONE) cpu_done = 1'b1;
            end
            S_SNOOP_HANDLE: begin
                snoop_ack = 1'b1;
                if (snoop_valid_out && snoop_tag_out == snp_tag && snoop_mesi_out != INVALID) begin
                    snoop_hit = 1'b1;
                    case (cur_snoop_cmd)
                        SNOOP_READ: begin
                            if (snoop_mesi_out == MODIFIED) begin
                                snoop_wdata_out = ctrl_rdata;
                                ctrl_mesi_in    = SHARED;
                                ctrl_mesi_we    = 1'b1;
                                ctrl_dirty_we   = 1'b1;
                                ctrl_dirty_in   = 1'b0;
                                mem_addr        = cur_snoop_addr;
                                mem_wdata       = ctrl_rdata;
                                mem_wen         = 1'b1;
                            end else if (snoop_mesi_out == EXCLUSIVE) begin
                                ctrl_mesi_in    = SHARED;
                                ctrl_mesi_we    = 1'b1;
                            end
                        end
                        SNOOP_READX,
                        SNOOP_UPGR: begin
                            if (snoop_mesi_out == MODIFIED) begin
                                snoop_wdata_out = ctrl_rdata;
                                mem_addr        = cur_snoop_addr;
                                mem_wdata       = ctrl_rdata;
                                mem_wen         = 1'b1;
                            end
                            ctrl_mesi_in  = INVALID;
                            ctrl_mesi_we  = 1'b1;
                            ctrl_dirty_we = 1'b1;
                            ctrl_dirty_in = 1'b0;
                        end
                        default: ;
                    endcase
                end
            end
            default: ;
        endcase
    end
endmodule