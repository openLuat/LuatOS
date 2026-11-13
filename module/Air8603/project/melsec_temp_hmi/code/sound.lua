--[[
@module  sound
@summary 报警语音播报（TTS → exaudio type=1 → 内置 DAC → HT6873 功放）

=== 设计要点（照抄 Air8603 已验证工程的结论）===

1. **必须走 exaudio，不能用旧框架 audio.tts()**
   合宙出厂工程 tts_app.lua 头部记着："旧框架在 DAC 模式下不出声（PA/DAC 通路未正确配置）"。
   所以 setup 显式 audio_mode = "new"（audio_v2）。日志里会打实际生效的框架。

2. **严禁 pm(SHUTDOWN)**
   DAC 下电之后 setup + play_start 会失败。停止一律只用 play_stop。

3. **懒加载**
   exaudio 是 140KB+ 的 Lua 库，不进开机关键路径；只有真要播时才 require。
   固件缺 audio_v2 或打包漏了库，available() 返回 false，全部静默降级 —— 有界面没声音，
   总比开不了机好。

4. **单任务串行**
   所有 play_start / play_stop 只在 worker 协程里调。事件回调只改 text/muted 两个标志，
   不碰音频接口 —— 否则"消音 stop"和"新报警 start"会互相插队，把新播报掐掉。

5. **报警持续期间重复播报**
   间隔由 config.alarm.speech_gap 控制（0 = 只播一次），直到消音 / 复位 / 温度回落。
]]

local cfg = require("config")

local M = {}

local POLL_MS   = 50      -- 播报途中检查"要不要停"的节奏，决定消音响应速度
local SETTLE_MS = 100     -- setup 后等 DAC/PA 上电稳定，太早起播会吃掉开头

local ex, ex_loaded = nil, false
local ready, failed = false, false
local muted = false
local armed = false       -- 是否有活动报警（= 该不该出声）
local gen   = 0           -- 代数：报警 / 消音 / 解除时 +1，用来打断正在播的那句
local provider = nil      -- 取文案的函数；每轮重新调用，所以能念"当前温度"
local extra = nil         -- 插播（"已回落"这类一次性提示），优先于报警循环
local started = false

--[[ 编译系统按 require "exaudio" 的字面文本决定打包范围，
     写成 pcall(require, "exaudio") 会被漏打包，所以单独包一层函数。]]
local function load_exaudio_mod()
    return require "exaudio"
end

local function load_ex()
    if ex_loaded then return ex end
    ex_loaded = true
    local ok, m = pcall(load_exaudio_mod)
    if ok and type(m) == "table" then
        ex = m
    else
        log.warn("sound", "exaudio 不可用（固件缺 audio_v2 或打包漏了 exaudio.lua）", tostring(m))
    end
    return ex
end

function M.available()
    local e = load_ex()
    return e ~= nil and type(e.setup) == "function"
        and type(e.play_start) == "function" and type(e.play_stop) == "function"
end

-- 初始化音频通路（幂等；exaudio.setup 的第一次入参决定全局，本工程只此一处）
local function ensure_ready()
    if ready then return true end
    if failed then return false end
    local e = load_ex()
    if not e then failed = true return false end

    local ac = cfg.audio or {}
    local ok, ret = pcall(e.setup, {
        model       = "dac",
        audio_mode  = "new",              -- 102 固件走 audio_v2，TTS 才出声
        pa_ctrl     = ac.pa_pin or 73,    -- GPIO73 = AUDIOPA_EN
        pa_on_level = 1,                  -- HT6873 高电平使能
        pa_delay    = ac.pa_delay or 10,  -- 起播后延迟拉高 PA，防 POP
        dac_delay   = ac.dac_delay or 6,
    })
    if not ok or ret == false then
        failed = true
        log.warn("sound", "exaudio.setup 失败，报警将没有声音", tostring(ret))
        return false
    end
    if type(e.vol) == "function" then pcall(e.vol, ac.vol or 20) end

    sys.wait(SETTLE_MS)
    ready = true
    log.info("sound", "音频就绪",
        type(e.get_audio_mode) == "function" and tostring(e.get_audio_mode()) or "",
        "音量", ac.vol or 20)
    return true
end

local function stop_now()
    if ex and type(ex.play_stop) == "function" then
        pcall(ex.play_stop, { type = 1 })
    end
end

