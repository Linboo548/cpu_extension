`include "mycpu_head.v"

module MEM_stage(
    input  wire                         clk,
    input  wire                         reset,
    // 新增
    input  wire                         wb_flush,

    // 新增：通知 EXE，MEM 中存在即将清空流水线的指令
    output wire                         ms_flush_pending,

    input  wire                         ws_allowin,
    output wire                         ms_allowin,

    input  wire                         es_to_ms_valid,
    input  wire [`ES_TO_MS_BUS_WD-1:0]  es_to_ms_bus,

    output wire                         ms_to_ws_valid,
    output wire [`MS_TO_WS_BUS_WD-1:0]  ms_to_ws_bus,

    input  wire [31:0]                  data_sram_rdata,

    /* 向 ID 提供前递信息 */
    output wire                         ms_valid_out,
    output wire                         ms_gr_we_out,
    output wire [4:0]                   ms_dest_out,
    output wire [31:0]                  ms_forward_result_out,
    // 新增：通知 ID 等待 CSR 状态更新
    output wire ms_csr_pending,
    output wire                         ms_result_pending_out
);

reg                                 ms_valid;
reg [`ES_TO_MS_BUS_WD-1:0]          es_to_ms_bus_r;

// 新增
wire ms_syscall;
wire ms_ertn;
// 新增
wire [4:0] ms_ex_flags;
wire       ms_has_ex;
wire [31:0] ms_badv;
//==============================================================
// 新增：CSR 流水信息
//==============================================================
wire        ms_csr_re;
wire        ms_csr_we;
wire [13:0] ms_csr_num;
wire [31:0] ms_csr_wmask;
wire [31:0] ms_csr_wvalue;

wire        ms_gr_we;
wire [4:0]  ms_dest;
wire        ms_res_from_mem;
wire [31:0] ms_alu_result;
wire [31:0] ms_pc;
wire        ms_load_op;
wire        ms_mem_we;
wire [31:0] ms_rkd_value;
wire [1:0]  ms_mem_size;
wire        ms_mem_signed;


assign ms_has_ex =
    ms_syscall ||
    (|ms_ex_flags);

// ADEF 保存出错的取指 PC；ALE 保存计算出的访存地址
assign ms_badv =
    ms_ex_flags[`EX_ADEF] ? ms_pc : ms_alu_result;

assign ms_csr_pending =
    ms_valid &&
    (ms_csr_we || ms_ertn);
    
assign {
    ms_ex_flags,     // 新增

    ms_syscall,
    ms_ertn,

    ms_csr_re,
    ms_csr_we,
    ms_csr_num,
    ms_csr_wmask,
    ms_csr_wvalue,

    ms_gr_we,
    ms_dest,
    ms_res_from_mem,
    ms_alu_result,
    ms_pc,
    ms_load_op,
    ms_mem_we,
    ms_rkd_value,
    ms_mem_size,
    ms_mem_signed
} = es_to_ms_bus_r;

// 修改：任何异常都需要提前阻止后面的 EXE 访存
assign ms_flush_pending =
    ms_valid &&
    (ms_has_ex || ms_ertn);

/* 根据地址低位选择字节或半字 */
wire [7:0] selected_byte =
    (ms_alu_result[1:0] == 2'b00) ? data_sram_rdata[7:0]   :
    (ms_alu_result[1:0] == 2'b01) ? data_sram_rdata[15:8]  :
    (ms_alu_result[1:0] == 2'b10) ? data_sram_rdata[23:16] :
                                    data_sram_rdata[31:24];

wire [15:0] selected_half =
    ms_alu_result[1] ?
    data_sram_rdata[31:16] :
    data_sram_rdata[15:0];

wire [31:0] load_byte_result =
    ms_mem_signed ?
    {{24{selected_byte[7]}}, selected_byte} :
    {24'b0, selected_byte};

wire [31:0] load_half_result =
    ms_mem_signed ?
    {{16{selected_half[15]}}, selected_half} :
    {16'b0, selected_half};

wire [31:0] mem_result =
    (ms_mem_size == 2'b01) ? load_byte_result :
    (ms_mem_size == 2'b10) ? load_half_result :
                             data_sram_rdata;

wire [31:0] final_result =
    ms_res_from_mem ?
    mem_result :
    ms_alu_result;

/*
 * SRAM 请求已经由 EXE 阶段发出。
 * 指令进入 MEM 时，同步 RAM 的返回数据已经有效，
 * 所以 MEM 不需要额外等待周期。
 */
wire ms_ready_go = 1'b1;

assign ms_allowin =
    ~ms_valid ||
    (ms_ready_go && ws_allowin);

assign ms_to_ws_valid =
    ms_valid &&
    ms_ready_go &&
    !wb_flush;

// Load 与 CSR 的最终数据由 WB 前递，MEM 只给 ID 提供寄存后的运算结果。
assign ms_result_pending_out = ms_valid && (ms_res_from_mem || ms_csr_re);

/* MEM 前递信息 */
assign ms_valid_out        = ms_valid;
// 修改：异常指令不参与有效前递
assign ms_gr_we_out =
    ms_gr_we &&
    !ms_has_ex &&
    !ms_ertn;
assign ms_dest_out         = ms_dest;
assign ms_forward_result_out = ms_alu_result;

/* MEM -> WB 流水级总线*/
assign ms_to_ws_bus = {
    ms_ex_flags,     // 新增：5
    ms_badv,         // 新增：32

    ms_syscall,
    ms_ertn,

    ms_csr_re,
    ms_csr_we,
    ms_csr_num,
    ms_csr_wmask,
    ms_csr_wvalue,

    ms_gr_we,
    ms_dest,
    final_result,
    ms_pc
};

always @(posedge clk) begin
    if (reset || wb_flush) begin
        ms_valid <= 1'b0;
    end
    else if (ms_allowin) begin
        ms_valid <= es_to_ms_valid;
    end

    if (!reset && !wb_flush &&
        es_to_ms_valid && ms_allowin) begin
        es_to_ms_bus_r <= es_to_ms_bus;
    end
end

endmodule
