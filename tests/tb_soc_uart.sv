`timescale 1ns/1ps
module tb_soc_uart #(parameter BR_PREDICT_ENABLE=1,
                     parameter ICACHE_ENABLE=1, parameter DCACHE_ENABLE=1);
localparam CPB=64;
reg clk=0;always #5 clk=~clk;
reg resetn=0,rx=1;wire tx;wire [15:0] led;wire [31:0] num;
integer tx_count=0,irq_count=0,return_count=0;
reg [7:0] expected[0:2];reg [7:0] got;integer j;
soc_lite_top #(.SIMULATION(1)) dut(
 .clk(clk),.resetn(resetn),.switch(8'h5a),.btn_step(2'b11),.btn_key_row(4'hf),
 .led(led),.led_rg0(),.led_rg1(),.num_csn(),.num_a_g(),.num_data(num),
 .btn_key_col(),.uart_rx(rx),.uart_tx(tx));
defparam dut.cpu.BR_PREDICT_ENABLE=BR_PREDICT_ENABLE;
defparam dut.cpu.ICACHE_ENABLE=ICACHE_ENABLE;
defparam dut.cpu.DCACHE_ENABLE=DCACHE_ENABLE;
defparam dut.cpu.UART_CLKS_PER_BIT=CPB;
task send_byte(input [7:0] b);
 integer k;
 begin
  @(negedge clk);rx=0;repeat(CPB) @(negedge clk);
  for(k=0;k<8;k=k+1) begin rx=b[k];repeat(CPB) @(negedge clk);end
  rx=1;repeat(CPB) @(negedge clk);
 end
endtask
initial begin
 expected[0]=8'h41;expected[1]=8'h42;expected[2]=8'h7e;
 repeat(8) @(negedge clk);resetn=1;
 wait(dut.cpu.u_csr.csr_crmd_ie && dut.cpu.u_uart.irq_enable);
 repeat(30) @(negedge clk);
 for(integer k=0;k<3;k=k+1) begin
  send_byte(expected[k]);
  wait(tx_count==k+1 && return_count==k+1);
  repeat(2*CPB) @(negedge clk);
 end
 repeat(2*CPB) @(negedge clk);
 if(irq_count!=3 || num!==3 || led!==16'h007e || dut.cpu.u_uart.irq!==0)
  $fatal(1,"UART interrupt/display result wrong irq=%d num=%h led=%h",irq_count,num,led);
 $display("PASS SoC: 3 UART RX interrupts, EENTRY/ERA/ERTN, serial echo, LED and numeric display");
 $finish;
end
// 自动检查真实TX引脚的8N1位流，不读取UART内部移位寄存器冒充串口验证。
initial forever begin
 @(negedge tx);
 if(resetn) begin
  #(CPB*10/2);
  if(tx!==0) $fatal(1,"echo start bit");
  for(j=0;j<8;j=j+1) begin #(CPB*10);got[j]=tx;end
  #(CPB*10);
  if(tx_count>=3 || got!==expected[tx_count] || tx!==1)
   $fatal(1,"UART echo mismatch index=%d got=%h",tx_count,got);
  tx_count=tx_count+1;
 end
end
always @(posedge clk) if(resetn) begin
 if(dut.cpu.wb_ex) begin
  if(dut.cpu.wb_ecode!==0 || dut.cpu.wb_pc!==32'h1c000038)
   $fatal(1,"unexpected exception/ERA pc=%h ecode=%h",dut.cpu.wb_pc,dut.cpu.wb_ecode);
  irq_count=irq_count+1;
  #1;
  if(dut.cpu.u_csr.csr_crmd_ie!==0 || dut.cpu.u_csr.csr_prmd_pie!==1 ||
     dut.cpu.u_csr.csr_era_pc!==32'h1c000038)
   $fatal(1,"interrupt context save failed");
 end else if(dut.cpu.ertn_flush) begin
  return_count=return_count+1;
  #1;
  if(dut.cpu.u_csr.csr_crmd_ie!==1) $fatal(1,"ERTN did not restore IE");
 end
end
initial begin #1000000;$fatal(1,"SoC UART timeout");end
endmodule
