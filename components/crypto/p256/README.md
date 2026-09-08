# components/crypto/p256 — P-256 常数时间快速路径

secp256r1 (NIST P-256) 的专用实现,用于加速 TLS 1.1/1.2 握手中的
ECDHE 密钥协商、ECDSA 签名/验签等所有 `mbedtls_ecp_mul*()` 路径。

## 来源与许可证

- 算法结构参考 **BearSSL** `src/ec/ec_p256_m31.c`(MIT license, (c) Thomas Pornin):
  点加法/倍点公式、Fermat 求逆加法链、窗口点乘的 qz 标志 + CCOPY 选择结构。
- 域表示从 BearSSL 的 30-bit limb 改为 **8 x 32-bit little-endian limb**,
  模约减配方与 mbedtls `ecp_curves.c: ecp_mod_p256` 相同(Solinas),
  便于替换为 Cortex-M3 Thumb-2 汇编内核。
- G 基点窗口表 (`p256_g_table.c`) 由 `tools/gen_p256_gwin.py` 离线生成,
  并与独立纯 python P-256 实现交叉校验。

## 宏开关(在目标 mbedtls 配置头中定义,如 mbedtls_ec7xx_config.h)

| 宏 | 作用 |
|---|---|
| `LUAT_CONF_MBEDTLS_ECP_P256_FAST` | 启用 P-256 快速路径(纯 C,全平台可编译) |
| `LUAT_CONF_MBEDTLS_ECP_P256_ASM` | 在 FAST 基础上启用 Thumb-2 汇编域内核(仅 `__ARM_ARCH_7M__` 生效,其他平台自动回退 C) |

两个宏都不定义时,行为与原生 mbedtls 完全一致(本目录代码不参与挂钩)。

## 文件

| 文件 | 内容 |
|---|---|
| `luat_p256.h` | 字节级 API(mbedtls 无关) |
| `p256_ct.c` | 常数时间 C 实现(域运算/点运算/标量乘);ASM 模式下域内核切换到 .S |
| `p256_g_table.c` | 基点 G 窗口表(flash const,k*G k=1..15) |
| `p256_field_armm3.S` | Cortex-M3 Thumb-2 汇编域内核(fe_add/fe_sub/256x256 乘积,全程无分支) |
| `luat_p256_glue.c` | mbedtls 2.x 胶水层(仅 FAST 宏下有内容) |

ASM 内核只实现 fe_add/fe_sub 与 512-bit 原始乘积;Solinas 约减与
最终条件减 p 仍在 C 侧(fe_reduce512/fe_reduce_once),两种模式共用。

## 挂钩方式

`components/mbedtls/library/ecp.c: mbedtls_ecp_mul_restartable()` 中,
`grp->id == MBEDTLS_ECP_DP_SECP256R1` 且非 restartable 调用时走
`luat_mbedtls_p256_mul()`;返回 1(不适用:非 P-256/点非仿射/标量或点异常/
结果为无穷远)时**静默落回原 `ecp_mul_comb`**,不产生新的失败模式。
`mbedtls_ecp_muladd_restartable()`(ECDSA 验签)内部走
`mbedtls_ecp_mul_shortcuts`,自动受益。

标量前置条件(1 <= m < n、P 在曲线上)由 mbedtls 入口处的
`check_privkey`/`check_pubkey` 保证;快速路径内部仍做完整校验。

## 安全性质

- 常数时间:秘密标量不参与分支、不做秘密索引内存访问;窗口查表为 CT select;
  进位传播轮数固定。
- P-256 cofactor = 1,点解码时做完整在曲线校验(y² == x³-3x+b),
  无效曲线攻击不适用。

## 测试

- 独立交叉验证(开发用):`tools/gen_p256_tv.py` 生成向量,`tools/p256_test_main.c`
  独立 harness 比对(86 条向量:k*G/变基点/muladd/ECDH/边界标量/非法输入)。
- ASM 内核仿真验证:`tools/p256_m3_sim_test.py` 用 unicorn 引擎仿真 Cortex-M3
  执行 `p256_field_armm3.S` + 整条 ASM 域路径,与纯 python P-256 参考比对
  (200 组域原语 + 48 组完整 mul_g/mul/muladd + 边界/非法输入,全部通过)。
- PC 模拟器:`LUAT_USE_UTEST=y` 编译后运行
  `testcase/utest/lib/crypto_basic/`,`crypto.utest("p256_fast")`
  执行 KAT + 与 PC mbedtls 原生 ECP 的 32 轮随机交叉比对 + 非法输入拒绝。
- 设备端:ec718pm 上用 DWT cycle 计数对比宏开/关的 `mbedtls_ecp_mul` 耗时
  (探针临时加入,测完移除),并做实际 https/mqtts 握手计时。

## 内存与栈

- 变基点窗口表:15 点 x 96B ≈ 1.4KB,在栈上(调用 `mbedtls_ecp_mul` 的任务
  栈需预留 ~2KB 余量,与 mbedtls 原 comb 路径量级相当)。
- G 表:960B flash const。
