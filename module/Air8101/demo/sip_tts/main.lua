--[[
@module sip_tts
@summary SIP 通话中向对端播报 TTS（Air8101 / BK7258）
@version 1.0
@date    2026.10.20
@usage

前提：
1. 固件需启用 LUAT_USE_VOIP_PLAY，Lua 侧存在 voip.playTTS；Air8101 请使用 106 及以上固件。
2. SIP 媒体必须是 G.711（PCMU/PCMA）8kHz/20ms，这是 voip.playTTS 的唯一放行条件。
3. 本机不需要出声，TTS 只走上行 RTP 给对端。

本示例直接调用 voip.playTTS，不依赖 exsip.say，只合并本文件即可验证。
接通后会自动播报一次 SAY_TEXT，并打印 started/done/stopped/error 事件。
]]

--[[
必须定义PROJECT和VERSION变量，Luatools工具会用到这两个变量，远程升级功能也会用到这两个变量
PROJECT：项目名，ascii string类型，可以随便定义，只要不使用,就行
VERSION：项目版本号，ascii string类型
        如果使用合宙iot.openluat.com进行远程升级，必须按照"XXX.YYY.ZZZ"三段格式定义
]]
PROJECT = "Air8101_SipTts_Demo"
VERSION = "001.999.000"

log.info("main", PROJECT, VERSION)

local exaudio = require "exaudio"
local exsip = require "exsip"

-- 设备 ID：WiFi 模组的 hmeta.devid() 返回的是 6 字节原始 MAC（二进制），不是十六进制文本，
-- 所以先按 wlan.getMac() 同款规则统一成 12 位十六进制字符串。
-- SIP 平台账号规则：MAC 转十进制数字，末尾补一个 "0"。
local function mac_to_hex()
    local raw
    if hmeta and type(hmeta.devid) == "function" then
        raw = hmeta.devid()
    end
    if type(raw) == "string" and #raw == 6 then
        -- 原始 6 字节，逐字节转十六进制
        return (raw:gsub(".", function(c)
            return string.format("%02X", string.byte(c))
        end))
    end
    if type(raw) == "string" and #raw > 0 then
        local hex = raw:gsub("[:%-%s]", "")
        if hex:match("^%x+$") then
            return (hex:upper())
        end
    end
    -- 兜底：wlan.getMac() 直接返回十六进制字符串
    if wlan and type(wlan.getMac) == "function" then
        local mac = wlan.getMac()
        if type(mac) == "string" and #mac == 12 and mac:match("^%x+$") then
            return (mac:upper())
        end
    end
    return nil
end

