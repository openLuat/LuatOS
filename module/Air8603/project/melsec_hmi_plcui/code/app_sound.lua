--[[
@module  app_sound
@summary 报警语音提示（TTS 播报 → exaudio type=1 → 内置 DAC → HT6873）
@version 1.0.0
@date    2026.11.09

=== 设计要点 ===

1. 只负责"出声"，不参与报警判定：订阅 app_alarm.on_change 的
   new / recover / mute / ack 事件，要不要响仍由 app_alarm 决定。
   消音语义与界面一致：mute/ack 立即停播；新报警由 add_record 把
   muted 置回 false 后发 new，本模块随之恢复播报。

2. 单任务串行：所有 play_start / play_stop 都只在 worker 协程里调用。
   事件回调只改 want 标志，不碰音频接口——否则"消音 stop"和
   "新报警 start" 两条异步任务会互相插队，把新播报停掉。

3. 必须走 exaudio，不能用旧框架 audio.tts()：
   module/Air8603/factory/app/common/tts_app.lua 头部第 1 条已记录
   "旧框架在 DAC 模式下不出声（PA/DAC 通路未正确配置）"。
   故 setup 显式 audio_mode="new"（audio_v2），日志会打印实际框架。

4. 严禁 pm(SHUTDOWN)：DAC 下电后 setup + play_start 会失败，
   停止一律只用 play_stop（同上文件第 3 条）。

5. exaudio 是 140KB+ 的 Lua 库，懒加载：只有真正要播时才 require，
   不进开机关键路径；固件/打包缺库时 available() 为 false，全部静默。

6. 报警持续期间按 conf.alarm.speech_gap 重复播报（0 = 只播一次），
   直到消音 / 复位 / 报警条件恢复。
]]
local M = {}

local conf  = require "conf"
local alarm = require "app_alarm"

local POLL_MS   = 50    -- 播报中途检查"是否该停"的间隔，决定消音响应速度
local SETTLE_MS = 100   -- setup 后等 DAC/PA 上电稳定，太早起播会被切掉开头

local ex        = nil   -- exaudio 模块（nil = 固件或打包缺库）
local ex_loaded = false
local ready     = false -- setup 是否已完成
local want      = false -- 当前是否应该出声（由报警事件置位）

-- TTS 读字母单位的发音不准，常见单位转成汉字
-- 百分比不走"数值+单位"的拼接，单独在 text_of 里读成"百分之七十五"
local UNIT_TEXT = { V = "伏", A = "安", W = "瓦", C = "度", ["℃"] = "摄氏度" }

-- 编译系统按 require "exaudio" 的字面文本决定打包范围（audio_hw.lua:61 同款写法），
-- 写成 pcall(require, "exaudio") 会被漏打包，故单独包一层
local function load_exaudio_mod()
    return require "exaudio"
end

--[[
懒加载 exaudio（140KB+ Lua 库，不能进开机关键路径）
]]
local function load_exaudio()
    if ex_loaded then
        return ex
    end
    ex_loaded = true
    local ok, m = pcall(load_exaudio_mod)
    if ok and type(m) == "table" then
        ex = m
    else
        log.warn("app_sound", "exaudio 不可用（固件缺 audio_v2 或打包漏了 exaudio.lua）", tostring(m))
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

--[[
初始化音频通路（幂等）。exaudio.setup 第一次的入参决定全局，
本工程只此一处 setup，配置全部来自 conf.board.audio。
@return boolean
]]
local function ensure_ready()
    if ready then
        return true
    end
    local e = load_exaudio()
    if not e then
        return false
    end

    local ac = conf.board.audio or {}
    local ok, ret = pcall(e.setup, {
        model       = ac.model or "dac",
        audio_mode  = ac.audio_mode or "new",  -- 102 固件走 audio_v2，TTS 才出声
        pa_ctrl     = ac.pa_ctrl,              -- GPIO73 = AUDIOPA_EN
        pa_on_level = ac.pa_on_level or 1,     -- HT6873 高电平使能
        pa_delay    = ac.pa_delay,             -- 起播后延迟拉高 PA，防 POP
        dac_delay   = ac.dac_delay,
    })
    if not ok or ret == false then
        log.warn("app_sound", "exaudio.setup 失败，报警将没有声音", tostring(ret))
        return false
    end

    if type(e.get_audio_mode) == "function" then
        log.info("app_sound", "音频框架:", e.get_audio_mode())
    end
    if type(e.vol) == "function" then
        pcall(e.vol, ac.play_vol or 20)
    end

    sys.wait(SETTLE_MS)
    ready = true
    return true
