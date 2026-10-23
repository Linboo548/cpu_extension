`include "mycpu_head.v"

module WB_stage(
    input  wire                         clk,
    input  wire                         reset,

    output wire                         ws_allowin,
    input  wire                         ms_to_ws_valid,
    input  wire [`MS_TO_WS_BUS_WD-1:0]  ms_to_ws_bus,

    output wire [`WS_TO_RF_BUS_WD-1:0]  ws_to_rf_bus,

    // CSR 指令访问接口
    output wire                         csr_re,
    output wire                         csr_we,
    output wire [13:0]                  csr_num,
    output wire [31:0]                  csr_wmask,
    output wire [31:0]                  csr_wvalue,
    input  wire [31:0]                  csr_rvalue,

    // 新增：异常、返回和统一清空接口
    output wire                         wb_ex,
    output wire                         ertn_flush,
    output wire                         wb_flush,
    output wire [5:0]                   wb_ecode,
    output wire [8:0]                   wb_esubcode,
    output wire [31:0]                  wb_pc,

    output wire [31:0]                  debug_wb_pc,
    output wire [3:0]                   debug_wb_rf_we,
    output wire [4:0]                   debug_wb_rf_wnum,
    // 新增
    output wire        ws_csr_pending,
    output wire [31:0] wb_badv,
    output wire [31:0]                  debug_wb_rf_wdata
);

reg                                  ws_valid;
wire                                 ws_ready_go;
reg [`MS_TO_WS_BUS_WD-1:0]           ms_to_ws_bus_r;

// 新增：异常和返回标志
wire ws_syscall;
wire ws_ertn;

// 新增
wire [4:0]  ws_ex_flags;
wire [31:0] ws_badv;
wire        ws_has_ex;

wire        ws_csr_re;
wire        ws_csr_we;
wire [13:0] ws_csr_num;
wire [31:0] ws_csr_wmask;
wire [31:0] ws_csr_wvalue;

wire        ws_gr_we;
wire [4:0]  ws_dest;
wire [31:0] ws_final_result;
wire [31:0] ws_pc;

assign ws_has_ex =
    ws_syscall ||
    (|ws_ex_flags);

assign ws_csr_pending =
    ws_valid &&
    (ws_csr_we || ws_ertn);

assign wb_badv = ws_badv;

assign {
    ws_ex_flags,     // 新增
    ws_badv,         // 新增

    ws_syscall,
    ws_ertn,

    ws_csr_re,
    ws_csr_we,
    ws_csr_num,
    ws_csr_wmask,
    ws_csr_wvalue,

    ws_gr_we,
    ws_dest,
    ws_final_result,
    ws_pc
} = ms_to_ws_bus_r;

//==============================================================
// 新增：异常确认和 ERTN 返回
//==============================================================

// 修改：不再只处理 syscall
assign wb_ex =
    ws_valid &&
    ws_has_ex &&
    !reset;

// 异常优先于返回
assign ertn_flush =
    ws_valid &&
    ws_ertn &&
    !wb_ex &&
    !reset;

// 统一清空信号
assign wb_flush = wb_ex || ertn_flush;

// 修改：同一条指令存在多个标志时按优先级选择。
// 中断优先于同步异常；取指异常优先于后续阶段异常。
assign wb_ecode =
    ws_ex_flags[`EX_INT]  ? `ECODE_INT  :
    ws_ex_flags[`EX_ADEF] ? `ECODE_ADEF :
    ws_syscall           ? `ECODE_SYS  :
    ws_ex_flags[`EX_BRK]  ? `ECODE_BRK  :
    ws_ex_flags[`EX_INE]  ? `ECODE_INE  :
    ws_ex_flags[`EX_ALE]  ? `ECODE_ALE  :
                           6'b0;

// 本次实现的这些异常，二级编码均为0
assign wb_esubcode = 9'b0;

// CSR 用它记录触发异常的指令地址
assign wb_pc = ws_pc;


//==============================================================
// CSR 普通读写接口
//==============================================================

// 修改：异常/返回周期禁止普通 CSR 指令访问
assign csr_re =
    ws_valid &&
    ws_csr_re &&
    !reset &&
    !wb_flush;

assign csr_we =
    ws_valid &&
    ws_csr_we &&
    !reset &&
    !wb_flush;

assign csr_num    = ws_csr_num;
assign csr_wmask  = ws_csr_wmask;
assign csr_wvalue = ws_csr_wvalue;


//==============================================================
// 通用寄存器写回
//==============================================================

wire        rf_we;
wire [4:0]  rf_waddr;
wire [31:0] rf_wdata;

// 修改：异常和 ERTN 不允许产生普通寄存器写回
assign rf_we =
    ws_valid &&
    ws_gr_we &&
    !reset &&
    !wb_flush;

assign rf_waddr = ws_dest;

assign rf_wdata =
    ws_csr_re ? csr_rvalue :
                ws_final_result;

assign ws_to_rf_bus = {
    rf_we,
    rf_waddr,
    rf_wdata
};


//==============================================================
// Debug
//==============================================================

assign debug_wb_pc       = ws_pc;
assign debug_wb_rf_we    = {4{rf_we}};
assign debug_wb_rf_wnum  = rf_waddr;
assign debug_wb_rf_wdata = rf_wdata;


//==============================================================
// 流水线控制
//==============================================================

assign ws_ready_go = 1'b1;

assign ws_allowin =
    !ws_valid ||
    ws_ready_go;

always @(posedge clk) begin
    // 修改：触发清空后，WB 自己也撤销有效位
    if (reset || wb_flush) begin
        ws_valid <= 1'b0;
    end
    else if (ws_allowin) begin
        ws_valid <= ms_to_ws_valid;
    end

    if (!reset && !wb_flush &&
        ms_to_ws_valid && ws_allowin) begin
        ms_to_ws_bus_r <= ms_to_ws_bus;
    end
end

endmodule