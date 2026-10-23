`include "mycpu_head.v"

module mycpu_top #(parameter BR_PREDICT_ENABLE = 1)(
    input  wire        clk,
    input  wire        resetn,
    // 新增：外部8路硬件中断
    input wire [7:0] hw_int_in,

    output wire        inst_sram_en,
    output wire [3:0]  inst_sram_we,
    output wire [31:0] inst_sram_addr,
    output wire [31:0] inst_sram_wdata,
    input  wire [31:0] inst_sram_rdata,

    output wire        data_sram_en,
    output wire [3:0]  data_sram_we,
    output wire [31:0] data_sram_addr,
    output wire [31:0] data_sram_wdata,
    input  wire [31:0] data_sram_rdata,

    output wire [31:0] debug_wb_pc,
    output wire [3:0]  debug_wb_rf_we,
    output wire [4:0]  debug_wb_rf_wnum,
    output wire [31:0] debug_wb_rf_wdata,
    // [新增] 预测器统计；关闭预测后也保留基线分支/纠错次数统计。
    output wire [31:0] bp_branch_count,
    output wire [31:0] bp_miss_count
);

//==============================================================
// 新增：WB 异常和返回信息
//==============================================================
wire        wb_ex;
wire        ertn_flush;
wire        wb_flush;
wire [5:0]  wb_ecode;
wire [8:0]  wb_esubcode;
wire [31:0] wb_pc;
// 新增：CSR 模块判断出的中断有效状态
wire has_int;

// 新增：CSR 写入/ERTN 未完成标志
wire es_csr_pending;
wire ms_csr_pending;
wire ws_csr_pending;

// 新增：WB 提交的错误地址
wire [31:0] wb_badv;

// 新增：MEM 提前通知 EXE 禁止后续访存/除法启动
wire ms_flush_pending;

wire reset = ~resetn;

/* IF <-> ID */
wire                         ds_allowin;
wire                         fs_to_ds_valid;
wire [`FS_TO_DS_BUS_WD-1:0]  fs_to_ds_bus;
wire [`BR_BUS_WD-1:0]        br_bus;

/* ID <-> EXE */
wire                         es_allowin;
wire                         ds_to_es_valid;
wire [`DS_TO_ES_BUS_WD-1:0]  ds_to_es_bus;

/* EXE <-> MEM */
wire                         ms_allowin;
wire                         es_to_ms_valid;
wire [`ES_TO_MS_BUS_WD-1:0]  es_to_ms_bus;

/* MEM <-> WB */
wire                         ws_allowin;
wire                         ms_to_ws_valid;
wire [`MS_TO_WS_BUS_WD-1:0]  ms_to_ws_bus;

