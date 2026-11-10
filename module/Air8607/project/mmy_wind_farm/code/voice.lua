--[[
@module  voice
@summary 北岭风电场集控中枢 - 中文语音播报（TTS 三后端自动降级）
@version 1.0
@date    2026.11.09
@board   Air8607 + 板载 DAC + HT6873 功放（AUDIOPA_EN = GPIO73，高有效）

=== 这块屏为什么要说话 ===
中控室经常没人正对屏幕（在交接班、打电话、翻记录），语音只补两件事：
  1、值班员刚做的操作有没有生效 —— 挂牌、复位、模拟限电、确认告警；
  2、全场级事件 —— 阵风、限电指令、机组故障。
所以对外两个入口，语义不同：
  M.say(text, pri)   动作回执：pri >= 2 表示告警级，可以掐掉当前这句直接播
  M.auto(text)       状态变化播报：忙就丢弃、最小间隔冷却，不打断正在播的内容
静音键在界面右下角，关掉时顺手把功放拉低（夜班没人想听底噪）。

=== 后端探测（不同 Air8607 固件带的东西不一样）===
  1. ex_tts   exaudio + (audio_v2.tts / audio.tts) -> exaudio.play_start{type = 1, content = 文本}
  2. av2_tts  没有 exaudio，但固件有 audio_v2.tts  -> 自己配 DAC + PA，直接 audio_v2.tts()
  3. aud_tts  旧框架 audio.tts                     -> audio.config + setBus(DAC) + audio.tts()
  4. silent   都没有（PC 模拟器就是这种）：界面照常，标签显示"语音不可用"

=== 两个必然踩到的坑 ===
1、起播前必须重建通路：play_stop -> setup -> 音量 -> 唤醒(pm RESUME)。
   少这段，第二句起 play_start 可能返回 true 却不出声，也永远等不到结束回调。
2、结束回调会丢（被打断 / 被高优先级顶掉 / 合成失败）。每句都挂一个按字数估算
   的看门狗，回调里带播报代次 gen，过期回调直接丢弃 —— 否则 busy 一旦焊死就永久静音。
]]

local T = require "theme"

local M = {}
local A = T.audio

local st = {
    ready = false,
    mode = nil,         -- "ex_tts" / "av2_tts" / "aud_tts" / nil(静音)
    enabled = true,
    busy = false,
    pending = nil,
    req_gen = 0,
    last = "",
    diag = "",
    last_auto = 0,      -- 上次自动播报时刻（os.time 秒）
    auto_text = "",
}
M.st = st

-- ==================== 库探测 ====================
local function has_fn(t, k)
    if t == nil then return false end
    local ok, f = pcall(function() return t[k] end)
    return ok and type(f) == "function"
end

local function get_lib(name)
    local g = rawget(_G, name)
    if g then return g, nil end
    local ok, lib = pcall(require, name)
    if not ok then return nil, tostring(lib) end
    if lib == nil then return nil, "require 返回 nil" end
    return lib, nil
end

local ex, av2, aud
local ex_err, av2_err, aud_err
local AUDIO_ID = 0

local function pa_set(on)
    if not (gpio and gpio.setup) then return end
    pcall(gpio.setup, A.pa_ctrl, on and A.pa_on_level or (1 - A.pa_on_level))
end

-- ==================== 播报代次 / 收尾 / 看门狗 ====================
local gen = 0
local function bump_gen()
    gen = gen + 1
    return gen
end

local function finish(my_gen, why)
    if my_gen and my_gen ~= gen then return end
    if not st.busy then return end
    st.busy = false
    if why then log.warn("voice", why, st.last) end
    local p = st.pending
    st.pending = nil
    if p and st.enabled and st.ready then
        sys.taskInit(function()
            if not st.busy and st.enabled then M.say(p) end
        end)
    end
end

-- 按汉字数估播报时长：1500ms 起步 + 每字 240ms，夹在 3s ~ 20s
local function say_ms(text)
    local chars = #text / 3
    local ms = 1500 + chars * 240
    if ms < 3000 then ms = 3000 elseif ms > 20000 then ms = 20000 end
    return math.floor(ms)
end

local function arm_watchdog(my_gen, ms)
    sys.taskInit(function()
        sys.wait(ms)
        if my_gen == gen then finish(my_gen, "播报超时没收到结束回调，强制收尾") end
    end)
end

-- exaudio 通路配置：字段与 factory/app/common/tts_app.lua 的 tts_setup 对齐
local function ex_open()
    return (pcall(function()
        -- 每次传新表：exaudio 会把参数表存成内部状态，复用同一张表有被改写的风险
        local cfg = {
            model = A.model,
            pa_ctrl = A.pa_ctrl,
            pa_on_level = A.pa_on_level,
            dac_delay = A.dac_delay,
        }
        if ex.setup(cfg) == false then error("setup 返回失败") end
        if has_fn(ex, "vol") then ex.vol(A.vol) end
        if has_fn(ex, "pm") and ex.RESUME then ex.pm(ex.RESUME) end
    end))
