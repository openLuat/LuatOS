.section .text.init
.global _start
.align 4

_start:
    csrr a0, 0x139

    lui a4, 0x1000
    addi a4, a4, 1
    csrw 0x001, zero
    .word 0xD0077053 /* fcvt.s.w f0, a4 */
    .word 0x00052027 /* fsw f0, 0(a0) */
    csrr a1, 0x001
    sw a1, 8(a0)

    li a5, 1
    csrw 0x001, zero
    .word 0xD017F0D3 /* fcvt.s.wu f1, a5 */
    .word 0x00152227 /* fsw f1, 4(a0) */
    csrr a1, 0x001
    sw a1, 12(a0)

    li a0, 0
    ecall
    j .