end

local function stop_now()
    if ex and type(ex.play_stop) == "function" then
        pcall(ex.play_stop, { type = 1 })
    end
end

--[[
把报警记录转成一句可读的中文
@param rec table 报警记录（app_alarm.recs[1]）
@return string
]]
local function text_of(rec)
    local level = (rec.level == 2) and "报警" or "预警"
    local val = tonumber(rec.val) or 0

    -- 百分比要读成"百分之七十五"，不能拼成"75.0%"（TTS 会念成"75点零百分号"）
    if conf.scale.unit == "%" then
        return string.format("%s，%s，当前百分之%d", level, rec.name or "通道",
            math.floor(val + 0.5))
    end

    -- 摄氏度同理：整数直接读"七十五摄氏度"，带小数会被念成"七十五点零摄氏度"
    if conf.scale.unit == "℃" then
        local n = math.floor(val + 0.5)
        if math.abs(val - n) < 0.05 then
            return string.format("%s，%s，当前%d摄氏度", level, rec.name or "通道", n)
        end
        return string.format("%s，%s，当前%.1f摄氏度", level, rec.name or "通道", val)
    end

    local unit = UNIT_TEXT[conf.scale.unit] or ""
    return string.format("%s，%s，当前%.1f%s", level, rec.name or "通道", val, unit)
end

--[[
播一条 TTS，阻塞到播完 / 超时 / 被要求停止
@return boolean 是否正常播完
]]
local function say_once(text)
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

    local limit = conf.alarm.speech_timeout or 15000
    local t = 0
    while not done and want and t < limit do
        sys.wait(POLL_MS)
        t = t + POLL_MS
    end

    if not want then
        stop_now()                       -- 播报中途被消音：立即掐掉
    elseif not done then
        log.warn("app_sound", "播报超时，强制停止")
        stop_now()
    end
    return done
end

--[[
播报主循环：唯一碰音频接口的地方
]]
local function worker()
    if not ensure_ready() then
        log.warn("app_sound", "音频初始化失败，报警不出声")
    end

    local gap = conf.alarm.speech_gap or 0
    local playing = false

    while true do
        if not want then
            if playing then
                stop_now()
                playing = false
            end
            sys.wait(100)
        else
            -- 只播最新一条：同屏最多两条通道，合并播报反而不如逐条清楚
            local rec = alarm.recs[1]
            if not rec or alarm.max_level() == 0 then
                want = false
                sys.wait(100)
            else
                playing = true
                say_once(text_of(rec))
                playing = false

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
启动报警语音。须在 alarm.init() 之后调用（本模块不改报警状态）
@return nil
]]
function M.start()
    if conf.alarm.speech == false then
        log.info("app_sound", "报警语音已关闭（conf.alarm.speech=false）")
        return
    end
    if not M.available() then
        log.warn("app_sound", "报警无声音：缺少 exaudio / audio_v2")
        return
    end

    alarm.on_change(function(evt)
        if evt == "new" then
            want = true
        elseif evt == "mute" or evt == "ack" then
            want = false
        elseif evt == "recover" then
            if alarm.max_level() == 0 then
                want = false
            end
        end
    end)

    sys.taskInit(worker)
    log.info("app_sound", "报警语音已启动")
end

--[[
出声自检：开机验证 DAC/PA 通路是否正常（不依赖报警条件）
@return boolean 是否已受理
]]
function M.test()
    local e = load_exaudio()
    if not e then
        return false
    end
    sys.taskInit(function()
        if not ensure_ready() then
            return
        end
        stop_now()
        pcall(e.play_start, { type = 1, content = "报警测试，温度一，七十五摄氏度" })
        sys.wait(3000)
        stop_now()
    end)
    return true
end

return M
