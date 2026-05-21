.section .text.init
.global _start
.align 4

_start:
    csrr t0, 0x139

    lui a1, 0x7f800
    fmv.w.x f1, a1
    lui a2, 0x7fc00
    fmv.w.x f2, a2
    lui a3, 0x4f000
    fmv.w.x f3, a3
    lui a4, 0xbf800
    fmv.w.x f4, a4
    lui a5, 0xff800
    fmv.w.x f5, a5

    csrw 0x001, zero
    fcvt.w.s a1, f1, rtz
    sw a1, 0(t0)
    csrr a6, 0x001
    sw a6, 4(t0)

    csrw 0x001, zero
    fcvt.w.s a1, f2, rtz
    sw a1, 8(t0)
    csrr a6, 0x001
    sw a6, 12(t0)

    csrw 0x001, zero
    fcvt.w.s a1, f3, rtz
    sw a1, 16(t0)
    csrr a6, 0x001
    sw a6, 20(t0)

    csrw 0x001, zero
    fcvt.wu.s a1, f4, rtz
    sw a1, 24(t0)
    csrr a6, 0x001
    sw a6, 28(t0)

    csrw 0x001, zero
    fcvt.wu.s a1, f5, rtz
    sw a1, 32(t0)
    csrr a6, 0x001
    sw a6, 36(t0)

    li a0, 0
    ecall
    j .
