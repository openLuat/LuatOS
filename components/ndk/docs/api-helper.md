# `luat_ndk_helper.h` — NDK guest 标准库

> 本文是 NDK 文档集的一部分。完整索引见 [`../README.md`](../README.md)。

[`luat_ndk_helper.h`](../guest/include/luat_ndk_helper.h) 是 NDK guest 的"标准库"——一个 header-only 的 C 头，集中提供 NDK guest 编程中常用的小工具。它通过 `#include "luat_ndk_builtin.h"` 与 `#include "luat_ndk_abi.h"` 提供底层能力，所有 API 都是 `static inline` / 宏，没有需要链接的额外翻译单元。

## 用法

在 guest 源码里：

```c
#include "luat_ndk_helper.h"

static int main(void) {
    ndk_exchange_write_bytes(0, (const uint8_t *)"HELLO", 5);
    ndk_exit_ok();
    return 0;
}
NDK_GUEST_START(main)
```

构建时确保 `-I` 指向两个目录：

- `components/ndk/include`（`luat_ndk_abi.h` / `luat_ndk_builtin.h` / `luat_ndk.h`）
- `components/ndk/guest/include`（本文件）

`components/ndk/guest/examples/build_example.ps1` 已经自动加好这两个 `-I`。

## 分组

### 常量

| 名称 | 值 | 说明 |
|---|---|---|
| `NDK_RAM_BASE` | `0x80000000u` | guest RAM 起始地址 |
| `NDK_SYSCON_ADDR` | `0x11100000u` | SYSCON MMIO 退出地址 |
| `NDK_DONE_MARKER` | `0x5555u` | "I am done" 魔法值 |

### 启动

| 名称 | 用途 |
|---|---|
| `ndk_stack_top()` | 返回 `NDK_RAM_BASE + ndk_memory_size() - 16`（含 16 字节红区） |
| `NDK_GUEST_START(fn)` | 宏：定义 `_start`，设置 sp，调用 `fn()`，main 返回后进 wfi；支持 non-leaf `main`（`main` 可自由调非 inline 助手或自然 return） |
| `ndk_wfi_loop()` | 死循环 wfi |
| `ndk_exit(code)` | 写 `code` 到 SYSCON |
| `ndk_exit_ok()` | `ndk_exit(NDK_DONE_MARKER)` 简写 |

### 交换区

| 名称 | 用途 |
|---|---|
| `ndk_exchange_ptr()` | 返回 `volatile uint8_t *` 指向 exchange 头部 |
| `ndk_exchange_u32(off)` | 返回 `volatile uint32_t *` 指向 exchange + `off` |
| `ndk_exchange_read_u32(off)` | 32 位读 |
| `ndk_exchange_write_u32(off, v)` | 32 位写 |
| `ndk_exchange_write_bytes(off, src, n)` | 字节拷贝（用 ASCII 字符串时**必须**用这个） |

### 字节序

| 名称 | 用途 |
|---|---|
| `ndk_load32_le(p)` | 4 字节 little-endian → `uint32_t` |
| `ndk_store32_le(p, v)` | `uint32_t` → 4 字节 little-endian |

### 日志（CSR 0x136/0x137/0x138）

| 名称 | 用途 |
|---|---|
| `ndk_log_str(s)` | 打印 guest-resident C 字符串（限 120 字节） |
| `ndk_log_int(v)` | 打印 32-bit 整数（`vm num: %d`） |
| `ndk_log_hex(v)` | 打印 32-bit 十六进制（`vm ptr: 0x%08X`） |
| `ndk_log_ptr(p)` | 同 `ndk_log_hex` |

### GPIO v2 pack/unpack

| 名称 | 用途 |
|---|---|
| `NDK_GPIO_CONFIG_PACK(pin, mode, pull, irq_mode)` | 4 字节打包给 `ndk_gpio_config` |
| `NDK_GPIO_WRITE_PACK(pin, level)` | 4 字节打包给 `ndk_gpio_write_v2` |
| `NDK_GPIO_IRQ_STATE_PIN/PENDING/REASON_OF(v)` | 解包 `GPIO_IRQ_STATE` 返回值（别名自 `LUAT_NDK_GPIO_IRQ_STATE_*`） |

### Status 解码

| 名称 | 范围 | 返回字符串例子 |
|---|---|---|
| `ndk_host_error_name(s)` | 0..3 | `"OK"` / `"BAD_OPCODE"` / `"PARAM"` / `"UNSUPPORTED"` |
| `ndk_gpio_status_name(s)` | 10..15 | `"GPIO_OK"` / `"GPIO_BAD_PIN"` / ... |
| `ndk_uart_status_name(s)` | 20..26 | `"UART_OK"` / ... |
| `ndk_crypto_status_name(s)` | 30..33 | `"CRYPTO_OK"` / ... |
| `ndk_status_name(s)` | 任何 | 上面 4 个的 dispatcher |

### Host hash（CSR 0x230 / 0x231）

| 名称 | 用途 | 返回 |
|---|---|---|
| `ndk_hash_md5(in_off, in_len, out_off)` | 调 host 算 MD5，写 16B 到 `out_off` | `LUAT_NDK_CRYPTO_STATUS_*` |
| `ndk_hash_crc32(in_off, in_len)` | 调 host 算 CRC32（IEEE polynomial） | **直接是 CRC32 值**（不是 status） |

> **CRC32 返回的是数值本身**，不是状态码。判断"成功 / 越界"要查 `ndk_last_error()`（CSR 0x13F）。详见 [`csr-abis.md`](./csr-abis.md) 的 Crypto v1 节。

### 事件 ring

| 名称 | 用途 |
|---|---|
| `ndk_event_peek(out)` | 把下一个事件拷到 `*out`（不前进 guest_read），返回事件 type 或 `LUAT_NDK_EVENT_NONE` |

## 不提供的 API

- memcpy / memset 包装：用编译器 builtin
- printf 变参格式化：开销大，超出 helper 范围
- 浮点辅助：RV32F guest 直接用原生 float
- UART RX 用户态缓存：用 `ndk_uart_*` CSR 即可

## 移植到 Rust

`luat_ndk_helper.h` 是 C-only（`static inline` + `__asm__`），Rust 移植需要 unsafe wrapper crate，每个 csrrw 都要 unsafe。本仓库目前不提供 `ndk-helper` crate，未来可作为独立 follow-up。
