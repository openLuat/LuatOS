--[[
@module  voice
@summary 华康无菌车间 - 中文语音播报（exaudio 后端 + 静音降级）
@version 1.0
@date    2026.11.11
@board   Air8607 + 板载 DAC + HT6873 功放（AUDIOPA_EN = GPIO73，高有效）

=== 这块屏为什么要说话 ===
洁净区值守的人经常在更衣、在记录，眼睛不总在屏幕上。语音只补两件事：
  1、压差 / 粒子越限 —— 必须立刻让人抬头；
  2、值班员刚做的动作有没有生效 —— 切模式、隔离、复位。
两个入口语义不同：
  M.say(text, pri)   动作回执：pri >= 2 可以顶掉当前这句
  M.auto(text)       状态播报：忙就丢弃 + 冷却，不打断正在播的内容

=== 只做一个后端 ===
Air8607 的正式固件自带 exaudio（ex_tts）；没有它说明固件裁过 TTS，
直接进入静音模式，界面右下角会标"语音不可用"，不影响面板主流程。
PC 模拟器没有音频库，走同一个静音分支。

=== 一个必然踩到的坑 ===
结束回调会丢（被打断 / 合成失败）。每句都挂一个按字数估算的看门狗，
回调里带播报代次 gen，过期回调直接丢弃 —— 否则 busy 一旦焊死就永久静音。
]]

local T = require "theme"

local M = {}
local A = T.audio

local st = {
    ready = false, enabled = true, busy = false,
    pending = nil, gen = 0, last_auto = 0, diag = "",
}
M.st = st

local ex
local worker        -- 播报工作者（在文件后半段赋值，M.init 里拉起）
local enqueue       -- 入队（同样在文件后半段赋值）

-- 播报请求队列：触摸回调只往里塞，起播时的 sys.wait 全在 worker 里做
local q = {}
local QMAX = 3

local function has_fn(t, k)
    if t == nil then return false end
    local ok, f = pcall(function() return t[k] end)
    return ok and type(f) == "function"
end

local function get_lib(name)
    local g = rawget(_G, name)
    if g then return g end
    local ok, lib = pcall(require, name)
    if ok then return lib end
    return nil
end

local function pa_set(on)
    if not (gpio and gpio.setup and A.pa_ctrl) then return end
    pcall(gpio.setup, A.pa_ctrl, on and A.pa_on_level or (1 - A.pa_on_level))
end

