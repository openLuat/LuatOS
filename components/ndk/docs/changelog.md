# NDK 变更日志

> 本文是 NDK 文档集的一部分。完整索引见 [`../README.md`](../README.md)。

## 2026-06 — `perf_guest_v1` `_start` 缺 `naked` 修复

- **Bug 修复**：`components/ndk/guest/examples/perf_guest_v1/main.c` 的 `_start` 只标了 `__attribute__((noreturn))`，没标 `naked`，所以编译器仍给它生成函数 prologue（`addi sp, sp, -0x10; sw ra, 0xc(sp)`）——而 host 的 `ndk_reset_core` 把 32 个 GPR 全部 `memset` 为 0，**入口 sp=0**。Prologue 第一步 `addi sp, sp, -0x10` → sp=`0xFFFFFFF0`，第二步 `sw ra, 0xc(sp)` 写到 `0xFFFFFFFC` → `mcause=7` (store access fault) `mtval=0xFFFFFFFC`。**注意**：`mtvec` 被设成 `0x80000000`（即 guest 镜像起点），trap 后 PC 被设回 `mtvec`，所以**同一次 `ndk.exec` 调用里 trap 后又从 `_start` 重新跑，每次重新 trap**，循环直到 step budget 用完。
- **症状**：`ndk.exec` 返回 `false, "trap", 7, 0xFFFFFFFC`。Log 里**看不到任何 guest 输出**（`vm: M0\n` / `vm: S1\n` 等一行都没有），因为 trap 发生在 `_start` prologue，第一个 `csrr 0x13B` / `ndk_lprint("S1")` 还没到。
- **触发条件**：guest 的 `_start` 是手写 C 函数（没走 `NDK_GUEST_START` 宏）且没用 `naked` 属性，编译器就会加 prologue。`hello_world` / `exchange_buffer_demo` / `gpio_hostabi_demo` / `crypto_hash_demo` 都用 `NDK_GUEST_START` 宏（`naked` 实现的），所以**全部 4 个官方示例都掩盖了 bug**。`perf_guest_v1` 因为作者刻意避开 `NDK_GUEST_START` 宏（main.c 的注释说 "if any function is defined before main() in the source, the linker puts main() at 0x80000000"），又忘了加 `naked`，trap 必现。
- **修复**：把 `perf_guest_v1/main.c` 的 `_start` 改成 `__attribute__((naked, noreturn))` + 内联汇编裸 `csrr 0x13B` / `mv sp` / `jalr ra, t0` / `wfi` 循环；`__test_minimal.c` / `__test_dispatch.c` 已经用 `NDK_GUEST_START` 宏不需要改。
- **诊断建**：`bsp/pc/pclogs/luatos_pc_<ts>.log` 出现 `mcause=7 mtval=0xFFFFFFFC` 且 log 里**没有 guest 任何 `vm:` 输出** → 99% 是 `_start` prologue 路径；修复前 1 次 `ndk.exec` 会反复 trap 直到 budget 用尽。
- **回归**：`testcase/ndk/ndk_perf_guest` 套件原本 28/31 失败（`test_md5_*` / `test_crc32_*` / `test_fnv1a_*` / `test_heapsort_*` / `test_base64_*`），本次修复**只解掉了 `_start` prologue 这一类 trap**（MD5/CRC32/FNV1A 全过）；剩余 18 个失败是独立 bug：base64 输出超过 `MAX_CHUNK=0x3c0` 触发 `BAD_BOUNDS`、heapsort C / Lua baseline 算法 bug、base64 Lua baseline 对 'f' 输入的 bug——与 `_start` 无关，留作另外 ticket。`bsp/pc/test/116.ndk_examples_smoke` 5 个 case 仍全过；`testcase/ndk/ndk_basic` 42/0、`ndk_hostabi_basic` 39/0 baseline 不变。

## 2026-06 — `NDK_GUEST_START` 链接寄存器修复

- **Bug 修复**：`NDK_GUEST_START` 宏在 `98d4c79e2` 重构时把 `call main` 改成 `mv t0, %1; jalr zero, t0` 以解决 `static main` 在汇编端不可见的问题，但同时把 `ra` 的写入丢到了 `x0`。宿主 `ndk_reset_core` 把 32 个 GPR 全部 `memset` 为 0，所以 `main` 的 `ret` 跳到地址 0 → 取指违例 (`mcause=1, mtval=0`)。
- 4 个官方示例 (`hello_world` / `exchange_buffer_demo` / `gpio_hostabi_demo` / `crypto_hash_demo`) 全部以 `ndk_exit_ok()` 结尾，host 的 stepper 在 SYSCON 0x5555 写入当次迭代就 `return`，**根本没到 main 的 `ret`** —— bug 被巧合遮住。任何让编译器为 `main` 生成真实 `call`/`ret` 边界的代码（调非 inline 函数）会立即暴露 trap。
- 修复：`jalr zero, t0` → `jalr ra, t0`，ra 写入 `_start` 的 PC+4（即 wfi 循环入口），main 自然 return 后安全 park。
- 回归测试：新增 `components/ndk/guest/examples/nonleaf_call_demo`（`__attribute__((noinline))` 助手 + 自然 return，无 `ndk_exit_ok`），`bsp/pc/test/116.ndk_examples_smoke/main.lua` 追加该 case 并把 "step budget 用尽但 `mcause == 0`" 识别为合法干净退出。修复后 case 5 报 `budget-exhausted-clean`，exchange[0] 写入 `compute(0,0)=0x9E3779B9`（端到端证明 non-leaf call 真的跑通）。修复前同一 case 会 `mcause=1, mtval=0`。
- `ndk_basic` 42/0、`ndk_hostabi_basic` 39/0 baseline 不变。

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
