.section .text.init
.global _start
.align 4

_start:
    csrr t0, 0x139

    lui a1, 0x80000
    .word 0xF00580D3 /* fmv.w.x f1, a1 */
    .word 0xE0009553 /* fclass.s a0, f1 */
    sw a0, 0(t0)

    li a1, 1
    .word 0xF00580D3 /* fmv.w.x f1, a1 */
    .word 0xE0009553 /* fclass.s a0, f1 */
    sw a0, 4(t0)

    lui a1, 0x7f800
    addi a1, a1, 1
    .word 0xF00580D3 /* fmv.w.x f1, a1 */
    .word 0xE0009553 /* fclass.s a0, f1 */
    sw a0, 8(t0)

    lui a1, 0x7fc00
    .word 0xF00580D3 /* fmv.w.x f1, a1 */
    .word 0xE0009553 /* fclass.s a0, f1 */
    sw a0, 12(t0)

    li a0, 0
    ecall
    j .
