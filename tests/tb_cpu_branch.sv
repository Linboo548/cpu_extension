`timescale 1ns/1ps
module branch_harness #(parameter ENABLE=1)(
 input wire clk,resetn,output reg done=0,output reg [31:0] cycles=0,
 output reg [31:0] branches=0,misses=0,
 output wire [31:0] pc,wd,output wire [3:0] we,output wire [4:0] wn);
wire ie,de;wire [3:0] iw,dwe;wire [31:0] ia,idw,da,dw,idr,dr,bc,mc;
mycpu_top #(.BR_PREDICT_ENABLE(ENABLE)) dut(.clk(clk),.resetn(resetn),.hw_int_in(8'b0),
 .inst_sram_en(ie),.inst_sram_we(iw),.inst_sram_addr(ia),.inst_sram_wdata(idw),.inst_sram_rdata(idr),
 .data_sram_en(de),.data_sram_we(dwe),.data_sram_addr(da),.data_sram_wdata(dw),.data_sram_rdata(dr),
 .debug_wb_pc(pc),.debug_wb_rf_we(we),.debug_wb_rf_wnum(wn),.debug_wb_rf_wdata(wd),
 .bp_branch_count(bc),.bp_miss_count(mc));
inst_ram im(.clka(clk),.ena(ie),.wea(iw),.addra(ia[19:2]),.dina(idw),.douta(idr));
data_ram dm(.clka(clk),.ena(de),.wea(dwe),.addra(da[17:2]),.dina(dw),.douta(dr));
always @(posedge clk) begin
 if(!resetn) begin done<=0;cycles<=0;branches<=0;misses<=0;end
 else if(!done) begin
  cycles<=cycles+1;
  if(dut.wb_ex) $fatal(1,"unexpected exception in branch benchmark pc=%h",dut.wb_pc);
  if(de && (|dwe) && da==32'h10000100) begin
   if(dw!==1) $fatal(1,"branch benchmark reached FAIL path");
   done<=1;branches<=bc;misses<=mc;
  end
 end
end
endmodule
module tb_cpu_branch;
reg clk=0;always #5 clk=~clk;
reg resetn=0;
wire d0,d1;wire [31:0] c0,c1,b0,b1,m0,m1,p0,p1,w0,w1;
wire [3:0] e0,e1;wire [4:0] n0,n1;
branch_harness #(.ENABLE(0)) baseline(clk,resetn,d0,c0,b0,m0,p0,w0,e0,n0);
branch_harness #(.ENABLE(1)) predicted(clk,resetn,d1,c1,b1,m1,p1,w1,e1,n1);
reg [68:0] trace0[0:2047],trace1[0:2047];integer len0=0,len1=0,checked=0;
initial begin repeat(8) @(negedge clk);resetn=1;end
always @(posedge clk) begin
 #1;
 if(resetn) begin
  if((|e0)&&n0!=0) begin trace0[len0]={p0,n0,w0};len0=len0+1;end
  if((|e1)&&n1!=0) begin trace1[len1]={p1,n1,w1};len1=len1+1;end
  while(checked<len0 && checked<len1) begin
   if(trace0[checked]!==trace1[checked]) $fatal(1,"prediction changed architectural trace at %d",checked);
   checked=checked+1;
  end
  if(d0&&d1) begin
   if(len0!=len1) $fatal(1,"architectural trace length differs");
   if(!(c1<c0 && m1<m0)) $fatal(1,"prediction did not improve loop: cycles=%d/%d misses=%d/%d",c0,c1,m0,m1);
   $display("PASS CPU prediction: identical %d writebacks; cycles OFF=%d ON=%d; misses OFF=%d ON=%d",checked,c0,c1,m0,m1);
   $finish;
  end
 end
end
initial begin #200000;$fatal(1,"CPU branch timeout");end
endmodule
