# NDK 变更日志

> 本文是 NDK 文档集的一部分。完整索引见 [`../README.md`](../README.md)。

## 2026-06 — 文档与 API 现代化

- **NDK 升级**（本次重构）：
  - 引入 `components/ndk/guest/include/luat_ndk_helper.h`：guest "标准库" header，集中提供 `_start` 模板、exchange buffer 类型化访问、日志、SYSCON 退出、status 解码、字节序、host hash 调用
  - `LUAT_NDK_MAX_RAM_SIZE` 从 32 KiB 提升到 **512 KiB**
  - `ndk.exec` / `ndk.thread` 的 `steps = 0` 语义从"使用默认预算 32768"改为"**不限步数**"（运行到 SYSCON 退出 / ecall / trap / ndk.stop）
  - 4 个 C guest 示例 (`hello_world` / `exchange_buffer_demo` / `gpio_hostabi_demo` / `crypto_hash_demo`) 全部改用 helper，删除每个 `main.c` 里重复的 `_start` / `ndk_memory_size` / SYSCON 硬编码写
  - `crypto_hash_demo` 由"guest 软算 MD5 + CRC32"切换为"guest 调 host CSR 0x230 / 0x231"
  - 新增 `rust_hello_world` Rust no-std 示例（target `riscv32imac-unknown-none-elf`，后因 build 工具链复杂度放弃）
  - 单文件 `README.md` (751 行) 拆为 `docs/{quickstart,build,troubleshooting,lua-api,csr-abis,examples,changelog,api-helper}.md`，原 `README.md` 缩为索引
  - 新增 `DESIGN.md` 15 节设计文档
  - 新增 512 KiB RAM 烟雾测试（`bsp/pc/test/113.ndk_simple/main.lua` 改为 `512*1024`）
  - `testcase/ndk/ndk_basic/scripts/ndk_test.lua` 的 `MEM_SIZE` 从 32 KiB 提升到 64 KiB（保持"超限"用例在 512 KiB 边界内仍有效）

## 2026-05 — RV32F 收尾

- 阶段化 RV32F 浮点扩展（`rv32imf`）支持：`FLW/FSW` / `FMV.*` / `FADD/FSUB/FMUL/FDIV/FSQRT.S` / `FMADD/FMSUB/FNMSUB/FNMADD.S` / `FMIN/FMAX.S` / `FEQ/FLT/FLE.S` / `FCLASS.S` / `FCVT.*.W/WU` / `FCVT.W/WU.S`
- Host-backed rounding 支持 `RNE/RTZ/RDN/RUP`（`rm/frm = 0..3`）；`RMM` (`rm/frm = 4`) 仍走非法指令路径
- 补充 `baremetal_fadd_rmm_static.bin`（`rm=4`）与 `baremetal_fadd_rmm_dynamic.bin`（`frm=4 + rm=dyn`）作为 `RMM` 限制回归

## 2026-05 — Host ABI v1 / GPIO v2 / UART v1

- 新增 Host ABI v1 命令链：`LUAT_NDK_CMD_*` opcodes
- GPIO v2：`GPIO_CONFIG` / `GPIO_WRITE` / `GPIO_READ` / `GPIO_IRQ_STATE` / `GPIO_IRQ_CLEAR`，request/response 模式（`csrrw a0, csr, a0`）
- GPIO ownership 策略：上下文级别 pin 仲裁，`HOST_ERROR` 表示被占
- UART v1：`UART_CONFIG` / `UART_TX` / `UART_RX_STATE` / `UART_RX_READ` / `UART_RX_CLEAR`，loopback-backed PC 回归模型
- `event ring` 异步通知（`TIMER` / `GPIO_IRQ` / `UART_RX_READY`）
- 新增 `hostabi_v1` fixture + `ndk_stubs.c`（独立 out-of-line CSR helpers）

## 2025-12 — 初始落地

- mini-rv32ima 内核接入（`include/mini-rv32ima.h`）
- PC 模拟器侧 RV32IMA 沙箱 + 同步 / 异步执行 + 状态机
- Lua 绑定 `ndk.{rv32i,setData,getData,exec,thread,stop,reset,info}`
- 32 KiB RAM 上限的 baremetal.bin + 简单 smoke
- `docs/superpowers/specs/2026-05-20-gpio-v2-design.md` 等 superpowers spec 起步
