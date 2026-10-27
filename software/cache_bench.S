# I/D Cache directed CPU test: aliases, byte writes, locality, conflicts,
# write-no-allocate, live MMIO reads and a wrong-path store.
    li $r20, 0x10001000
    li $r21, 0xa0001000
    li $r22, 0x80001000
    li $r12, 0x11223344
    st.w $r12, $r20, 0
    ld.w $r13, $r21, 0
    bne $r12, $r13, fail
    addi.w $r14, $r0, 0xaa
    st.b $r14, $r22, 1
    li $r12, 0x1122aa44
    ld.w $r13, $r20, 0
    bne $r12, $r13, fail
    addi.w $r12, $r0, 1
    st.w $r12, $r20, 0
    addi.w $r12, $r0, 2
    st.w $r12, $r20, 4
    addi.w $r12, $r0, 3
    st.w $r12, $r20, 8
    addi.w $r12, $r0, 4
    st.w $r12, $r20, 12
    addi.w $r15, $r0, 0
    addi.w $r16, $r0, 0
    addi.w $r17, $r0, 64
loop:
    ld.w $r12, $r21, 0
    add.w $r15, $r15, $r12
    ld.w $r12, $r22, 4
    add.w $r15, $r15, $r12
    ld.w $r12, $r20, 8
    add.w $r15, $r15, $r12
    ld.w $r12, $r21, 12
    add.w $r15, $r15, $r12
    addi.w $r16, $r16, 1
    blt $r16, $r17, loop
    addi.w $r12, $r0, 640
    bne $r15, $r12, fail
    # Same index, different tag; then return to the original line.
    addi.w $r12, $r0, 9
    st.w $r12, $r20, 0x400
    ld.w $r13, $r21, 0x400
    bne $r12, $r13, fail
    ld.w $r13, $r20, 0
    addi.w $r12, $r0, 1
    bne $r12, $r13, fail
    # A store miss at the same index must not evict the current read line.
    li $r23, 0x10001800
    st.w $r12, $r23, 0
    ld.w $r13, $r21, 0
    bne $r12, $r13, fail
    # The test platform returns a new value for every GPIO-region read.
    li $r24, 0x1faf0020
    ld.w $r12, $r24, 0
    ld.w $r13, $r24, 0
    addi.w $r12, $r12, 1
    bne $r12, $r13, fail
    # Private UART reads must never reach the external bus or D-Cache.
    li $r24, 0xbfaff11c
    ld.w $r12, $r24, 0
    li $r13, 0x55415254
    bne $r12, $r13, fail
    b passed
    st.w $r0, $r20, 0x104
passed:
    li $r20, 0x10000000
    addi.w $r16, $r0, 1
    st.w $r16, $r20, 0x100
done:
    b done
fail:
    li $r20, 0x10000000
    addi.w $r16, $r0, -1
    st.w $r16, $r20, 0x100
    b done
