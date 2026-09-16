# 日志口用户指令协议 v2（usercmd v2）

通过日志口扩展用户指令，由设备端 Lua 脚本实现具体功能（如文件系统操作），无需额外 UART。
协议具备：**版本号、命令序号、滑动窗口 + 逐片确认 + 自动重传、分片大小协商、open/read/write/close 文件模型**。

- 下行（PC→设备）：0xA5 帧，`cmd = SOC_CMD_USER_CMD(19)`，`address` 置 0，payload 为本协议帧
- 上行（设备→PC）：本协议帧经 `log.usercmd_write` 以日志帧发出（payload 二进制安全），以 2 字节 magic 与普通日志区分
- 多字节一律小端（LE）

## 1. 帧格式

固定头 7 字节，后跟子指令特定字段。

| 偏移 | 字段 | 类型 | 说明 |
|---|---|---|---|
| 0..1 | magic | u8[2] | 固定 `0xC5 0x5C`，标识 usercmd 协议帧 |
| 2 | version | u8 | 协议版本，当前 `0x01` |
| 3 | subcmd | u8 | 子指令号，见 §3 |
| 4 | flags | u8 | bit0=ERR（回应为错误），bit1=MORE（LSDIR 还有后续页），bit2..7 保留，置 0 |
| 5..6 | seq | u16 | 命令序号，host 每请求递增（允许回绕） |

回应帧回显请求的 seq。除 HELLO 外的请求 seq 由 host 单调分配；设备不主动发帧。

- magic / version 不符：设备**静默丢弃**（不回应），host 侧靠超时重传兜底
- path 上限 127 字节，超长回应 errno=6
- 错误回应：flags 置 ERR，body 首字节为 errno

## 2. 错误码（errno）

| 值 | 含义 |
|---|---|
| 0 | 成功 |
| 1 | not found |
| 2 | denied（脚本拒绝执行该操作） |
| 3 | io error |
| 4 | bad request（格式/参数非法） |
| 5 | bad fd |
| 6 | path too long |
| 7 | busy |

## 3. 子指令

| subcmd | 名称 | 类别 | 请求 body | 回应 body |
|---|---|---|---|---|
| 0 | HELLO | 控制 | u32 nonce + u16 propose_chunk | u32 nonce + u16 chunk + u8 version |
| 1 | OPEN | 控制 | u8 mode + path（余下全部字节） | u8 errno + u8 fd |
| 2 | CLOSE | 控制 | u8 fd | u8 errno + u32 size（写/追加模式为最终文件大小） |
| 3 | WRITE_DATA | 数据 | u8 fd + u32 offset + data | u8 errno + u8 fd + u32 offset |
| 4 | READ_DATA | 数据 | u8 fd + u32 offset + u16 len | u8 errno + u8 fd + u32 offset + u16 len + data |
| 5 | LSDIR | 控制 | u8 pathlen + path + u32 offset + u16 count | u32 remaining + u16 entries_len + entries |
| 6 | MKDIR | 控制 | path | u8 errno |
| 7 | RMDIR | 控制 | path | u8 errno |
| 8 | REMOVE | 控制 | path | u8 errno |
| 9 | STAT | 控制 | path | u8 errno + u8 type + u32 size |
| 10 | EXISTS | 控制 | path | u8 errno + u8 exists |

- mode：0=读，1=写（覆盖），2=追加，3=读写不截断（随机写场景，追加写建议用 3 并按 stat 的 size 定位偏移）
- fd：设备分配的小整数句柄（1..4），OPEN 失败 fd 置 0
- LSDIR 条目序列化（连续排列，总长 entries_len 字节）：
  `u8 type(0=file,1=dir) + u32 size + u8 namelen + name`
  设备按可用空间尽量填充；塞不下时置 flags.MORE，host 以 offset（条目索引）+count 翻页。
  `remaining` = 本页之后还剩多少条目。
- STAT：errno=0 时 type/size 有效；文件不存在 errno=1。EXISTS 用 errno=0 + exists 标志区分"不存在"与"出错"。
- READ_DATA 回应 len ≤ 请求 len；读至 EOF 时 len 小于请求值。data 之后可能随带日志帧 4 对齐填充，host 必须按 len 截取，不得按帧长。

## 4. 传输层约束（与固件相关）

下行 0xA5 帧在 C 层（ccm42xx `am_log.c`）有两道硬限制：

```
线上(转义后)帧长  ≤ sizeof(rx_cache2)   // 线上累积缓冲, 超限丢字节
解包后帧长        ≤ sizeof(rx_cache1)   // 24B帧头 + payload + 2B CRC, 超限整帧丢弃(有界反转义)
```

当前固件 `rx_cache1[512]` / `rx_cache2[1056]`，故：
- 解包后 ≤ 512 → 下行 payload ≤ **486B** → WRITE_DATA 数据区 chunk = 486 - 12(应用头) = **474B**
- 转义最坏 1→2 字节：线上 ≤ 2×(38+474)+1 = 1025 ≤ 1056 ✓（任意内容安全）

