--[[
@module  app_sound
@summary 报警语音播报（片上 TTS → exaudio type=1 → 内置 DAC → HT6873）
@version 1.0.0
@date    2026.11.16

=== 设计要点 ===

1. 只负责"出声"，不参与报警判定。订阅 app_alarm 的事件，要不要响由 app_alarm 决定。
   消音立刻停播；新报警到来时由 app_alarm 把 mute 清掉，本模块随之恢复播报。

2. 单任务串行：play_start / play_stop 只在 worker 协程里调用。
   事件回调只改标志位，不碰音频接口——否则"消音停止"和"新报警起播"两条异步
   路径会互相插队，把刚起来的播报停掉。

3. 必须走 exaudio，不能用旧框架 audio.tts()：DAC 模式下旧框架不出声。

4. 严禁 pm(SHUTDOWN)：DAC 下电后 setup + play_start 会失败，停止一律只用 play_stop。

5. exaudio 是 147KB 的 Lua 库，懒加载：只有真正要播时才 require，不进开机关键路径。
   固件缺少 TTS 或打包漏了库时 available() 为 false，全部静默，不影响其它功能。

6. 报警持续期间按 conf.alarm.speech_gap 重复播报（0 = 只播一次）。
]]
local M = {}

local conf  = require "conf"
local alarm = require "app_alarm"

local POLL_MS   = 50    -- 播报中途检查"是否该停"的间隔
local SETTLE_MS = 100   -- setup 后等 DAC/PA 稳定，太早起播会切掉开头

local ex        = nil
local ex_loaded = false
local ready     = false
local initing   = false
local want      = false

-- 编译系统按 require "exaudio" 的字面文本决定打包范围，故单独包一层
local function load_exaudio_mod()
    return require "exaudio"
end

local function load_exaudio()
    if ex_loaded then
        return ex
    end
    ex_loaded = true
    local ok, m = pcall(load_exaudio_mod)
    if ok and type(m) == "table" then
        ex = m
    else
        log.warn("app_sound", "exaudio 不可用（固件缺 audio_v2/TTS 或打包漏了 exaudio.lua）", tostring(m))
    end
    return ex
end

--[[
当前固件/工程是否具备播报能力
@return boolean
]]
function M.available()
    local e = load_exaudio()
    return e ~= nil
        and type(e.setup) == "function"
        and type(e.play_start) == "function"
        and type(e.play_stop) == "function"
end

-- 初始化音频通路（幂等）
local function ensure_ready()
    if ready then
        return true
    end
    if initing then
        -- 另一个协程正在初始化，等它完成
        local t = 0
        while initing and t < 3000 do
            sys.wait(50)
            t = t + 50
        end
        return ready
    end
    initing = true
    local e = load_exaudio()
    if not e then
        initing = false
        return false
    end

    local ac = conf.board.audio or {}
    local ok, ret = pcall(e.setup, {
        model       = ac.model or "dac",
        audio_mode  = ac.audio_mode or "new",
        pa_ctrl     = ac.pa_ctrl,          -- GPIO73 = AUDIOPA_EN
        pa_on_level = ac.pa_on_level or 1, -- HT6873 高电平使能
        pa_delay    = ac.pa_delay,
        dac_delay   = ac.dac_delay,
    })
    if not ok or ret == false then
        initing = false
        log.warn("app_sound", "exaudio.setup 失败，报警将没有声音", tostring(ret))
        return false
    end

    if type(e.get_audio_mode) == "function" then
        log.info("app_sound", "音频框架:", e.get_audio_mode())
    end
    if type(e.vol) == "function" then
        pcall(e.vol, ac.play_vol or 60)
    end

    sys.wait(SETTLE_MS)
    ready = true
    initing = false
    log.info("app_sound", "音频通路就绪")
    return true
end

local function stop_now()
    if ex and type(ex.play_stop) == "function" then
        pcall(ex.play_stop, { type = 1 })
    end
end

