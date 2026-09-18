# 日志口用户指令协议 v2（usercmd v2）

通过日志口扩展用户指令，由设备端 Lua 脚本实现具体功能（如文件系统操作），无需额外 UART。
协议具备：**版本号、命令序号、滑动窗口 + 逐片确认 + 自动重传、分片大小协商、open/read/write/close 文件模型、
可选 HMAC 挑战应答鉴权、挂载点枚举（LSMOUNT）、文件系统空间查询（FSSTAT）**。

- 下行（PC→设备）：0xA5 帧，`cmd = SOC_CMD_USER_CMD(20)`，`address` 置 0，payload 为本协议帧
- 上行（设备→PC）：同样以 0xA5 帧发出，`cmd = SOC_CMD_USER_CMD(20)`，`address` 置 0，payload 为本协议帧。
  设备端经 `log.usercmd_write` 发送，走**独占命令帧**通道（`cmd != 0`），不占用日志显示/打印窗
- 多字节一律小端（LE）

## 1. 帧格式

固定头 5 字节，后跟子指令特定字段。上下行帧结构完全一致。

| 偏移 | 字段 | 类型 | 说明 |
|---|---|---|---|
| 0 | version | u8 | 协议版本，当前 `0x01` |
| 1 | subcmd | u8 | 子指令号，见 §3 |
| 2 | flags | u8 | bit0=ERR（回应为错误），bit1=MORE（LSDIR 还有后续页），bit2..7 保留，置 0 |
| 3..4 | seq | u16 | 命令序号，host 每请求递增（允许回绕） |
| 5.. | body | u8[n] | 子指令特定字段 |

A5 传输层：`0xA5` + 转义后的（24 字节 SOC 帧头 + payload + 2 字节 CRC16-LE）+ `0xA5`。
SOC 帧头为设备端 `soc_cmd_head_t`（`ms:u64 + address:u32 + len:u32 + cmd:u32 + sn:u16 + type:u8 + cpu:u8`），
日志口以 `cmd != 0` 判定命令帧（不打印），`cmd == 0` 为普通日志帧。本协议上下行 `cmd` 均为 20。
（历史：2026-09-17 同步主干时，`SOC_CMD_USER_CMD` 与主干新增的 `SOC_CMD_LOG_RELOAD` 撞值 19，
按"主干优先"把本协议后移为 20；主机库与固件必须成对升级。）

回应帧回显请求的 seq。除 HELLO 外的请求 seq 由 host 单调分配；设备不主动发帧。

- version 不符：设备**静默丢弃**（不回应），host 侧靠超时重传兜底
- path 上限 127 字节，超长回应 errno=6
- 错误回应：flags 置 ERR，body 首字节为 errno
- 版本号保持 `0x01`：AUTH/LSMOUNT/FSSTAT 与 caps 均为向后兼容扩展
  （回应加长字段由 host 按长度判断，旧设备回旧格式，互不干扰）
- **v2.2 传输层变更**：上行帧由"嵌入日志帧 + 2 字节 magic 区分"改为**独占命令帧**，
  payload 取消 magic、固定头 `7B → 5B`。子指令语义与 v2.1 完全一致。
  该变更不向下兼容（v2.1 host 认不出 v2.2 上行帧），固件与 host 库须成对升级。
  设备端 C 实现为 `luat_log_user_cmd_write()`，ccm42xx 端口映射到 `soc_cmd_response(SOC_CMD_USER_CMD, 0, len, data)`
- **v2.3 参数适配**（帧格式与 v2.2 一致，`UC_VERSION` 保持 `0x01`）：适配厂商新固件 —
  单帧分片上限 476→1024（RX 解包缓冲 `rx_cache1` 扩至 1064B，转义流缓冲 2128B）；
  host 读片长 `read_chunk` 760→4096（TX 新增 16KB 专用 response_fifo，
  命令响应不再被 1600B log record 截断）。详见 §4/§6。

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
| 8 | nosys（子指令不存在：旧固件或未注册；与"denied"区分） |

## 3. 子指令

