`include "mycpu_head.v"

module csr(
    input  wire        clk,
    input  wire        reset,

    // 普通 CSR 指令访问
    input  wire        csr_re,
    input  wire [13:0] csr_num,
    output reg  [31:0] csr_rvalue,

    input  wire        csr_we,
    input  wire [31:0] csr_wmask,
    input  wire [31:0] csr_wvalue,

    // WB 异常提交
    input  wire        wb_ex,
    input  wire [5:0]  wb_ecode,
    input  wire [8:0]  wb_esubcode,
    input  wire [31:0] wb_pc,

    // 新增：异常对应的错误地址
    input  wire [31:0] wb_badv,

    input  wire        ertn_flush,

    // 新增：8个外部硬件中断输入，高电平有效
    input  wire [7:0]  hw_int_in,

    // 新增：存在允许响应的中断
    output wire        has_int,

    output wire [31:0] ex_entry,
    output wire [31:0] ertn_entry
);

//==============================================================
// CSR 状态寄存器
//==============================================================

reg [1:0] csr_crmd_plv;
reg       csr_crmd_ie;

reg [1:0] csr_prmd_pplv;
reg       csr_prmd_pie;

// 新增：局部中断使能
reg [12:0] csr_ecfg_lie;

// ESTAT 的不同字段分别维护
reg [1:0] csr_estat_is10;
reg [7:0] csr_estat_hw;
reg       csr_estat_ti;

reg [5:0] csr_estat_ecode;
reg [8:0] csr_estat_esubcode;

reg [31:0] csr_era_pc;
reg [31:0] csr_badv;
reg [25:0] csr_eentry_va;

reg [31:0] csr_save0_data;
reg [31:0] csr_save1_data;
reg [31:0] csr_save2_data;
reg [31:0] csr_save3_data;

reg [31:0] csr_tid;

// 新增：定时器配置和倒计时计数器
reg        csr_tcfg_en;
reg        csr_tcfg_periodic;
reg [29:0] csr_tcfg_initval;
reg [31:0] timer_cnt;


//==============================================================
// 新增：定时器辅助信号
//==============================================================

wire [31:0] tcfg_value;
wire [31:0] tcfg_next_value;
wire        tcfg_write;
wire        timer_expire;
wire        timer_clear;

assign tcfg_value = {
    csr_tcfg_initval,
    csr_tcfg_periodic,
    csr_tcfg_en
};

// 先结合掩码得到本次写入后的完整 TCFG
assign tcfg_next_value =
    (csr_wmask & csr_wvalue) |
    (~csr_wmask & tcfg_value);

assign tcfg_write =
    csr_we &&
    (csr_num == `CSR_TCFG);

