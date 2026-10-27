// Blocking, direct-mapped SRAM cache: four 32-bit words per cache line.
// cpu_ready completes the current request at the rising edge. cpu_rdata is
// valid after that edge, matching the original one-cycle synchronous SRAM.
// Writes are write-through / no-write-allocate. MMIO must set cpu_uncached.
module cpu_sram_cache #(
    parameter ENABLE = 1,
    parameter READ_ONLY = 0,
    parameter ADDR_BITS = 18,
    parameter INDEX_BITS = 6
)(
    input  wire        clk,
    input  wire        reset,
    input  wire        cancel,
    input  wire        cpu_req,
    input  wire [3:0]  cpu_we,
    input  wire [31:0] cpu_addr,
    input  wire [31:0] cpu_wdata,
    input  wire        cpu_uncached,
    output wire        cpu_ready,
    output wire [31:0] cpu_rdata,
    output reg         mem_en,
    output reg  [3:0]  mem_we,
    output reg  [31:0] mem_addr,
    output reg  [31:0] mem_wdata,
    input  wire [31:0] mem_rdata,
    output reg  [31:0] hit_count,
    output reg  [31:0] miss_count
);
localparam LINES = 1 << INDEX_BITS;
localparam TAG_BITS = ADDR_BITS - INDEX_BITS - 4;
localparam IDLE = 2'd0, REFILL = 2'd1, RESPONSE = 2'd2;

reg [1:0] state;
reg [LINES-1:0] valid_bits;
reg [TAG_BITS-1:0] tags [0:LINES-1];
reg [31:0] words [0:LINES*4-1];
reg [31:0] saved_addr;
reg [1:0] refill_word;
reg [31:0] result_reg;
reg last_from_mem;

wire [INDEX_BITS-1:0] index = cpu_addr[INDEX_BITS+3:4];
wire [TAG_BITS-1:0] tag = cpu_addr[ADDR_BITS-1:INDEX_BITS+4];
wire [INDEX_BITS+1:0] word_index = {index, cpu_addr[3:2]};
wire [INDEX_BITS-1:0] saved_index = saved_addr[INDEX_BITS+3:4];
wire [TAG_BITS-1:0] saved_tag = saved_addr[ADDR_BITS-1:INDEX_BITS+4];
wire [INDEX_BITS+1:0] saved_word_index = {saved_index, saved_addr[3:2]};
wire [1:0] next_refill_word = refill_word + 2'd1;
wire write_request = !READ_ONLY && (|cpu_we);
wire cacheable = ENABLE && !cpu_uncached;
wire hit = valid_bits[index] && tags[index] == tag;

// High address aliases share a line because tags use the physical SRAM bits.
// ADDR_BITS is 20 for the instruction RAM and 18 for the data RAM.
assign cpu_ready = !reset && !cancel &&
    ((state == IDLE && (!cpu_req || write_request || !cacheable || hit)) ||
     state == RESPONSE);
assign cpu_rdata = last_from_mem ? mem_rdata : result_reg;

always @(*) begin
    mem_en = 1'b0;
    mem_we = 4'b0;
    mem_addr = cpu_addr;
    mem_wdata = cpu_wdata;
    if (!reset && !cancel) begin
        if (state == IDLE && cpu_req) begin
            if (write_request) begin
                mem_en = 1'b1;
                mem_we = cpu_we;
            end else if (!cacheable) begin
                mem_en = 1'b1;
            end else if (!hit) begin
                mem_en = 1'b1;
                mem_addr = {cpu_addr[31:4], 4'b0};
            end
        end else if (state == REFILL && refill_word != 2'd3) begin
            // The previous word returns at this edge while the next is issued.
            mem_en = 1'b1;
            mem_addr = {saved_addr[31:4], next_refill_word, 2'b0};
        end
    end
end

integer lane;
always @(posedge clk) begin
    if (reset) begin
        state <= IDLE;
        valid_bits <= {LINES{1'b0}};
        saved_addr <= 32'b0;
        refill_word <= 2'b0;
        result_reg <= 32'b0;
        last_from_mem <= 1'b0;
        hit_count <= 32'b0;
        miss_count <= 32'b0;
    end else if (cancel) begin
        // A refill victim was invalidated before any words were overwritten.
        // Aborting a partial refill therefore cannot expose a mixed cache line.
        state <= IDLE;
    end else begin
        case (state)
            IDLE: if (cpu_req) begin
                if (write_request) begin
                    if (cacheable && hit) begin
                        for (lane = 0; lane < 4; lane = lane + 1)
                            if (cpu_we[lane])
                                words[word_index][lane*8 +: 8] <=
                                    cpu_wdata[lane*8 +: 8];
                    end
                end else if (!cacheable) begin
                    // The external SRAM updates mem_rdata after this same edge.
                    last_from_mem <= 1'b1;
                end else if (hit) begin
                    result_reg <= words[word_index];
                    last_from_mem <= 1'b0;
                    hit_count <= hit_count + 1'b1;
                end else begin
                    valid_bits[index] <= 1'b0;
                    saved_addr <= cpu_addr;
                    refill_word <= 2'd0;
                    miss_count <= miss_count + 1'b1;
                    state <= REFILL;
                end
            end
            REFILL: begin
                words[{saved_index, refill_word}] <= mem_rdata;
                if (refill_word == 2'd3) begin
                    tags[saved_index] <= saved_tag;
                    valid_bits[saved_index] <= 1'b1;
                    state <= RESPONSE;
                end else begin
                    refill_word <= next_refill_word;
                end
            end
            RESPONSE: if (cpu_req) begin
                result_reg <= words[saved_word_index];
                last_from_mem <= 1'b0;
                state <= IDLE;
            end
            default: state <= IDLE;
        endcase
    end
end
endmodule
