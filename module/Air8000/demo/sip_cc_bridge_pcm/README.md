# Air8000 CC ↔ SIP：bridge_pcm 专用 Demo

本目录用于没有外置 codec 的 Air8000，支持 SIP 呼入转手机、手机呼入转 SIP、双向语音、早期媒体/彩铃与挂断同步。
CC 固定调用 `cc.init(0, cc.AUDIO_MODE_BRIDGE_PCM)`，VoIP 固定使用 `voip.AUDIO_MODE_BRIDGE`。
SIP 仅支持 PCMA/PCMU、8 kHz、20 ms；蜂窝侧支持 8/16 kHz PCM。

本 demo 不初始化 codec、I2S、DAC、UART 音频或 Audio V2 音频请求，不提供本地听筒、麦克风、录音及通话中切换后端。
固件仍保留 Audio V2，供其他应用使用。`sip_cc/pcm_sip.lua` 处理本 demo 的 SIP 媒体控制；本目录不需要 `exsip.lua`、`exaudio.lua` 或 `audio_drv.lua`。

## 固件与烧录

1. 使用已包含 CC 纯 PCM 后端和配套 SDK PCM 接口的 Air8000 13 号固件。
   原 V2050、未集成该功能的普通固件不能仅通过更新脚本获得该能力；版本号本身不能作为判断依据。
   脚本会检查 `cc.AUDIO_MODE_BRIDGE_PCM`，CC 初始化失败时停止启动。
2. 在 Luatools 新建脚本项目，添加**`main.lua`、`netdrv/` 下的 3 个脚本和 `sip_cc/` 下的 6 个脚本，共 10 个 `.lua` 文件**。
   添加子目录中的脚本时保留文件名，`require` 名称无需增加目录前缀。唯一入口为 `main.lua`。请移除项目中旧 demo 和诊断脚本的选择。
3. 从本仓库的 [script/libs](../../../../script/libs) 目录直接添加以下公共库文件，保留原文件名：
   `exsipclient.lua`、`exsipproto.lua`、`exnetif.lua`、`dnsproxy.lua`、`dhcpsrv.lua`、`httpdns.lua`、`udpsrv.lua`。
   这些文件包含 Wi-Fi 驱动的间接依赖，可满足 Luatools 对脚本中 `require` 的合并检查；不需要复制到 demo 目录。
   `sys`、`sysplus` 使用固件内置库。
4. 启动后应看到 `SIP_CC_BRIDGE_PCM 1.0.0`、`CC 初始化完成 bridge_pcm` 和 `SIP 注册成功`。

## 配置

`sip_cc/config.lua` 和 `netdrv/netdrv_wifi.lua` 使用示例占位值。**烧录前必须填写实际参数**，占位值不能用于注册或拨号。

| 文件/参数 | 设置内容 |
| --- | --- |
| `sip_cc/config.lua` 的 `sip_server_addr`、`sip_server_port`、`sip_domain` | SIP 服务器地址、端口及域；示例为 `sip.example.com:5060` |
| `sip_username`、`sip_password`、`sip_transport` | 模组 SIP 账号、密码和传输协议 |
| `target_phone_number` | SIP 来电后拨打的手机号 |
| `remote_sip_uri` | 手机来电后拨打的 SIP 客户端 URI |
| `codec`、`ptime` | PCMU 或 PCMA，20 ms |
| `cc_audio_start_timeout_ms` | 蜂窝接通后等待 PCM 就绪的超时，默认 1500 ms |
| `netdrv/netdrv_device.lua`、`config.adapter` | 网卡驱动与 SIP/RTP 网卡必须一致 |

默认使用 4G：启用 `require "netdrv_4g"`，`adapter=socket.LWIP_GP`。
使用 Wi-Fi 时改为启用 `require "netdrv_wifi"`，设置 `adapter=socket.LWIP_STA`，并填写 `netdrv/netdrv_wifi.lua` 中的热点名称和密码。
两种驱动只启用一种。Wi-Fi 脚本通过 `require "exnetif"` 使用公共库；其 DNS/DHCP/UDP 依赖也统一来自 `script/libs`。

## 实机测试

- SIP 客户端呼叫模组账号，手机等待 30～60 秒再接听；检查 SIP 端彩铃/早期媒体、接通后的双向语音及两侧挂断。
- 手机呼叫模组 SIM，等待 SIP 客户端接听；检查双向语音及两侧挂断。
- 检查响铃时取消、拒接、断网和连续重拨，确认另一侧同步结束。
- 两个方向各完成至少 20 轮，并完成至少一通 60 分钟连续通话；分别记录 PCMA/PCMU 和蜂窝实际出现的 8/16 kHz 模式，未覆盖的模式单独注明。

模块自身不播放早期媒体；真实蜂窝媒体优先于合成彩铃。
`PLAY=0` 只结束当前媒体阶段，接通后等待新 `AUDIO_START`；重复事件不延长 1500 ms 超时。
正常通话不会按固定时长自动挂断。保留通话事件和错误日志，运行统计可按需调用 `cc.bridgePcmStats()` 查询。

验收时确认无死机、无持续单向无声、无上一通残留音频，挂断后队列及 SDK pending 归零、内存占用不持续增长。
如果出现异常，保留从上电到挂断后的完整日志，以及匹配固件的 ELF、MAP 和崩溃信息。

## 自动化验证

开发阶段已检查 10 个 demo 脚本及 7 个公共依赖的语法和依赖闭包，并验证 20 个真实控制脚本场景。
CC、VoIP、网络及 SIP 客户端使用测试桩；这些测试不替代实机通话、SIP 互通或 Luatools 合并烧录验证。

另有 8 组集成场景使用真实公共 `exsipclient`、`exsipproto` 和 demo 媒体/控制脚本，覆盖 UDP/TCP 呼入呼出、早期媒体、取消与重拨、迟到事件、注册失败、OPTIONS 404 重新注册及断网恢复。网络、CC、VoIP 和调度器仍使用测试桩。