| subcmd | 名称 | 类别 | 请求 body | 回应 body |
|---|---|---|---|---|
| 0 | HELLO | 控制 | u32 nonce + u16 propose_chunk | u32 nonce + u16 chunk + u8 version + u16 caps |
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
| 11 | AUTH | 控制 | u8 maclen + mac（64B ASCII hex） | u8 errno + u8 status |
| 12 | LSMOUNT | 控制 | （空） | u16 entries_len + entries |
| 13 | FSSTAT | 控制 | path | u8 errno + u32 total + u32 used + u32 block_size + u8 fstype_len + fstype |

- mode：0=读，1=写（覆盖），2=追加，3=读写不截断（随机写场景，追加写建议用 3 并按 stat 的 size 定位偏移）
- fd：设备分配的小整数句柄（1..4），OPEN 失败 fd 置 0
- HELLO 回应 `caps`（u16, LE）：bit0=设备已配置鉴权 token（AUTH 必选），bit1..15 保留置 0。
  设备回应不足 9 字节（旧固件）时 host 视 caps=0，即设备不支持 AUTH。
  HELLO 同时重置设备的鉴权状态（authed=false）并记录 nonce 作为 AUTH 挑战
- AUTH（HMAC 挑战应答，详见 §5.5）：
  - `mac = HMAC-SHA256(key=token, msg=nonce 的 4 字节 LE 原串)` 的 64 字节 ASCII hex，
    **大小写不敏感**（各移植 hex 大小写不一，host 用 python `hexdigest()` 小写）
  - errno=0 + status：0=设备未配置 token（无需鉴权），1=鉴权成功
  - errno=2：mac 不匹配；errno=4：未先 HELLO（设备无可用挑战）
  - 仅设备配置了 token 时强制鉴权；未配置时 caps=0、AUTH 恒回 status=0、门控不生效
- LSMOUNT 条目序列化（连续排列，总长 entries_len 字节）：
  `u8 pathlen + path + u8 fstype_len + fstype`，path 为挂载点路径（根挂载为 ""，host 归一化为 "/"）
- FSSTAT：total/used 为字节数（设备端 block 数 × block_size 折算）；path 按 VFS 前缀匹配挂载点，
  配置了根挂载（如 ccm42xx 的 `""`）后所有路径都会落到根分区、恒返回成功；无 `io.fsstat`（非 VFS 移植）时 errno=8
- LSDIR 条目序列化（连续排列，总长 entries_len 字节）：
  `u8 type(0=file,1=dir) + u32 size + u8 namelen + name`
  设备按可用空间尽量填充；塞不下时置 flags.MORE，host 以 offset（条目索引）+count 翻页。
  `remaining` = 本页之后还剩多少条目。
- STAT：errno=0 时 type/size 有效；文件不存在 errno=1。EXISTS 用 errno=0 + exists 标志区分"不存在"与"出错"。
- READ_DATA 回应 len ≤ 请求 len；读至 EOF 时 len 小于请求值。命令帧 payload 长度精确（无对齐填充），
  host 仍应按 len 截取 data，不得按 payload 总长推断
- **WRITE_DATA 的 offset 是权威写入位置**，设备端必须按下列语义实现，否则窗口写的重传会损坏文件：
  - `offset ≤ 当前文件大小`：原地覆盖（重传同一片 = 幂等）
  - `offset > 当前文件大小`：先补零到 offset 再写。
    顺序写文件系统（如 ramfs）**不支持跳跃写未分配区域**：`f:seek("set", offset)` 越界会被忽略，
    数据落到 EOF（既不报错也不补零），从而静默截断/错位
  - 补零长度上限 64 KiB，超出回应 errno=4（防异常空洞耗尽内存）
  - 写后必须回读文件大小，确认 `size ≥ offset + len`，否则回应 errno=3（设备端 FS 静默丢弃写的兜底）
- host 侧校验（把静默损坏变成显式报错）：
  - WRITE_DATA 成功回应的 offset 必须与请求一致，不一致则该确认作废并重传同 seq；
    重试耗尽报 `write offset=N ack mismatch`
  - CLOSE 返回的最终大小必须等于预期长度，否则报 `write_file <path>: size X != expected Y`
    （下标越界/未分配区域的写被 FS 丢弃时就靠这条兜底）

