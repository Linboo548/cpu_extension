`ifndef MYCPU_H
`define MYCPU_H

// 宏定义各流水级之间的总线位宽
// [修改] {纠错有效,正确nextPC,训练有效,是分支,条件分支,实际跳转,分支PC,目标}
`define BR_BUS_WD        101
// [修改] {该指令预测的nextPC[31:0], ADEF, inst[31:0], PC[31:0]}
`define FS_TO_DS_BUS_WD  97
`define DS_TO_ES_BUS_WD  250
//译码到执行（ALU 控制、操作数、立即数、访存控制、写回控制等)
`define ES_TO_MS_BUS_WD  195
`define MS_TO_WS_BUS_WD  189
`define WS_TO_RF_BUS_WD  38  //写回到寄存器（1位使能+5（2的5次方=32）位目标地址+32位数据）

//==============================================================
// 新增：第一阶段 CSR 编号
//==============================================================
`define CSR_CRMD    14'h0000
`define CSR_PRMD    14'h0001
`define CSR_ESTAT   14'h0005
`define CSR_ERA     14'h0006
`define CSR_EENTRY  14'h000c
`define CSR_SAVE0   14'h0030
`define CSR_SAVE1   14'h0031
`define CSR_SAVE2   14'h0032
`define CSR_SAVE3   14'h0033

//==============================================================
// 新增：CRMD 各字段位置
//==============================================================
`define CSR_CRMD_PLV   1:0
`define CSR_CRMD_IE    2
`define CSR_CRMD_DA    3
`define CSR_CRMD_PG    4
`define CSR_CRMD_DATF  6:5
`define CSR_CRMD_DATM  8:7

//==============================================================
// 新增：PRMD 各字段位置
//==============================================================
`define CSR_PRMD_PPLV  1:0
`define CSR_PRMD_PIE   2

//==============================================================
// 新增：ESTAT 各字段位置
//==============================================================
`define CSR_ESTAT_IS10      1:0
`define CSR_ESTAT_ECODE     21:16
`define CSR_ESTAT_ESUBCODE  30:22

//==============================================================
// 新增：EENTRY 各字段位置
//==============================================================
`define CSR_EENTRY_VA  31:6

//==============================================================
// 新增：第一阶段用到的异常编码
//==============================================================
`define ECODE_INT   6'h00
`define ECODE_ADEF  6'h08
`define ECODE_ALE   6'h09
`define ECODE_SYS   6'h0b
`define ECODE_BRK   6'h0c
`define ECODE_INE   6'h0d

`define ESUBCODE_ADEF  9'h000

//==============================================================
// 新增：第二阶段 CSR 编号
//==============================================================
`define CSR_ECFG    14'h0004
`define CSR_BADV    14'h0007
`define CSR_TID     14'h0040
`define CSR_TCFG    14'h0041
`define CSR_TVAL    14'h0042
`define CSR_TICLR   14'h0044

//==============================================================
// 新增：异常标志中的位号
//
// syscall 继续使用原来的独立标志，不放进这个向量。
// ID->EXE 携带低4位；EXE 再增加 ALE，形成5位。
//==============================================================
`define EX_INT     0
`define EX_ADEF    1
`define EX_BRK     2
`define EX_INE     3
`define EX_ALE     4

`endif
