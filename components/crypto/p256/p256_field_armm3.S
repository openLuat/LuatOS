/*
 * p256_field_armm3.S — P-256 域运算 Cortex-M3 (ARMv7-M, Thumb-2) 汇编内核.
 *
 * 由 LUAT_CONF_MBEDTLS_ECP_P256_ASM 控制(还需 __ARM_ARCH_7M__),
 * 替换 p256_ct.c 中的 fe_add/fe_sub 与 256-bit 乘积内核;
 * 约减(Solinas)仍在 C 侧 fe_reduce512/fe_reduce_once 完成,
 * 接口与语义和纯 C 路径完全一致.
 *
 * 指令约束: 仅用 umull/umlal (Cortex-M3 无 umaal/DSP), 全程无分支.
 * 注意: 进位链(adds/adcs/subs/sbcs)中间不得插入影响 C 标志的指令,
 * 常量一律在链前预载或用 adcs/sbcs 的立即数形式.
 */

#if defined(LUAT_CONF_MBEDTLS_ECP_P256_ASM) && defined(__ARM_ARCH_7M__)

    .syntax unified
    .thumb
    .cpu cortex-m3
    .text

/* ------------------------------------------------------------------ */
/* void p256_fe_add_m3(uint32_t d[8], const uint32_t a[8], const uint32_t b[8])
 * d = a + b mod p; 输入 < p, 输出 < p; 全程无分支.
 * p limbs: FFFFFFFF FFFFFFFF FFFFFFFF 00000000 00000000 00000000 00000001 FFFFFFFF
 */
    .global p256_fe_add_m3
    .type   p256_fe_add_m3, %function