assign timer_expire =
    csr_tcfg_en &&
    (timer_cnt == 32'b0);

// TICLR.CLR：掩码为1并且写入1才有效
assign timer_clear =
    csr_we &&
    (csr_num == `CSR_TICLR) &&
    csr_wmask[0] &&
    csr_wvalue[0];


//==============================================================
// 新增：中断状态和中断响应条件
//==============================================================

wire [12:0] csr_estat_is;

// IS[12]：核间中断，本实验不实现，固定0
// IS[11]：定时器中断
// IS[10]：保留，固定0
// IS[9:2]：8个硬件中断
// IS[1:0]：2个软件中断
assign csr_estat_is = {
    1'b0,
    csr_estat_ti,
    1'b0,
    csr_estat_hw,
    csr_estat_is10
};

assign has_int =
    csr_crmd_ie &&
    (|(csr_estat_is & csr_ecfg_lie));

assign ex_entry   = {csr_eentry_va, 6'b0};
assign ertn_entry = csr_era_pc;


//==============================================================
// CRMD、PRMD
//==============================================================

always @(posedge clk) begin
    if (reset) begin
        csr_crmd_plv <= 2'b0;
        csr_crmd_ie  <= 1'b0;
    end
    else if (wb_ex) begin
        csr_crmd_plv <= 2'b0;
        csr_crmd_ie  <= 1'b0;
    end
    else if (ertn_flush) begin
        csr_crmd_plv <= csr_prmd_pplv;
        csr_crmd_ie  <= csr_prmd_pie;
    end
    else if (csr_we && csr_num == `CSR_CRMD) begin
        csr_crmd_plv <=
            (csr_wmask[1:0] & csr_wvalue[1:0]) |
            (~csr_wmask[1:0] & csr_crmd_plv);

        csr_crmd_ie <=
            (csr_wmask[2] & csr_wvalue[2]) |
            (~csr_wmask[2] & csr_crmd_ie);
    end

    if (reset) begin
        csr_prmd_pplv <= 2'b0;
        csr_prmd_pie  <= 1'b0;
    end
    else if (wb_ex) begin
        csr_prmd_pplv <= csr_crmd_plv;
        csr_prmd_pie  <= csr_crmd_ie;
    end
    else if (csr_we && csr_num == `CSR_PRMD) begin
        csr_prmd_pplv <=
            (csr_wmask[1:0] & csr_wvalue[1:0]) |
            (~csr_wmask[1:0] & csr_prmd_pplv);

        csr_prmd_pie <=
            (csr_wmask[2] & csr_wvalue[2]) |
            (~csr_wmask[2] & csr_prmd_pie);
    end
end


//==============================================================
// 新增：ECFG 和完整 ESTAT
//==============================================================

always @(posedge clk) begin
    if (reset) begin
        csr_ecfg_lie       <= 13'b0;
        csr_estat_is10     <= 2'b0;
        csr_estat_hw       <= 8'b0;
        csr_estat_ti       <= 1'b0;
        csr_estat_ecode    <= 6'b0;
        csr_estat_esubcode <= 9'b0;
    end
    else begin
        if (csr_we && csr_num == `CSR_ECFG) begin
            // ECFG[10] 为保留位，强制为0
            csr_ecfg_lie <=
                (
                    (csr_wmask[12:0] & csr_wvalue[12:0]) |
                    (~csr_wmask[12:0] & csr_ecfg_lie)
                ) & 13'h1bff;
        end

        if (csr_we && csr_num == `CSR_ESTAT) begin
            // 软件只能修改 IS[1:0]
            csr_estat_is10 <=
                (csr_wmask[1:0] & csr_wvalue[1:0]) |
                (~csr_wmask[1:0] & csr_estat_is10);
        end

        // 每拍采样外部硬件中断
        csr_estat_hw <= hw_int_in;

        // 定时器到0置中断；写 TICLR 清中断
        if (timer_expire)
            csr_estat_ti <= 1'b1;
        else if (timer_clear)
            csr_estat_ti <= 1'b0;

        // 异常原因只能由硬件提交更新
        if (wb_ex) begin
            csr_estat_ecode    <= wb_ecode;
            csr_estat_esubcode <= wb_esubcode;
        end
    end
end


//==============================================================
// ERA、BADV、EENTRY、SAVE、TID
//==============================================================

always @(posedge clk) begin
    if (reset) begin
        csr_era_pc     <= 32'b0;
        csr_badv       <= 32'b0;
        csr_eentry_va  <= 26'b0;

        csr_save0_data <= 32'b0;
        csr_save1_data <= 32'b0;
        csr_save2_data <= 32'b0;
        csr_save3_data <= 32'b0;

        csr_tid        <= 32'b0;
    end
    else begin
        if (wb_ex)
            csr_era_pc <= wb_pc;
        else if (csr_we && csr_num == `CSR_ERA)
            csr_era_pc <=
                (csr_wmask & csr_wvalue) |
                (~csr_wmask & csr_era_pc);

        // 新增：地址相关异常记录错误地址
        if (wb_ex &&
            ((wb_ecode == `ECODE_ADEF) ||
             (wb_ecode == `ECODE_ALE))) begin
            csr_badv <= wb_badv;
        end
        else if (csr_we && csr_num == `CSR_BADV) begin
            csr_badv <=
                (csr_wmask & csr_wvalue) |
                (~csr_wmask & csr_badv);
        end

        if (csr_we && csr_num == `CSR_EENTRY)
            csr_eentry_va <=
                (csr_wmask[31:6] & csr_wvalue[31:6]) |
                (~csr_wmask[31:6] & csr_eentry_va);

        if (csr_we && csr_num == `CSR_SAVE0)
            csr_save0_data <=
                (csr_wmask & csr_wvalue) |
                (~csr_wmask & csr_save0_data);

        if (csr_we && csr_num == `CSR_SAVE1)
            csr_save1_data <=
                (csr_wmask & csr_wvalue) |
                (~csr_wmask & csr_save1_data);

        if (csr_we && csr_num == `CSR_SAVE2)
            csr_save2_data <=
                (csr_wmask & csr_wvalue) |
                (~csr_wmask & csr_save2_data);

        if (csr_we && csr_num == `CSR_SAVE3)
            csr_save3_data <=
                (csr_wmask & csr_wvalue) |
                (~csr_wmask & csr_save3_data);

        if (csr_we && csr_num == `CSR_TID)
            csr_tid <=
                (csr_wmask & csr_wvalue) |
                (~csr_wmask & csr_tid);
    end
end


//==============================================================
// 新增：TCFG、TVAL、定时器
//==============================================================

always @(posedge clk) begin
    if (reset) begin
        csr_tcfg_en       <= 1'b0;
        csr_tcfg_periodic <= 1'b0;
        csr_tcfg_initval  <= 30'b0;
        timer_cnt         <= 32'hffffffff;
    end
    else begin
        if (tcfg_write) begin
            csr_tcfg_en       <= tcfg_next_value[0];
            csr_tcfg_periodic <= tcfg_next_value[1];
            csr_tcfg_initval  <= tcfg_next_value[31:2];
        end

        if (tcfg_write) begin
            // 使用本次写入的新配置装载，而不是旧配置
            if (tcfg_next_value[0])
                timer_cnt <= {tcfg_next_value[31:2], 2'b0};
        end
        else if (csr_tcfg_en &&
                 timer_cnt != 32'hffffffff) begin
            if (timer_cnt == 32'b0 && csr_tcfg_periodic)
                timer_cnt <= {csr_tcfg_initval, 2'b0};
            else
                timer_cnt <= timer_cnt - 32'd1;
        end
    end
end


//==============================================================
// CSR 读出
//==============================================================

always @(*) begin
    csr_rvalue = 32'b0;

    if (csr_re) begin
        case (csr_num)
            // 当前仍然只支持直接地址翻译：
            // DA=1、PG=0、DATF=0、DATM=0
            `CSR_CRMD:
                csr_rvalue = {
                    23'b0,
                    2'b0,
                    2'b0,
                    1'b0,
                    1'b1,
                    csr_crmd_ie,
                    csr_crmd_plv
                };

            `CSR_PRMD:
                csr_rvalue = {
                    29'b0,
                    csr_prmd_pie,
                    csr_prmd_pplv
                };

            `CSR_ECFG:
                csr_rvalue = {19'b0, csr_ecfg_lie};

            `CSR_ESTAT:
                csr_rvalue = {
                    1'b0,
                    csr_estat_esubcode,
                    csr_estat_ecode,
                    3'b0,
                    csr_estat_is
                };

            `CSR_ERA:
                csr_rvalue = csr_era_pc;

            `CSR_BADV:
                csr_rvalue = csr_badv;

            `CSR_EENTRY:
                csr_rvalue = ex_entry;

            `CSR_SAVE0:
                csr_rvalue = csr_save0_data;

            `CSR_SAVE1:
                csr_rvalue = csr_save1_data;

            `CSR_SAVE2:
                csr_rvalue = csr_save2_data;

            `CSR_SAVE3:
                csr_rvalue = csr_save3_data;

            `CSR_TID:
                csr_rvalue = csr_tid;

            `CSR_TCFG:
                csr_rvalue = tcfg_value;

            `CSR_TVAL:
                csr_rvalue = timer_cnt;

            // TICLR 只捕获写1动作，读出恒为0
            `CSR_TICLR:
                csr_rvalue = 32'b0;

            default:
                csr_rvalue = 32'b0;
        endcase
    end
end

endmodule