历史固件的帧长预检把"转义后帧长"错比到解包缓冲（128B），导致含 0xA5/0xA6 字节的帧被静默丢弃；
v2 固件已修正为线上比线上缓冲 + 有界反转义，chunk=474 对任意数据内容成立。

除解包缓冲外，下行链路还有两道固件约束（v2 固件均已配套修改）：

1. **UART RX 中转缓冲**：日志口 UART 的 IRQ 回调原本用 `uint8_t temp[32]` 接收，
   `Uart_NoBlockRxPart/RxAll` 单次最多抽 32B，大于 ~130B 的突发帧被截断丢弃（v1 的"偶发丢帧"主因）。
   v2 固件：回调改静态 512B 缓冲 + 驱动 Len 参数从 uint8_t 加宽为 uint32_t。
2. **UART 硬件 FIFO**：接收触发阈值内必须及时抽走，host 侧持续灌入时靠 RFTS 中断重复触发；
   实测 6M 波特、512B 静态抽吸缓冲下 474B 帧连续发送无丢字节。

**chunk 通过 HELLO 协商**：host 发送期望片长 propose_chunk，设备回应实际可用值
`chunk = min(设备能力, propose_chunk)`。设备能力 = min(固件 UART RX 缓冲, am_log 解包链路上限)
（旧固件为 90B 且受转义影响），host 后续 WRITE_DATA 一律按协商值分片。
加大固件缓冲即可提升吞吐，协议无需变更。

## 5. 会话与确认机制

### 5.1 HELLO 握手

host 开串口后首先发送 HELLO(nonce, propose_chunk)：
- 设备收到后**清空控制去重缓存**，回显 nonce、报告 chunk 与版本
- host 校验 nonce 回显正确，否则重发（超时 1000ms，最多 5 次）
- host 可用 HELLO 探测设备重启（nonce 不匹配 / 无响应）

### 5.2 控制类（OPEN / CLOSE / LSDIR / MKDIR / RMDIR / REMOVE / STAT / EXISTS）

stop-and-wait，单请求在途：
- 超时 1000ms 重传，共 5 次，仍失败则向上层报错
- 设备端去重：缓存 `(last_ctrl_seq, last_ctrl_resp)`，同 seq 重发直接重发缓存回应、**不重复执行**
  （解决"回应帧丢失导致 host 重发"时 CLOSE 等被二次执行的问题）

### 5.3 数据类（WRITE_DATA / READ_DATA）

滑动窗口，默认 W=8（host 可配）：
- host 连续发出至多 W 个请求（seq 递增），每个请求独立计时
- 设备收到即执行并立即回应（同 seq 回显）；**所有数据操作按 offset 幂等**（重复执行结果相同），
  因此设备端无需缓存窗口/去重状态
- host 每收到一个 seq 的回应即标记确认；未确认请求超时 500ms 重发，单帧最多 10 次
- 全部确认后窗口滑动（以最早未确认 seq 为窗口前沿）

写文件流程：
```
OPEN(path, w) --stop-and-wait--> fd
WRITE_DATA(fd, off0, d0) ┐
WRITE_DATA(fd, off1, d1) ├ 窗口流水，逐片 ACK
...                      ┘
CLOSE(fd) --> size
```

读文件流程：
```
OPEN(path, r) --> fd
READ_DATA(fd, off, 512) × N  窗口流水，按 offset 拼接
  （每片返回 ≤512B，EOF 时返回短读）
CLOSE(fd)
```

### 5.4 丢帧模型

- 下行丢帧（设备忙 RX 溢出）：host 超时重传，设备幂等重执行 → 无损
- 上行丢帧（回应未达 host）：同上下行，host 重发请求 → 设备重执行（幂等）→ 重回应
- 唯一的非幂等点是控制类"执行后回应丢失"，由设备端 `(seq,resp)` 缓存解决

## 6. 时序参考值（ccm42xx @ 6M 波特）

| 参数 | 默认值 |
|---|---|
| 控制超时 | 1000ms × 5 次 |
| 数据片超时 | 500ms × 10 次 |
| 窗口 W | 8 |
| 读片长 | 512B（host 侧参数，上行无此限制） |
| 协商写片长 chunk | 474B（当前固件） |

吞吐估算：`chunk × W / RTT`，RTT≈10ms 时约 370KB/s。

## 7. 权限模型

设备端不内置任何文件操作逻辑：`log_usercmd.lua` 仅实现协议栈（解析/序号/回应/分片），
具体 open/read/write/close/lsdir 等处理函数由脚本通过 `reg_op(name, fn)` 注册。
脚本可以选择只暴露部分操作，或加入路径白名单，从设备侧控制权限。