end

local function tts_prep()
    local mode = st.mode
    if mode == "ex_tts" then
        if has_fn(ex, "play_stop") then pcall(ex.play_stop, { type = 1 }) end
        ex_open()
        sys.wait(60)                       -- DAC/PA 上电约 60ms
    elseif mode == "av2_tts" then
        if has_fn(av2, "stop") then pcall(av2.stop) end
        pa_set(true)
        if has_fn(av2, "shutdown") then pcall(av2.shutdown, false, false, false) end
    elseif mode == "aud_tts" then
        if has_fn(aud, "stop") then pcall(aud.stop, AUDIO_ID) end
        pa_set(true)
    end
end

-- ==================== 后端 1：exaudio ====================
local function ex_tts_start(text)
    pcall(tts_prep)
    local my = bump_gen()
    st.req_gen = my
    st.busy = true
    local ok, ret = pcall(ex.play_start, {
        type = 1,
        content = text,
        priority = A.priority,
        cbfnc = function() M.done(my) end,
    })
    if not ok or ret == false then
        st.busy = false
        return false, tostring(ret)
    end
    arm_watchdog(my, say_ms(text))
    return true
end

function M.done(my_gen)
    finish(my_gen)
end

-- ==================== 后端 2：直连 audio_v2 ====================
local function av2_setup()
    if not has_fn(av2, "tts") then return false end
    local ok = pcall(function()
        if has_fn(av2, "on") then
            -- 回调签名 (请求索引, 事件, 附加参数)：少写参数会拿 request_index 去比
            -- REQUEST_END，永远不成立 -> busy 清不掉 -> 只有第一句能播
            av2.on(function(_, event)
                if event == av2.REQUEST_END then M.done(st.req_gen) end
            end)
        end
        if has_fn(av2, "config_pa_power_ctrl") then
            av2.config_pa_power_ctrl(true, A.pa_ctrl, A.pa_on_level, 10)
        end
        if has_fn(av2, "soft_volume") then av2.soft_volume(A.vol) end
        if has_fn(av2, "shutdown") then av2.shutdown(false, false, false) end
    end)
    if ok then pa_set(true) end
    return ok
end

local function av2_tts_start(text)
    pcall(tts_prep)
    local my = bump_gen()
    st.req_gen = my
    st.busy = true
    local ok, ret = pcall(av2.tts, text, A.priority)
    if not ok or ret == false then
        st.busy = false
        return false, tostring(ret)
    end
    arm_watchdog(my, say_ms(text))
    return true
end

-- ==================== 后端 3：旧框架 audio ====================
local function aud_setup()
    if not has_fn(aud, "tts") then return false end
    local ok = pcall(function()
        if has_fn(aud, "config") then
            aud.config(AUDIO_ID, A.pa_ctrl, A.pa_on_level, 0, 10)
        end
        if has_fn(aud, "setBus") and aud.BUS_DAC then
            aud.setBus(AUDIO_ID, aud.BUS_DAC, { dacid = 0 })
        end
        if has_fn(aud, "on") then
            local d1, d2 = aud.PLAY_DONE, aud.SPEAK_DONE
            aud.on(function(_, event)
                if (d1 and event == d1) or (d2 and event == d2) then M.done(st.req_gen) end
            end)
        end
        if has_fn(aud, "vol") then aud.vol(AUDIO_ID, A.vol) end
    end)
    if ok then pa_set(true) end
    return ok
end

local function aud_tts_start(text)
    pcall(tts_prep)
    local my = bump_gen()
    st.req_gen = my
    st.busy = true
    local ok, ret = pcall(aud.tts, AUDIO_ID, text)
    if not ok or ret == false then
        st.busy = false
        return false, tostring(ret)
    end
    arm_watchdog(my, say_ms(text))
    return true
end

-- ==================== 对外接口 ====================
local function pick_backend()
    ex, ex_err = get_lib("exaudio")
    av2, av2_err = get_lib("audio_v2")
    aud, aud_err = get_lib("audio")

    st.diag = string.format("ex:%d a2:%d au:%d",
        ex and 1 or 0, av2 and 1 or 0, aud and 1 or 0)

    if ex and has_fn(ex, "setup") and has_fn(ex, "play_start") then
        if has_fn(av2, "tts") or has_fn(aud, "tts") then
            if ex_open() then return "ex_tts" end
            log.warn("voice", "exaudio 初始化失败，尝试直连 audio_v2")
        end
    end
    if av2_setup() then return "av2_tts" end
    if aud_setup() then return "aud_tts" end
    return nil
end

