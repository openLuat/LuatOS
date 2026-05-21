.section .text.init
.global _start
.align 4

_start:
    li a0, 4
    csrw 0x002, a0

    lui a0, 0x3f800
    .word 0xF0050053 /* fmv.w.x f0, a0 */

    lui a1, 0x33800
    .word 0xF00580D3 /* fmv.w.x f1, a1 */

    .word 0x00107153 /* fadd.s f2, f0, f1, dyn */
    .word 0xE0010553 /* fmv.x.w a0, f2 */
    ecall
    j .
