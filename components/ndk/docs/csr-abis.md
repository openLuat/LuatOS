# NDK CSR / MMIO / ABI 接口

> 本文是 NDK 文档集的一部分。完整索引见 [`../README.md`](../README.md)。

## CSR 写（guest → host）

| CSR 地址 | 功能 | 参数格式 | 对应 host 行为 |
|----------|------|----------|---------------|
| `0x136` | 打印数字 | 32-bit 整数 | `DBG_ERR("vm num: %d", value)` |
| `0x137` | 打印指针 | 32-bit 地址 | `DBG_ERR("vm ptr: 0x%08X", value)` |
| `0x138` | 打印字符串 | guest 地址 | 读取并打印 C 字符串（最多 120 字节） |
| `0x143` | 延时 | us | 请求 host 延时（PC 实现按 ms 向上取整） |
| `0x144` | 事件开关 | `0/1` | 开启/关闭 timer 事件投递 |
| `0x200` | GPIO 输出（legacy） | `(level << 16) \| pin` | 设置 GPIO（v1，未实现完整） |
| `0x210` | `GPIO_CONFIG` v2 | `pin \| mode \| pull \| irq_mode` | 返回 `LUAT_NDK_GPIO_STATUS_*` |
| `0x211` | `GPIO_WRITE` v2 | `pin \| level` | 返回 `LUAT_NDK_GPIO_STATUS_*` |
| `0x212` | `GPIO_READ` v2 | `pin` | 成功：电平 `0/1`；失败：错误码 |
| `0x213` | `GPIO_IRQ_STATE` v2 | `pin` | 成功：packed IRQ state；失败：错误码 |
| `0x214` | `GPIO_IRQ_CLEAR` v2 | `pin` | 清 pending |
| `0x220` | `UART_CONFIG` v1 | `port \| cfg_offset` | 返回 `LUAT_NDK_UART_STATUS_*` |
| `0x221` | `UART_TX` v1 | `port \| data_offset \| length` | 返回状态 |
| `0x222` | `UART_RX_STATE` v1 | `port` | packed RX state |
| `0x223` | `UART_RX_READ` v1 | `port \| data_offset \| length` | 把 RX 数据拷到 exchange |
| `0x224` | `UART_RX_CLEAR` v1 | `port` | 丢弃 RX buffer |
| `0x230` | `CRYPTO_MD5` v1 | `in_off \| in_len \| out_off` | 写 16B MD5，返回 status |
| `0x231` | `CRYPTO_CRC32` v1 | `in_off \| in_len` | 返回 CRC32 值（不是 status） |

## CSR 读（host → guest）

| CSR 地址 | 返回值 | 说明 |
|----------|--------|------|
| `0x139` | 交换区起始地址 | guest 侧的绝对地址 |
| `0x13A` | 交换区大小 | 字节数 |
| `0x13B` | RAM 总大小 | 字节数（≤ 512 KiB） |
| `0x13C` | Host ABI magic | 当前为 `NDK1` |
| `0x13D` | Host ABI 版本 | 当前为 `0x00010000` |
| `0x13E` | Host 功能位图 | 对应 `ndk.info(ctx).features` |
| `0x13F` | 最近一次 Host 错误码 | 对应 `ndk.info(ctx).last_error` |
| `0x140` | 事件槽数量 | 对应 `ndk.info(ctx).event_slots` |
| `0x141` | 当前时间低 32 位 | ABI 单位为 us |
| `0x142` | 当前时间高 32 位 | ABI 单位为 us |
| `0x145` | 事件 pending 标志 | `0/1` |
| `0x201` | GPIO 输入（legacy） | 低 16 位为 pin 号（v1，未实现完整） |

## MMIO

| 地址 | 操作 | 行为 |
|------|------|------|
| `0x11100000` | store | 返回写入值到 a0，并把 guest PC 重置到镜像入口；后续 `do_reset=false` 会从 `_start` 重新进入 |

**示例**（guest 侧）：

```c
// 打印调试信息
asm volatile("csrw 0x138, %0" :: "r"("Hello from guest"));

// 获取交换区地址
uint32_t exchange_addr;
asm volatile("csrr %0, 0x139" : "=r"(exchange_addr));

// 退出并返回 0x5555
*(volatile uint32_t*)0x11100000 = 0x5555;
```

---

## Host ABI v1 / GPIO v2 / UART v1

当前基础能力覆盖：

- ABI 发现：magic / version / feature bits / last_error / event_slots
- 时间/事件核心：`delay_us`、`time_us_lo/hi`、`event_enable`、`event_pending`
- GPIO v2：`GPIO_CONFIG`、`GPIO_WRITE`、`GPIO_READ`、`GPIO_IRQ_STATE`、`GPIO_IRQ_CLEAR`
- UART v1：`UART_CONFIG`、`UART_TX`、`UART_RX_STATE`、`UART_RX_READ`、`UART_RX_CLEAR`
- **Crypto v1**：`CRYPTO_MD5`、`CRYPTO_CRC32`（见下文）
- PC 回归 fixture：`components\ndk\guest\fixtures\hostabi_v1`

交换区布局：

- `0..15`：guest 命令区（`hostabi_cmd_t`）
- `16..31`：guest 结果区（`hostabi_result_t`）
- `32..47`：事件头（`luat_ndk_event_header_t`）
- `48..`：事件槽数组（`luat_ndk_event_t[event_slots]`）

