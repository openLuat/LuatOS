# NDK Lua API 参考

> 本文是 NDK 文档集的一部分。完整索引见 [`../README.md`](../README.md)。

## 运行时 API

### `ndk.rv32i(path, mem_size, exchange_size, opts)`

创建 RV32IMA 执行上下文。

**参数**：
- `path`：guest 镜像路径（相对或绝对）
- `mem_size`：guest RAM 大小（字节，默认 8 KiB，**最大 512 KiB**）
- `exchange_size`：host-guest 交换区大小（字节，默认 4 KiB，必须 < `mem_size`）
- `opts`：可选表 `{ isa = "rv32ima" | "rv32imf" }`

**返回**：
- 成功：`ctx` userdata（Lua GC 托管，`__gc` 时自动清理）
- 失败：`nil, error_message`

**内存布局**：
```
[镜像加载区 | 自由空间 | 交换区（尾部）]
 ^                        ^
 0x80000000              exchange_offset = mem_size - exchange_size
```

**约束**：
- `mem_size <= 512 * 1024`
- `exchange_size < mem_size`

---

### `ndk.exec(ctx, opts)`

同步执行 guest 代码。

**参数**：
- `ctx`：执行上下文
- `opts`：选项表（可选）
  - `steps`：步数预算（**默认 0 = 不限步数**）
  - `elapsed`：每步时间 us（默认 100）

**返回**：
- 成功（SYSCON 写 `0x5555` 退出）：`true, 0`
- 成功（ecall 退出，`mcause = 11`）：`true, retval`（`retval` = a0 寄存器值）
- 步数耗尽 / `ndk.stop` 打断：`false, "timeout", mcause, mtval`
- Trap / 异常：`false, "trap", mcause, mtval`
- 繁忙（已在运行）：`false, "busy", mcause, mtval`

**状态约束**：仅在空闲态可调用。

**示例**：
```lua
-- 旧式：限 100k 步
local ok, ret, mcause, mtval = ndk.exec(ctx, {steps = 100000, elapsed = 500})

-- 新式：不限步数（推荐），靠 SYSCON / ndk.stop 兜底
local ok, ret = ndk.exec(ctx, {steps = 0, elapsed = 100})
```

---

### `ndk.thread(ctx, opts)`

异步执行 guest 代码（后台线程）。

**参数**：同 `exec`

**返回**：
- 成功启动：线程 ID（递增整数）
- 繁忙：`nil, "busy"`

**注意**：需要后续调用 `ndk.stop()` 停止线程。`steps = 0` 仍表示不限步数。

---

### `ndk.stop(ctx, wait_ms)`

停止异步线程。

**参数**：
- `ctx`：执行上下文
- `wait_ms`：等待超时（毫秒，默认 1000）

**返回**：
- 成功：`true`
- 超时：`false, "timeout"`

**幂等性**：空闲态/已停止时调用为安全幂等。`wait_ms = 0` 可用于非阻塞轮询。

---

### `ndk.reset(ctx)`

重新加载镜像并重置状态。

**行为**：
- 重新从文件读取镜像
- 清零 RAM 和交换区
- 重置 CPU 寄存器（PC = 0x80000000）

**返回**：
- 成功：`true`
- 繁忙：`false, "busy"`

**状态约束**：仅在空闲态可调用。

---

### `ndk.info(ctx)`

获取上下文状态。

**返回表字段**：
- `mem`：RAM 总大小（字节）
- `exchange`：交换区大小（字节）
- `exchange_addr`：交换区起始地址（guest 视角）
- `image`：镜像路径
- `running`：是否正在运行（boolean）
- `mcause`：最后一次 trap 原因码
- `mtval`：最后一次 trap 值
- `abi_magic`：Host ABI magic（当前为 `NDK1`）
- `abi_version`：Host ABI 版本（当前 `0x00010000`）
- `features`：功能位图
- `last_error`：最近一次 Host ABI 错误码
- `event_slots`：当前事件槽数量
- `isa`：当前 ISA 字符串
- `flen`：FPU 寄存器位宽（0/32）
- `fcsr` / `frm` / `fflags`：浮点 CSR 当前值

**当前 `features` 位图**：
- bit0 `META`
- bit1 `TIME`
- bit2 `EVENT`
- bit3 `GPIO`
- bit4 `UART`
- bit5 `CRYPTO`

---

### `ndk.setData(ctx, data_str, offset)`

写数据到交换区。

**参数**：
- `ctx`：执行上下文
- `data_str`：要写入的字符串（或 zbuff）
- `offset`：交换区内偏移（默认 0）

**返回**：
- 成功：写入字节数
- 失败：`false, error_message`

---

### `ndk.getData(ctx, [buff], len, offset)`

从交换区读数据。

**参数**：
- `ctx`：执行上下文
- `buff`：可选 zbuff 输出缓冲
- `len`：读取长度（字节）
- `offset`：交换区内偏移（默认 0）

**返回**：
- 成功：数据字符串 / 写入字节数
- 失败：`false, error_message`

---

## 最小使用示例

```lua
-- 完整生命周期示例
local IMAGE = "/luadb/baremetal.bin"
local ctx, err = ndk.rv32i(IMAGE, 32 * 1024, 1024)
assert(ctx, err)

local info = ndk.info(ctx)
log.info("ndk", "mem", info.mem, "exchange", info.exchange)

-- 写入数据到交换区
local n, err = ndk.setData(ctx, "hello ndk")
assert(n and n ~= false, "ndk.setData failed: " .. tostring(err))

-- 执行 guest（不限步数）
local ok, ret, mcause, mtval = ndk.exec(ctx, {steps = 0, elapsed = 100})
assert(ok, string.format("exec fail %s mcause=%s mtval=%s",
    tostring(ret), tostring(mcause), tostring(mtval)))

-- 读取交换区结果
local data, data_err = ndk.getData(ctx, 64, 0)
assert(data and data ~= false, "ndk.getData failed: " .. tostring(data_err))
log.info("ndk", "ret", ret, "data", data)

-- 清理
assert(ndk.stop(ctx, 1000))
assert(ndk.reset(ctx))

ctx = nil
collectgarbage("collect")
```
