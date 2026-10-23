# [新增] 真串口8N1接收中断回显：收到字符后LED显示字符，数码管显示接收次数。
# 板上默认50MHz/115200；仿真通过SoC参数缩小每比特周期，不改本程序。
.equ GPIO, 0x1FAFF000
.equ UART, 0x1FAFF100
    li $r20, GPIO
    li $r21, UART
    addi.w $r23, $r0, 0
    la $r12, irq_handler
    csrwr $r12, 0x00c       # EENTRY：必须64字节对齐
    addi.w $r12, $r0, 4
    csrwr $r12, 0x004       # ECFG.LIE[2]，允许硬件中断0
    addi.w $r12, $r0, 1
    st.w $r12, $r21, 8     # UART RX中断使能
    addi.w $r12, $r0, 12
    csrwr $r12, 0x000       # CRMD：DA=1，IE=1，PLV=0
wait_irq:
    b wait_irq

.org 0x1C000100
irq_handler:
    csrwr $r12, 0x030       # SAVE0/1保存处理程序使用的临时寄存器
    csrwr $r13, 0x031
    ld.w $r22, $r21, 0     # 读取RXDATA即清除外设中断请求，不是写TICLR
    st.w $r22, $r20, 0x020
    addi.w $r23, $r23, 1
    st.w $r23, $r20, 0x050
wait_tx:
    ld.w $r12, $r21, 4
    andi $r12, $r12, 1
    beq $r12, $r0, wait_tx
    st.w $r22, $r21, 0     # 确认TX_READY后回显收到的字节
    csrrd $r13, 0x031
    csrrd $r12, 0x030
    ertn                   # 硬件中断返回ERA，不应给ERA加4
