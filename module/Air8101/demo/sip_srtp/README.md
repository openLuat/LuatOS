# sip_srtp — Air8101 SIP over TLS + SDES/DTLS-SRTP 验收脚本

对应方案：SDK 仓库 `luatos-sdk-bk72xx-smp/docs/voip-dtls-srtp-air8101-port.md`
的 **M1 / M2 / M3** 上机验收入口。

## 前提

1. 固件：Air8101 16M 机型 **106 / 107 / 108**，需带 `LUAT_USE_SRTP` + `LUAT_USE_DTLS_SRTP`
   （`python build_luatos_types.py Air8101 106` 直接编出的固件即可）。
   自检会先验证 `voip.securityIdentity/securityCreate/securityInfo/securityRelease`，缺失时直接报错退出。
2. 服务器：支持 **SIP over TLS（5061）** 且启用 **SDES 或 DTLS-SRTP** 的 PBX
   （Asterisk `res_pjsip` / FreeSWITCH `sofia` 均可）。
3. CA：PBX 证书链的 CA，PEM 文本，传到设备 `/luadb/ca.pem`（路径可在 `CA_FILE` 改）。
   **固件不内置 CA**——CA 由脚本侧提供。

## 配置

改 `main.lua` 顶部：

| 变量 | 说明 |
|---|---|
| `WIFI_SSID` / `WIFI_PASSWORD` | 留空表示工程里已有联网逻辑 |
| `SIP.*` | 服务器地址、**5061**、域、账号、密码 |
| `MEDIA_MODE` | `"dtls-srtp"`（M3）/ `"sdes"`（M2）/ `"none"`（M1，只验信令） |
| `CA_FILE` | CA PEM 路径 |
| `CALLEE` | 外呼号码；留空则只注册不外呼 |
| `AEC` | 是否开回声消除（双向通话建议 true） |

## 预期日志（按阶段）

### 能力自检（不上网）

```
[srtp] 本机安全模式: dtls-srtp
[srtp] 本机 DTLS 指纹(sha-256): 3A:7F:...          <-- 用于和对端 SDP a=fingerprint 对照
[srtp] 自检通过，媒体模式: dtls-srtp
[srtp] CA 已加载: 1728 字节
```

### M1：信令 TLS

```
[srtp] 注册事件: ok
[srtp] M1 通过：TLS 注册成功，耗时 1200 ms
```

失败即 **M1 未通过**，后续不用做。常见原因：端口不是 5061、CA 不对、服务器要求 TLS1.3
（BK 的 mbedtls 只开 TLS1.2）、域名为 IP 但证书 CN/SAN 不含该 IP。

### M2/M3：媒体加密

```
[srtp] 媒体事件: offer
[srtp] 媒体事件: ready
[srtp] 协商结果: encryption= dtls-srtp
[srtp] 通话事件: connected
```

判据：
- 双端 SDP：SDES → `RTP/SAVP` + `a=crypto:1 AES_CM_128_HMAC_SHA1_80 inline:...`；
  DTLS-SRTP → `UDP/TLS/RTP/SAVP` + `a=fingerprint:sha-256 ...`；
- 本机与对端指纹互相对得上（本机指纹见自检打印）；
- 双向音频清晰可懂。

## 负向用例（必须全部失败，且不得明文）

| 用例 | 操作 | 期望 |
|---|---|---|
| CA 不匹配 | 把 `/luadb/ca.pem` 换成另一张 CA | `register: failed`（证书校验失败），**不得**注册成功 |
| 关校验 | `sip_tls.verify = false` | 直接被 Lua 层拒绝：`tls_verification_required` |
| 指纹不匹配 | 对端 SDP 伪造 `a=fingerprint` | `call`/握手 failed，**不得**回落到明文 RTP |
| 对端不回包 | 防火墙丢弃 UDP 媒体端口 | 15s 内 `failed`（DTLS 超时），SIP 侧正常 BYE，不悬挂 |

## 排错

| 现象 | 排查 |
|---|---|
| `voip.securityIdentity 缺失` | 固件不对：必须 106/107/108（`CONFIG_LUAT_VOIP_SRTP=y`） |
| `encrypted_media_requires_tls` | `sip_transport` 不是 `"tls"`：共享层硬性要求加密媒体必须 TLS 信令 |
| `tls_ca_required` | 没给 `sip_tls.ca_cert` |
| 注册成功但媒体起不来 | 服务器没开 SRTP profile，或编解码不是 PCMU/PCMA |
| 上电即崩 | 检查 `audio_setup_param.pa_ctrl` 是否与实际底板一致 |
| `attempt to index a nil value (global 'SIP')` 后 `Lua VM exit` | 脚本被裁剪/合并过：本示例的配置表叫 **`sip_config`**，被叫变量叫 **`callee_number`**，不是 `SIP` / `CALLEE` |

## ⚠️ 不要和其他示例合并

本文件是**独立示例**，请整文件替换，不要和 `sip_tts/main.lua` 之类的脚本混在一起拷贝：

- 混编会导致配置表名、被叫变量名对不上，轻则参数错、重则 `Lua VM exit` 重启；
- 任务体开头已加**配置自检**（缺 `sip_config` / `MEDIA_MODE` / `CA_FILE` 时只打 `E/srtp 配置缺失: …` 并 `return`，不再崩 VM）。

改完脚本先跑一次宿主干跑，秒级就能发现变量名改漏：

```bash
cd LuatOS
bsp/pc/build/out/luatos-lua.exe bsp/pc/test/157.sip_srtp_demo_dryrun
```
