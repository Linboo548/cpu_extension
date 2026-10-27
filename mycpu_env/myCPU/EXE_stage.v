`include "mycpu_head.v"

module EXE_stage(
    input  wire                         clk,
    input  wire                         reset,
     // 新增：WB 正式清空流水线
    input  wire                         wb_flush,

    // 新增：MEM 中有即将引起清空的 syscall/ertn
    input  wire                         ms_flush_pending,

    input  wire                         ms_allowin,
    output wire                         es_allowin,

    input  wire                         ds_to_es_valid,
    input  wire [`DS_TO_ES_BUS_WD-1:0]  ds_to_es_bus,

    output wire                         es_to_ms_valid,
    output wire [`ES_TO_MS_BUS_WD-1:0]  es_to_ms_bus,

    /* 数据 SRAM 接口：访问请求在 EXE 阶段发出 */
    output wire                         data_sram_en,
    output wire [3:0]                   data_sram_we,
    output wire [31:0]                  data_sram_addr,
    output wire [31:0]                  data_sram_wdata,
    input  wire                         data_sram_ready,

    /* 提供给 ID 阶段的前递信息 */
    output wire                         es_valid_out,
    output wire                         es_gr_we_out,
    output wire [4:0]                   es_dest_out,
    /*
     * 为尽量少改顶层接口，继续使用es_load_op_out。
     * 该信号现在表示：
     * "EXE中的结果当前不能直接前递给ID"。
     * 对Load来说，EXE中只有访存地址；
     * 对除法来说，需要等待多周期除法器完成。
     */
    output wire                         es_load_op_out,
    // 新增：向 ID 报告尚未提交的 CSR 写入/ERTN
    output wire es_csr_pending,
    output wire [31:0]                  es_alu_result_out
);

reg                                es_valid;
reg [`DS_TO_ES_BUS_WD-1:0]         ds_to_es_bus_r;

wire        es_ready_go;
// 新增：随指令携带的控制标志
wire es_syscall;
wire es_ertn;

// 新增：来自 ID 的异常信息和计数器控制
wire [3:0] es_ex_flags_in;
wire [1:0] es_rdcnt_op;

// 新增：加入 ALE 后的异常信息
wire [4:0] es_ex_flags;
wire       es_ale;
wire       es_has_ex;

// 新增：恒定频率自增计数器，不因异常清空而复位
reg [63:0] stable_counter;

always @(posedge clk) begin
    if (reset)
        stable_counter <= 64'b0;
    else
        stable_counter <= stable_counter + 64'd1;
end

//==============================================================
// 新增：CSR 流水信息
//==============================================================
wire        es_csr_re;
wire        es_csr_we;
wire [13:0] es_csr_num;
wire [31:0] es_csr_wmask;
wire [31:0] es_csr_wvalue;

wire [11:0] es_alu_op;
/* 新增：乘除法控制信号。
 * [0] mul.w
 * [1] mulh.w
 * [2] mulh.wu
 * [3] div.w
 * [4] mod.w
 * [5] div.wu
 * [6] mod.wu
 */
wire [6:0] es_mul_div_op;

wire        es_load_op;
wire        es_src1_is_pc;
wire        es_src2_is_imm;
wire        es_src2_is_4;
wire        es_gr_we;
wire        es_mem_we;
wire [4:0]  es_dest;
wire [31:0] es_imm;
wire [31:0] es_rj_value;
wire [31:0] es_rkd_value;
wire [31:0] es_pc;
wire        es_res_from_mem;
wire [1:0]  es_mem_size;
wire        es_mem_signed;

// ID -> EXE 总线拆分。
assign {
    es_ex_flags_in,
    es_rdcnt_op,

    es_syscall,
    es_ertn,

    es_csr_re,
    es_csr_we,
    es_csr_num,
    es_csr_wmask,
    es_csr_wvalue,

    es_alu_op,
    es_mul_div_op,
    es_load_op,
    es_src1_is_pc,
    es_src2_is_imm,
    es_src2_is_4,
    es_gr_we,
    es_mem_we,
    es_dest,
    es_imm,
    es_rj_value,
    es_rkd_value,
    es_pc,
    es_res_from_mem,
    es_mem_size,
    es_mem_signed
} = ds_to_es_bus_r;