其中 `event_slots` 会按交换区可用空间计算，最大为 8。

### GPIO v2 CSR

GPIO v2 通过 `csrrw a0, csr, a0` 的请求/应答模式工作，不再依赖 legacy `0x200/0x201` 语义：

- `0x210` `GPIO_CONFIG`
  - 请求：`a0 = pin[7:0] | mode[15:8] | pull[23:16] | irq_mode[31:24]`
  - 返回：`LUAT_NDK_GPIO_STATUS_*`
- `0x211` `GPIO_WRITE`
  - 请求：`a0 = pin[15:0] | level[16]`
  - 返回：`LUAT_NDK_GPIO_STATUS_*`
- `0x212` `GPIO_READ`
  - 请求：`a0 = pin[15:0]`
  - 返回：成功时为电平 `0/1`；失败时为 `LUAT_NDK_GPIO_STATUS_*`
- `0x213` `GPIO_IRQ_STATE`
  - 请求：`a0 = pin[15:0]`
  - 返回：成功时为 packed IRQ state，布局与 `components/ndk/include/luat_ndk_abi.h` 一致
- `0x214` `GPIO_IRQ_CLEAR`
  - 请求：`a0 = pin[15:0]`
  - 返回：`LUAT_NDK_GPIO_STATUS_*`
  - 语义：清除该 pin 的 pending 位，同时把记录的 reason 归零

GPIO ownership / error policy：

- `GPIO_CONFIG` / `GPIO_WRITE` 成功后才声明 pin 所有权；host HAL 失败返回 `HOST_ERROR`
- 所有权是上下文级别仲裁；另一上下文对已占用 pin 的 `GPIO_CONFIG` / `GPIO_WRITE` 会收到 `HOST_ERROR`
- `GPIO_READ` 是非 owning probe，只读取当前电平，不抢占或释放所有权

GPIO IRQ 事件语义：

- 异步通知仍走 event ring，事件类型为 `GPIO_IRQ`（`type = 2`）
- `source` 为触发 pin，`data` 为与 `GPIO_IRQ_STATE` 相同布局的 packed IRQ payload
- 这是通知型事件；权威状态与 ack 始终来自 `GPIO_IRQ_STATE` / `GPIO_IRQ_CLEAR`

### UART v1 CSR

- `0x220` `UART_CONFIG`
- `0x221` `UART_TX`
- `0x222` `UART_RX_STATE`
- `0x223` `UART_RX_READ`
- `0x224` `UART_RX_CLEAR`

`UART_RX_READY` 通过现有 event ring 异步投递（`type = 3`）。该事件只负责通知，缓冲区长度与确认/清理语义以 `UART_RX_STATE` / `UART_RX_READ` / `UART_RX_CLEAR` 为准。

当前 PC 模拟器回归使用确定性的上下文私有 loopback 模型：

- `UART_CONFIG` 启用 loopback-backed UART 上下文
- `UART_TX` 将交换区数据写入 host loopback backend
- `UART_RX_STATE` / `UART_RX_READ` 读取回环后的接收状态与数据
- `UART_RX_CLEAR` 会丢弃当前 RX buffer 中的全部字节

如果 `bsp\pc\luat_uart_i686.dll` 可用，且 CH340 loopback 接在 `COM14`，可以做手工 smoke；自动回归仍以确定性的 host-backed loopback 为准。

### Crypto v1 CSR（**新增于本 PR**）

- `0x230` `CRYPTO_MD5`
  - 请求：`a0 = in_offset[31:22] | in_len[21:12] | out_offset[11:2]`
  - host 读取 `in_offset..in_offset+in_len` 计算 MD5，写到 `out_offset..out_offset+16`
  - 返回：`a0 = LUAT_NDK_CRYPTO_STATUS_*`（OK / BAD_BOUNDS / UNSUPPORTED / HOST_ERROR）
  - 范围越界返 `BAD_BOUNDS`；host 底层（`luat_crypto_md5_simple`）失败返 `UNSUPPORTED`
- `0x231` `CRYPTO_CRC32`
  - 请求：`a0 = in_offset[31:20] | in_len[19:8]`
  - host 读取 `in_offset..in_offset+in_len` 计算 IEEE CRC32（init=0xFFFFFFFF）
  - 返回：`a0 = 实际 CRC32 值`（**不是 status code**）
  - 失败/越界需要通过 `ndk_last_error()`（CSR 0x13F）查询 host 设置的 `LUAT_NDK_HOST_ERR_PARAM`

> **设计取舍**：CRC32 handler 直接返回结果而不是 status，是因为 CRC32 的"成功/失败"语义比较弱（"成功"就是"算出来一个 32-bit 值"），而把"越界"放到 `ndk_last_error()` 不影响正常路径的返回值。

C-side helper 见 [`api-helper.md`](./api-helper.md)。`crypto_hash_demo` 演示了 MD5 + CRC32 两条路径。

### Host ABI 回归

重建 guest fixture：

```powershell
Set-Location components\ndk\guest
.\build_hostabi_v1.ps1
```

运行 Host ABI suite：

```powershell
Set-Location bsp\pc
cmd /c build_windows_32bit_msvc.bat
build\out\luatos-lua.exe ..\..\testcase\common\scripts\ ..\..\testcase\ndk\ndk_hostabi_basic\scripts\
```
