`timescale 1ns/1ps
module cache_cpu_harness #(parameter CACHE_ENABLE=1)(
 input wire clk,resetn, output reg done=0,
 output wire [31:0] pc,wd, output wire [3:0] we, output wire [4:0] wn,
 output reg [31:0] instruction_reads=0, data_reads=0, mmio_reads=0);
wire ie,de; wire [3:0] iw,dwe; wire [31:0] ia,idw,da,dw,idr,dr,ram_dr;
reg io_select=0; reg [31:0] io_data=0;
wire mmio=(da & 32'h1fff0000)==32'h1faf0000;
mycpu_top #(.ICACHE_ENABLE(CACHE_ENABLE),.DCACHE_ENABLE(CACHE_ENABLE)) dut(
 .clk(clk),.resetn(resetn),.hw_int_in(8'b0),.uart_rx(1'b1),.uart_tx(),
 .inst_sram_en(ie),.inst_sram_we(iw),.inst_sram_addr(ia),.inst_sram_wdata(idw),.inst_sram_rdata(idr),
 .data_sram_en(de),.data_sram_we(dwe),.data_sram_addr(da),.data_sram_wdata(dw),.data_sram_rdata(dr),
 .debug_wb_pc(pc),.debug_wb_rf_we(we),.debug_wb_rf_wnum(wn),.debug_wb_rf_wdata(wd),
 .bp_branch_count(),.bp_miss_count());
inst_ram im(.clka(clk),.ena(ie),.wea(iw),.addra(ia[19:2]),.dina(idw),.douta(idr));
data_ram dm(.clka(clk),.ena(de&&!mmio),.wea(dwe),.addra(da[17:2]),.dina(dw),.douta(ram_dr));
assign dr=io_select?io_data:ram_dr;
always @(posedge clk) begin
 if(!resetn) begin
  done<=0; instruction_reads<=0; data_reads<=0; mmio_reads<=0; io_select<=0;io_data<=0;
 end else if(!done) begin
  if(dut.wb_ex) $fatal(1,"cache benchmark unexpected exception pc=%h",dut.wb_pc);
  if(ie) instruction_reads<=instruction_reads+1;
  if(de) begin
   io_select<=mmio;
   if(mmio && !(|dwe)) begin io_data<=mmio_reads+1;mmio_reads<=mmio_reads+1;end
   if(!mmio && !(|dwe)) data_reads<=data_reads+1;
   if((da & 32'h1fffffe0)==32'h1faff100) $fatal(1,"private UART escaped CPU");
   if((|dwe) && da==32'h10001104) $fatal(1,"wrong-path store escaped");
   if((|dwe) && da==32'h10000100) begin
    if(dw!==1) $fatal(1,"cache benchmark reached FAIL path, cache=%0d",CACHE_ENABLE);
    if(mmio_reads!==2) $fatal(1,"MMIO reads duplicated or cached: %0d",mmio_reads);
    done<=1;
   end
  end
 end
end
endmodule

module tb_cache_cpu;
reg clk=0;always #5 clk=~clk;
reg resetn=0;
wire d0,d1; wire [31:0] p0,p1,w0,w1,ir0,ir1,dr0,dr1,mr0,mr1;
wire [3:0] e0,e1;wire [4:0] n0,n1;
cache_cpu_harness #(.CACHE_ENABLE(0)) uncached(clk,resetn,d0,p0,w0,e0,n0,ir0,dr0,mr0);
cache_cpu_harness #(.CACHE_ENABLE(1)) cached(clk,resetn,d1,p1,w1,e1,n1,ir1,dr1,mr1);
reg [68:0] trace0[0:4095],trace1[0:4095];integer len0=0,len1=0,checked=0;
initial begin repeat(8) @(negedge clk);resetn=1;end
always @(posedge clk) begin
 #1;
 if(resetn) begin
  if((|e0)&&n0!=0) begin
   if(len0>=4096) $fatal(1,"uncached trace overflow");
   trace0[len0]={p0,n0,w0};len0=len0+1;
  end
  if((|e1)&&n1!=0) begin
   if(len1>=4096) $fatal(1,"cached trace overflow");
   trace1[len1]={p1,n1,w1};len1=len1+1;
  end
  while(checked<len0 && checked<len1) begin
   if(trace0[checked]!==trace1[checked])
    $fatal(1,"Cache changed architectural writeback %0d: %h / %h",checked,trace0[checked],trace1[checked]);
   checked=checked+1;
  end
  if(d0&&d1) begin
   if(len0!=len1) $fatal(1,"Cache trace length differs");
   if(!(ir1<ir0 && dr1<dr0)) $fatal(1,"Cache failed to reduce external reads I=%0d/%0d D=%0d/%0d",ir0,ir1,dr0,dr1);
   if(cached.dut.icache_hit_count==0 || cached.dut.dcache_hit_count==0 ||
      cached.dut.icache_miss_count==0 || cached.dut.dcache_miss_count==0)
    $fatal(1,"Cache hit/miss coverage incomplete");
   $display("PASS CPU Cache: %0d identical writebacks; RAM reads OFF/ON I=%0d/%0d D=%0d/%0d; MMIO=%0d/%0d",
      checked,ir0,ir1,dr0,dr1,mr0,mr1);
   $finish;
  end
 end
end
initial begin #2000000;$fatal(1,"CPU Cache timeout");end
endmodule
