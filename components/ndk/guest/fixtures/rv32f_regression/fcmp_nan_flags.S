.section .text.init
.global _start
.align 4

_start:
    csrr t0, 0x139

    lui a1, 0x7fc00
    lui a2, 0x3f800
    .word 0xF00580D3 /* fmv.w.x f1, a1 */
    .word 0xF0060153 /* fmv.w.x f2, a2 */
    csrw 0x001, zero
    .word 0xA020A553 /* feq.s a0, f1, f2 */
    sw a0, 0(t0)
    csrr a0, 0x001
    sw a0, 4(t0)

    lui a1, 0x7f800
    addi a1, a1, 1
    .word 0xF00580D3 /* fmv.w.x f1, a1 */
    csrw 0x001, zero
    .word 0xA020A553 /* feq.s a0, f1, f2 */
    sw a0, 8(t0)
    csrr a0, 0x001
    sw a0, 12(t0)

    lui a1, 0x7fc00
    .word 0xF00580D3 /* fmv.w.x f1, a1 */
    csrw 0x001, zero
    .word 0xA0209553 /* flt.s a0, f1, f2 */
    sw a0, 16(t0)
    csrr a0, 0x001
    sw a0, 20(t0)

    csrw 0x001, zero
    .word 0xA0208553 /* fle.s a0, f1, f2 */
    sw a0, 24(t0)
    csrr a0, 0x001
    sw a0, 28(t0)

    li a0, 0
    ecall
    j .
