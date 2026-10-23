--[[
@module  config
@summary 项目集中配置
@version 1.0
@date    2026.09.23
@author  蒋骞
@usage
本文件为项目集中配置模块，核心业务逻辑为：
1、配置 SIP 服务器地址、端口、域名、传输方式，以及模组自身的 SIP 账号和密码；
2、配置远程 SIP URI(手机呼入时呼叫该地址)和目标手机号(SIP 呼入时拨打该号码)；
3、配置 RTP 端口、编解码(PCMU)和打包时长 ptime；
4、配置 Air1103 的 UART 端口(固定 2M 波特率)和喇叭音量；
5、配置网络适配器(4G 默认 LWIP_GP)；
6、配置自动行为开关(自动处理 SIP 来电、手机来电自动转 SIP、手机来电不转 SIP 时自动接听)、
   呼出早期媒体超时和失败播报宽限秒数、本地音频默认开关；

8784 + Air1103 方案的音频通路：SIP 侧 RTP PCM 与 VoLTE/CC 侧 PCM 由固件内部桥接完成
(exsip.init 的 cc_sip_bridge = true)，Air1103 只负责拉起本地 audio_v2 音频框架，
以及可选的"本地也能听/说"，不参与 SIP<->CC 的桥接数据通路；

烧录前请按实际环境修改 SIP 账号、密码、远程 SIP URI 和目标手机号；
本文件对外提供 config 配置表，直接在其他功能模块中require "config"就可以加载运行；
]]

local config = {
    -- ==================== SIP 服务器 ====================
    sip_server_addr = "cc.luatos.com",
    sip_server_port = 8910,
    sip_domain = "cc.luatos.com",
    sip_transport = "udp",

    -- ==================== 4G 模组 SIP 账号 ====================
    sip_username = mobile.imei().."0",
    sip_password = "123456",

    -- ==================== 远程 SIP 客户端（控制端 / 被叫端） ====================
    -- 手机呼入时，模组呼叫该 SIP URI
    remote_sip_uri = "sip:"..mobile.imei().."1@cc.luatos.com",

    -- ==================== 默认桥接目标手机号（SIP 呼入时拨打的号码） ====================
    target_phone_number = "1xxxxxxxxxx",

    -- ==================== 音频参数 ====================
    rtp_port = 40000,
    codec = "PCMU",
    ptime = 20,

    -- ==================== Air1103（UART 外置语音芯片） ====================
    air1103_uart_id = 1,          -- 连接 Air1103 的 UART 端口(固定 2M 波特率)
    air1103_volume = 20,          -- Air1103 喇叭音量 0..31(本地音频开启时生效)

    -- ==================== 网络适配器 ====================
    -- 4G only 默认使用 LWIP_GP
    -- 若 netdrv_device 切换为 WiFi/以太网，请同步改为 socket.LWIP_STA / socket.LWIP_ETH
    adapter = socket.LWIP_GP,

    -- ==================== 自动行为 ====================
    auto_answer_sip = true,               -- SIP 来电时自动处理(183 早期媒体 -> 拨手机 -> 接通后接听)
    auto_handle_mobile_incoming = true,   -- 手机来电时自动拨打 SIP
    auto_answer_mobile_incoming = true,   -- 手机来电且不转 SIP 时自动接听 CC
    outgoing_early_timeout = 90,          -- SIP->CC 呼出早期媒体阶段最大等待秒数
    outgoing_failure_prompt_grace = 6,    -- SIP->CC 未接通失败时保留运营商失败播报秒数

    -- 默认本地音频开关：false 表示仅桥接，本地麦克风/喇叭静音；true 表示本地也能听到/说话
    local_audio_default = false,

    -- 日志标签
    log_tag = "sip_cc_demo",
}

return config
