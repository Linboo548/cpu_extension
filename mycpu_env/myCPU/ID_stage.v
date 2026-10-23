`include "mycpu_head.v"

module ID_stage(
    input  wire                         clk,
    input  wire                         reset,
    // 新增：WB 发来的流水线清空信号
    input  wire                         wb_flush,
    
    // 新增：中断状态
    input wire has_int,
    
    // 新增：前面的 CSR 写入或 ERTN 尚未完成
    input wire es_csr_pending,
    input wire ms_csr_pending,
    input wire ws_csr_pending,

    input  wire                         es_allowin,
    output wire                         ds_allowin,

    input  wire                         fs_to_ds_valid,
    input  wire [`FS_TO_DS_BUS_WD-1:0]  fs_to_ds_bus,

    output wire                         ds_to_es_valid,
    output wire [`DS_TO_ES_BUS_WD-1:0]  ds_to_es_bus,

    output wire [`BR_BUS_WD-1:0]        br_bus,
    input  wire [`WS_TO_RF_BUS_WD-1:0]  ws_to_rf_bus,

    /* EXE 前递信息 */
    input  wire                         es_valid,
    input  wire                         es_gr_we,
    input  wire [4:0]                   es_dest,
    input  wire                         es_load_op,
    input  wire [31:0]                  es_alu_result,

    /* MEM 前递信息 */
    input  wire                         ms_valid,
    input  wire                         ms_gr_we,
    input  wire [4:0]                   ms_dest,
    input  wire [31:0]                  ms_final_result,

    // 新增：MEM 中的 CSR 结果尚不能使用
    input  wire                         ms_csr_re
);

reg                                  ds_valid;
reg  [`FS_TO_DS_BUS_WD-1:0]          fs_to_ds_bus_r;

wire [31:0] ds_inst;
wire [31:0] ds_pc;

// 新增
wire ds_adef;
// [新增] IF针对本条指令实际选择过的下一取指PC；随流水寄存器保存。
wire [31:0] ds_pred_nextpc;

// 修改：65位解包
assign {ds_pred_nextpc, ds_adef, ds_inst, ds_pc} = fs_to_ds_bus_r;

/* 指令字段 */
wire [5:0]  op_31_26 = ds_inst[31:26];
wire [3:0]  op_25_22 = ds_inst[25:22];
wire [1:0]  op_21_20 = ds_inst[21:20];
wire [4:0]  op_19_15 = ds_inst[19:15];

wire [4:0]  rd = ds_inst[4:0];  //通常情况目标寄存器
wire [4:0]  rj = ds_inst[9:5];  //通常情况第一个源寄存器
wire [4:0]  rk = ds_inst[14:10];//通常情况第二个源寄存器

wire [11:0] i12 = ds_inst[21:10];                    //addi.w、Load、Store
wire [19:0] i20 = ds_inst[24:5];                     //lu12i.w、pcaddu12i
wire [15:0] i16 = ds_inst[25:10];                    //条件分支、jirl
wire [25:0] i26 = {ds_inst[9:0], ds_inst[25:10]};    //b、bl

/* 译码器 */
wire [63:0] op_31_26_d;
wire [15:0] op_25_22_d;
wire [3:0]  op_21_20_d;
wire [31:0] op_19_15_d;

decoder_6_64 u_dec0(
    .in  (op_31_26),
    .out (op_31_26_d)
);

decoder_4_16 u_dec1(
    .in  (op_25_22),
    .out (op_25_22_d)
);

decoder_2_4 u_dec2(
    .in  (op_21_20),
    .out (op_21_20_d)
);

decoder_5_32 u_dec3(
    .in  (op_19_15),
    .out (op_19_15_d)
);
//==============================================================
// 新增：系统调用和异常返回指令
//==============================================================

