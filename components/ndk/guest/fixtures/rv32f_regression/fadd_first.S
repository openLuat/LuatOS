.section .text.init
.global _start
.align 4

_start:
    .word 0x00100153 /* fadd.s f2, f0, f1 */
    .word 0xE0010553 /* fmv.x.w a0, f2 */
    ecall
    j .