--[[
把报警记录转成一句可读的中文
@param rec table 报警记录
@return string
]]
local function text_of(rec)
    if not rec then
        return nil
    end

    if rec.ch == 0 then
        return rec.typ or "系统报警"
    end

    local name = conf.chs[rec.ch] and conf.chs[rec.ch].name or ("通道" .. rec.ch)
    local typ = rec.typ or "报警"

    if rec.typ == "断线" or not rec.value then
        return string.format("%s，%s，无信号", name, typ)
    end

    local val = tonumber(rec.value) or 0
    local n = math.floor(val + 0.5)
    -- 整数直接读"四十五摄氏度"，带小数会被念成"四十五点零摄氏度"
    if math.abs(val - n) < 0.05 then
        return string.format("%s，%s，当前%d摄氏度", typ, name, n)
    end
    return string.format("%s，%s，当前%.1f摄氏度", typ, name, val)
end

-- 播一条 TTS，阻塞到播完 / 超时 / 被要求停止
local function say_once(text)
    if not text then
        return false
    end
    local done = false
    local okc, started = pcall(ex.play_start, {
        type = 1,
        content = text,
        cbfnc = function(event)
            if event == ex.PLAY_DONE then
                done = true
            end
        end,
    })
    if not okc or not started then
        log.warn("app_sound", "play_start 失败", tostring(started))
        return false
    end
    log.info("app_sound", "播报:", text)

    local limit = conf.alarm.speech_timeout or 15000
    local t = 0
    local t0 = mcu.ticks()
    while not done and want and t < limit do
        sys.wait(POLL_MS)
        t = t + POLL_MS
    end
    local cost = mcu.ticks() - t0
    log.info("app_sound", ("播报结束 用时%dms %s"):format(cost, done and "正常" or (want and "超时" or "被中断")))

    if not want then
        stop_now()                    -- 播报中途被消音：立即掐掉
    elseif not done then
        log.warn("app_sound", "播报超时，强制停止")
        stop_now()
    end
    return done
end

-- 播报主循环：唯一碰音频接口的地方
local function worker()
    if not ensure_ready() then
        log.warn("app_sound", "音频初始化失败，报警不出声")
        return
    end

    -- 开机自检：先播一句验证通路，再进主循环
    if conf.alarm.speech_selftest then
        stop_now()
        sys.wait(50)
        want = true
        say_once("语音自检，当前温度正常")
        want = false
        stop_now()
        log.info("app_sound", "开机自检完成")
    end

    local gap = conf.alarm.speech_gap or 0

    while true do
        if not want then
            sys.wait(100)
        else
            local rec = alarm.records[1]
            if not rec then
                want = false
                sys.wait(100)
            else
                say_once(text_of(rec))

                if want and not alarm.should_sound() then
                    want = false
                end

                if want and gap > 0 then
                    local t = 0
                    while want and t < gap do
                        sys.wait(100)
                        t = t + 100
                    end
                elseif want then
                    want = false          -- gap=0：只播一次
                end
            end
        end
    end
end

--[[
启动报警语音。须在 alarm.init() 之后调用
]]
function M.start()
    if conf.alarm.speech == false then
        log.info("app_sound", "报警语音已关闭（conf.alarm.speech=false）")
        return
    end
    if not M.available() then
        log.warn("app_sound", "报警无声音：缺少 exaudio 或固件未开 TTS")
        return
    end

    alarm.on_update(function(evt)
        if evt == "record" then
            local rec = alarm.records[1]
            if rec and (rec.typ == "报警" or rec.typ == "预警" or rec.typ == "断线"
                        or rec.typ == "通信中断") then
                want = true
            end
        elseif evt == "mute" or evt == "reset" then
            want = false
        end
    end)

    sys.taskInit(worker)
    log.info("app_sound", "报警语音已启动")
end

--[[
出声自检：开机验证 DAC/PA 通路（不依赖报警条件）
]]
function M.test(text)
    local e = load_exaudio()
    if not e then
        log.warn("app_sound", "自检失败：exaudio 未加载")
        return false
    end
    sys.taskInit(function()
        if not ensure_ready() then
            log.warn("app_sound", "自检失败：音频通路未就绪")
            return
        end
        stop_now()
        sys.wait(50)
        want = true
        local ok = say_once(text or "语音自检，当前温度正常")
        want = false
        stop_now()
        log.info("app_sound", "自检结束", ok and "播放完成" or "未完成")
    end)
    return true
end

return M
