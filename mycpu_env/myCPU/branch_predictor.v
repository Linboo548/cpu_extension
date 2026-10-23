// [新增] 32项直接映射 BTB + 2位饱和计数器。仅 ID 真正离开时训练一次。
// 完整PC标签避免不同分支占用相同索引时误用旧目标；不预测未对齐地址。
module branch_predictor #(
    parameter ENABLE = 1,
    parameter INDEX_BITS = 5
)(
    input wire clk,
    input wire reset,
    input wire [31:0] lookup_pc,
    output wire predict_taken,
    output wire [31:0] predict_target,
    input wire update_valid,
    input wire update_is_branch,
    input wire update_conditional,
    input wire update_taken,
    input wire update_miss,
    input wire [31:0] update_pc,
    input wire [31:0] update_target,
    output reg [31:0] branch_count,
    output reg [31:0] miss_count
);
localparam ENTRIES = 1 << INDEX_BITS;
reg valid [0:ENTRIES-1];
reg [29:0] tag [0:ENTRIES-1];
reg [31:0] target [0:ENTRIES-1];
reg [1:0] counter [0:ENTRIES-1];
reg conditional [0:ENTRIES-1];
wire [INDEX_BITS-1:0] li = lookup_pc[INDEX_BITS+1:2];
wire [INDEX_BITS-1:0] ui = update_pc[INDEX_BITS+1:2];
wire update_hit = valid[ui] && tag[ui] == update_pc[31:2];
wire lookup_hit = valid[li] && tag[li] == lookup_pc[31:2];
assign predict_taken = ENABLE && !reset && lookup_pc[1:0] == 2'b0 &&
                       lookup_hit && (!conditional[li] || counter[li][1]);
assign predict_target = target[li];
integer i;
always @(posedge clk) begin
    if (reset) begin
        branch_count <= 0;
        miss_count <= 0;
        for (i=0; i<ENTRIES; i=i+1) begin
            valid[i] <= 1'b0;
            tag[i] <= 0;
            target[i] <= 0;
            counter[i] <= 2'b01; // 弱不跳转；首次实际结果作为训练
            conditional[i] <= 1'b0;
        end
    end else if (update_valid) begin
        if (update_is_branch) begin
            branch_count <= branch_count + 1'b1;
            if (update_miss) miss_count <= miss_count + 1'b1;
            if (ENABLE) begin
                valid[ui] <= 1'b1;
                tag[ui] <= update_pc[31:2];
                target[ui] <= update_target;
                conditional[ui] <= update_conditional;
                if (!update_conditional)
                    counter[ui] <= 2'b11;
                else if (!update_hit)
                    counter[ui] <= update_taken ? 2'b10 : 2'b01;
                else if (update_taken && counter[ui] != 2'b11)
                    counter[ui] <= counter[ui] + 1'b1;
                else if (!update_taken && counter[ui] != 2'b00)
                    counter[ui] <= counter[ui] - 1'b1;
            end
        end else if (ENABLE && update_hit) begin
            // 同一PC的指令被重新装载为非分支时，不能继续使用旧BTB项。
            valid[ui] <= 1'b0;
        end
    end
end
endmodule