## 4. 传输层约束（与固件相关）

下行 0xA5 帧在 C 层（ccm42xx `am_log.c`）有两道硬限制：

```
线上(转义后)帧长  ≤ sizeof(rx_cache2)   // 线上累积缓冲, 超限丢字节
解包后帧长        ≤ sizeof(rx_cache1)   // 24B帧头 + payload + 2B CRC, 超限整帧丢弃(有界反转义)
```

厂商新固件（2026-09-18 起）`rx_cache1[1064]` / `rx_cache2[2128]`，故：
- 解包后 ≤ 1064 → 下行 payload ≤ **1040B** → WRITE_DATA 数据区 chunk 取 **1024B**
  （应用头 10B: 5固定+fd1+offset4，payload = 10+1024 = 1034，反转义后 24+1034 = 1058 ≤ 1064 ✓）
- 转义最坏 1→2 字节：线上 ≤ 2×(24+1034+2)+2 = 2122 ≤ 2128 ✓（长度预检不会因此丢帧）

（历史：旧固件 `rx_cache1[512]` / `rx_cache2[1056]` 时，payload ≤ 486B、chunk 上限 476B。）

历史固件的帧长预检把"转义后帧长"错比到解包缓冲（128B），导致含 0xA5/0xA6 字节的帧被静默丢弃；
v2 固件已修正为线上比线上缓冲 + 有界反转义，chunk 取满协商值对任意数据内容成立。

除解包缓冲外，下行链路还有两道固件约束（v2 固件均已配套修改）：

1. **UART RX 中转缓冲**：日志口 UART 的 IRQ 回调原本用 `uint8_t temp[32]` 接收，
   `Uart_NoBlockRxPart/RxAll` 单次最多抽 32B，大于 ~130B 的突发帧被截断丢弃（v1 的"偶发丢帧"主因）。
   v2 固件：回调改静态 512B 缓冲 + 驱动 Len 参数从 uint8_t 加宽为 uint32_t。
2. **UART 硬件 FIFO 与 ISR 抽帧**：硬件 FIFO 只有 **16B**（`rx_level=3`），ISR 必须及时抽走。
   v2 固件原本一次中断只调一次 `Uart_NoBlockRxFrame(..., 512)`，而 chunk=476 的一帧线上 **~518B
   超过这 512B**，尾字节只能等下一次中断补回 —— 停等（W=1）时靠线空闲的 RTOS 中断能补上，
   连发时就被后续帧覆盖。**实测未修版把上位机的片长收缩关掉后，64K 写要重传 5~12 次。**

   2026-09-17 修为 **一次中断内循环抽干**：每轮先查 `dev_rx_buffer` 余量（`OS_BufferWriteLimit`
   装不下时是**整块丢弃**、一个字节都不写，比抽一部分更糟）再抽，单帧不再被拆到两次中断。
   零新增内存（临时缓冲仍 512B，流式缓冲允许一帧分次喂入）。修后同一测法重传为 **0**。

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

### 5.2 控制类（OPEN / CLOSE / LSDIR / MKDIR / RMDIR / REMOVE / STAT / EXISTS / AUTH / LSMOUNT / FSSTAT）

stop-and-wait，单请求在途：
- 超时 1000ms 重传，共 5 次，仍失败则向上层报错
- 设备端去重：缓存 `(last_ctrl_seq, last_ctrl_resp)`，同 seq 重发直接重发缓存回应、**不重复执行**
  （解决"回应帧丢失导致 host 重发"时 CLOSE 等被二次执行的问题）

### 5.3 数据类（WRITE_DATA / READ_DATA）

滑动窗口，**读写窗口默认都是 W=1**（host 可配）。实测在这套固件上 W=1 在读写两个方向都最快：

| 64K 读 | W=1 | W=2 | W=4 | W=8 |
|---|---|---|---|---|
| 吞吐 | **235KB/s** | 120KB/s | 110KB/s | 110KB/s |