/* ALU 输入选择 */
wire [31:0] alu_src1;
wire [31:0] alu_src2;
wire [31:0] alu_result;

//==============================================================
// 新增：地址非对齐检测
//
// mem_size：00字，01字节，10半字
// 字：地址低2位必须为0
// 半字：地址最低位必须为0
// 字节：无对齐限制
//==============================================================
assign es_ale =
    (es_load_op || es_mem_we) &&
    (
        ((es_mem_size == 2'b00) && (|alu_result[1:0])) ||
        ((es_mem_size == 2'b10) && alu_result[0])
    );

// [4]ALE；[3:0]来自 ID
assign es_ex_flags = {
    es_ale,
    es_ex_flags_in
};

assign es_has_ex =
    es_syscall ||
    (|es_ex_flags);

// 新增：让 ID 等待 CSR 状态写入完成
assign es_csr_pending =
    es_valid &&
    (es_csr_we || es_ertn);

assign alu_src1 =
    es_src1_is_pc ?
    es_pc :
    es_rj_value;

assign alu_src2 =
    es_src2_is_imm ?
    es_imm :
    es_rkd_value;

alu u_alu(
    .alu_op     (es_alu_op),
    .alu_src1   (alu_src1),
    .alu_src2   (alu_src2),
    .alu_result (alu_result)
);

/* ==================== 添加：乘法运算 ==================== */

wire es_mul_w   = es_mul_div_op[0];
wire es_mulh_w  = es_mul_div_op[1];
wire es_mulh_wu = es_mul_div_op[2];

wire es_mul_op =
    es_mul_w   |
    es_mulh_w  |
    es_mulh_wu;

/*
 * 有符号乘积和无符号乘积都保留64位。
 *
 * mul.w：
 *   取乘积低32位。低32位与有符号/无符号解释无关。
 *
 * mulh.w：
 *   两个操作数按有符号数相乘，取高32位。
 *
 * mulh.wu：
 *   两个操作数按无符号数相乘，取高32位。
 */
wire signed [63:0] signed_mul_result;
wire        [63:0] unsigned_mul_result;

assign signed_mul_result =
    $signed(es_rj_value) * $signed(es_rkd_value);

assign unsigned_mul_result =
    es_rj_value * es_rkd_value;

wire [31:0] mul_result =
    es_mul_w   ? signed_mul_result[31:0]   :
    es_mulh_w  ? signed_mul_result[63:32]  :
    es_mulh_wu ? unsigned_mul_result[63:32]:
                 32'b0;

/* ==================== 添加：除法运算 ==================== */

wire es_div_w  = es_mul_div_op[3];
wire es_mod_w  = es_mul_div_op[4];
wire es_div_wu = es_mul_div_op[5];
wire es_mod_wu = es_mul_div_op[6];

wire es_signed_div_op =
    es_div_w |
    es_mod_w;

wire es_unsigned_div_op =
    es_div_wu |
    es_mod_wu;

wire es_div_op =
    es_signed_div_op |
    es_unsigned_div_op;

/*
 * div_sent表示当前EXE中的除法请求是否已经发送给除法器。
 *
 * EXE会停留若干周期等待除法完成，所以必须记录请求是否已经发出，
 * 防止每个时钟周期都向除法器重复发送同一组操作数。
 */
reg div_sent;

wire        signed_dout_tvalid;//有符号除法器当前输出的数据是否有效。
wire [63:0] signed_dout_tdata;//高32位是商，低32位是余数

wire        unsigned_dout_tvalid;
wire [63:0] unsigned_dout_tdata;//无符号除法器当前输出的数据是否有效。


// 修改：已经标记异常的指令不能启动除法
wire signed_div_start =
    es_valid &&
    !es_has_ex &&
    es_signed_div_op &&
    !div_sent &&
    !reset &&
    !wb_flush &&
    !ms_flush_pending;

wire unsigned_div_start =
    es_valid &&
    !es_has_ex &&
    es_unsigned_div_op &&
    !div_sent &&
    !reset &&
    !wb_flush &&
    !ms_flush_pending;

/*
 * 有符号除法器。
 *
 * dividend：被除数，即rj
 * divisor ：除数，即rk
 *
 * 输出：
 * [63:32]为商
 * [31:0] 为余数
 */
div_signed u_div_signed(
    .aclk                       (clk),
    .aresetn                    (~reset),  // 低有效复位

    .s_axis_dividend_tvalid     (signed_div_start),//连接到被除数
    .s_axis_dividend_tdata      (alu_src1),

    .s_axis_divisor_tvalid      (signed_div_start),//连接到除数
    .s_axis_divisor_tdata       (alu_src2),

    .m_axis_dout_tvalid         (signed_dout_tvalid),
    .m_axis_dout_tdata          (signed_dout_tdata)
);

/* 无符号除法器 */
div_unsigned u_div_unsigned(
    .aclk                       (clk),
    .aresetn                    (~reset),  // 低有效复位

    .s_axis_dividend_tvalid     (unsigned_div_start),
    .s_axis_dividend_tdata      (alu_src1),

    .s_axis_divisor_tvalid      (unsigned_div_start),
    .s_axis_divisor_tdata       (alu_src2),

    .m_axis_dout_tvalid         (unsigned_dout_tvalid),
    .m_axis_dout_tdata          (unsigned_dout_tdata)
);


wire div_complete =
    div_sent &&
    (
        (es_signed_div_op   && signed_dout_tvalid)   |
        (es_unsigned_div_op && unsigned_dout_tvalid)
    );

/*
 * 选择商或余数：
 *
 * div.w/div.wu选择高32位商；
 * mod.w/mod.wu选择低32位余数。
 */
wire [31:0] div_result =
    es_div_w  ? signed_dout_tdata[63:32]   :
    es_mod_w  ? signed_dout_tdata[31:0]    :
    es_div_wu ? unsigned_dout_tdata[63:32] :
    es_mod_wu ? unsigned_dout_tdata[31:0]  :
                32'b0;

/*
 * 当前除法指令离开EXE后清除div_sent，
 * 使下一条除法指令能够重新发送请求。
 */
always @(posedge clk) begin
    // 修改：清空时同时丢弃本级的发送状态
    if (reset || wb_flush) begin
        div_sent <= 1'b0;
    end
    else if (es_allowin) begin
        div_sent <= 1'b0;
    end
    else if (signed_div_start || unsigned_div_start) begin
        div_sent <= 1'b1;
    end
end

/* ==================== EXE最终结果选择 ==================== */

/*
 * 普通指令使用ALU结果；
 * 乘法指令使用mul_result；
 * 除法指令使用div_result。
 */
// 修改：增加计数器结果
wire [31:0] exe_result =
    es_rdcnt_op[0] ? stable_counter[31:0]  :
    es_rdcnt_op[1] ? stable_counter[63:32] :
    es_mul_op     ? mul_result           :
    es_div_op     ? div_result           :
                    alu_result;

/* ==================== Store字节写使能 ==================== */

/*
 * mem_size：
 * 2'b00：字
 * 2'b01：字节
 * 2'b10：半字
 */
wire [3:0] store_byte_enable;

assign store_byte_enable =
    (es_mem_size == 2'b01) ?
        (4'b0001 << alu_result[1:0]) :
    (es_mem_size == 2'b10) ?
        (alu_result[1] ? 4'b1100 : 4'b0011) :
        4'b1111;

/*
 * 字节或半字写入时复制待写数据。
 * 实际写入哪个字节通道由data_sram_we决定。
 */
wire [31:0] store_data;

assign store_data =
    (es_mem_size == 2'b01) ?
        {4{es_rkd_value[7:0]}} :
    (es_mem_size == 2'b10) ?
        {2{es_rkd_value[15:0]}} :
        es_rkd_value;

/* ==================== 数据SRAM接口 ==================== */

//==============================================================
// 新增：EXE 访存是否允许真正发出
//==============================================================
wire es_mem_access_ok;
wire es_execute_ready = es_has_ex || !es_div_op || div_complete;
wire es_needs_memory = (es_load_op || es_mem_we) && !es_has_ex && !es_ertn;

// 修改：所有异常都禁止发出访存，尤其是 ALE
assign es_mem_access_ok =
    es_valid &&
    es_execute_ready &&
    ms_allowin &&
    !reset &&
    !wb_flush &&
    !ms_flush_pending &&
    !es_has_ex &&
    !es_ertn;

// 修改：错误路径上的 Load/Store 均不发起请求
assign data_sram_en =
    es_mem_access_ok &&
    (es_load_op || es_mem_we);

// 修改：特别禁止错误路径上的 Store 写内存
assign data_sram_we =
    (es_mem_access_ok && es_mem_we) ?
    store_byte_enable :
    4'b0000;

/*
 * Load/Store仍然使用普通ALU计算出来的地址，
 * 不能使用exe_result，因为exe_result还包括乘除法结果。
 */
assign data_sram_addr  = alu_result;
assign data_sram_wdata = store_data;

/* ==================== 提供给ID的前递信息 ==================== */

assign es_valid_out  = es_valid;
// 修改：异常指令不能成为有效的前递来源
assign es_gr_we_out =
    es_gr_we &&
    !es_has_ex &&
    !es_ertn;
assign es_dest_out   = es_dest;

/*
 * 复用原来的es_load_op_out信号：
 *
 * Load在EXE中只有地址，不能前递最终数据；
 * Divide在EXE中尚未完成时也不能前递最终数据。
 *
 * 因此两者都按照"EXE结果暂不可用"处理。
 */
assign es_load_op_out =
    es_load_op |
    es_div_op  |
    es_csr_re;
/*
 * 普通ALU和乘法结果可以直接从EXE前递。
 *
 * 对除法来说，依赖指令会等待除法进入MEM后，
 * 再使用MEM阶段的ms_final_result前递。
 */
assign es_alu_result_out = exe_result;

/* ==================== EXE -> MEM总线 ==================== */

/*
 * 乘除法结果已经统一放入exe_result，
 * 因此EXE -> MEM总线宽度不需要改变。
 */
assign es_to_ms_bus = {
    es_ex_flags,     // 新增：5

    es_syscall,
    es_ertn,

    es_csr_re,
    es_csr_we,
    es_csr_num,
    es_csr_wmask,
    es_csr_wvalue,

    es_gr_we,
    es_dest,
    es_res_from_mem,
    exe_result,
    es_pc,
    es_load_op,
    es_mem_we,
    es_rkd_value,
    es_mem_size,
    es_mem_signed
};

/* ==================== EXE流水线握手 ==================== */

/*
 * 普通指令和乘法指令一拍完成。
 *
 * 除法指令必须等Divider Generator产生m_axis_dout_tvalid，
 * 即div_complete=1后才能离开EXE。
 */
// 修改：已经发生异常时直接向后传递异常信息。
// 即使原指令是除法，也不能等待一个根本没有启动的除法请求。
// 请求有效不依赖 Cache ready；缺失时保持 EXE 指令和地址，直到完成。
assign es_ready_go = es_execute_ready && (!es_needs_memory || data_sram_ready);
    
assign es_allowin =
    ~es_valid ||
    (es_ready_go && ms_allowin);

assign es_to_ms_valid =
    es_valid &&
    es_ready_go &&
    !wb_flush;

/* ==================== EXE流水寄存器 ==================== */

always @(posedge clk) begin
    if (reset || wb_flush) begin
        es_valid <= 1'b0;
    end
    else if (es_allowin) begin
        es_valid <= ds_to_es_valid;
    end

    if (!reset && !wb_flush &&
        ds_to_es_valid && es_allowin) begin
        ds_to_es_bus_r <= ds_to_es_bus;
    end
end

endmodule
