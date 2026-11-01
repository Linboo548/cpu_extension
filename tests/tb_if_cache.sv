`timescale 1ns/1ps
`include "mycpu_head.v"
// Controlled cache completion exercises IF independently of refill internals.
module tb_if_cache;
reg clk=0; always #5 clk=~clk;
reg reset=1,allowin=1,ready=0,wb_ex=0,ertn=0;
reg [31:0] ex_entry=32'h1c000200,ertn_entry=32'h1c000300;
reg br=0,uv=0,ub=0,uc=0,ut=0;
reg [31:0] target=0,up=0,bt=0;
wire [`BR_BUS_WD-1:0] br_bus={br,target,uv,ub,uc,ut,up,bt};
wire en,cancel,valid; wire [3:0] we;wire [31:0] addr,wdata,bc,mc;
reg [31:0] rdata=0;
wire [`FS_TO_DS_BUS_WD-1:0] bus;
IF_stage dut(.clk(clk),.reset(reset),.ds_allowin(allowin),.br_bus(br_bus),
 .wb_ex(wb_ex),.ertn_flush(ertn),.ex_entry(ex_entry),.ertn_entry(ertn_entry),
 .fs_to_ds_valid(valid),.fs_to_ds_bus(bus),.inst_sram_en(en),.inst_sram_we(we),
 .inst_sram_addr(addr),.inst_sram_wdata(wdata),.inst_sram_rdata(rdata),
 .inst_sram_ready(ready),.inst_sram_cancel(cancel),.bp_branch_count(bc),.bp_miss_count(mc));
always @(posedge clk) if(en && ready && !cancel) rdata<=addr^32'h13572468;
task tick; begin @(posedge clk);#1; end endtask
task drive; begin @(negedge clk);#1;end endtask
task waiting(input [31:0] p);
 begin
  if(!en || addr!==p || valid!==0) $fatal(1,"unstable miss p=%h addr=%h en=%b valid=%b",p,addr,en,valid);
 end
endtask
task token(input [31:0] p,input bit adef);
 begin
  if(!valid || bus[31:0]!==p || bus[64]!==adef) $fatal(1,"wrong token p=%h pc=%h adef=%b valid=%b",p,bus[31:0],bus[64],valid);
  if(!adef && bus[63:32] !== (p^32'h13572468)) $fatal(1,"instruction/PC mismatch");
 end
endtask
initial begin
 repeat(3) tick();drive();reset=0;
 repeat(4) begin tick();waiting(32'h1c000000);end
 drive();ready=1;tick();token(32'h1c000000,0);
 drive();ready=0;tick();waiting(32'h1c000004);
 repeat(3) begin tick();waiting(32'h1c000004);end
 drive();br=1;target=32'h1c000100;tick();
 if(!cancel || en || valid) $fatal(1,"branch cancellation missing");
 drive();br=0;tick();waiting(32'h1c000100);
 repeat(3) begin tick();waiting(32'h1c000100);end
 drive();ready=1;tick();token(32'h1c000100,0);
 drive();allowin=0;repeat(3) begin tick();token(32'h1c000100,0);if(en) $fatal(1,"fetch overwrote stalled token");end
 drive();allowin=1;ready=0;tick();waiting(32'h1c000104);
 drive();wb_ex=1;ertn=1;tick();if(en||valid||!cancel) $fatal(1,"WB flush failed");
 drive();wb_ex=0;ertn=0;tick();waiting(32'h1c000200);
 repeat(3) begin tick();waiting(32'h1c000200);end
 drive();ready=1;tick();token(32'h1c000200,0);
 drive();ready=0;tick();waiting(32'h1c000204);
 drive();ertn=1;tick();if(en||valid||!cancel) $fatal(1,"ERTN flush failed");
 drive();ertn=0;tick();waiting(32'h1c000300);
 repeat(3) begin tick();waiting(32'h1c000300);end
 drive();ready=1;tick();token(32'h1c000300,0);
 drive();ready=0;tick();waiting(32'h1c000304);
 drive();br=1;target=32'h1c000402;tick();
 drive();br=0;tick();
 if(en) $fatal(1,"misaligned redirect sent memory request");
 tick();token(32'h1c000402,1);
 drive();br=1;target=32'h1c000500;ready=0;tick();
 drive();br=0;uv=1;ub=1;uc=0;ut=1;up=32'h1c000500;bt=32'h1c000600;tick();
 drive();uv=0;tick();waiting(32'h1c000500);
 drive();ready=1;tick();token(32'h1c000500,0);
 if(bus[96:65]!==32'h1c000600) $fatal(1,"BTB prediction missing");
 drive();ready=0;tick();waiting(32'h1c000600);
 repeat(5) begin tick();waiting(32'h1c000600);end
 drive();ready=1;tick();token(32'h1c000600,0);
 $display("PASS IF cache waits: stable addresses, predicted target, stalled token, branch cancel, WB/ERTN priority, ADEF");
 $finish;
end
initial begin #10000;$fatal(1,"timeout");end
endmodule
