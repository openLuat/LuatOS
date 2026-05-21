.section .text.init
.global _start
.align 4

_start:
    csrr t0, 0x139

    lui a2, 0x80000
    .word 0xF0060153 /* fmv.w.x f2, a2 */

    lui a1, 0x7fc12
    addi a1, a1, 0x345
    .word 0xF00580D3 /* fmv.w.x f1, a1 */
    .word 0x20208353 /* fsgnj.s f6, f1, f2 */
    .word 0x0062A027 /* fsw f6, 0(t0) */

    lui a1, 0x7fc23
    addi a1, a1, 0x456
    .word 0xF00580D3 /* fmv.w.x f1, a1 */
    .word 0x202093D3 /* fsgnjn.s f7, f1, f2 */
    .word 0x0072A227 /* fsw f7, 4(t0) */

    lui a1, 0xffc34
    addi a1, a1, 0x567
    .word 0xF00580D3 /* fmv.w.x f1, a1 */
    .word 0x2020A053 /* fsgnjx.s f0, f1, f2 */
    .word 0x0002A427 /* fsw f0, 8(t0) */

    csrr a0, 0x001
    sw a0, 12(t0)

    li a0, 0
    ecall
    j .