/* WB -> regfile */
wire [`WS_TO_RF_BUS_WD-1:0]  ws_to_rf_bus;

/* EXE 前递信息 */
wire        es_valid;
wire        es_gr_we;
wire [4:0]  es_dest;
wire        es_load_op;
wire [31:0] es_alu_result;

/* MEM 前递信息 */
wire        ms_valid;
wire        ms_gr_we;
wire [4:0]  ms_dest;
wire [31:0] ms_final_result;

//==============================================================
// 新增：MEM → ID 的 CSR 等待标志
//==============================================================
wire ms_csr_re;

//==============================================================
// 新增：WB ? CSR 接口
//==============================================================
wire        csr_re;
wire        csr_we;
wire [13:0] csr_num;
wire [31:0] csr_wmask;
wire [31:0] csr_wvalue;
wire [31:0] csr_rvalue;

// 新增：暂时保留，下一步连接到 IF
wire [31:0] ex_entry;
wire [31:0] ertn_entry;

IF_stage #(.BR_PREDICT_ENABLE(BR_PREDICT_ENABLE)) u_IF_stage(
    .clk             (clk),
    .reset           (reset),
    
    .wb_ex          (wb_ex),
    .ertn_flush     (ertn_flush),
    .ex_entry       (ex_entry),
    .ertn_entry     (ertn_entry),

    .ds_allowin      (ds_allowin),
    .br_bus          (br_bus),

    .fs_to_ds_valid  (fs_to_ds_valid),
    .fs_to_ds_bus    (fs_to_ds_bus),

    .inst_sram_en    (inst_sram_en),
    .inst_sram_we    (inst_sram_we),
    .inst_sram_addr  (inst_sram_addr),
    .inst_sram_wdata (inst_sram_wdata),
    .inst_sram_rdata (inst_sram_rdata),
    .bp_branch_count (bp_branch_count),
    .bp_miss_count   (bp_miss_count)
);

ID_stage u_ID_stage(
    .clk             (clk),
    .reset           (reset),
    
        // 新增
    .wb_flush       (wb_flush),

    .es_allowin      (es_allowin),
    .ds_allowin      (ds_allowin),
    
    .has_int        (has_int),
    .es_csr_pending (es_csr_pending),
    .ms_csr_pending (ms_csr_pending),
    .ws_csr_pending (ws_csr_pending),

    .fs_to_ds_valid  (fs_to_ds_valid),
    .fs_to_ds_bus    (fs_to_ds_bus),

    .ds_to_es_valid  (ds_to_es_valid),
    .ds_to_es_bus    (ds_to_es_bus),

    .br_bus          (br_bus),
    .ws_to_rf_bus    (ws_to_rf_bus),

    .es_valid        (es_valid),
    .es_gr_we        (es_gr_we),
    .es_dest         (es_dest),
    .es_load_op      (es_load_op),
    .es_alu_result   (es_alu_result),

    .ms_valid        (ms_valid),
    .ms_gr_we        (ms_gr_we),
    .ms_dest         (ms_dest),
    .ms_final_result (ms_final_result),

     // 新增
    .ms_csr_re       (ms_csr_re)
);

EXE_stage u_EXE_stage(
    .clk               (clk),
    .reset             (reset),
        // 新增
    .wb_flush         (wb_flush),
    .ms_flush_pending (ms_flush_pending),

    .ms_allowin        (ms_allowin),
    .es_allowin        (es_allowin),
    
    .es_csr_pending (es_csr_pending),

    .ds_to_es_valid    (ds_to_es_valid),
    .ds_to_es_bus      (ds_to_es_bus),

    .es_to_ms_valid    (es_to_ms_valid),
    .es_to_ms_bus      (es_to_ms_bus),

    .data_sram_en      (data_sram_en),
    .data_sram_we      (data_sram_we),
    .data_sram_addr    (data_sram_addr),
    .data_sram_wdata   (data_sram_wdata),

    .es_valid_out      (es_valid),
    .es_gr_we_out      (es_gr_we),
    .es_dest_out       (es_dest),
    .es_load_op_out    (es_load_op),
    .es_alu_result_out (es_alu_result)
);

MEM_stage u_MEM_stage(
    .clk                 (clk),
    .reset               (reset),
        // 新增
    .wb_flush         (wb_flush),
    .ms_flush_pending (ms_flush_pending),

    .ws_allowin          (ws_allowin),
    .ms_allowin          (ms_allowin),
    
    .ms_csr_pending (ms_csr_pending),

    .es_to_ms_valid      (es_to_ms_valid),
    .es_to_ms_bus        (es_to_ms_bus),

    .ms_to_ws_valid      (ms_to_ws_valid),
    .ms_to_ws_bus        (ms_to_ws_bus),

    .data_sram_rdata     (data_sram_rdata),

    .ms_valid_out        (ms_valid),
    .ms_gr_we_out        (ms_gr_we),
    .ms_dest_out         (ms_dest),
    .ms_final_result_out (ms_final_result),

    // 新增
    .ms_csr_re_out       (ms_csr_re)
);

WB_stage u_WB_stage(
    .clk               (clk),
    .reset             (reset),

    .ws_allowin        (ws_allowin),
    .ms_to_ws_valid    (ms_to_ws_valid),
    .ms_to_ws_bus      (ms_to_ws_bus),
        // 新增
    .wb_ex          (wb_ex),
    .ertn_flush     (ertn_flush),
    .wb_flush       (wb_flush),
    .wb_ecode       (wb_ecode),
    .wb_esubcode    (wb_esubcode),
    .wb_pc          (wb_pc),
    
    .ws_csr_pending (ws_csr_pending),
    .wb_badv        (wb_badv),

    .ws_to_rf_bus      (ws_to_rf_bus),
     // 新增：WB 与 CSR 模块连接
    .csr_re            (csr_re),
    .csr_we            (csr_we),
    .csr_num           (csr_num),
    .csr_wmask         (csr_wmask),
    .csr_wvalue        (csr_wvalue),
    .csr_rvalue        (csr_rvalue),

    .debug_wb_pc       (debug_wb_pc),
    .debug_wb_rf_we    (debug_wb_rf_we),
    .debug_wb_rf_wnum  (debug_wb_rf_wnum),
    .debug_wb_rf_wdata (debug_wb_rf_wdata)
);

//==============================================================
// 新增：实例化第一阶段 CSR 模块
//==============================================================
csr u_csr(
    .clk          (clk),
    .reset        (reset),

    .csr_re       (csr_re),
    .csr_num      (csr_num),
    .csr_rvalue   (csr_rvalue),
    
    .hw_int_in      (hw_int_in),
    .has_int        (has_int),
    .wb_badv        (wb_badv),

    .csr_we       (csr_we),
    .csr_wmask    (csr_wmask),
    .csr_wvalue   (csr_wvalue),

    // 修改：原来的常量连接改成真实 WB 信号
    .wb_ex        (wb_ex),
    .wb_ecode     (wb_ecode),
    .wb_esubcode  (wb_esubcode),
    .wb_pc        (wb_pc),
    .ertn_flush   (ertn_flush),

    .ex_entry     (ex_entry),
    .ertn_entry   (ertn_entry)
);

endmodule
