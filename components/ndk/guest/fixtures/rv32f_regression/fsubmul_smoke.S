.section .text.init
.global _start
.align 4

_start:
    csrr t0, 0x139

    lui a1, 0x3f800
    .word 0xF00580D3 /* fmv.w.x f1, a1 */
    lui a2, 0x40000
    .word 0xF0060153 /* fmv.w.x f2, a2 */
    .word 0x0820F253 /* fsub.s f4, f1, f2 */
    .word 0x0042A027 /* fsw f4, 0(t0) */

    lui a1, 0x3fc00
    .word 0xF00580D3 /* fmv.w.x f1, a1 */
    lui a3, 0xc0000
    .word 0xF00681D3 /* fmv.w.x f3, a3 */
    .word 0x1030F2D3 /* fmul.s f5, f1, f3 */
    .word 0x0052A227 /* fsw f5, 4(t0) */

    csrr a0, 0x001
    sw a0, 8(t0)

    li a0, 0
    ecall
    j .
