--[[
@module  config
@summary 项目集中配置
@version 1.0
@date    2026.09.16
@description
SIP 服务器、账号、音频和按键参数集中在此，烧录前请按实际环境修改。
保留 config.sip、config.audio、config.keys 和 config.dial_number 接口。
]]

-- 填写实际 SIP 服务器和账号；不把其他测试工程的账号复制进来。
local config = {}

-- Air1602 无 IMEI：合宙账号用 hmeta.devid() 转十进制（devid 回退链 devid→unique_id→imei→mac）
local function devid_dec()
    local ok, devid = pcall(function() return hmeta.devid() end)
    if not (ok and type(devid) == "string" and devid ~= "") then
        devid = mcu.unique_id()                 -- 兜底：直接取芯片唯一ID
    end
    -- devid 可能是十六进制串(如 "C8C2C69555AD")或二进制串，统一转十进制整数
    if devid:match("^%x+$") then
        return tostring(tonumber(devid, 16))
    end
    local dec = 0
    for i = 1, #devid do dec = dec * 256 + devid:byte(i) end
    return tostring(dec)
end

-- ==================== SIP 配置 ====================

config.sip = {
    sip_server_addr = "cc.luatos.com", -- 合宙 SIP 服务器
    sip_server_port = 8910,
    sip_domain = "cc.luatos.com",      -- 留空时使用服务器地址
    -- sip_username = devid_dec() .. "0",  -- Air1602无IMEI，合宙账号=devid十进制+"0"(对应8784的 IMEI+"0")
    sip_username = "8643170886718160",  -- 临时模拟设备账号(后续改回上方 devid_dec().."0" 接真实MAC)
    sip_password = "123456",           -- 合宙默认密码
    sip_transport = "udp", -- udp / tcp；RTP 仍使用 UDP
    rtp_port = 40000,
    expires = 300,
    -- call_timeout = 60,
    auto_answer = false,
    codecs = {"PCMA", "PCMU"},
    ptime = 20,
    aec = false,
    aec_denoise = false,
    aec_agc = false,
    debug_sip_response = false,
}

-- ==================== 默认拨号目标 ====================
-- 空闲时按 SOS 键呼出的目标；合宙CC约定：本机账号=MAC十进制，被叫(配对端)取同号+"1"

    -- config.dial_number = devid_dec() .. "1"   -- 被叫(配对端)=同 devid 十进制+"1"
config.dial_number = "8643170886718161"   -- 临时模拟被叫(后续改回上方 devid_dec().."1" 接真实MAC)

-- ==================== 音频配置 ====================

config.audio = {
    uart_id = 6,        -- AIR8605: Air1103 接在 Air1602 的 UART6(TX6/RX6)，原 8784 的 1 不适用
    power_gpio = 73,    -- AIR8605: AUDIOPA_EN = Air1602 pin55 = GPIO73，高电平使能 VBAT_AIR1103 并兼做喇叭 PA 使能
    pa_ctrl    = 73,    -- 同上脚，消 pop 音警告（AIR8605 的 PA 使能就是这根 AUDIOPA_EN）
    volume = 31, -- 1103 喇叭 0..31
    mic_gain = 2, -- 软件数字增益 1..8，过大会削顶
    play_buffer_ms = 60, -- 下行目标水位，范围40..120ms；吸收Lua任务调度抖动
    boot_ms = 1500,
    ready_timeout_ms = 10000,
    mic_timeout_ms = 3000,
}

-- ==================== 按键配置 ====================

config.keys = {
    enabled = true,
    vref_gpio = 23,
    sos_gpio = 20,
    up_gpio = 21,
    debounce_ms = 150,
}

return config
