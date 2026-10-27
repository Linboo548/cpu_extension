`timescale 1ns/1ps
module tb_cache;
reg clk = 0;
always #5 clk = ~clk;
reg reset = 1;
reg cancel = 0, req = 0, uncached = 0;
reg [3:0] we = 0;
reg [31:0] addr = 0, wdata = 0;
wire ready;
wire [31:0] rdata, mem_addr, mem_wdata, hits, misses;
wire mem_en;
wire [3:0] mem_we;
reg [31:0] mem_rdata = 0;
reg [31:0] memory [0:65535];
integer reads = 0, writes = 0, io_reads = 0, io_writes = 0;
reg [31:0] peripheral = 32'ha5000000;
wire io_access = (mem_addr & 32'h1fff0000) == 32'h1faf0000;
cpu_sram_cache dut(
    .clk(clk), .reset(reset), .cancel(cancel), .cpu_req(req),
    .cpu_we(we), .cpu_addr(addr), .cpu_wdata(wdata),
    .cpu_uncached(uncached), .cpu_ready(ready), .cpu_rdata(rdata),
    .mem_en(mem_en), .mem_we(mem_we), .mem_addr(mem_addr),
    .mem_wdata(mem_wdata), .mem_rdata(mem_rdata),
    .hit_count(hits), .miss_count(misses));
integer i, lane;
initial for (i = 0; i < 65536; i = i + 1) memory[i] = 32'h50000000 + i*4;
always @(posedge clk) if (mem_en) begin
    if (io_access) begin
        mem_rdata <= peripheral;
        if (|mem_we) io_writes = io_writes + 1;
        else begin io_reads = io_reads + 1; peripheral <= peripheral + 1; end
    end else begin
        mem_rdata <= memory[mem_addr[17:2]];
        if (|mem_we) begin
            writes = writes + 1;
            for (lane = 0; lane < 4; lane = lane + 1)
                if (mem_we[lane]) memory[mem_addr[17:2]][lane*8 +: 8] <= mem_wdata[lane*8 +: 8];
        end else reads = reads + 1;
    end
end

task d_access(input [3:0] mask, input [31:0] address,
              input [31:0] data, input bypass,
              output [31:0] value, output integer stalls);
begin
    @(negedge clk); req = 1; we = mask; addr = address; wdata = data; uncached = bypass;
    stalls = 0;
    begin : wait_done
        forever begin
            @(posedge clk);
            if (ready) begin #1; value = rdata; disable wait_done; end
            stalls = stalls + 1;
        end
    end
    @(negedge clk); req = 0; we = 0;
end
endtask

// A disabled cache preserves the original single-edge SRAM request interface.
reg off_req = 0;
reg [3:0] off_we = 0;
reg [31:0] off_addr = 0, off_wdata = 0, off_mem_rdata = 0;
wire off_ready, off_mem_en;
wire [3:0] off_mem_we;
wire [31:0] off_rdata, off_mem_addr, off_mem_wdata, off_hits, off_misses;
integer off_reads = 0, off_writes = 0;
reg [31:0] off_word = 32'h01020304;
cpu_sram_cache #(.ENABLE(0)) disabled_cache(
    .clk(clk), .reset(reset), .cancel(1'b0), .cpu_req(off_req),
    .cpu_we(off_we), .cpu_addr(off_addr), .cpu_wdata(off_wdata),
    .cpu_uncached(1'b0), .cpu_ready(off_ready), .cpu_rdata(off_rdata),
    .mem_en(off_mem_en), .mem_we(off_mem_we), .mem_addr(off_mem_addr),
    .mem_wdata(off_mem_wdata), .mem_rdata(off_mem_rdata),
    .hit_count(off_hits), .miss_count(off_misses));
always @(posedge clk) if (off_mem_en) begin
    off_mem_rdata <= off_word;
    if (|off_mem_we) begin off_word <= off_mem_wdata; off_writes = off_writes + 1; end
    else off_reads = off_reads + 1;
end
task off_access(input [3:0] mask, input [31:0] data, output [31:0] value);
begin
    @(negedge clk); off_req = 1; off_we = mask; off_wdata = data;
    @(posedge clk);
    if (!off_ready) $fatal(1, "disabled cache added wait states");
    #1; value = off_rdata;
    @(negedge clk); off_req = 0; off_we = 0;
end
endtask

// The instruction memory has 20 physical address bits, unlike the data RAM.
reg i_req = 0;
reg [31:0] i_addr = 0, i_mem_rdata = 0;
wire i_ready, i_mem_en;
wire [3:0] i_mem_we;
wire [31:0] i_rdata, i_mem_addr, i_mem_wdata, i_hits, i_misses;
integer i_reads = 0;
cpu_sram_cache #(.READ_ONLY(1), .ADDR_BITS(20)) instruction_cache(
    .clk(clk), .reset(reset), .cancel(1'b0), .cpu_req(i_req),
    .cpu_we(4'b0), .cpu_addr(i_addr), .cpu_wdata(32'b0),
    .cpu_uncached(1'b0), .cpu_ready(i_ready), .cpu_rdata(i_rdata),
    .mem_en(i_mem_en), .mem_we(i_mem_we), .mem_addr(i_mem_addr),
    .mem_wdata(i_mem_wdata), .mem_rdata(i_mem_rdata),
    .hit_count(i_hits), .miss_count(i_misses));
always @(posedge clk) if (i_mem_en) begin
    if (|i_mem_we) $fatal(1, "I-cache wrote instruction memory");
    i_reads = i_reads + 1;
    i_mem_rdata <= 32'hc0000000 | {12'b0, i_mem_addr[19:2], 2'b0};
end
task i_access(input [31:0] address, output [31:0] value, output integer stalls);
begin
    @(negedge clk); i_req = 1; i_addr = address; stalls = 0;
    begin : wait_i_done
        forever begin
            @(posedge clk);
            if (i_ready) begin #1; value = i_rdata; disable wait_i_done; end
            stalls = stalls + 1;
        end
    end
    @(negedge clk); i_req = 0;
end
endtask

reg [31:0] value;
integer stalls, before_reads, before_writes, before_io;
initial begin
    repeat (3) @(negedge clk); reset = 0;

    before_reads = reads;
    d_access(0, 32'h00000104, 0, 0, value, stalls);
    if (value !== 32'h50000104 || stalls != 5 || reads-before_reads != 4 || misses != 1)
        $fatal(1, "cold refill failed value=%h stalls=%0d reads=%0d", value, stalls, reads-before_reads);
    before_reads = reads;
    d_access(0, 32'h0000010c, 0, 0, value, stalls);
    if (value !== 32'h5000010c || stalls != 0 || reads != before_reads)
        $fatal(1, "same-line hit did not avoid memory");
    d_access(0, 32'h80000104, 0, 0, value, stalls);
    if (value !== 32'h50000104 || stalls != 0 || reads != before_reads)
        $fatal(1, "high address alias did not hit same physical data");

    before_writes = writes;
    d_access(4'hf, 32'ha0000104, 32'hdeadbeef, 0, value, stalls);
    d_access(4'h2, 32'h10000104, 32'h0000ab00, 0, value, stalls);
    d_access(4'hc, 32'h00000104, 32'h12340000, 0, value, stalls);
    d_access(0, 32'h80000104, 0, 0, value, stalls);
    if (value !== 32'h1234abef || memory[65] !== 32'h1234abef || writes-before_writes != 3 || reads != before_reads)
        $fatal(1, "write-through byte merge or alias coherence failed value=%h", value);

    before_reads = reads;
    d_access(0, 32'h00000504, 0, 0, value, stalls);
    if (value !== 32'h50000504 || reads-before_reads != 4 || stalls != 5)
        $fatal(1, "conflicting tag did not refill");
    d_access(0, 32'h00000104, 0, 0, value, stalls);
    if (value !== 32'h1234abef || reads-before_reads != 8)
        $fatal(1, "conflict replacement returned stale data");

    before_reads = reads; before_writes = writes;
    d_access(4'hf, 32'h00008000, 32'h89abcdef, 0, value, stalls);
    if (reads != before_reads || writes-before_writes != 1 || stalls != 0)
        $fatal(1, "write miss allocated or duplicated a request");
    d_access(0, 32'h00008000, 0, 0, value, stalls);
    if (value !== 32'h89abcdef || reads-before_reads != 4 || stalls != 5)
        $fatal(1, "write-no-allocate readback failed");

    before_io = io_reads;
    d_access(0, 32'h1faff064, 0, 1, value, stalls);
    if (value !== 32'ha5000000 || stalls != 0 || io_reads-before_io != 1)
        $fatal(1, "MMIO bypass read timing/side effects wrong");
    d_access(0, 32'hbfaff064, 0, 1, value, stalls);
    if (value !== 32'ha5000001 || stalls != 0 || io_reads-before_io != 2)
        $fatal(1, "MMIO bypass returned stale cached value");
    d_access(4'hf, 32'h1faff020, 32'h55, 1, value, stalls);
    if (io_writes != 1 || stalls != 0) $fatal(1, "MMIO write was duplicated");

    // Cancel after two refill requests; the old victim must remain invalid.
    d_access(0, 32'h00000104, 0, 0, value, stalls);
    @(negedge clk); req = 1; we = 0; addr = 32'h00000504; uncached = 0;
    @(posedge clk); #1;
    @(posedge clk); #1;
    @(negedge clk); cancel = 1;
    #1; if (mem_en || ready) $fatal(1, "cancel did not suppress memory/CPU completion");
    @(posedge clk); #1;
    @(negedge clk); cancel = 0; req = 0;
    before_reads = reads;
    d_access(0, 32'h00000104, 0, 0, value, stalls);
    if (value !== 32'h1234abef || reads-before_reads != 4 || stalls != 5)
        $fatal(1, "partial refill left mixed valid line");

    @(negedge clk); reset = 1;
    repeat (2) @(negedge clk); reset = 0;
    before_reads = reads;
    d_access(0, 32'h00000104, 0, 0, value, stalls);
    if (value !== 32'h1234abef || reads-before_reads != 4 || hits != 0 || misses != 1)
        $fatal(1, "reset did not invalidate cache and counters");

    off_access(0, 0, value);
    if (value !== 32'h01020304) $fatal(1, "disabled bypass read failed");
    off_access(0, 0, value);
    off_access(4'hf, 32'h76543210, value);
    off_access(0, 0, value);
    if (value !== 32'h76543210 || off_reads != 3 || off_writes != 1 || off_hits != 0 || off_misses != 0)
        $fatal(1, "disabled cache request counts or writeback wrong");

    i_access(32'h1c000104, value, stalls);
    if (value !== 32'hc0000104 || stalls != 5 || i_reads != 4) $fatal(1, "I-cache refill failed");
    i_access(32'h9c00010c, value, stalls);
    if (value !== 32'hc000010c || stalls != 0 || i_reads != 4) $fatal(1, "I-cache alias/same-line hit failed");
    i_access(32'h1c040104, value, stalls);
    if (value !== 32'hc0040104 || stalls != 5 || i_reads != 8) $fatal(1, "I-cache truncated the 20-bit physical address");

    $display("PASS cache: I/D refill, hits, conflict, reset, write-through byte masks, no-write-allocate, physical aliases, MMIO, cancel, disabled bypass");
    $finish;
end
initial begin #100000; $fatal(1, "cache unit test timeout"); end
endmodule
