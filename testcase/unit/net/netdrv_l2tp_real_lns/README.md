# netdrv_l2tp_real_lns — L2TP 客户端 × 真实 LNS 联调用例

针对客户提供的运营商 LNS（默认 `58.213.164.4`）做的端到端联调用例。
与 `netdrv_l2tp_basic`（PC 本地 mock LNS）互补：那套验证协议细节，
这套验证**真实运营商 LNS 的互通**。

## 覆盖点

| # | 验证点 | 说明 |
|---|---|---|
| 1 | 隧道 + 会话建立 | 该 LNS **允许无 IPsec 的纯 L2TP**（裸 SCCRQ 也会回 SCCRP） |
| 2 | PPP 认证 | LNS 在 LCP ConfReq 中唯一要求 `CHAP alg=0x05`(MD5)，认证通过 |
| 3 | IPCP | 下发隧道内 `/32` 地址，对端（LNS）为 `10.129.128.1` |
| 4 | 数据面 | 隧道内 TCP + HTTP 真实往返（LNS 80 端口回 `HTTP/1.1 301`） |

> 客户的 Windows 端配置是「L2TP/IPsec + 可选加密 + PAP/CHAP/MS-CHAPv2」，
> 但该 LNS 实测**不要求 IPsec**，也**不要求 MS-CHAPv2/MPPE**，因此当前实现直接可用。
> 代价：隧道内数据不加密（仅 CHAP-MD5 认证）。

## 凭据（不入库）

账号与口令都不进仓库，按优先级取：

1. 环境变量（PC 模拟器）
   ```powershell
   $env:L2TP_USER="..."     # 必填
   $env:L2TP_PASS="..."     # 必填
   # 可选: $env:L2TP_HOST (默认 58.213.164.4) / $env:L2TP_PEER
   ```
2. `/luadb/lns_secret.txt`（真机必用；PC 也可用）
   ```
   user=<账号>
   pass=<口令>
   host=58.213.164.4     # 可选, 默认值同上
   peer=10.129.128.1     # 可选, 隧道内 HTTP 验证目标, 默认用 IPCP 网关
   ```

两者都没有时套件会打印告警并跳过（不会误判为 FAIL）。

> 真机刷机时把 `lns_secret.txt` 单独放一个目录，用第二个 `--script` 传进去，
> 这样口令文件不必落在仓库树里。

## 跑法

```powershell
# PC 模拟器
cd bsp\pc
$env:L2TP_USER="..."; $env:L2TP_PASS="..."
.\build\out\luatos-lua.exe ..\..\testcase\common\scripts\ ..\..\testcase\unit\net\netdrv_l2tp_real_lns\scripts\
# 期望: ### OVERALL_PASS ### netdrv_l2tp_real_lns

# Air1601 真机 (COM23) — 真机需先编入 L2TP, 见 docs/l2tp-design.md §8
$CLI flash test --soc $SOC --port COM23 --baud 6000000 `
  --script <common scripts> --script <本目录 scripts> --script <放 lns_secret.txt 的目录> `
  --timeout 150 --keyword '### OVERALL_PASS ###' --fail-keyword '### OVERALL_FAIL ###'
```

> 用例脚本文件名要短：`luatos-cli` 合成 LuaDB 时**单文件名上限 27 字节**（含 `.luac`），
> 超了会在打包阶段直接报错（本套件因此把测试模块命名为 `l2tp_lns_test.lua`）。

## 诊断工具（排查互通问题用）

`tools/` 下两个脚本是本次互通排查的产物，改 LNS / 排查连不上时先跑它们：

| 脚本 | 用途 |
|---|---|
| `tools/lns_probe.py` | 发一个合法 SCCRQ，判断 LNS 是否**允许明文 L2TP**（不需要 IPsec），顺带探测 IKE 500/4500 |
| `tools/lns_relay.py` | L2TP 中继 + 协议跟踪：透传 UDP 的同时解码 L2TP 控制面与 PPP(LCP/PAP/CHAP/IPCP)，能看清 LNS 到底要求哪种认证、IPCP 给了什么地址 |

```powershell
# 1) 是否允许明文 L2TP (期望: REPLY ... SCCRP)
python tools/lns_probe.py --host 58.213.164.4 --what l2tp

# 2) 抓一次完整协商: 先起中继, 再把客户端指向 127.0.0.1:1701
python tools/lns_relay.py --listen 1701 --host 58.213.164.4 --port 1701
$env:L2TP_HOST="127.0.0.1"; $env:L2TP_USER="..."; $env:L2TP_PASS="..."
.\build\out\luatos-lua.exe ..\..\testcase\common\scripts\ ..\..\testcase\unit\net\netdrv_l2tp_real_lns\scripts\
```

> 踩过的坑：L2TP 的 AVP 头是 `M|H|rsvd|Length(10bit) | VendorID(2) | AttrType(2) | Value`，
> Length 在第一个 16bit 字的低 10 位、**不是**独立的 2 字节字段，且中间有 Vendor ID 字段。
> 早期探针漏了 Vendor ID 字段，发包畸形，LNS 静默丢弃 —— 看起来像"服务器不响应"。

## 已知边界

- 该 LNS 若改成只允许 MS-CHAPv2/EAP，当前实现会连不上（会进入 NAK→CONFREJ→重连循环）；
  改造清单见调研结论文档。
- 该 LNS 给的是 `/32` 地址 + 对端网关，隧道内可达范围取决于 LNS 侧策略；本用例只验证
  到 LNS 自身（网关）的往返。
- **不覆盖断线重连**：真实 LNS 快速重连可能被限速（实测首个 SCCRQ 偶发被丢，靠客户端
  内部重传才成功），做成用例会偶发 FAIL；重连机制由 `netdrv_l2tp_basic`（本地 mock LNS）
  确定性覆盖。

## 实测记录

| 目标 | 结果 |
|---|---|
| PC 模拟器（正确口令） | `### OVERALL_PASS ###`，3/3；隧道 ~0.2s 就绪，IP `10.133.128.x`，隧道内 HTTP 收到 `HTTP/1.1 301` |
| PC 模拟器（错误口令） | `### OVERALL_FAIL ###`，3 失败 —— 证明 LNS 真的在校验凭据，用例不是空跑 |
| Air1601 / COM23（真机） | `### OVERALL_PASS ###`，3/3；CH390 以太网 DHCP `192.168.1.6` → 隧道 ~3s 就绪 |
