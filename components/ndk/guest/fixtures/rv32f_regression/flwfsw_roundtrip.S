.section .text.init
.global _start
.align 4

_start:
    lui t2, 0x80008
    addi t2, t2, -1024
    lbu t3, 0(t2)
    li t4, 1
    beq t3, t4, flw_mmio

    la t0, payload
    la t1, scratch
    .word 0x0002A007 /* flw f0, 0(t0) */
    .word 0x00032027 /* fsw f0, 0(t1) */
    lw a0, 0(t1)
    ecall
    j .

flw_mmio:
    lui t0, 0x10000
    .word 0x0002A007 /* flw f0, 0(t0) */
    ecall
    j .

.section .data
.align 4
payload:
    .word 0x12345678
scratch:
    .word 0x00000000
