# SIP / CC 桥接期间自动发送 DTMF 测试

基于同级 `sip_cc_bridge_pcm` 新建的独立示例，入口版本为 `1.0.0`。本轮只验证：**SIP 软电话与蜂窝通话通过 PCM 桥接时，模组仍能向 CC 对端发送网络 DTMF，并能在软电话中听到 10086 菜单切换。**

```text
软电话呼叫模组的 SIP 账号
  → 模组启动 SIP 早期媒体，通过 CC 固定拨打 10086
  → CC 真正接通且 PCM 就绪，SIP 应答并确认媒体就绪
  → 等待 2000 ms
  → cc.sendDtmf(0, "2", 300)，每通只尝试一次
  → 保持双向语音桥，使用软电话收听 10086 的业务菜单
  → 任一侧挂断，联动释放另一侧，下一通重新测试
```

原示例中的 MP3/TTS 播报、播报前静音逻辑已从本示例移除。本示例不接入 SIP INFO / RFC4733 按键接收，不转发软电话的实时拨号盘按键，也不启用 `cc.dtmfRx()`；这些不是验证主动发键所必需的功能。

## 硬件与固件

目录按要求放在 Air8783H 项目下；当前测试目标仍可使用此前的 **Air780EHV / EC718HM**。目录名称不决定固件型号，应选择实际硬件匹配的固件。

- SIM 卡需要语音、VoLTE 和数据业务，能够拨通 10086。
- 固件需同时包含 CC PCM 桥接、VoIP PCM 桥接和 `cc.sendDtmf()`。仅下载 Lua 不能补齐这些能力。
- 关键接口：`cc.AUDIO_MODE_BRIDGE_PCM`、`cc.bridgePcmStats()`、`cc.bridgeAudioStop()`、`cc.sendDtmf()`，以及 `voip.AUDIO_MODE_BRIDGE`、`voip.setAudioMode()`、`voip.pcmIn()`、`voip.pcmOut()`、`voip.start()`、`voip.getState()`。
- 当前 EC718HM 的 DTMF 功能范围是 13 / 113 / 22 / 122 号固件；编号满足不代表旧构建已包含所需接口。缺少 `cc.sendDtmf()` 时入口会明确报错，缺少桥接能力时初始化会停止并打印原因。
- 语音在模组内部桥接；不需要 ES8311、板载喇叭、麦克风或音频回环线。通过软电话的耳机/扬声器听音。

## 配置与下载

1. 编辑 `sip_cc/config.lua`，把 SIP 服务地址、端口、域、模组账号和密码改为原 PCM 示例已可用的配置。新示例使用占位值，没有复制原目录中的测试账号和私人目标号码。软电话使用另一个 SIP 账号。
2. 默认 `target_phone_number = "10086"`、`dtmf_delay_ms = 2000`、`dtmf_duration_ms = 300`，数字固定为 `2`。拨号目标只填主号码，不填 `10086,2`。
3. 默认使用 4G 网卡和 PCMA，`ptime = 20`。首轮软电话也启用 PCMA，减少与本次测试无关的编解码变量。
4. Luatools 新建独立脚本项目，加入本目录全部 **11 个 Lua 文件**，以及当前仓库 `script/libs/exsipclient.lua`、`script/libs/exsipproto.lua`。保持文件名，确保所有模块可以通过 `require "模块名"` 加载；不要同时加入原示例的同名 Lua 文件。
5. 默认 UDP / 4G 不需要 MP3、PCM 提示音、SD 卡或 CA 文件，也不需要 `audio_drv.lua`、`exsip.lua`。启用 TLS 时自行提供与服务器匹配的 CA 并设置 `sip_tls`；默认包未附带证书。

文件分工：

