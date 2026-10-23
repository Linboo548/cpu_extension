`timescale 1ns/1ps
// [新增，仅仿真] 保持原BRAM的一拍读、读优先及字节写语义。
// 不得加入综合源文件集。真实IP回归应使用ip/*.xci及原RAM IP。
module inst_ram(input wire clka,ena,input wire [3:0] wea,
 input wire [17:0] addra,input wire [31:0] dina,output reg [31:0] douta);
reg [31:0] mem[0:262143]; integer i,j;
initial begin
 for(i=0;i<262144;i=i+1) mem[i]=32'h03400000;
 $readmemb("inst_ram.mif",mem);
end
always @(posedge clka) if(ena) begin
 douta<=mem[addra];
 for(j=0;j<4;j=j+1) if(wea[j]) mem[addra][j*8+:8]<=dina[j*8+:8];
end
endmodule
module data_ram(input wire clka,ena,input wire [3:0] wea,
 input wire [15:0] addra,input wire [31:0] dina,output reg [31:0] douta);
reg [31:0] mem[0:65535]; integer i,j;
initial begin
 for(i=0;i<65536;i=i+1) mem[i]=0;
 $readmemb("data_ram.mif",mem);
end
always @(posedge clka) if(ena) begin
 douta<=mem[addra];
 for(j=0;j<4;j=j+1) if(wea[j]) mem[addra][j*8+:8]<=dina[j*8+:8];
end
endmodule

// [新增，仅仿真] NonBlocking除法器接口行为模型。非真实IP周期/资源模型。
module divider_model #(parameter SIGNED_OP=0,parameter LATENCY=36)(
 input wire aclk,aresetn,s_axis_dividend_tvalid,
 input wire [31:0] s_axis_dividend_tdata,
 input wire s_axis_divisor_tvalid,input wire [31:0] s_axis_divisor_tdata,
 output reg m_axis_dout_tvalid,output reg [63:0] m_axis_dout_tdata);
integer left;reg [63:0] result;
// 先独立计算有/无符号结果，再选择，避免三目表达式的混合符号传播。
wire [31:0] signed_q=$signed(s_axis_dividend_tdata)/$signed(s_axis_divisor_tdata);
wire [31:0] signed_r=$signed(s_axis_dividend_tdata)%$signed(s_axis_divisor_tdata);
wire [31:0] unsigned_q=s_axis_dividend_tdata/s_axis_divisor_tdata;
wire [31:0] unsigned_r=s_axis_dividend_tdata%s_axis_divisor_tdata;
wire [31:0] q=SIGNED_OP ? signed_q : unsigned_q;
wire [31:0] r=SIGNED_OP ? signed_r : unsigned_r;
always @(posedge aclk) begin
 if(!aresetn) begin left<=0; m_axis_dout_tvalid<=0; m_axis_dout_tdata<=0;result<=0;end
 else begin
  m_axis_dout_tvalid<=0;
  if(s_axis_dividend_tvalid && s_axis_divisor_tvalid) begin
   if(left!=0) $fatal(1,"CPU submitted a second divide while one was pending");
   result<={q,r};left<=LATENCY;
  end else if(left!=0) begin
   left<=left-1;
   if(left==1) begin m_axis_dout_tvalid<=1;m_axis_dout_tdata<=result;end
  end
 end
end
endmodule
module div_signed(input wire aclk,aresetn,s_axis_dividend_tvalid,
 input wire [31:0] s_axis_dividend_tdata,input wire s_axis_divisor_tvalid,
 input wire [31:0] s_axis_divisor_tdata,output wire m_axis_dout_tvalid,
 output wire [63:0] m_axis_dout_tdata);
divider_model #(.SIGNED_OP(1)) model(.*);
endmodule
module div_unsigned(input wire aclk,aresetn,s_axis_dividend_tvalid,
 input wire [31:0] s_axis_dividend_tdata,input wire s_axis_divisor_tvalid,
 input wire [31:0] s_axis_divisor_tdata,output wire m_axis_dout_tvalid,
 output wire [63:0] m_axis_dout_tdata);
divider_model #(.SIGNED_OP(0)) model(.*);
endmodule