-- 按汉字数估播报时长：1500ms 起步 + 每字 240ms，夹在 3s ~ 20s
local function say_ms(text)
    local ms = 1500 + (#text / 3) * 240
    if ms < 3000 then ms = 3000 elseif ms > 20000 then ms = 20000 end
    return math.floor(ms)
end

local function bump_gen()
    st.gen = st.gen + 1
    return st.gen
end

local function finish(my_gen, why)
    if my_gen and my_gen ~= st.gen then return end
    if not st.busy then return end
    st.busy = false
    if why then log.warn("voice", why) end
    local p = st.pending
    st.pending = nil
    if p and st.enabled and st.ready then
        enqueue(p, 1)
    end
end
M.done = function(my_gen) finish(my_gen) end

local function arm_watchdog(my_gen, ms)
    sys.taskInit(function()
        sys.wait(ms)
        if my_gen == st.gen then finish(my_gen, "播报超时没收到结束回调，强制收尾") end
    end)
end

-- 起播前重建通路：play_stop -> setup -> 音量 -> 唤醒。少这段第二句起可能不出声
local function ex_open()
    return pcall(function()
        local cfg = {
            model = A.model, pa_ctrl = A.pa_ctrl, pa_on_level = A.pa_on_level,
            dac_delay = A.dac_delay,
        }
        if ex.setup(cfg) == false then error("setup 返回失败") end
        if has_fn(ex, "vol") then ex.vol(A.vol) end
        if has_fn(ex, "pm") and ex.RESUME then ex.pm(ex.RESUME) end
    end)
end

function M.init()
    ex = get_lib("exaudio")
    st.diag = ex and "exaudio" or "silent"
    if not (ex and has_fn(ex, "setup") and has_fn(ex, "play_start")) then
        st.ready = false
        log.info("voice", "无 exaudio，语音按静音模式运行")
        return false
    end
    if not ex_open() then
        st.ready = false
        log.warn("voice", "exaudio 初始化失败，语音按静音模式运行")
        return false
    end
    st.ready = true
    sys.wait(60)   -- DAC / PA 上电约 60ms
    sys.taskInit(worker)
    log.info("voice", "语音后端就绪 exaudio")
    if A.boot and A.boot_text then
        sys.taskInit(function()
            sys.wait(200)
            M.say(A.boot_text, 1)
        end)
    end
    return true
end

--[[真正起播：只能在 task 上下文调用（里面有 sys.wait）]]
local function say_now(text, pri)
    if st.busy then
        if (pri or 1) >= 2 then
            -- 高优先级：停掉当前这句，代次作废，直接起新的
            pcall(function() if has_fn(ex, "play_stop") then ex.play_stop({ type = 1 }) end end)
            bump_gen()
            st.busy = false
        else
            st.pending = text
            return false
        end
    end

    pcall(function()
        if has_fn(ex, "play_stop") then ex.play_stop({ type = 1 }) end
        ex_open()
    end)
    sys.wait(40)

    local my = bump_gen()
    st.busy = true
    local ok, ret = pcall(ex.play_start, {
        type = 1,
        content = text,
        priority = pri or 1,
        cbfnc = function() M.done(my) end,
    })
    if not ok or ret == false then
        st.busy = false
        log.warn("voice", "起播失败", tostring(ret))
        return false
    end
    arm_watchdog(my, say_ms(text))
    return true
end

--[[入队。
高优先级（pri >= 2）清空排队直接插到最前；普通请求最多积 3 条，
再多就丢 —— 排队排到十几秒后念一句"门已开启"没有任何意义。]]
function enqueue(text, pri)
    pri = pri or 1
    if pri >= 2 then
        for i = #q, 2, -1 do q[i] = nil end
        q[1] = { text = text, pri = pri }
        return true
    end
    if #q >= QMAX then return false end
    q[#q + 1] = { text = text, pri = pri }
    return true
end

--[[播报工作者：唯一的起播点。
起播要 play_stop -> setup -> 等 40ms -> play_start，这一串只能在 task 里跑；
所以对外接口只入队，真正干活全在这里。]]
worker = function()
    while true do
        local req = table.remove(q, 1)
        if req then
            say_now(req.text, req.pri)
        else
            sys.wait(80)
        end
    end
end

--[[动作回执对外接口：只入队，不阻塞、不建 task。
触摸回调、LVGL 消息线程、普通 task 里都可以直接调。
@return boolean 是否受理（队列满或语音不可用时为 false）
]]
function M.say(text, pri)
    if not st.ready or not st.enabled then return false end
    if type(text) ~= "string" or text == "" then return false end
    return enqueue(text, pri)
end

--[[状态播报：忙就丢弃、20 秒内不重复，不打断正在播的内容]]
function M.auto(text)
    if not st.ready or not st.enabled then return false end
    local now = os.time()
    if now - st.last_auto < A.auto_gap then return false end
    st.last_auto = now
    if st.busy then return false end
    return M.say(text, 1)
end

function M.set_enabled(on)
    st.enabled = on and true or false
    if not st.enabled then
        pcall(function()
            if has_fn(ex, "play_stop") then ex.play_stop({ type = 1 }) end
        end)
        bump_gen()
        st.busy, st.pending = false, nil
        for i = #q, 1, -1 do q[i] = nil end
        pa_set(false)
    else
        pa_set(true)
    end
    return st.enabled
end

function M.toggle() return M.set_enabled(not st.enabled) end
function M.enabled() return st.enabled end
function M.ready() return st.ready end

return M
