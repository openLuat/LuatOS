.section .text.init
.global _start
.align 4

_start:
    csrr t0, 0x139

    li a1, 3
    csrw 0x002, a1

    lui a4, 0x1000
    addi a4, a4, 1
    csrw 0x001, zero
    .word 0xD0077053 /* fcvt.s.w f0, a4, dyn */
    .word 0x0002A027 /* fsw f0, 0(t0) */

    csrr a0, 0x001
    sw a0, 4(t0)

    li a0, 0
    ecall
    j .