| 64K 写到 /ram/ | W=1 | W=2 | W=4 | W=8 |
|---|---|---|---|---|
| chunk=466 | **199KB/s / 0 重传** | 105KB/s / 1 | 89KB/s / 3 | — |
| chunk=256 | **152KB/s / 0 重传** | 91KB/s / 1 | 103KB/s / 3 | 41KB/s / 12 |

- 写窗口开大的失败模式（实测 W=8）：连发 8 帧稳定丢 3~4 帧，窗口因前沿未确认而始终填满，
  重传也以整窗突发发出、同样被丢，形成"重传即突发、突发即丢帧"的活锁，
  直到单帧重试次数耗尽后报 `write offset=N timeout x10`。
  **此时设备本身仍然健康**（同一连接上 exists/stat/hello 均 0.00s 正常回应，无需复位）。
- 结论：本固件的瓶颈不是并发度，而是**单帧线上长度**（见 §4 与下方"内容自适应分片"）。
  所以提速手段是"每帧多带数据"，不是"同时发多帧"。

#### 内容自适应分片（wire_budget）

这套机制诞生时，设备端 ISR 用固定 **512B** 缓冲抽一帧（`Uart_NoBlockRxFrame`，见 §4），
且一次中断只抽一次 —— **当时**线上帧长超过它就会被拆到两次中断里，连发时丢帧。而 usercmd 的 chunk=476 时线上长是 518B：

```
线上长 = 2(A5边界) + 转义后( 24(SOC帧头) + 10(应用头 fd+offset) + chunk + 2(CRC) )
chunk=476 -> 2 + 512 + 转义膨胀 ≈ 518  ❌ 超过 512
```

修复前的实测拐点精确落在 512B（chunk=470 线上 512 仍不稳、466 线上 508 干净）：

| chunk | 线上长 | 64K 写重传 | 吞吐 |
|---|---|---|---|
| 476 | ~518 | **8~9 次** | 13KB/s |
| 466 | ~508 | **0** | **199KB/s** |
| 300 | — | 0（但全 0xA5 时 FAIL）| — |
| 219 | 最坏 512 | 0 | 138KB/s |

（以上为丢帧修复前的实测，用于说明该机制当年为何必须。）

**2026-09-17 起 512B 不再是硬约束**：`soc_rx` 改为一次中断内循环抽干（见 §4）后，单帧不再被拆到
两次中断。度量脚本（`host/test_rx_tx_robustness.py`）A 用例把 `wire_budget` 故意抬到 **4096**
（不收缩片长），实测 64K 写仍**零重传**（~328ms）。

但转义会把 0xA5/0xA6 各膨胀成 2 字节，固定片长要么保守（按"整帧最坏 2 倍"只能取 219，138KB/s）
要么对转义敏感内容偏大。因此 host 端仍按**实际内容的转义长度**逐片求解最大片长
（`wire_budget` 默认 508B，二分求解、以长度精确生成的帧为准，另留 4B 余量）：

- 随机/普通内容 → 片长取满 ~470B → **199KB/s**
- 内容全是 0xA5 → 片长自动收到 ~240B

默认 508B 现在的理由是**保守取向**，而不是"不这样就会丢帧"：帧更小、对 16B 硬件 FIFO 与
`dev_rx_buffer`(1056B) 的压力更小、余量更大。要调大（甚至 4096）可以，但没有必要。

这不需要设备端配合：WRITE_DATA 显式带 offset，READ_DATA 回应带 len，分片长度本来就是可变的。
设备端 HELLO 协商出的 chunk 仍是片长上界。

其余规则：
- host 连续发出至多 W 个请求（seq 递增），每个请求独立计时
- 设备收到即执行并立即回应（同 seq 回显）；**所有数据操作按 offset 幂等**（重复执行结果相同），
  因此设备端无需缓存窗口/去重状态
- host 每收到一个 seq 的回应即标记确认；未确认请求超时 **200ms** 重发，单帧最多 10 次
  （正常单帧往返仅 ~2.4ms(/ram/) ~65ms(/ flash)，500ms 的超时会把每次丢帧放大成 10~200 倍代价；
  实测 500ms→200ms 使 64K 写快 3 倍）
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

