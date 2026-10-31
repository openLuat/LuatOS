-- SIP <-> CC 桥接及双向按键转发（SIP INFO / RFC2833/RFC4733）。
-- 填入与原 PCM demo 相同的 SIP 服务配置；软电话使用另一个 SIP 账号。
-- 下列范围均含端点；“省略时”表示代码回退值，“建议”不是额外的代码校验。
-- 修改配置后重新下载脚本并重启。
local config = {
    -- SIP 服务器地址：非空字符串，地址长度 1-253 字节；填写域名或 IPv4 地址。
    -- 不带 sip:、端口、路径或首尾空格；IPv6 未作为本 demo 的完整媒体链路验收。
    sip_server_addr = "YOUR_SIP_SERVER",

    -- SIP 服务器端口：整数 1-65535，与服务端监听端口一致。
    -- 省略时 UDP/TCP 使用 5060、TLS 使用 5061；切换传输方式不会覆盖已显式填写的端口。
    sip_server_port = 5060,

    -- SIP 域：服务器要求的域名/IP 字符串，用于 REGISTER、From/To 和短号 URI。
    -- 可以与连接地址不同；省略或设 nil 时回退 sip_server_addr，空字符串 "" 不会回退。
    sip_domain = "",

    -- SIP 账号：服务器分配的用户名字符串，不带 sip: 或 @域；长度按服务器账号规则。
    -- 账号可用设备标识拼接生成；填写的值须与服务器已配置的账号一致。
    sip_username = "YOUR_SIP_USERNAME",

    -- SIP 鉴权密码：字符串，与服务器账号密码一致；本 demo 没有单独的长度上限。
    -- 只有服务器允许空密码时才可填 ""；不能省略该字段。
    sip_password = "YOUR_SIP_PASSWORD",

    -- SIP 信令传输：可选 "udp" / "tcp" / "tls"，建议使用小写；省略时底层默认 "tcp"。
    -- TLS 需启用下面的 sip_tls，并下载匹配 CA；启动时自动校时，校时失败则停止启动。
    -- 此项只选择信令传输，不会自动把 RTP 改为 TCP，也不会自动启用媒体加密。
    sip_transport = "udp",

    -- TLS 配置：table，UDP/TCP 可不配置；TLS 必须提供 ca_cert 非空证书内容字符串。
    -- ca_cert 是 PEM 内容而不是路径；io.readFile 读取的 CA 文件需同步下载到 /luadb。
    -- 可选 verify 只能为 true 或省略，不允许 false；本客户端不透传任意客户端证书字段。
    -- sip_tls = {ca_cert = io.readFile("/luadb/sip-ca.pem")},

    -- 媒体加密：精确取值 "none" / "sdes" / "dtls-srtp"，省略时为 "none"。
    -- none：明文 RTP；sdes：SDES-SRTP；dtls-srtp：DTLS 协商 SRTP。
    -- 后两者要求 sip_transport="tls"，并要求固件和对端支持对应能力；TLS+none 只加密信令。
    media_encryption = "none",

    -- 手机呼入后拨打的 SIP/IVR 目标：非空字符串，可填 "sip:分机@域" 或服务器内短号。
    -- 短号会补上 sip_domain；不要填 sips: URI，TLS 由 sip_transport 控制。
    -- 仅 auto_handle_mobile_incoming=true 时使用；模组不在本地收集分机号再选择目标。
    remote_sip_uri = "",

    -- SIP 呼入后固定拨打的蜂窝号码：非空字符串，cc.dial 接口允许长度 1-255 字节。
    -- 填写运营商可拨通的电话号码；这里不从软电话的被叫号码动态提取目标，也不拼接后拨 DTMF。
    target_phone_number = "10086",

    -- 是否自动处理 SIP 呼入：布尔值 true / false。
    -- true：发送 183、媒体就绪后拨 CC，CC 接通且 PCM 就绪后应答 SIP；
    -- false：不自动启动该桥接流程，本 demo 没有配套的手动接听入口。
    auto_answer_sip = true,

    -- 是否处理手机呼入模组 SIM：布尔值 true / false。
    -- true：先拨 remote_sip_uri，SIP 接通后接听手机并转发按键；false：拒接手机来电。
    auto_handle_mobile_incoming = true,

    -- 模组向 SIP 发送 DTMF 的模式：仅允许小写 "auto" / "info" / "rfc4733"；省略时为 "auto"。
    -- auto：已协商 telephone-event 时用 RFC4733，否则用 SIP INFO；不是 RTP 失败后重试 INFO。
    -- info：固定发送 SIP INFO；rfc4733：固定发送 RTP telephone-event，未协商成功则拒绝发键。
    -- 该项不限制 SIP 收键方式；接收同时支持 INFO 与 RFC2833/RFC4733。
    -- 软电话应选一种发送方式，同一次按键不要同时发送 INFO 和 RTP，以免重复。
    dtmf_mode = "auto",

    -- 双向实时转发队列的键间隔：整数 50-2000，单位 ms，省略时为 100。
    -- 每个方向独立等待上一键确认及预期时长结束，再等待此间隔；0 不合法。
    dtmf_interval_ms = 100,

    -- 自动发键开关：布尔值 true / false，仅 true 开启；不影响实时双向按键转发。
    -- 仅 SIP 呼入→CC 外呼接通后自动尝试一次，不重试；手机呼入→SIP 不触发。
    -- 自动键由 bridge.lua 的 DTMF_DIGIT 指定，当前为 "2"，需要其他单键时修改该常量。
    auto_dtmf = true,

    -- 自动发键额外等待时间：整数 0-60000，单位 ms；省略时为 2000。
    -- 两侧接通且媒体就绪后计时；0 表示不额外等待，不表示关闭自动发键。
    -- 当前 6000 ms 已实测；按实际 IVR 开放输入的时机调整。auto_dtmf=false 时仍须填写合法值。
    dtmf_delay_ms = 6000,

    -- 自动键及实时转发默认键时长：整数 100-1000，单位 ms，省略时为 300。
    -- CC/RTP 收键按此默认值重发；SIP INFO 若携带有效时长则优先使用，并限制到 100-1000 ms。
    -- 即使关闭自动发键，此项仍须合法；自动键内容由 bridge.lua 的 DTMF_DIGIT 决定。
    dtmf_duration_ms = 300,

    -- 本地 RTP 端口基值：应为 1-65535 的可用整数端口，不能填 0；省略时为 40000。
    -- 建议选未占用的高位偶数端口，并预留附近端口；旧通话清理时可能按 2 递增/递减分配。
    -- 此链路未对该值单独校验范围，不要依赖超范围值自动修正。
    rtp_port = 40000,

    -- 语音编码：规范取值 "PCMA" / "PCMU" / "G729" / "G722"，必须与对端及固件能力匹配。
    -- G729、G722 需要固件编入对应 codec；当前沿用已验收的 PCMA。
    -- 如需多个编码，可另加 codecs={"PCMA", "PCMU"}；非空数组按优先顺序排列，并优先于 codec。
    codec = "PCMA",

    -- 每个语音 RTP 包的时长：本 PCM 桥接只允许数字 20，单位 ms；省略时也为 20。
    -- 不能填字符串 "20"，也不能使用底层 VoIP 其他模式支持的不同包时长。
    ptime = 20,

    -- 网络适配器枚举：本 demo 的 4G 用 socket.LWIP_GP，支持 Wi-Fi 的硬件可用 socket.LWIP_STA。
    -- 须与 netdrv/netdrv_device.lua 启用的网络驱动一致；不要直接填写猜测的网卡编号。
    -- 省略时使用系统默认网卡，不表示禁用联网。
    adapter = socket.LWIP_GP,

    -- CC 已报告接通后等待 PCM 就绪的超时：单位 ms；建议有限正整数，<=0 关闭此检测。
    -- 未配置/无法转为数字时为 0；demo 未限制上限，取值须在 sys 定时器支持范围内。
    -- 到期仍未就绪会请求挂断；不受 cc_media_reboot_on_error=false 影响。
    cc_audio_start_timeout_ms = 3000,

    -- 无 PCM 异常通话的最短接通媒体阶段时长：单位 ms，建议有限正整数，省略时为 2000。
    -- 代码向下取整；<=0 关闭连续无 PCM 监测；demo 未限制上限。
    -- 仅在通话结束时，阶段时长达到门槛且无真实下行 PCM 才计数，不是超时后立即重启。
    cc_media_min_connected_ms = 2000,

    -- 连续无 PCM 异常通话次数阈值：单位次，建议有限正整数，省略时为 3。
    -- 代码向下取整；<=0 关闭监测；demo 未限制上限。真实 PCM 到达或统计未知会清零。
    -- 达到次数后上报异常；是否清理并重启由 cc_media_reboot_on_error 决定。
    cc_media_missing_call_limit = 3,

    -- 连续无 PCM 异常后的重启开关：布尔值 true / false，只有明确 false 才禁止重启。
    -- true（或省略）：异常触发后清理并重启；false：保留诊断日志，不因此自动重启。
    -- 此项不关闭异常统计，也不关闭音频启动超时的挂断；当前诊断配置为 false。
    cc_media_reboot_on_error = false,
}

-- 外置 Air153C/Air153x 看门狗配置。未连接硬件时保持关闭，避免占用 GPIO。
config.WDT_CONFIG = {
    -- ENABLE：布尔值 true / false，仅 true 开启；还需接好硬件并下载 exair153x_wdt.lua。
    ENABLE = false,

    -- FEED_PIN：实际已接线的 LuatOS GPIO 编号（数字），不是模组物理脚号。
    -- 可用范围由硬件决定，无统一最大值；仅 ENABLE=true 时使用，需避免与其他功能冲突。
    FEED_PIN = 23,

    -- FEED_INTERVAL：目标喂狗起点间隔，单位秒；非负有限数字，可含小数，省略时为 180。
    -- 库未限制上限；应小于外置看门狗硬件超时时间，并为波形和调度保留余量。
    -- 0 仍自动喂狗，实际最短周期约 4.45 秒；关闭喂狗须用 ENABLE=false。
    FEED_INTERVAL = 180,
}
return config