--[[初始化：探测后端、配置通路并播一句开机语（A.boot 控制）
@return boolean 是否具备出声能力
]]
function M.init()
    if st.ready then return true end

    st.mode = pick_backend()
    if not st.mode then
        st.ready = false
        log.warn("voice", "无可用音频后端，进静音模式（面板照常显示）",
            "诊断", st.diag,
            "exaudio:", tostring(ex_err),
            "audio_v2:", tostring(av2_err),
            "audio:", tostring(aud_err))
        return false
    end

    st.ready = true
    log.info("voice", "语音就绪 后端", st.mode, "音量", A.vol, "诊断", st.diag)

    if A.boot then
        sys.taskInit(function()
            sys.wait(300)
            M.say(A.boot_text or "北岭风电场集控已启动，语音播报就绪")
        end)
    end
    return true
end

--[[播报文本的读法修正：屏幕上 "MW" 会被逐字母念成"艾姆达不溜"，"m/s" 更糟。
所以换成口语句式，这里只兜单位与符号，顺序"先长后短"：
MWh 必须先替掉，否则会被 MW 规则吃掉前半截，变成"兆瓦h"这种半中半英的东西。
WT-05 这种机位号也要先处理，否则会被后面的 "-" 规则念成"WT负05"。]]
local UNIT_FIX = {
    { "MWh", "兆瓦时" },
    { "kWh", "千瓦时" },
    { "KWH", "千瓦时" },
    { "MW",  "兆瓦" },
    { "kW",  "千瓦" },
    { "KW",  "千瓦" },
    { "m/s", "米每秒" },
    { "rpm", "转每分钟" },
    { "C",   "摄氏度" },
    { "-",   "负" },
}

local function norm(text)
    text = text:gsub("WT%-0?(%d+)", "第%1号机")
    for i = 1, #UNIT_FIX do
        text = text:gsub(UNIT_FIX[i][1], UNIT_FIX[i][2])
    end
    return text
end
M.norm = norm

--[[用户动作反馈 / 告警播报
@param string text 播报文本
@param number pri 优先级：>= 2 表示告警级，会掐掉正在播的那句立即播；其余挂起（只留最后一句）
@return number 1 已起播 / 0 未播
]]
function M.say(text, pri)
    if not st.ready or not st.enabled then return 0 end
    if type(text) ~= "string" or text == "" then return 0 end
    text = norm(text)          -- 挂起的那句也要规整
    if st.busy then
        if not (type(pri) == "number" and pri >= 2) then
            st.pending = text
            return 0
        end
        -- 告警压过回执：先硬停当前这句（stop 会 bump 代次，旧回调不再改状态）
        M.stop()
    end

    st.last = text
    local ok
    if st.mode == "ex_tts" then
        ok = ex_tts_start(text)
    elseif st.mode == "av2_tts" then
        ok = av2_tts_start(text)
    else
        ok = aud_tts_start(text)
    end
    if not ok then
        log.warn("voice", "起播失败", st.mode, text)
        return 0
    end
    log.info("voice", "播报", text)
    return 1
end

--[[状态变化播报：不打断当前句子，且受最小间隔限制（A.auto_gap 秒）
同一句话在 30 秒内重复触发会被忽略，多路同时超温时不会连珠炮。
@param string text 播报文本
@return number 1 已起播 / 0 跳过
]]
function M.auto(text)
    if not st.ready or not st.enabled or st.busy then return 0 end
    local now = os.time()
    if st.auto_text == text and now - st.last_auto < 30 then return 0 end
    if now - st.last_auto < (A.auto_gap or 8) then return 0 end
    st.last_auto = now
    st.auto_text = text
    return M.say(text)
end

function M.stop()
    st.pending = nil
    st.busy = false
    bump_gen()          -- 上一条的回调别再动状态
    local mode = st.mode
    if mode == "ex_tts" and has_fn(ex, "play_stop") then
        pcall(ex.play_stop, { type = 1 })
    elseif mode == "av2_tts" and has_fn(av2, "stop") then
        pcall(av2.stop)
    elseif mode == "aud_tts" and has_fn(aud, "stop") then
        pcall(aud.stop, AUDIO_ID)
    end
end

--[[开关语音
@param boolean on 是否开启
@return boolean 当前状态
]]
function M.set_enabled(on)
    st.enabled = on and true or false
    if not st.enabled then
        M.stop()
        pa_set(false)                  -- 关了就把功放拉低，夜里没有底噪
    elseif st.ready then
        if st.mode == "ex_tts" then
            ex_open()                  -- stop 后通路已下电，光 pm(RESUME) 恢复不了
        elseif st.mode == "av2_tts" and has_fn(av2, "shutdown") then
            pcall(av2.shutdown, false, false, false)
        end
        pa_set(true)
    end
    log.info("voice", st.enabled and "语音开" or "语音关")
    return st.enabled
end

function M.toggle()
    return M.set_enabled(not st.enabled)
end

function M.enabled()
    return st.enabled
end

function M.ready()
    return st.ready
end

return M
