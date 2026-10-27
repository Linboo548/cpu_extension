`include "mycpu_head.v"

module IF_stage #(parameter BR_PREDICT_ENABLE = 1)(
    input  wire                         clk,
    input  wire                         reset,

    input  wire                         ds_allowin,
    input  wire [`BR_BUS_WD-1:0]        br_bus,

    // 新增：异常和 ERTN 重定向
    input  wire                         wb_ex,
    input  wire                         ertn_flush,
    input  wire [31:0]                  ex_entry,
    input  wire [31:0]                  ertn_entry,

    output wire                         fs_to_ds_valid,
    output wire [`FS_TO_DS_BUS_WD-1:0]  fs_to_ds_bus,

    output wire                         inst_sram_en,
    output wire [3:0]                   inst_sram_we,
    output wire [31:0]                  inst_sram_addr,
    output wire [31:0]                  inst_sram_wdata,
    input  wire [31:0]                  inst_sram_rdata,
    // Cache hit completes immediately; a miss holds the request until ready.
    input  wire                         inst_sram_ready,
    output wire                         inst_sram_cancel,
    // [新增] 统计已解析的分支及预测错误数，可供MMIO读取。
    output wire [31:0] bp_branch_count,
    output wire [31:0] bp_miss_count
);

reg         fs_valid;
reg [31:0]  fs_pc;

wire        fs_ready_go;
wire        fs_allowin;
wire        to_fs_valid;

wire        br_taken;
wire [31:0] br_target;
// ID 当拍只杀死错误路径，寄存后的取消信号避免接回 ID -> RAM 长路径。
reg         redirect_pending;
reg [31:0]  redirect_target;
reg         redirect_cancel;
// 已经开始的 miss 必须保持原请求地址，不能随 fs_valid 或 BTB 改变。
reg         fetch_waiting;
reg [31:0]  fetch_addr;

wire [31:0] seq_pc;
wire [31:0] nextpc;
wire [31:0] fs_inst;

// 新增：当前 IF 指令是否发生取指地址错
reg fs_adef;

// 新增：检查即将取指的地址
wire nextpc_adef;
assign nextpc_adef = |nextpc[1:0];

// 新增：本级使用的统一清空标志
wire wb_flush = wb_ex || ertn_flush;

// [修改] br_taken现在表示“预测错误需要纠正”，不再表示所有实际跳转。
wire bp_update_valid, bp_update_branch, bp_update_conditional, bp_update_taken;
wire [31:0] bp_update_pc, bp_update_target;
wire bp_taken;
wire [31:0] bp_target;
wire [31:0] fs_pred_nextpc;
assign {br_taken, br_target, bp_update_valid, bp_update_branch,
        bp_update_conditional, bp_update_taken, bp_update_pc,
        bp_update_target} = br_bus;
branch_predictor #(.ENABLE(BR_PREDICT_ENABLE)) u_predictor (
    .clk(clk), .reset(reset), .lookup_pc(fs_pc),
    .predict_taken(bp_taken), .predict_target(bp_target),
    .update_valid(bp_update_valid), .update_is_branch(bp_update_branch),
    .update_conditional(bp_update_conditional), .update_taken(bp_update_taken),
    .update_miss(br_taken), .update_pc(bp_update_pc),
    .update_target(bp_update_target), .branch_count(bp_branch_count),
    .miss_count(bp_miss_count)
);
// [新增] 与当前IF指令绑定的预测信息。ID阻塞时IF不发送新请求，
// 只有IF->ID接收的同一上升沿才使用这个预测值并取下一条指令。
assign fs_pred_nextpc = (fs_valid && !fs_adef && bp_taken) ? bp_target : seq_pc;

// 重定向目标一直保留到取指完成；异常/ERTN 优先于较年轻分支。
// redirect_cancel 只维持一拍，取消旧 miss 后可继续请求新目标。
always @(posedge clk) begin
    if (reset) begin
        redirect_pending <= 1'b0;
        redirect_target <= 32'b0;
        redirect_cancel <= 1'b0;
    end else if (wb_flush) begin
        redirect_pending <= 1'b1;
        redirect_target <= wb_ex ? ex_entry : ertn_entry;
        redirect_cancel <= 1'b0;
    end else begin
        redirect_cancel <= br_taken;
        if (br_taken) begin
            redirect_pending <= 1'b1;
            redirect_target <= br_target;
        end else if (redirect_pending && to_fs_valid) begin
            redirect_pending <= 1'b0;
        end
    end
end


//==============================================================
// Pre-IF：选择下一次取指地址
//==============================================================

// 请求与完成分开，不能用 ready 门控请求而形成组合环。
assign to_fs_valid = !reset && !inst_sram_cancel &&
                     (fs_allowin || redirect_pending) &&
                     (nextpc_adef || inst_sram_ready);

assign seq_pc = fs_pc + 32'd4;

// 异常/ERTN 已锁存到 redirect_target；miss 期间继续使用同一地址。
assign nextpc =
    redirect_pending ? redirect_target :
    fetch_waiting    ? fetch_addr : fs_pred_nextpc;


//==============================================================
// IF 控制
//==============================================================

assign fs_ready_go = 1'b1;

assign fs_allowin =
    !fs_valid ||
    (fs_ready_go && ds_allowin);

// 修改：清空周期不能把旧路径指令送进 ID
assign fs_to_ds_valid =
    fs_valid &&
    fs_ready_go &&
    !br_taken &&
    !redirect_pending &&
    !redirect_cancel &&
    !wb_flush;


//==============================================================
// 指令 SRAM 接口
//==============================================================

// 修改：非对齐地址不向 RAM 发起请求，
// 但仍通过 IF 有效位传递一条带 ADEF 标志的异常指令。
assign inst_sram_en =
    !reset && !inst_sram_cancel &&
    (fs_allowin || redirect_pending) &&
    !nextpc_adef;

assign inst_sram_cancel = wb_flush || redirect_cancel;

assign inst_sram_we    = 4'b0000;
assign inst_sram_addr  = nextpc;
assign inst_sram_wdata = 32'b0;


//==============================================================
// IF 流水寄存器
//==============================================================

always @(posedge clk) begin
    if (reset || wb_flush || br_taken || redirect_cancel) begin
        fs_valid <= 1'b0;
    end
    else if (fs_allowin || redirect_pending) begin
        // 仅完成请求才生成有效 token，miss 期间不重复发送旧指令。
        fs_valid <= to_fs_valid;
    end

    if (reset) begin
        fs_pc <= 32'h1bff_fffc;
    end
    else if (to_fs_valid && !br_taken) begin
        fs_pc <= nextpc;
    end

    if (reset || wb_flush || br_taken || redirect_cancel) begin
        fetch_waiting <= 1'b0;
        fetch_addr <= 32'b0;
    end else if (to_fs_valid) begin
        fetch_waiting <= 1'b0;
    end else if (inst_sram_en && !inst_sram_ready) begin
        fetch_waiting <= 1'b1;
        fetch_addr <= nextpc;
    end
end

// 修改：发生 ADEF 时不使用 RAM 中残留的旧指令
assign fs_inst =
    fs_adef ? 32'b0 : inst_sram_rdata;

// 修改：65位，最高位新增 ADEF
assign fs_to_ds_bus = {
    fs_pred_nextpc, // [新增] ID据此判断预测错误，支持跳/不跳和目标错误
    fs_adef,
    fs_inst,
    fs_pc
};
// 新增：ADEF 标志与 fs_pc 同步保存
always @(posedge clk) begin
    if (reset) begin
        fs_adef <= 1'b0;
    end
    else if (to_fs_valid && !br_taken) begin
        fs_adef <= nextpc_adef;
    end
end

endmodule