| 文件 | 用途 |
| --- | --- |
| `main.lua` | 启动标识、DTMF 接口检查、加载应用 |
| `sip_cc/config.lua` | SIP 配置、固定 10086、发键等待和持续时间 |
| `sip_cc/bridge.lua` | 两侧呼叫协调、每通一次发键、确认与清理 |
| `sip_cc/cc_main.lua` | CC 呼叫和 PCM 就绪状态，媒体停止通知 |
| `sip_cc/pcm_sip.lua` | SIP 信令与 VoIP PCM 适配、当前媒体就绪检查 |
| `sip_cc/sip_main.lua`、`sip_cc/sip_cc_app.lua` | 原示例的 SIP 生命周期与启动流程 |
| `sip_cc/air153c_wdt.lua` | 可选外置看门狗，默认关闭 |
| `netdrv/` 下 3 个 Lua | 默认 4G，保留原示例的可选 Wi-Fi 配置 |

仅在硬件/固件支持 Wi-Fi 时才切换 `netdrv_device.lua` 并同步修改 `config.adapter`；还需加入当前仓库的 `exnetif.lua`、`dnsproxy.lua`、`dhcpsrv.lua`、`httpdns.lua`、`udpsrv.lua`。启用外置 Air153C 看门狗时，确认引脚并另加 `exair153x_wdt.lua`。

**软电话拨号方式：** 本轮呼叫模组注册的 SIP 账号，模组固定外呼 10086。若要在软电话中直接输入 `10086`，需 SIP 服务器将该被叫号码路由到模组账号；本示例没有增加 SIP URI 目标号解析或服务器拨号规则。

## 自动发键行为

- 同时收到 `CC_CONNECTED`、`SIP_CONNECTED` 后开始等待；原状态机保证这两个事件分别包含接通和媒体就绪条件。彩铃、183、单独 `SPEECH_START` 均不会触发发键。
- 发键前再次核对当前 CC 会话、两侧媒体运行状态和 PCM 故障状态；等待期间发生 SIP/CC 媒体中断就取消本通自动发键。即使随后恢复、重复接通或媒体重建，也不再次发送。
- `cc.sendDtmf()` 通过 IMS 主动发送网络按键，不向桥接 PCM 混入本地合成音。正常音频桥持续工作。
- 通过请求编号匹配 `CC_DTMF_TX`。提交失败、SDK 拒绝或 5 秒内未收到确认均打印失败，保持语音通话，不自动重试、不自动挂断。
- `DTMF_SDK_ACCEPTED` 只表示 SDK 确认请求，不证明 10086 已切换菜单。已发向网络的按键不能撤回；挂断会取消本通尚未提交的操作，迟到确认不会被认作下一通结果。
- 默认不处理蜂窝呼入转 SIP，来电会被拒绝。原有连续无 PCM 检测保留，诊断配置默认不自动重启。

## 真机测试与验收

1. 确认启动日志为 `SIP_CC_BRIDGE_DTMF 1.0.0`，CC 初始化和 SIP 注册成功。
2. 软电话呼叫模组 SIP 账号，确认 CC 拨打目标为 10086；本轮不按软电话拨号盘、不播放 WAV。
3. 接通后确认出现以下日志，同一通只有一条 `DTMF_SUBMITTED`：

   ```text
   bridge_dtmf AUTO_DTMF_WAIT ... digit 2 delay_ms 2000 duration_ms 300
   bridge_dtmf DTMF_SUBMITTED ... digit 2 request ... duration_ms 300
   bridge_dtmf DTMF_SDK_ACCEPTED ... 仅 SDK 确认，请在软电话收听菜单是否切换
   ```

4. 在软电话听到 10086 原始提示及按 `2` 后的对应业务菜单，确认发送期间及之后仍持续有音频，没有被本地测试音覆盖或静音。如果当地菜单不接受过早按键，将 `dtmf_delay_ms` 改为 5000 或更长后重新呼叫；不要把没有菜单响应直接判为发送成功。
5. 正常挂断后再拨一通，确认旧通话清理完成、新通话仍只发一次。另测试在 2 秒等待期间挂断，确认出现取消且没有后续发键。
6. 可将目标临时改为自己的测试手机，使用软电话与手机双向说话，观察发键期间及之后音频是否保持；该对照用于检查语音桥，不替代 10086 菜单验收。

**通过标准：软电话实际听到 10086 按 `2` 对应的菜单变化，桥接音频持续正常，挂断后能重拨。仅有接通日志、音频帧增长或 SDK 成功确认不能单独判定通过。**
