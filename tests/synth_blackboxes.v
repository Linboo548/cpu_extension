// 仅用于check_synth.tcl的RTL接口检查。不是功能模型，也不用于最终综合。
(* black_box *) module inst_ram(input clka,ena,input [3:0] wea,
 input [17:0] addra,input [31:0] dina,output [31:0] douta);endmodule
(* black_box *) module data_ram(input clka,ena,input [3:0] wea,
 input [15:0] addra,input [31:0] dina,output [31:0] douta);endmodule
(* black_box *) module div_signed(input aclk,aresetn,s_axis_dividend_tvalid,
 input [31:0] s_axis_dividend_tdata,input s_axis_divisor_tvalid,
 input [31:0] s_axis_divisor_tdata,output m_axis_dout_tvalid,output [63:0] m_axis_dout_tdata);endmodule
(* black_box *) module div_unsigned(input aclk,aresetn,s_axis_dividend_tvalid,
 input [31:0] s_axis_dividend_tdata,input s_axis_divisor_tvalid,
 input [31:0] s_axis_divisor_tdata,output m_axis_dout_tvalid,output [63:0] m_axis_dout_tdata);endmodule
