`timescale 1ns/1ps
module tb_uart;
localparam CPB=16;
reg clk=0; always #5 clk=~clk;
reg resetn=0,en=0; reg [3:0] we=0;
reg [4:0] addr=0; reg [31:0] wd=0;
reg rx=1; wire tx,irq; wire [31:0] rd;
reg [31:0] value;
uart_mmio #(.DEFAULT_CLKS_PER_BIT(CPB)) dut(.clk(clk),.resetn(resetn),
 .en(en),.we(we),.addr(addr),.wdata(wd),.rdata(rd),
 .uart_rx(rx),.uart_tx(tx),.irq(irq),
 .bp_branch_count(32'd123),.bp_miss_count(32'd7));
task wr(input [4:0] a,input [31:0] d,input [3:0] mask);
 begin
  @(negedge clk); en=1;we=mask;addr=a;wd=d;
  @(negedge clk); en=0;we=0;
 end
endtask
task rr(input [4:0] a,output [31:0] d);
 begin
  @(negedge clk); en=1;we=0;addr=a;
  @(negedge clk); d=rd;en=0;
 end
endtask
task receive_frame(input [7:0] d,input bit good_stop);
 integer j;
 begin
  @(negedge clk);rx=0;repeat(CPB) @(negedge clk);
  for(j=0;j<8;j=j+1) begin rx=d[j];repeat(CPB) @(negedge clk);end
  rx=good_stop;repeat(CPB) @(negedge clk);
  rx=1;repeat(CPB) @(negedge clk);
 end
endtask
task check_tx(input [7:0] expected);
 integer j; reg [7:0] got;
 begin
  @(negedge tx);
  #(CPB*10/2);
  if(tx!==0) $fatal(1,"TX start bit");
  for(j=0;j<8;j=j+1) begin #(CPB*10);got[j]=tx;end
  #(CPB*10);
  if(tx!==1 || got!==expected) $fatal(1,"TX expected %h got %h",expected,got);
 end
endtask
initial begin
 repeat(5) @(negedge clk);resetn=1;
 rr(4,value);if(value!==1 || irq!==0 || tx!==1) $fatal(1,"reset status");
 rr(20,value);if(value!==123) $fatal(1,"branch MMIO counter");
 rr(24,value);if(value!==7) $fatal(1,"miss MMIO counter");
 rr(28,value);if(value!==32'h55415254) $fatal(1,"UART ID");
 // 全0字节使能是读取，不允许触发发送。
 wr(0,32'h41,0);if(tx!==1) $fatal(1,"zero byte-enable wrote UART");
 fork check_tx(8'hA5); wr(0,32'hA5,1); join
 repeat(CPB) @(negedge clk);
 rr(4,value);if(value[0]!==1) $fatal(1,"TX did not finish");
 receive_frame(8'h3c,1);
 rr(4,value);if(value[1]!==1 || irq!==0) $fatal(1,"RX or disabled IRQ");
 wr(8,1,1);if(irq!==1) $fatal(1,"pending RX did not assert enabled IRQ");
 rr(16,value);if(value!==1 || irq!==1) $fatal(1,"IRQ status must not consume RX");
 rr(0,value);if(value!==32'h3c || irq!==0) $fatal(1,"RX read must acknowledge IRQ");
 receive_frame(8'h11,1);receive_frame(8'h22,1);
 rr(4,value);if(value[2:1]!==2'b11) $fatal(1,"RX overrun not recorded");
 rr(0,value);if(value!==32'h22) $fatal(1,"overrun policy must preserve newest byte");
 wr(4,4,1);rr(4,value);if(value[2]!==0) $fatal(1,"overrun W1C");
 receive_frame(8'h55,0);
 rr(4,value);if(value[3]!==1 || value[1]!==0) $fatal(1,"bad stop bit accepted");
 wr(4,8,1);rr(4,value);if(value[3]!==0) $fatal(1,"frame error W1C");
 wr(12,0,15);rr(12,value);if(value!==4) $fatal(1,"divider minimum clamp");
 $display("PASS UART: 8N1 TX/RX, IRQ, overrun, framing, byte enables, MMIO");
 $finish;
end
initial begin #200000; $fatal(1,"UART timeout");end
endmodule
