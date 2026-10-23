# [新增] 原有外设演示。开关bit0选择加/减，BTN_STEP bit0按下计数，bit1清零。
# 现有confreg负责按键消抖；远程顶层将touch_btn[0:1]映射到这两位。
.equ GPIO, 0x1FAFF000
    li $r12, GPIO
    addi.w $r16, $r0, 0
    addi.w $r15, $r0, 0
loop:
    ld.w $r13, $r12, 0x060
    st.w $r13, $r12, 0x020
    ld.w $r14, $r12, 0x080
    andi $r17, $r14, 2
    bne $r17, $r0, clear
    andi $r14, $r14, 1
    beq $r14, $r15, show
    or $r15, $r14, $r0
    beq $r14, $r0, show
    andi $r13, $r13, 1
    bne $r13, $r0, subtract
    addi.w $r16, $r16, 1
    b show
subtract:
    addi.w $r16, $r16, -1
    b show
clear:
    addi.w $r16, $r0, 0
show:
    st.w $r16, $r12, 0x050
    b loop