--[[ 播一条 TTS，阻塞到播完 / 超时 / 被要求停止
     @return boolean 是否正常播完]]
local function say_once(t, mygen)
    local done = false
    local ok, accepted = pcall(ex.play_start, {
        type    = 1,
        content = t,
        cbfnc   = function(ev)
            if ev == ex.PLAY_DONE then done = true end
        end,
    })
    if not ok or not accepted then
        log.warn("sound", "play_start 失败", tostring(accepted))
        return false
    end

    local limit = (cfg.alarm and cfg.alarm.speech_timeout) or 15000
    local elapsed = 0
    while not done and elapsed < limit do
        -- 播到一半被消音、或者又来了新报警（gen 变了）：立刻掐掉
        if muted or gen ~= mygen then
            stop_now()
            return false
        end
        sys.wait(POLL_MS)
        elapsed = elapsed + POLL_MS
    end
    if not done then
        log.warn("sound", "播报超时", elapsed .. "ms，强制停止")
        stop_now()
    end
    return done
end

--[[ 播报主循环：唯一碰音频接口的地方]]
local function worker()
    if not ensure_ready() then return end
    while true do
        if muted then
            sys.wait(200)
        elseif extra then
            -- 插播：立刻念一句，念完回原流程。不改变 armed（报警可能还挂着）
            local t = extra
            extra = nil
            say_once(t, gen)
            sys.wait(200)
        elseif not armed then
            sys.wait(200)
        else
            --[[ 关键：文案每轮现取，不在触发时冻结。
                 温度已经从 30 掉到 29.6 时 provider 返回 nil —— 报警还挂着（回差没走完），
                 但语音不再重复"当前 30 度"，符合现场直觉。]]
            local mygen = gen
            local txt = provider and provider() or nil
            if txt then
                say_once(txt, mygen)
            else
                sys.wait(500)          -- 暂时没内容，过会儿再看
            end

            if gen == mygen then
                local gap = (cfg.alarm and cfg.alarm.speech_gap) or 10000
                if gap <= 0 then
                    armed = false      -- gap=0：只播一次，等下次报警再响
                else
                    local waited = 0
                    while waited < gap and gen == mygen and not muted do
                        sys.wait(200)
                        waited = waited + 200
                    end
                end
            end
        end
    end
end

-- 启动播报任务（须在报警模块就绪后调用；本模块不改报警状态）
function M.start()
    if started then return end
    started = true

    if cfg.alarm and cfg.alarm.speech == false then
        log.info("sound", "语音播报已关闭（config.alarm.speech=false）")
        return
    end
    if not M.available() then
        log.warn("sound", "报警无声音：缺少 exaudio / audio_v2 固件能力")
        return
    end
    sys.taskInit(worker)
    log.info("sound", "报警语音已启动")
end

--[[ 设置取文案的函数：provider() 返回一句要念的话，返回 nil 表示"这轮不用念"。
     由 main 提供，因为只有它同时拿得到实时温度、阈值和当前报警级别。
     TTS 念"68.4 摄氏度"会读成"六十八点四"，念整数更干净，所以四舍五入到整度 —— 
     这句拼装放在 main 的 provider 里。]]
function M.set_provider(fn)
    provider = fn
end

-- 新报警：开始播报（新报警自动解除消音，与 alarm_mgr 的语义一致）
function M.alert()
    armed = true
    muted = false
    gen = gen + 1          -- 打断正在播报的上一条（比如预警升级成报警）
end

--[[ 插播一句话（比如"预警已回落"）。
     会打断正在播的那句：gen +1，say_once 里发现代数变了就 stop。
     不改变 armed —— 报警条件可能仍然挂着，只是数值回来了。]]
function M.announce(t)
    if not t then return end
    extra = t
    gen = gen + 1
end

-- 报警全部解除 / 复位：停止播报
function M.clear()
    armed = false
    gen = gen + 1
    stop_now()
end

function M.set_muted(b)
    muted = b and true or false
    gen = gen + 1
    if muted then stop_now() end
end

function M.is_muted() return muted end

-- 出声自检：不依赖报警条件，开机验证 DAC/PA 通路
function M.test()
    if not M.available() then return false end
    sys.taskInit(function()
        if not ensure_ready() then return end
        stop_now()
        pcall(ex.play_start, { type = 1, content = "语音测试，通道一，二十六摄氏度" })
        sys.wait(3000)
        stop_now()
    end)
    return true
end

return M