-- 十六进制字符串 -> 十进制数字字符串。
-- 注意：本固件 printf 未链接浮点支持（无 _printf_float），string.format("%.0f", ...)
-- 会输出成 "2e+14" 这种形式，因此这里用十进制逐位进位，全程整数运算。
local function hex_to_dec(hex)
    local digits = { 0 }                    -- 十进制各位，低位在 index 1
    for i = 1, #hex do
        local carry = tonumber(hex:sub(i, i), 16)
        if not carry then
            return nil
        end
        for j = 1, #digits do
            local v = digits[j] * 16 + carry
            digits[j] = v % 10
            carry = math.floor(v / 10)
        end
        while carry > 0 do
            digits[#digits + 1] = carry % 10
            carry = math.floor(carry / 10)
        end
    end
    local out = {}
    for i = #digits, 1, -1 do
        out[#out + 1] = string.char(48 + digits[i])
    end
    return table.concat(out)
end

local function device_sip_dec()
    local hex = mac_to_hex()
    if not hex then
        return nil
    end
    return hex_to_dec(hex)
end

-- 账号规则：STA MAC 十进制末尾补 "0"；默认被叫：同一前缀末尾补 "1"
local mac_dec = device_sip_dec()
local sip_username = mac_dec and (mac_dec .. "0") or nil
local callee_number = mac_dec and (mac_dec .. "1") or nil
log.info("sip_tts", "设备 SIP 账号:", sip_username or "nil", "默认被叫:", callee_number or "nil")

-- ======== 需要修改的部分 ========
local sip_config = {
    sip_server_addr = "cc.luatos.com",
    sip_server_port = 8910,
    sip_domain      = "cc.luatos.com",
    sip_username    = sip_username, -- 设备ID(STA MAC)转十进制后末尾补 0
    sip_password    = "123456",
}
-- 默认被叫为设备ID十进制末尾补 1，实际号码不同时直接改这里
local callee_override = nil
if type(callee_override) == "string" and #callee_override > 0 then
    callee_number = callee_override
end
local SAY_TEXT = "您好，本次通话将会录音，请注意"                -- 播报内容（UTF-8）

-- WiFi：若你的工程里已有联网逻辑，把这两项留空即可
local WIFI_SSID     = "admin-降功耗，找合宙！"
local WIFI_PASSWORD = "Air123456"
-- ================================

-- Air8101 使用内置 DAC 输出，PA 控制脚按实际底板调整
local audio_setup_param = {
    model = "dac",
    pa_ctrl = 27,
    pa_on_level = 1,
    dac_delay = 6,
}

local say_pending = false
local say_done = false
local play_id = nil

local function on_play_event(event, status)
    local samples = status and status.sip_samples or 0
    local reason = status and status.reason or ""
    log.info("sip_tts", "play 事件:", event, "sip_samples:", samples, "reason:", reason)
    if event == "done" or event == "stopped" or event == "error" then
        play_id = nil
        -- 播报结束后的收尾逻辑放这里
    end
end

-- 向对端播报：先等媒体稳定，未就绪时在窗口内重试。
-- 必须在 task 上下文调用（内部有 sys.wait）。
local function say_to_peer(text, opts)
    if not voip or type(voip.playTTS) ~= "function" then
        return nil, "unsupported"
    end
    opts = type(opts) == "table" and opts or {}
    local play_opts = {
        target = "sip",
        mode = opts.mode == "mix" and "mix" or "replace",
    }
    if type(opts.gain) == "number" then play_opts.gain = opts.gain end
    if type(opts.speech_gain) == "number" then play_opts.speech_gain = opts.speech_gain end

    local delay_ms = tonumber(opts.delay_ms) or 500
    local retry_ms = tonumber(opts.retry_ms) or 800
    if delay_ms > 0 then sys.wait(delay_ms) end

    local interval_ms = 100
    local attempts = math.floor(retry_ms / interval_ms) + 1
    if attempts < 1 then attempts = 1 end
    local id, err
    for attempt = 1, attempts do
        id, err = voip.playTTS(text, play_opts)
        if id then
            log.info("sip_tts", "播报已启动, id =", id, "attempt =", attempt)
            return id
        end
        if err ~= "unsupported" then break end
        if attempt < attempts then sys.wait(interval_ms) end
    end
    return nil, err or "failed"
end

-- 通话事件只置标志，真正的播报放到任务里做
local function on_sip_event(event_type, action, data)
    if event_type == "register" then
        log.info("sip_tts", "注册:", action)
    elseif event_type == "call" then
        log.info("sip_tts", "通话:", action)
        if action == "connected" then
            if not say_done then say_pending = true end
        elseif action == "ended" then
            say_pending = false
            say_done = false
            play_id = nil
        end
    elseif event_type == "media" then
        log.info("sip_tts", "媒体:", action)
    elseif event_type == "voip" then
        log.info("sip_tts", "voip:", action)
    elseif event_type == "error" then
        log.error("sip_tts", "错误:", action)
    end
end

sys.taskInit(function()
    -- 能力检查放在最前面，缺能力时给出明确提示而不是静默失败
    if not voip or type(voip.playTTS) ~= "function" then
        log.error("sip_tts", "本固件未启用 voip.playTTS，请烧录启用向对端播报功能的固件(106)")
        return
    end

    if not exaudio.setup(audio_setup_param) then
        log.error("sip_tts", "音频初始化失败，请检查 DAC/PA 配置")
        return
    end

    if type(voip.on) == "function" then
        voip.on("play", on_play_event)
    end
    if not sip_username or not callee_number then
        log.error("sip_tts", "无法获取设备 ID，请检查 hmeta.devid()")
        return
    end

    exsip.on(on_sip_event)
    exsip.init(sip_config)

    -- WiFi：留空则假定工程里已有联网逻辑
    if type(WIFI_SSID) == "string" and #WIFI_SSID > 0 then
        log.info("sip_tts", "连接 WiFi:", WIFI_SSID)
        wlan.init()
        wlan.connect(WIFI_SSID, WIFI_PASSWORD, 1)
    end

    exsip.start()

    -- 等注册成功再外呼，最多等 30s
    local waited = 0
    while not exsip.isRegistered() and waited < 30000 do
        sys.wait(1000)
        waited = waited + 1000
    end
    if not exsip.isRegistered() then
        log.warn("sip_tts", "30s 内未注册成功，仍尝试外呼")
    end
    sys.wait(1000)
    exsip.dial(callee_number)

    while true do
        if say_pending then
            say_pending = false
            local id, err = say_to_peer(SAY_TEXT)
            if id then
                play_id = id
                say_done = true
            else
                log.error("sip_tts", "播报失败:", err)
            end
        end
        sys.wait(100)
    end
end)

-- 用户代码已结束---------------------------------------------
-- 结尾总是这一句
sys.run()
-- sys.run()之后后面不要加任何语句!!!!!
