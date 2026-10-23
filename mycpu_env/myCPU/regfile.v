module regfile(
    input  wire        clk,

    input  wire [4:0]  raddr1,
    output wire [31:0] rdata1,

    input  wire [4:0]  raddr2,
    output wire [31:0] rdata2,

    input  wire        we,
    input  wire [4:0]  waddr,
    input  wire [31:0] wdata
);

reg [31:0] rf[31:0];

/* $r0 恒为零，禁止向 $r0 实际写入数据 */
always @(posedge clk) begin
    if (we && (waddr != 5'd0)) begin
        rf[waddr] <= wdata;
    end
end

/*
 * 同周期写回旁路：
 * 当 WB 正在写某寄存器，而 ID 同时读取该寄存器时，
 * 直接返回 WB 写入值。
 */
assign rdata1 =
    (raddr1 == 5'd0) ?
    32'b0 :
    ((we && (waddr != 5'd0) && (raddr1 == waddr)) ?
        wdata :
        rf[raddr1]);

assign rdata2 =
    (raddr2 == 5'd0) ?
    32'b0 :
    ((we && (waddr != 5'd0) && (raddr2 == waddr)) ?
        wdata :
        rf[raddr2]);

endmodule