### 5.5 鉴权流程（可选，HMAC 挑战应答）

设备端脚本调用 `uc.set_auth(token)` 配置 token（8..64 字节，生产建议 ≥16 字节随机串）后启用：

```
host                                   设备
 |-- HELLO(nonce, chunk) ------------->| 记录挑战 nonce, authed=false
 |<-- nonce + chunk + version + caps --| caps.bit0 = 1
 |-- AUTH(maclen, mac) --------------->| mac == HMAC-SHA256(token, nonce)?
 |<-- errno + status ------------------|  匹配: authed=true, status=1
 |-- OPEN/LSDIR/... (任意业务指令) ---->| authed=true, 正常执行
```

- mac 校验失败 errno=2；设备无挑战（未先 HELLO）errno=4
- 未鉴权状态下，除 HELLO/AUTH 外**所有**子指令（含数据类 WRITE_DATA/READ_DATA）
  一律回应 errno=2，不执行业务，回应仍走控制类去重缓存
- 重放防护：nonce 每次 HELLO 随机，MAC 绑定本次握手；HELLO 重置 authed，重握后必须重新鉴权
- 未配置 token 的设备 caps=0，host `auth()` 直接跳过（返回"无需鉴权"）
- 已知限制：MAC 以 ASCII hex 字符串比对，非恒定时间实现；token 存储于设备脚本内。
  适用场景为日志口物理访问已受控、需要防误连/防误操作/防明文窃听的场合；
  更高要求应使用带外安全通道或禁用本功能

## 6. 时序参考值（ccm42xx @ 6M 波特）

| 参数 | 默认值 |
|---|---|
| 控制超时 | 1000ms × 5 次 |
| 数据片超时 | **200ms** × 10 次 |
| 读窗口 W | 1 |
| 写窗口 W | 1 |
| 读片长 | **4096B**（host 侧参数；新固件响应走 16KB response_fifo，见下） |
| 协商写片长 chunk | 1024B（设备上界，`rx_cache1[1064]`；实际片长由 `wire_budget` 按内容收缩） |
| wire_budget | 508B（保守默认：帧小、对 16B 硬件 FIFO 压力小、余量大；2026-09-17 修复后已非硬约束，实测抬到 4096 也零重传） |

**读片长的设备端上限（厂商新固件，2026-09-18 起）**：TX 侧为命令响应新增 **16KB 专用
response_fifo**，响应不再经过 1600B log record 通道，**静默截断消除**：

```
最坏(每字节都转义)线上长 = 1(A5) + 2*(24帧头 + 7应用头 + n) + 4(CRC) + 1(A5) <= 16384  ->  n <= 8159
read_chunk = 4096 时最坏线上长 8266B, 16KB fifo 余量充足
```

故 `read_chunk` 默认取 **4096**（保守安全值，理论单响应上限约 8100B）。

主机侧两道校验**保留为防御机制**（万一未来固件回归引入截断，仍是显式报错而非静默损坏）：

- `_read_window`：回应的 `len` 字段若大于实际数据长度（`len(body) - 7 < rlen`）→ 报"响应被截断"
- `read_file`：读完再与 `stat` 的文件大小交叉校验 → 不符即报错

> 历史（2026-09-17 同步主干后 ~ 新固件前）：app 构建的上行改走
> `__LOG_PORT_UNDEPENDABLE__` 的 log record 通道，**单条记录 `__LOG_ONE_RECORD_MAX_LEN__ = 1600`
> 字节**，超长响应会被 `_make_log_packet_to_log_record` 在 `pos >= 1595` 处 **break —— 静默截断，
> 没有任何信号**（实测 read_chunk>=1600 只回 ~1545B，4K 文件只回 1546 字节而 `stat` 报 4096）。
> 当时 `read_chunk` 取 **760** 为任意内容安全值（n ≤ 766 由 1600B 上限推出）；
> 截断比"丢弃"更危险：短读会被上位机当成正常**短读/EOF**，`read_file` 静默返回残缺内容，
> 上述两道主机侧校验正是那时加入的。

