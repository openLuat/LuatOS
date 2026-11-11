--[[
@module  voice
@summary 喇叭语音播报（Air8603 内置 DAC + HT6873 功放，exaudio 离线中文 TTS）
@note    参考 module/Air1601.../demo/audio/Air1601&Air1603/play_tts.lua
         PA 使能脚 Air8603 = GPIO73（AUDIOPA_EN），高电平使能
         播放结束必须主动关 PA，否则功放常开会持续输出嘶嘶底噪
         依赖说明：本文件 require "exaudio" 使用 LuatOS 仓库公共扩展库
                   script/libs/exaudio.lua（v3.13），本工程不自带 core/exaudio.lua；
                   烧录时须把该公共库一并加入脚本清单，否则开机报模块找不到。
]]

local exaudio = require "exaudio"
local CFG = require "config"
local M = {}

-- ▲【按需 O07】← 就是这一行：现场把 15 调到 70 左右（官方 W1 默认 play_vol = 70）
-- 注意 DAC 模式下走 audio_v2.soft_volume，100 = 原音量，只缩放 PCM、不改变功放底噪
local PLAY_VOL = 15

-- 播放收尾：只关 PA，保留 DAC 驱动与 CODEC。
-- 依据 audio/describe.md「仅关闭 PA」：audio_v2.shutdown(false, false, true)
-- 不用 exaudio.play_stop()：它会 audio_v2.stop + pm(SHUTDOWN) -> deactivate 驱动，
-- 在 PLAY_DONE 回调里重入、并与下一句起播抢状态，容易出现第二句无声。
-- 固件侧 config_pa_power_ctrl 会把 pa_power_state 清零，下一句起播时按 pa_delay 自动重开 PA。
local function pa_off()
    if audio_v2 and audio_v2.shutdown then
        pcall(audio_v2.shutdown, false, false, true)
    else
        pcall(exaudio.play_stop, { type = 1 })  -- 旧框架兜底
    end
end

local function on_play_end(event)
    if event == exaudio.PLAY_DONE then
        pa_off()
    end
    sys.publish("VOICE_DONE", event)
end

function M.setup()
    local ok = exaudio.setup({
        model       = "dac",
        pa_ctrl     = CFG.hw.pa_ctrl,
        pa_on_level = 1,
        dac_delay   = 6,
        pa_delay    = 10,       -- 官方 W1 配置值，PA 上电延时(ms)
    })
    log.info("voice", "exaudio.setup", ok)
    if ok then exaudio.vol(PLAY_VOL) end
    return ok
end

-- 在协程里播一句中文，等播完再返回，避免与下一句叠音
function M.say(text)
    if not text or text == "" then return end
    log.info("voice", "TTS", text)
    exaudio.play_start({
        type    = 1,                    -- 1 = TTS 文本转语音
        content = "[m55]" .. text,      -- m51 女声，可换 m51~m55
        cbfnc   = on_play_end,
    })
    sys.waitUntil("VOICE_DONE", 10000)  -- 10 秒兜底，防止回调丢失卡死
    pa_off()                            -- 兜底：回调丢失/超时也要关 PA，否则功放常开出底噪
    sys.wait(200)
end

-- ============ 金额中文读法（分 → 「十二元三角五分」） ============
local DIG = { "零", "一", "二", "三", "四", "五", "六", "七", "八", "九" }

local function cn_int(n)
    n = math.floor(n or 0)
    if n < 10 then return DIG[n + 1] end
    if n < 20 then
        return "十" .. (n % 10 > 0 and DIG[n % 10 + 1] or "")
    end
    if n < 100 then
        return DIG[math.floor(n / 10) + 1] .. "十" .. (n % 10 > 0 and DIG[n % 10 + 1] or "")
    end
    if n < 1000 then
        local h = math.floor(n / 100)
        local r = n % 100
        local tail = ""
        if r == 0 then tail = ""
        elseif r < 10 then tail = "零" .. DIG[r + 1]
        elseif r < 20 then tail = "一十" .. (r % 10 > 0 and DIG[r % 10 + 1] or "")
        else tail = cn_int(r) end
        return DIG[h + 1] .. "百" .. tail
    end
    return tostring(n)
end

function M.amount_text(fen)
    fen = math.floor(fen or 0)
    local yuan  = math.floor(fen / 100)
    local jiao  = math.floor((fen % 100) / 10)
    local fen1  = fen % 10
    local s = cn_int(yuan) .. "元"
    if jiao > 0 then s = s .. DIG[jiao + 1] .. "角" end
    if fen1 > 0 then s = s .. DIG[fen1 + 1] .. "分" end
    return s
end

return M