p256_fe_add_m3:
    push    {r4-r11}
    ldmia   r1, {r3-r10}        @ a
    ldr     r11, [r2, #0]
    adds    r3, r3, r11
    ldr     r11, [r2, #4]
    adcs    r4, r4, r11
    ldr     r11, [r2, #8]
    adcs    r5, r5, r11
    ldr     r11, [r2, #12]
    adcs    r6, r6, r11
    ldr     r11, [r2, #16]
    adcs    r7, r7, r11
    ldr     r11, [r2, #20]
    adcs    r8, r8, r11
    ldr     r11, [r2, #24]
    adcs    r9, r9, r11
    ldr     r11, [r2, #28]
    adcs    r10, r10, r11

    movw    r12, #0
    adc     r12, r12, r12       @ r12 = cc (加法溢出位)

    movw    r1, #0              @ r1 备用作标志捕获 (a 已入寄存器)
    movw    r11, #0
    mvn     r11, r11            @ 0xFFFFFFFF (此间标志无依赖, 可随意)
    subs    r3, r3, r11         @ d -= p, 全程 sbcs 立即数/寄存器保链
    sbcs    r4, r4, r11
    sbcs    r5, r5, r11
    sbcs    r6, r6, #0
    sbcs    r7, r7, #0
    sbcs    r8, r8, #0
    sbcs    r9, r9, #1
    sbcs    r10, r10, r11
    adc     r1, r1, r1          @ r1 = C (1 = 未借位, 即 d >= p)

    orrs    r1, r1, r12         @ want_sub = cc | C (此后标志无依赖)
    subs    r1, r1, #1          @ mask m: want_sub=1 → 0, 否则 0xFFFFFFFF
    movs    r12, #1
    ands    r12, r12, r1        @ p6 & m = 1 & m

    @ d += p & m (want_sub=1 时加 0, 否则加回 p)
    adds    r3, r3, r1
    adcs    r4, r4, r1
    adcs    r5, r5, r1
    adcs    r6, r6, #0
    adcs    r7, r7, #0
    adcs    r8, r8, #0
    adcs    r9, r9, r12
    adcs    r10, r10, r1
    stmia   r0, {r3-r10}
    pop     {r4-r11}
    bx      lr
    .size   p256_fe_add_m3, . - p256_fe_add_m3

/* ------------------------------------------------------------------ */
/* void p256_fe_sub_m3(uint32_t d[8], const uint32_t a[8], const uint32_t b[8])
 * d = a - b mod p; 输入 < p, 输出 < p; 全程无分支.
 */
    .global p256_fe_sub_m3
    .type   p256_fe_sub_m3, %function
p256_fe_sub_m3:
    push    {r4-r11}
    ldmia   r1, {r3-r10}        @ a
    ldr     r11, [r2, #0]
    subs    r3, r3, r11
    ldr     r11, [r2, #4]
    sbcs    r4, r4, r11
    ldr     r11, [r2, #8]
    sbcs    r5, r5, r11
    ldr     r11, [r2, #12]
    sbcs    r6, r6, r11
    ldr     r11, [r2, #16]
    sbcs    r7, r7, r11
    ldr     r11, [r2, #20]
    sbcs    r8, r8, r11
    ldr     r11, [r2, #24]
    sbcs    r9, r9, r11
    ldr     r11, [r2, #28]
    sbcs    r10, r10, r11

    movw    r1, #0
    adc     r1, r1, r1          @ r1 = C (1 = 未借位)
    subs    r1, r1, #1          @ mask m: 借位 → 0xFFFFFFFF (加 p), 否则 0
    movs    r12, #1
    ands    r12, r12, r1        @ 1 & m

    @ d += p & m
    adds    r3, r3, r1
    adcs    r4, r4, r1
    adcs    r5, r5, r1
    adcs    r6, r6, #0
    adcs    r7, r7, #0
    adcs    r8, r8, #0
    adcs    r9, r9, r12
    adcs    r10, r10, r1
    stmia   r0, {r3-r10}
    pop     {r4-r11}
    bx      lr
    .size   p256_fe_sub_m3, . - p256_fe_sub_m3

/* ------------------------------------------------------------------ */
/* void p256_mul256_m3(uint32_t c[16], const uint32_t a[8], const uint32_t b[8])
 * 原始 256x256 -> 512 学校乘法 (row-wise), 不做约减.
 * 与 C 版 schoolbook 语义一致: c 逐 limb 读-改-写累加, 调用方需先将 c 清零.
 *
 * 寄存器: r0=c, r1=a, r2=b, r3=a_i, r4=b_j, r5=lo, r6=carry
 * 每个乘积累加: t = c[i+j] + carry + a_i*b_j (carry 属于本列低位!):
 *   r5(=c[i+j]) += r6(carry); 溢出位经 adc 进 r6 高位; umlal 累乘;
 *   str 低 32 位, r6 = t>>32 即下一列 carry (≤ 0xFFFFFFFF).
 * (movs r6,#0 汇编为 16-bit T1 编码, 不影响 C 标志)
 */
.macro MULSTEP ioff, boff
    ldr     r4, [r2, #\boff]
    ldr     r5, [r0, #\ioff]
    adds    r5, r5, r6
    movs    r6, #0
    adc     r6, r6, r6
    umlal   r5, r6, r3, r4
    str     r5, [r0, #\ioff]
.endm

.macro MULROW i
    ldr     r3, [r1, #(4*\i)]
    movs    r6, #0              @ carry = 0
    MULSTEP (4*\i+0),  0
    MULSTEP (4*\i+4),  4
    MULSTEP (4*\i+8),  8
    MULSTEP (4*\i+12), 12
    MULSTEP (4*\i+16), 16
    MULSTEP (4*\i+20), 20
    MULSTEP (4*\i+24), 24
    MULSTEP (4*\i+28), 28
    str     r6, [r0, #(4*\i+32)]
.endm

    .global p256_mul256_m3
    .type   p256_mul256_m3, %function
p256_mul256_m3:
    push    {r4-r7}
    MULROW  0
    MULROW  1
    MULROW  2
    MULROW  3
    MULROW  4
    MULROW  5
    MULROW  6
    MULROW  7
    pop     {r4-r7}
    bx      lr
    .size   p256_mul256_m3, . - p256_mul256_m3

#endif /* LUAT_CONF_MBEDTLS_ECP_P256_ASM && __ARM_ARCH_7M__ */