// syscall 的低 15 位是 code，不参与指令类别判断
wire inst_syscall =
    op_31_26_d[6'h00] &&
    op_25_22_d[4'h0]  &&
    op_21_20_d[2'h2]  &&
    op_19_15_d[5'h16];

// ertn 没有操作数，匹配完整指令码
wire inst_ertn = (ds_inst == 32'h06483800);

/* 基本运算指令 */
wire inst_add_w =
    op_31_26_d[6'h00] &&
    op_25_22_d[4'h0]  &&
    op_21_20_d[2'h1]  &&
    op_19_15_d[5'h00];

wire inst_sub_w =
    op_31_26_d[6'h00] &&
    op_25_22_d[4'h0]  &&
    op_21_20_d[2'h1]  &&
    op_19_15_d[5'h02];
//有符号小于比较
wire inst_slt =
    op_31_26_d[6'h00] &&
    op_25_22_d[4'h0]  &&
    op_21_20_d[2'h1]  &&
    op_19_15_d[5'h04];
//无符号小于比较
wire inst_sltu =
    op_31_26_d[6'h00] &&
    op_25_22_d[4'h0]  &&
    op_21_20_d[2'h1]  &&
    op_19_15_d[5'h05];

wire inst_nor =
    op_31_26_d[6'h00] &&
    op_25_22_d[4'h0]  &&
    op_21_20_d[2'h1]  &&
    op_19_15_d[5'h08];

wire inst_and =
    op_31_26_d[6'h00] &&
    op_25_22_d[4'h0]  &&
    op_21_20_d[2'h1]  &&
    op_19_15_d[5'h09];

wire inst_or =
    op_31_26_d[6'h00] &&
    op_25_22_d[4'h0]  &&
    op_21_20_d[2'h1]  &&
    op_19_15_d[5'h0a];

wire inst_xor =
    op_31_26_d[6'h00] &&
    op_25_22_d[4'h0]  &&
    op_21_20_d[2'h1]  &&
    op_19_15_d[5'h0b];

//乘除法指令译码
/*
 * 乘法指令：
 * mul.w   rd, rj, rk：取乘积低32位
 * mulh.w  rd, rj, rk：取有符号乘积高32位
 * mulh.wu rd, rj, rk：取无符号乘积高32位
 */
wire inst_mul_w =
    op_31_26_d[6'h00] &&
    op_25_22_d[4'h0]  &&
    op_21_20_d[2'h1]  &&
    op_19_15_d[5'h18];

wire inst_mulh_w =
    op_31_26_d[6'h00] &&
    op_25_22_d[4'h0]  &&
    op_21_20_d[2'h1]  &&
    op_19_15_d[5'h19];

wire inst_mulh_wu =
    op_31_26_d[6'h00] &&
    op_25_22_d[4'h0]  &&
    op_21_20_d[2'h1]  &&
    op_19_15_d[5'h1a];

/*
 * 除法指令：
 * div.w   rd, rj, rk：有符号商
 * mod.w   rd, rj, rk：有符号余数
 * div.wu  rd, rj, rk：无符号商
 * mod.wu  rd, rj, rk：无符号余数
 */
wire inst_div_w =
    op_31_26_d[6'h00] &&
    op_25_22_d[4'h0]  &&
    op_21_20_d[2'h2]  &&
    op_19_15_d[5'h00];

wire inst_mod_w =
    op_31_26_d[6'h00] &&
    op_25_22_d[4'h0]  &&
    op_21_20_d[2'h2]  &&
    op_19_15_d[5'h01];

wire inst_div_wu =
    op_31_26_d[6'h00] &&
    op_25_22_d[4'h0]  &&
    op_21_20_d[2'h2]  &&
    op_19_15_d[5'h02];

wire inst_mod_wu =
    op_31_26_d[6'h00] &&
    op_25_22_d[4'h0]  &&
    op_21_20_d[2'h2]  &&
    op_19_15_d[5'h03];

/* 乘除法指令统一标志 */
wire all_mul_div =
    inst_mul_w   |
    inst_mulh_w  |
    inst_mulh_wu |
    inst_div_w   |
    inst_mod_w   |
    inst_div_wu  |
    inst_mod_wu;

/*
 * 传给EXE的7位乘除法控制信号。
 *
 * [0] mul.w
 * [1] mulh.w
 * [2] mulh.wu
 * [3] div.w
 * [4] mod.w
 * [5] div.wu
 * [6] mod.wu
 */
wire [6:0] mul_div_op;

assign mul_div_op = {
    inst_mod_wu,
    inst_div_wu,
    inst_mod_w,
    inst_div_w,
    inst_mulh_wu,
    inst_mulh_w,
    inst_mul_w
};
/* 立即数逻辑左移 */
wire inst_slli_w =
    op_31_26_d[6'h00] &&
    op_25_22_d[4'h1]  &&
    op_21_20_d[2'h0]  &&
    op_19_15_d[5'h01];
/* 立即数逻辑右移 */
wire inst_srli_w =
    op_31_26_d[6'h00] &&
    op_25_22_d[4'h1]  &&
    op_21_20_d[2'h0]  &&
    op_19_15_d[5'h09];
/* 立即数算术右移 */
wire inst_srai_w =
    op_31_26_d[6'h00] &&
    op_25_22_d[4'h1]  &&
    op_21_20_d[2'h0]  &&
    op_19_15_d[5'h11];
// 逻辑左移 rd = rj << rk[4:0] 右侧补0
wire inst_sll_w =
    op_31_26_d[6'h00] &&
    op_25_22_d[4'h0]  &&
    op_21_20_d[2'h1]  &&
    op_19_15_d[5'h0e];
//逻辑右移   左侧补0
wire inst_srl_w =
    op_31_26_d[6'h00] &&
    op_25_22_d[4'h0]  &&
    op_21_20_d[2'h1]  &&
    op_19_15_d[5'h0f];
//算术右移  左侧补符号位
wire inst_sra_w =
    op_31_26_d[6'h00] &&
    op_25_22_d[4'h0]  &&
    op_21_20_d[2'h1]  &&
    op_19_15_d[5'h10];

/* 立即数运算 */
wire inst_addi_w =
    op_31_26_d[6'h00] &&
    op_25_22_d[4'ha];
//有符号立即数小于比较
wire inst_slti =
    op_31_26_d[6'h00] &&
    op_25_22_d[4'h8];
//无符号立即数小于比较(符号扩展，按照无符号数进行比较)
wire inst_sltui =
    op_31_26_d[6'h00] &&
    op_25_22_d[4'h9];
//立即数按位与（零扩展）
wire inst_andi =
    op_31_26_d[6'h00] &&
    op_25_22_d[4'hd];
//立即数按位或
wire inst_ori =
    op_31_26_d[6'h00] &&
    op_25_22_d[4'he];
//立即数按位异或
wire inst_xori =
    op_31_26_d[6'h00] &&
    op_25_22_d[4'hf];

/* 跳转和分支 */
//寄存器间接跳转并保存返回地址
wire inst_jirl = op_31_26_d[6'h13];
//无条件相对跳转
wire inst_b    = op_31_26_d[6'h14];
//跳转并链接（把返回地址保存在 r1寄存器）
wire inst_bl   = op_31_26_d[6'h15];
//相等则跳
wire inst_beq  = op_31_26_d[6'h16];
//不等则跳
wire inst_bne  = op_31_26_d[6'h17];
//有符号小于则跳转
wire inst_blt  = op_31_26_d[6'h18];
//有符号大于等于则跳转
wire inst_bge  = op_31_26_d[6'h19];
//无符号小于则跳转
wire inst_bltu = op_31_26_d[6'h1a];
//无符号大于等于则跳转
wire inst_bgeu = op_31_26_d[6'h1b];

/* 高位立即数 */
wire inst_lu12i_w =
    op_31_26_d[6'h05] &&
    ~ds_inst[25];
//PC 加高位立即数（rd = PC + (si20 << 12)）
wire inst_pcaddu12i =
    op_31_26_d[6'h07] &&
    ~ds_inst[25];

/* 访存指令 */
wire inst_ld_b =
    op_31_26_d[6'h0a] &&
    op_25_22_d[4'h0];

wire inst_ld_h =
    op_31_26_d[6'h0a] &&
    op_25_22_d[4'h1];

wire inst_ld_w =
    op_31_26_d[6'h0a] &&
    op_25_22_d[4'h2];

wire inst_st_b =
    op_31_26_d[6'h0a] &&
    op_25_22_d[4'h4];

wire inst_st_h =
    op_31_26_d[6'h0a] &&
    op_25_22_d[4'h5];

wire inst_st_w =
    op_31_26_d[6'h0a] &&
    op_25_22_d[4'h6];

wire inst_ld_bu =
    op_31_26_d[6'h0a] &&
    op_25_22_d[4'h8];

wire inst_ld_hu =
    op_31_26_d[6'h0a] &&
    op_25_22_d[4'h9];
// 所有Load指令
wire all_lds = inst_ld_w  |
               inst_ld_b  |
               inst_ld_h  |
               inst_ld_bu |
               inst_ld_hu;
// 所有Store指令
wire all_sts = inst_st_w |
               inst_st_b |
               inst_st_h;

wire all_ls = all_lds | all_sts;

wire condition_branch = inst_beq  |
                        inst_bne  |
                        inst_blt  |
                        inst_bge  |
                        inst_bltu |
                        inst_bgeu;
//==============================================================
// CSR 译码：从原位置移到这里，避免先使用后声明
//==============================================================

wire inst_csr_common = (ds_inst[31:24] == 8'h04);

wire inst_csrrd =
    inst_csr_common && (rj == 5'd0);

wire inst_csrwr =
    inst_csr_common && (rj == 5'd1);

wire inst_csrxchg =
    inst_csr_common &&
    (rj != 5'd0) &&
    (rj != 5'd1);

wire all_csr =
    inst_csrrd |
    inst_csrwr |
    inst_csrxchg;

wire [13:0] csr_num;
wire        csr_re;
wire        csr_we;
wire [31:0] csr_wmask;
wire [31:0] csr_wvalue;

// 修改：提前声明，原位置改为 assign
wire arithmetic_write;


//==============================================================
// 新增：BREAK、计数器指令
//==============================================================

// BREAK 低15位是 code
wire inst_break = (ds_inst[31:15] == 17'h54);

// RDCNTVL.W：rj 字段固定为0，结果写 rd
wire inst_rdcntvl_w =
    (ds_inst[31:10] == 22'h18) &&
    (rj == 5'd0);

// RDCNTVH.W：rj 字段固定为0，结果写 rd
wire inst_rdcntvh_w =
    (ds_inst[31:10] == 22'h19) &&
    (rj == 5'd0);

// RDCNTID：rd 字段固定为0，结果写 rj
// rj=0、rd=0 的重合编码归入 RDCNTVL.W，写r0无副作用。
wire inst_rdcntid =
    (ds_inst[31:10] == 22'h18) &&
    (rd == 5'd0) &&
    (rj != 5'd0);

// [0]读低32位；[1]读高32位
wire [1:0] rdcnt_op = {
    inst_rdcntvh_w,
    inst_rdcntvl_w
};


//==============================================================
// 新增：指令不存在异常及其他异常标志
//==============================================================

wire inst_known =
    arithmetic_write |
    all_lds |
    all_sts |
    condition_branch |
    inst_jirl |
    inst_b |
    inst_bl |
    all_csr |
    inst_syscall |
    inst_break |
    inst_ertn |
    inst_rdcntvl_w |
    inst_rdcntvh_w |
    inst_rdcntid;

wire inst_ine = !inst_known;

// [0]INT，[1]ADEF，[2]BRK，[3]INE
wire [3:0] ds_ex_flags = {
    inst_ine,
    inst_break,
    ds_adef,
    has_int
};

wire ds_has_ex =
    inst_syscall ||
    (|ds_ex_flags);

/* ALU 控制 */
wire [11:0] alu_op;
//alu加法控制位
assign alu_op[0] = inst_add_w     |
                   inst_addi_w    |
                   all_ls         |
                   inst_jirl      |
                   inst_bl        |
                   inst_pcaddu12i;
// 减法控制位                   
assign alu_op[1] = inst_sub_w;

// slti复用有符号小于比较
assign alu_op[2] =
    inst_slt |
    inst_slti;

// sltui复用无符号小于比较
assign alu_op[3] =
    inst_sltu |
    inst_sltui;

// andi、ori、xori复用原有逻辑运算
//与
assign alu_op[4] =
    inst_and |
    inst_andi;
//或非
assign alu_op[5] = inst_nor;
//或
assign alu_op[6] =
    inst_or |
    inst_ori;
//异或
assign alu_op[7] =
    inst_xor |
    inst_xori;

// 寄存器移位复用原来的移位器
assign alu_op[8] =
    inst_slli_w |
    inst_sll_w;

assign alu_op[9] =
    inst_srli_w |
    inst_srl_w;

assign alu_op[10] =
    inst_srai_w |
    inst_sra_w;

assign alu_op[11] = inst_lu12i_w;

/* 访存宽度 */
// 00：字，01：字节，10：半字
wire [1:0] mem_size;
// ld.b、ld.h需要符号扩展
// ld.bu、ld.hu需要零扩展
wire       mem_signed;

assign mem_size =
    (inst_ld_b | inst_ld_bu | inst_st_b) ? 2'b01 :   //字节
    (inst_ld_h | inst_ld_hu | inst_st_h) ? 2'b10 :   //半字
                                           2'b00;    //字

assign mem_signed = inst_ld_b | inst_ld_h;    //有符号读取标志

/* 立即数生成 */
wire need_ui5  = inst_slli_w |
                 inst_srli_w |
                 inst_srai_w;

wire need_ui12 = inst_andi |
                 inst_ori  |
                 inst_xori;

wire need_si20 = inst_lu12i_w |
                 inst_pcaddu12i;

wire need_si26 = inst_b |
                 inst_bl;

wire src2_is_4 = inst_jirl |
                 inst_bl;

wire [31:0] imm;
wire [31:0] br_offs;
wire [31:0] jirl_offs;

assign imm =
    src2_is_4 ? 32'd4 ://jirl 和 bl 都需要保存返回地址：
    need_si20 ? {i20, 12'b0} ://补0，把 20 位立即数放到结果的高 20 位
    need_ui5  ? {27'b0, rk} ://rk表示5 位移位量。
    need_ui12 ? {20'b0, i12} ://无符号扩展
                {{20{i12[11]}}, i12};

assign br_offs =
    need_si26 ?
    {{4{i26[25]}}, i26, 2'b0} :
    {{14{i16[15]}}, i16, 2'b0};

assign jirl_offs =
    {{14{i16[15]}}, i16, 2'b0};

/* 数据通路控制 */
wire src1_is_pc;
wire src2_is_imm;
wire res_from_mem;
wire load_op;
wire gr_we;
wire mem_we;
wire [4:0] dest;

assign src1_is_pc =
    inst_jirl |
    inst_bl   |
    inst_pcaddu12i;

assign src2_is_imm =
    inst_slli_w |
    inst_srli_w |
    inst_srai_w |
    inst_addi_w |
    all_ls      |
    inst_lu12i_w|
    inst_jirl   |
    inst_bl     |
    inst_slti   |
    inst_sltui  |
    inst_andi   |
    inst_ori    |
    inst_xori   |
    inst_pcaddu12i;

assign res_from_mem = all_lds;
assign load_op      = all_lds;
assign mem_we       = all_sts;

//会写通用寄存器的算术逻辑指令
assign arithmetic_write =
    inst_add_w     |
    inst_sub_w     |
    inst_slt       |
    inst_sltu      |
    inst_nor       |
    inst_and       |
    inst_or        |
    inst_xor       |
    inst_slli_w    |
    inst_srli_w    |
    inst_srai_w    |
    inst_addi_w    |
    inst_slti      |
    inst_sltui     |
    inst_andi      |
    inst_ori       |
    inst_xori      |
    inst_sll_w     |
    inst_srl_w     |
    inst_sra_w     |
    inst_lu12i_w   |
    inst_pcaddu12i |
    all_mul_div;

// 修改：增加计数器指令写回
assign gr_we =
    arithmetic_write |
    all_lds |
    inst_jirl |
    inst_bl |
    all_csr |
    inst_rdcntvl_w |
    inst_rdcntvh_w |
    inst_rdcntid;

// 修改：rdcntid 的目的寄存器是 rj
assign dest =
    inst_bl      ? 5'd1 :
    inst_rdcntid ? rj    :
                   rd;

/* 寄存器堆 */
wire       src_reg_is_rd;
wire [4:0] rf_raddr1;
wire [4:0] rf_raddr2;

// 修改：csrwr/csrxchg 的写入数据来自 rd 的旧值
assign src_reg_is_rd =
    condition_branch |
    all_sts          |
    inst_csrwr       |
    inst_csrxchg;

assign rf_raddr1 = rj;
assign rf_raddr2 = src_reg_is_rd ? rd : rk;

wire        rf_we;
wire [4:0]  rf_waddr;
wire [31:0] rf_wdata;

assign {rf_we, rf_waddr, rf_wdata} = ws_to_rf_bus;

wire [31:0] rf_rdata1;
wire [31:0] rf_rdata2;

regfile u_regfile(
    .clk    (clk),
    .raddr1 (rf_raddr1),
    .rdata1 (rf_rdata1),
    .raddr2 (rf_raddr2),
    .rdata2 (rf_rdata2),
    .we     (rf_we),
    .waddr  (rf_waddr),
    .wdata  (rf_wdata)
);

/* 判断当前指令是否真的读取对应源寄存器 */
// 修改：这些指令不读取第一路通用寄存器操作数。
// csrxchg 仍然需要读取 rj 作为掩码。
wire src1_read =
    ~(inst_b         |
      inst_bl        |
      inst_lu12i_w   |
      inst_pcaddu12i |
      inst_csrrd     |
      inst_csrwr     |
      inst_syscall   |
      inst_ertn      |
      inst_break     |
      inst_rdcntvl_w |
      inst_rdcntvh_w |
      inst_rdcntid);
      
wire src2_read =
    inst_add_w |
    inst_sub_w |
    inst_slt   |
    inst_sltu  |
    inst_nor   |
    inst_and   |
    inst_or    |
    inst_xor   |
    inst_sll_w |
    inst_srl_w |
    inst_sra_w |
    all_sts    |
    all_mul_div|  // 新增：乘除法需要读取第二个源寄存器rk
    condition_branch |
    inst_csrwr |       // 新增：读取 rd 原值
    inst_csrxchg;      // 新增：读取 rd 原值

/* EXE、MEM、WB 数据相关检测 */
//ID阶段指令的第一个源寄存器，是否依赖EXE阶段正在生成的结果
wire ex_hazard_r1 =
    es_valid &&
    es_gr_we &&//写寄存器
    (es_dest != 5'd0) &&//目标不是0寄存器
    (es_dest == rf_raddr1) &&//要写的和要读的是一个
    src1_read;//当前指令是否真的使用第一个源寄存器

//第二个同理
wire ex_hazard_r2 =
    es_valid &&
    es_gr_we &&
    (es_dest != 5'd0) &&
    (es_dest == rf_raddr2) &&
    src2_read;

wire mem_hazard_r1 =
    ms_valid &&
    ms_gr_we &&
    (ms_dest != 5'd0) &&
    (ms_dest == rf_raddr1) &&
    src1_read;

wire mem_hazard_r2 =
    ms_valid &&
    ms_gr_we &&
    (ms_dest != 5'd0) &&
    (ms_dest == rf_raddr2) &&
    src2_read;

wire wb_hazard_r1 =
    rf_we &&
    (rf_waddr != 5'd0) &&
    (rf_waddr == rf_raddr1) &&
    src1_read;

wire wb_hazard_r2 =
    rf_we &&
    (rf_waddr != 5'd0) &&
    (rf_waddr == rf_raddr2) &&
    src2_read;

// 原有：EXE 结果不能前递且存在寄存器相关时，需要等待。
// EXE 输出的 es_load_op 现在也包含 CSR 等待标志。
wire load_use_hazard =
    es_load_op &&
    (ex_hazard_r1 || ex_hazard_r2);

// 新增：MEM 中的 CSR 指令还没有产生真实写回值。
//
// 如果 EXE 中有更新的一条指令也写相同寄存器，
// ID 应依赖更新的 EXE 指令，因此排除对应的 EXE 命中。
wire csr_use_hazard =
    ms_csr_re &&
    (
        (mem_hazard_r1 && !ex_hazard_r1) ||
        (mem_hazard_r2 && !ex_hazard_r2)
    );

// 修改：CSR 写入尚未提交时，ID 等待。
// 这样不会使用旧的 CRMD/ECFG/ESTAT 状态判断中断。
wire ds_ready_go =
    !(load_use_hazard ||
      csr_use_hazard ||
      es_csr_pending ||
      ms_csr_pending ||
      ws_csr_pending);

/* 前递优先级：EXE > MEM > WB > regfile */
reg [31:0] rj_value;
reg [31:0] rkd_value;

always @(*) begin
    rj_value  = rf_rdata1;
    rkd_value = rf_rdata2;

    if (ex_hazard_r1 && !es_load_op) begin
        rj_value = es_alu_result;
    end
    else if (mem_hazard_r1) begin
        rj_value = ms_final_result;
    end
    else if (wb_hazard_r1) begin
        rj_value = rf_wdata;
    end

    if (ex_hazard_r2 && !es_load_op) begin
        rkd_value = es_alu_result;
    end
    else if (mem_hazard_r2) begin
        rkd_value = ms_final_result;
    end
    else if (wb_hazard_r2) begin
        rkd_value = rf_wdata;
    end
end

//==============================================================
// 新增：生成 CSR 写掩码和写数据
//
// 此处必须使用 rj_value、rkd_value，不能直接使用
// rf_rdata1、rf_rdata2，因为操作数可能需要从前级旁路。
//==============================================================

// csrwr：全部 32 位都允许写
// csrxchg：rj 寄存器的每一位决定对应 CSR 位是否允许写
// csrrd：不写 CSR，因此掩码为 0
assign csr_wmask =
    inst_csrwr   ? 32'hffffffff :
    inst_csrxchg ? rj_value      :
                   32'b0;

// csrwr/csrxchg 的写数据都是 rd 寄存器的旧值
assign csr_wvalue = rkd_value;

/* 分支判断 */
wire rj_eq_rd  = (rj_value == rkd_value);
wire rj_lt_rd  = ($signed(rj_value) < $signed(rkd_value));
wire rj_ltu_rd = (rj_value < rkd_value);

// 修改：WB 清空时禁止 ID 发出普通分支跳转
wire br_taken =
    ds_valid &&
    ds_ready_go &&
    es_allowin &&
    !wb_flush &&
    !ds_has_ex &&
    (
        (inst_beq  &&  rj_eq_rd)  |
        (inst_bne  && ~rj_eq_rd)  |
        (inst_blt  &&  rj_lt_rd)  |
        (inst_bge  && ~rj_lt_rd)  |
        (inst_bltu &&  rj_ltu_rd) |
        (inst_bgeu && ~rj_ltu_rd) |
        inst_jirl                |
        inst_bl                  |
        inst_b
    );
    
wire [31:0] br_target =
    (condition_branch | inst_bl | inst_b) ?
    (ds_pc + br_offs) :
    (rj_value + jirl_offs);//寄存器间跳转

// [新增] 一条指令只在真正离开ID时解析/训练一次，阻塞时绝不重复训练。
wire bp_resolve_valid = ds_valid && ds_ready_go && es_allowin &&
                        !wb_flush && !ds_has_ex && !inst_ertn;
wire bp_is_branch = condition_branch | inst_jirl | inst_bl | inst_b;
wire [31:0] actual_nextpc = br_taken ? br_target : ds_pc + 32'd4;
wire br_redirect = bp_resolve_valid && (actual_nextpc != ds_pred_nextpc);
// [修改] 实际跳转且预测正确时不冲刷；预测跳但实际不跳时也必须纠错。
assign br_bus = {br_redirect, actual_nextpc, bp_resolve_valid,
                 bp_is_branch, condition_branch, br_taken, ds_pc, br_target};

//==============================================================
// 新增：CSR 指令译码
//
// CSR 指令共同特征：inst[31:24] == 8'h04
//
// rj == 0：csrrd
// rj == 1：csrwr
// 其他值：csrxchg
//==============================================================

// 修改：rdcntid 通过现有 CSR 读通路读取 TID
assign csr_num =
    inst_rdcntid ? `CSR_TID : ds_inst[23:10];

assign csr_re =
    all_csr |
    inst_rdcntid;

// 保留：只有这两种指令写 CSR
assign csr_we =
    inst_csrwr |
    inst_csrxchg;

/* ID -> EXE 流水级总线*/
assign ds_to_es_bus = {
    ds_ex_flags,     // 新增：4
    rdcnt_op,        // 新增：2

    inst_syscall,
    inst_ertn,

    csr_re,
    csr_we,
    csr_num,
    csr_wmask,
    csr_wvalue,

    alu_op,
    mul_div_op,
    load_op,
    src1_is_pc,
    src2_is_imm,
    src2_is_4,
    gr_we,
    mem_we,
    dest,
    imm,
    rj_value,
    rkd_value,
    ds_pc,
    res_from_mem,
    mem_size,
    mem_signed
};

/* 流水级握手 */
assign ds_allowin =
    ~ds_valid ||                   //ID 级内部当前是否保存着一条有效指令
    (ds_ready_go && es_allowin);

// 修改：清空周期不向 EXE 发送指令
assign ds_to_es_valid =
    ds_valid &&
    ds_ready_go &&
    !wb_flush;
    
always @(posedge clk) begin
    // 修改：清空的优先级高于阻塞
    if (reset || wb_flush) begin
        ds_valid <= 1'b0;
    end
    else if (ds_allowin) begin
        ds_valid <= fs_to_ds_valid && ~br_redirect; // [修改] 仅预测错误才丢弃IF
    end

    // 修改：清空周期不接收旧路径指令
    if (!reset && !wb_flush &&
        fs_to_ds_valid && ds_allowin) begin
        fs_to_ds_bus_r <= fs_to_ds_bus;
    end
end

endmodule
