`timescale 1ns/1ps
module tb_predictor;
reg clk=0; always #5 clk=~clk;
reg reset=1, uv=0, ub=0, uc=0, ut=0, um=0;
reg [31:0] pc=32'h1c000000, up=0, target=0;
wire taken; wire [31:0] pt, branches, misses;
branch_predictor dut(.clk(clk),.reset(reset),.lookup_pc(pc),
 .predict_taken(taken),.predict_target(pt),.update_valid(uv),
 .update_is_branch(ub),.update_conditional(uc),.update_taken(ut),
 .update_miss(um),.update_pc(up),.update_target(target),
 .branch_count(branches),.miss_count(misses));
task train(input [31:0] p, input bit b, input bit c, input bit t, input [31:0] dest);
 begin
  @(negedge clk); up=p; ub=b; uc=c; ut=t; target=dest; uv=1;
  @(negedge clk); uv=0;
 end
endtask
initial begin
 repeat(3) @(negedge clk); reset=0; #1;
 if(taken!==0) $fatal(1,"BTB must start invalid");
 train(pc,1,1,1,32'h1c000080); #1;
 if(taken!==1 || pt!==32'h1c000080) $fatal(1,"first taken training");
 train(pc,1,1,1,32'h1c000080);
 train(pc,1,1,1,32'h1c000080);
 train(pc,1,1,0,32'h1c000080); #1;
 if(taken!==1) $fatal(1,"two-bit hysteresis lost");
 train(pc,1,1,0,32'h1c000080); #1;
 if(taken!==0) $fatal(1,"two-bit transition to not-taken");
 // 相差128字节共用索引，必须用标签区分。
 train(32'h1c000080,1,0,1,32'h1c000100); #1;
 if(taken!==0) $fatal(1,"BTB alias tag mismatch");
 pc=32'h1c000080; #1;
 if(taken!==1 || pt!==32'h1c000100) $fatal(1,"unconditional target");
 train(pc,0,0,0,0); #1;
 if(taken!==0) $fatal(1,"nonbranch did not invalidate stale BTB");
 if(branches!==6) $fatal(1,"training count wrong: %d", branches);
 train(pc,1,0,1,32'h1c000120); #1;
 if(taken!==1 || pt!==32'h1c000120) $fatal(1,"target update failed");
 pc=32'h1c000081; #1;
 if(taken!==0) $fatal(1,"misaligned lookup predicted a branch");
 pc=32'h1c000080;
 @(negedge clk); reset=1;
 @(negedge clk); #1;
 if(taken!==0 || branches!==0 || misses!==0) $fatal(1,"reset did not clear predictor");
 reset=0;
 train(pc,1,1,0,32'h1c000100); #1;
 if(taken!==0) $fatal(1,"first not-taken branch predicted taken");
 train(pc,1,1,1,32'h1c000100); #1;
 if(taken!==1) $fatal(1,"weak not-taken counter failed to advance");
 $display("PASS predictor: saturation, hysteresis, PC tags, target changes, alignment, reset");
 $finish;
end
initial begin #10000; $fatal(1,"predictor timeout"); end
endmodule
