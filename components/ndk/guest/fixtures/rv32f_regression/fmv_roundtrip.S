.section .text.init
.global _start
.align 4

_start:
    lui a0, 0x3f800
    .word 0xF0050053 /* fmv.w.x f0, a0 */
    .word 0xE0000553 /* fmv.x.w a0, f0 */
    ecall
    j .
