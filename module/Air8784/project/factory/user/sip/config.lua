--[[
@module  config
@summary Air8784 出厂固件集中配置（SIP 通话 + 按键 + 音频 + 管脚）
@version 1.0
@date    2026.09.27
@author  王世豪
@usage
本文件为项目集中配置模块，核心业务逻辑为：
1、配置 SIP 服务器地址/端口/域名/传输方式，以及模组自身的 SIP 账号（IMEI+0）与默认呼叫目标（IMEI+1）；
2、配置 Air1103 语音芯片的 UART 端口、供电脚与音量；
3、配置功能按键的 GPIO 与消抖时长；
4、配置状态灯 GPIO（主灯 24 / SMS 灯 26 / 网络灯 27）；

注意：
    GPIO24 主 LED | GPIO26 SMS_LED | GPIO27 NET_STATUS
    GPIO20 SOS 按键 | GPIO21 UP 按键 | GPIO22 语音芯片供电 | GPIO23 VREF 全局上拉
    UART1 语音芯片（固定 2M 波特率）

烧录前请按实际环境修改 SIP 密码；
本文件对外提供 config 配置表，直接在其他功能模块中 require "config" 即可加载运行；
]]

local imei = mobile.imei() or ""

local config = {}

-- ==================== SIP 配置 ====================
config.sip = {
    -- 官方 2026-09-24 提交 bd313708a 把 SIP 服务器从 IP 改成域名，原话"后续都用域名"；
    -- 端口不变仍是 8910。域名依赖 APN 的 DNS，若专网卡解析失败可临时改回 180.152.6.34
    sip_server_addr = "cc.luatos.com",      -- 必填：4G 网络可达的 SIP 服务器
    sip_server_port = 8910,
    sip_domain = "cc.luatos.com",           -- 留空时使用服务器地址
    sip_username = imei .. "0",             -- 规则：设备 = IMEI + "0"
    sip_password = "123456",                -- 必填：在本地填写，不打印到日志
    sip_transport = "udp",                  -- udp / tcp；RTP 仍使用 UDP
    rtp_port = 10000,
    expires = 300,
    auto_answer = false,                    -- 由业务层检查音频就绪后再接听
    codecs = { "PCMA", "PCMU" },
    ptime = 20,
    aec = false,
    aec_denoise = false,
    aec_agc = false,
    debug_sip_response = false,
}

-- ==================== 默认拨号目标 ====================
-- 默认模式：单击 SOS 键向软终端（IMEI+1）拨号，用户在 microSIP / linphone 上登录该账号接听
config.dial_number = imei .. "1"

-- ==================== 音频配置（Air1103） ====================
config.audio = {
    uart_id = 1,                -- 连接语音芯片的 UART 端口（固定 2M 波特率）
    power_gpio = 22,            -- 7014_EN，拉高给语音芯片供电
    power_on_level = 1,
    volume = 31,                -- 喇叭音量 0..31
    mic_gain = 2,               -- 软件数字增益 1..8，过大会削顶
    play_buffer_ms = 60,        -- 下行目标水位，范围 40..120ms
    boot_ms = 1500,             -- 供电后等待上电稳定
    ready_timeout_ms = 10000,   -- 等待首帧 MIC 数据超时
    mic_timeout_ms = 3000,      -- 通话中判定 MIC 中断的超时
}

-- ==================== 按键配置 ====================
-- 2026-09-28 决议：SOS 兼顾接听与呼叫（设备按 SIP 状态自行判断，用户无需区分），
--                 UP 短按播放留言、长按挂断 / 拒接。
-- 开发板实际有三个功能键（短按 / 长按 / SOS），当前只接了 SOS(GPIO20) 与 UP(GPIO21)；
config.keys = {
    enabled = true,
    vref_gpio = 23,             -- 上拉参考电压，开机常开
    sos_gpio = 20,              -- SOS：来电中接听，空闲时向 config.dial_number（IMEI+1）拨号；
                                -- 通话中默认忽略（见 sos_preempt_in_call）
    up_gpio = 21,               -- UP：短按播放语音留言，长按挂断 / 拒接
    debounce_ms = 150,          -- 消抖，滤掉机械抖动
    long_press_ms = 1000,       -- 长按判定阈值（按住达到即触发，不等松开）
                                -- 原 2000ms：挂断要按住 2 秒手感太差，改 1000ms。
                                -- UP 短按按快了只是没反应（不会误接/误挂），故可以取短值
    -- 长按动作：dial = 向 config.dial_number 呼出（与 SOS 同目标，多一条触发路径）
    --           hangup = 强制挂断（当前用法：长按 UP 挂机）
    long_press_action = "hangup",
    -- 通话中按 SOS 是否抢占（先挂断当前通话再呼出）：
    -- false（默认）= 忽略。单号码下抢占 = 挂掉再打给同一个人，只有副作用；
    -- true = 恢复抢占式求救，等做多号码轮拨（换下一个号码）时再打开。
    sos_preempt_in_call = false,
}

-- ==================== 语音留言（UP 短按播放） ====================
-- 硬约束：Air1103 只支持 exaudio.play_start({type=2}) PCM 流式播放
--         （exaudio.lua:1550 明确拒绝 type=0 文件 / type=1 TTS），
--         因此留言必须是 16kHz / 16bit / 单声道裸 PCM，20ms = 640 字节。
-- 出厂预置：把留言 PCM 放在工程根目录，烧录后路径为 /luadb/<文件名>。
config.message = {
    enabled = true,             -- false 时 app_main 不加载 msg_player
    file = "/luadb/msg.pcm",    -- 出厂预置留言（16kHz/16bit/单声道裸 PCM）
}

-- ==================== 状态灯 ====================
config.leds = {
    main_pin = 24,              -- 主 LED（高电平点亮）
    sms_pin = 26,               -- SMS 指示灯
    net_pin = 27,               -- 网络状态灯
}

-- ==================== AirCloud 上报 ====================
config.aircloud = {
    enabled = true,
    report_cycle = 180,        -- 上报周期(秒)，规划默认 180；web 端可下发 cycle:N 修改并持久化
    min_cycle = 30,            -- 最小周期，防止误设成 1 秒刷爆服务器
    -- 8784 个性字段：SIP 通话状态。
    -- 协议依据：上行业务载荷合法区间 256~2047，269 在区间内且未被 excloud 收录
    sip_state_field = 269,
}

-- ==================== 网络适配器 ====================
config.adapter = socket.LWIP_GP

-- 日志标签
config.log_tag = "air8784_factory"

return config
