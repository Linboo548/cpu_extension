# [新增] 循环分支、反向分支、load-use、除法阻塞、jirl及链接寄存器测试。
# 结果写0x10000100为1表示程序执行到了正确路径，-1为错误路径。
    li $r20, 0x10000000
    addi.w $r12, $r0, 0
    addi.w $r13, $r0, 40
loop:
    addi.w $r12, $r12, 1
    blt $r12, $r13, loop
    st.w $r12, $r20, 0
    ld.w $r14, $r20, 0
    beq $r14, $r13, load_ok
    b fail
load_ok:
    addi.w $r17, $r0, 5
    div.w $r18, $r14, $r17
    addi.w $r19, $r0, 8
    bne $r18, $r19, fail
    bl link_test
after_call:
    bne $r15, $r13, fail
    addi.w $r16, $r0, 1
    st.w $r16, $r20, 0x100
done:
    b done
link_test:
    or $r15, $r14, $r0
    jirl $r0, $r1, 0
fail:
    addi.w $r16, $r0, -1
    st.w $r16, $r20, 0x100
    b done