> 历史（同步主干前）：`soc_cmd_response` 的 cache 分支**没有 `else`**，余量不足时整条响应被
> **静默丢弃**（不发也不报错），推导上限 `read_chunk <= 32732`，实测 16384 正常、32768 稳定超时。
> 该分支现已只在 dependable 构建（bootloader/ramrun）生效，app 构建走上面的 log record 路径。

读片长实测（128K 文件，W=1，**同步主干前**的固件）：

| read_chunk | 512 | 1024 | 4096 | 16384 | 32768 |
|---|---|---|---|---|---|
| 吞吐 | 240KB/s | 306KB/s | **389KB/s** | 432KB/s | **静默丢弃→超时** |

同步主干后、新固件前（log record 路径）实测：`read_chunk=760` 时读 64K **267KB/s**、读 4K 209KB/s，
36 例真机用例全通过。新固件（response_fifo）后 `read_chunk=4096`。

实测（Air1601 @ 6M 波特，COM6，2026-09）：

| 场景 | 吞吐 | 说明 |
|---|---|---|
| 控制类 RTT | ~1.5ms | host 必须按 `in_waiting` 读串口；固定 `read(4096)` 会阻塞到 timeout(50ms)，RTT 退化为 ~62ms |
| 读 64K | **~235KB/s** | 上行密集，设备是发送方，不受 RX 缓冲限制；read_chunk=512 时 |
| 读 128K | **~389KB/s** | read_chunk=4096 |
| 读 64K（W=8 对照） | 110KB/s | 窗口越大越慢 |
| 写 64K 到 /ram/ | **~170KB/s** | 自适应分片 + W=1；（修复前）分片过大时（chunk=476，线上 518B）掉到 13KB/s |
| 写 4K 到 / | ~47KB/s | 修复前 2KB/s（1721ms）|
| 写 64K 到 / | ~46KB/s | 除丢帧外还有 flash page program ~50ms 停顿（64B 写 ~1ms，256B 起跳变到 ~52ms） |
| 写 4K 全 0xA5 到 /ram/ | ~86KB/s | 转义最坏内容，片长自动收缩后零丢帧 |
| 连发帧能力 | ~4 帧 | 每帧线上 ~518B；连着发超过 ~2KB 就会被 `OS_BufferWriteLimit` 整块丢弃 |

吞吐瓶颈不在协议开销，而在**单帧线上长度**（修复前的根因是 512B 抽帧缓冲把超长帧拆到两次中断，
2026-09-17 修复后该约束已解除，见 §4/§5.3）。修好 host 读串口 + 按内容收缩片长后，
单帧往返只有 1~2ms。

剩余空间：写方向要再提速，方向是**加大每帧载荷**（把 `rx_cache1` 等解包链路缓冲放大，
或降低转义膨胀），而不是开大窗口（实测开大只会更快丢帧）。
2026-09-17 修复前曾发现两个设备端问题：`soc_cmd_response` 的静默丢包（见上），
以及 `Uart_NoBlockRxFrame` 的 512B 缓冲装不下一帧 chunk=476（线上 518B）——**两者均已修复**。

## 7. 权限模型

设备端不内置任何文件操作逻辑：`log_usercmd.lua` 仅实现协议栈（解析/序号/回应/分片/鉴权门控），
具体 open/read/write/close/lsdir 等处理函数由脚本通过 `reg_op(name, fn)` 注册。
脚本可以选择只暴露部分操作，或加入路径白名单，从设备侧控制权限。

两层权限控制：

1. **连接级（AUTH）**：`uc.set_auth(token)` 开启后，未鉴权连接只能执行 HELLO/AUTH，
   其余指令一律 errno=2。见 §5.5。
2. **操作级（reg_op）**：协议栈不强制注册任何操作；`uc.fs()` 安装的标准文件系统操作集
   可由脚本裁剪（如只读挂载点开放 lsdir/stat，敏感路径在 handler 内拒绝并返回 errno=2），
   权限逻辑完全由 Lua 脚本掌控，与 C 固件无关。
