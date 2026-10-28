--[[
@module main
@summary Air8000 + ES8311 普通语音通话，以及网络 DTMF 按键收发
@version 1.0.0
@usage
下载 main.lua、audio_drv.lua、exaudio.lua、es8311.lua，并使用支持
cc.sendDtmf / cc.dtmfRx 的配套固件。硬件引脚在 audio_drv.lua 中配置。

启动：初始化 ES8311 → cc.init(0) → 等待 CC READY → 开启 DTMF 接收。
通话：自动接听来电或主动拨号 → 等待真实 AUDIO_START → 执行后续发键。
接收：手机按键 → CC_DTMF_RX → 打印按键；收到结束事件后再打印时长。
这里接收的是 VoLTE 网络按键事件，不需要从麦克风声音中识别按键。
]]
PROJECT = "air8000_cc_dtmf_duplex"
VERSION = "1.0.0"
sys = require("sys")

-- 可修改的业务配置：
-- dial_string = ""          ：不开机外呼，等待手机呼入并自动接听。
-- dial_string = "10086"     ：开机主动拨一次 10086，接通后不自动发送按键。
-- dial_string = "10086,2"   ：拨通 10086，真实音频开始后等待 pause_ms，再发送 2。
-- dial_string = "10086,,,2" ：连续三个逗号，等待 3 * pause_ms 后发送 2。
-- 也可填写自己的测试手机号码。主号码用于建立呼叫，不转换为 DTMF；
-- 只有逗号后的数字/符号才逐个调用 cc.sendDtmf。本示例不处理分号等待。
--
-- incoming_postdial 只控制来电接听后的发键，与 dial_string 的外呼序列独立。
-- 设为 ",2" 表示接通后暂停再发送 2；设为 "" 则只通话、接收手机按键。
-- 以下时间参数均以 ms 为单位：
-- pause_ms：每个逗号的暂停时间。
-- duration_ms：每个发送按键的请求时长，接口允许 100～1000。
-- gap_ms：按键间额外间隔；实际等待计算见 on_tx。
-- tx_timeout_ms：等待一笔发送请求获得 SDK 确认的最长时间。
-- call_limit_ms：从发起拨号/接听起的总时限，包含等待接通时间，到期自动挂断。
local dial_string = "10086"   -- 主动呼叫
local incoming_postdial = ",2" -- 响铃，来电，来电自动接通后等待 2 秒，给对端发送一次按键 2。
local pause_ms = 2000
local duration_ms = 300
local gap_ms = 300
local tx_timeout_ms = 15000
local call_limit_ms = 120000 

-- 尽早检查固件接口；只替换脚本不能为旧固件增加普通通话的 DTMF 接收能力。
assert(cc and type(cc.sendDtmf) == "function", "firmware missing cc.sendDtmf")
assert(type(cc.dtmfRx) == "function", "firmware missing normal-codec cc.dtmfRx")

-- 后续序列只允许逗号和 0～9、A～D、*、#；空串表示无需自动发键。
local function valid_postdial(value)
    return type(value) == "string" and not value:find("[^,0-9A-D*#]")
end

assert(valid_postdial(incoming_postdial), "invalid incoming_postdial")
local outgoing_number, outgoing_postdial
if dial_string ~= "" then
    -- 例如 "10086,2" 拆成 "10086" 和 ",2"；cc.dial 只收到前者。
    outgoing_number, outgoing_postdial = dial_string:match("^([+]?%d+)(.*)$")
    assert(outgoing_number and valid_postdial(outgoing_postdial), "invalid dial_string")
    assert(outgoing_postdial == "" or outgoing_postdial:sub(1, 1) == ",",
        "postdial must start with comma")
end

local audio_drv = require("audio_drv")
local exaudio = require("exaudio")
local wake = "CC_DTMF_DUPLEX_WAKE"
-- 订阅回调只入队，由同一个业务任务按顺序处理，集中修改通话状态。
local pending = {}
-- IDLE 空闲 → WAIT_AUDIO 等待真实音频 → POSTDIAL 处理后续序列
-- → WAIT_TX 等待发送确认 → POSTDIAL；序列结束进入 COMPLETE。
-- COMPLETE 只表示“自动发键结束”，仍可说话和接收按键；挂断才回到 IDLE。
local state, cc_ready, outgoing_attempted = "IDLE", false, false
-- active 从开始拨号/接听就置 true；audio_ready 要等到真实 AUDIO_START。
local active, audio_ready = false, false
-- position 指向下一字符；due_ms 是暂停截止时间；call_deadline 是整通电话的截止时间。
local postdial, position, due_ms, call_deadline = "", 1, nil, nil
-- 同时只提交一个发送请求，用 SDK 返回的 request_id 匹配异步确认。
local request_id, request_digit, request_deadline = nil, nil, nil

-- ticks2(1) 返回以 1000000 毫秒分割的高、低部分，重组后用于计算暂停和超时。
-- 1000000.0 使乘法使用浮点数，避免 32 位 Lua 整数溢出；计时不受网络对时影响。
local function now_ms()
    local high, low = mcu.ticks2(1)
    return high * 1000000.0 + low
end

local function report(...)
    log.info("cc_dtmf_duplex", ...)
end

local function transition(next_state)
    if state ~= next_state then
        state = next_state
        report("state", state)
    end
end

local function enqueue(source, value)
    pending[#pending + 1] = {source = source, value = value}
    sys.publish(wake)
end

-- hangup=true：脚本主动挂断，例如超时/发送失败。
-- hangup=false：已经收到网络断开或挂断完成事件，只清理本地状态。
local function release(reason, hangup)
    if not active then return end
    active, audio_ready = false, false
    -- 清掉待发送序列、暂停期限和请求 ID，防止上一通的操作延续到下一通。
    postdial, position, due_ms, call_deadline = "", 1, nil, nil
    request_id, request_digit, request_deadline = nil, nil, nil
    report("release", reason)
    if hangup then cc.hangUp(0) end
    exaudio.pm(exaudio.SHUTDOWN)
    transition("IDLE")
    -- 保留 cc_ready 与接收开关，下一通由固件重新创建接收会话。
    -- outgoing_attempted 也保留，因此主动外呼失败/结束后不会自动重拨。
end

-- 呼入和呼出共用准备步骤；每通电话从自己的后续序列第一个字符开始。
local function prepare_call(sequence)
    active, audio_ready = true, false
    postdial, position, due_ms = sequence, 1, nil
    request_id, request_digit, request_deadline = nil, nil, nil
    call_deadline = now_ms() + call_limit_ms
    exaudio.pm(exaudio.RESUME)
    transition("WAIT_AUDIO")
end

local function on_cc(status)
    -- 不打印 CC_IND 附带的真实号码。
    report("CC", status)
    if status == "READY" then
        -- cc.init 完成不等于 IMS 已就绪，等 READY 后再开启接收。
        -- 开关跨通话保留，重复 READY 不需要再次初始化。
        if cc_ready then return end
        local ok, reason = cc.dtmfRx(true)
        assert(ok, reason or "normal codec DTMF receiver init failed")
        report("RX_ENABLED")
        cc_ready = true
    elseif status == "INCOMINGCALL" then
        -- 本例一次只处理一通电话，不处理通话等待或第二通来电切换。
        if not cc_ready or active then return end
        prepare_call(incoming_postdial)
        report("ANSWER incoming")
        if not cc.accept(0) then release("answer rejected", true) end
    elseif status == "DISCONNECTED" or status == "HANGUP_CALL_DONE"
        or status == "MAKE_CALL_FAILED" then
        release("disconnected or dial failed", false)
    elseif status == "AUDIO_START" and active and not audio_ready then
        -- 普通 codec 的真实音频开始通知；READY/PLAY/SPEECH_START 不启动后续发键。
        -- audio_ready 避免重复音频通知导致同一通电话重复执行发键序列。
        audio_ready = true
        report("AUDIO_READY normal_codec ES8311")
        transition("POSTDIAL")
    end
end

-- CC_DTMF_TX 是“本模组发键请求”的 SDK 确认，不是收到手机按键。
local function on_tx(result)
    -- 已挂断或请求 ID 不匹配时忽略确认，避免旧请求推进当前序列。
    if not active or not request_id or result.id ~= request_id then return end
    local digit = request_digit
    request_id, request_digit, request_deadline = nil, nil, nil
    if result.ok ~= true then
        release("DTMF SDK rejected code " .. tostring(result.code), true)
        return
    end
    report("DTMF_SDK_ACCEPTED digit", digit, "code", result.code)
    -- SDK 受理不等于按键已发送完，也不证明对端 IVR 已切换菜单。
    -- 确认后再等待请求时长 + 额外间隔，才继续下一字符；不阻塞接收和挂断处理。
    due_ms = now_ms() + duration_ms + gap_ms
    transition("POSTDIAL")
end

-- CC_DTMF_RX 是“对端手机发来的按键”。此处只打印；可在 dtmf 分支接入自己的业务。
local function on_rx(event)
    if type(event) ~= "table" then return end
    if event.event == "dtmf" then
        -- 达到识别门限即通知哪个键，不必等用户松开，普通按键业务在这里处理一次即可。
        report("DTMF_RX digit", event.digit)
    elseif event.event == "dtmf_end" then
        -- 与前面的 dtmf 属于同一次按键，不要重复执行业务。
        -- duration_ticks 是按协商时钟计数的时长，clock_hz 是该时钟频率，
        -- duration_ms 是换算后的毫秒数；超出 Lua 整数范围的时长用十进制字符串交付。
        -- complete=false 表示只能确认部分时长；没收到有效结束包就不会产生这个事件。
        -- 这是网络事件时长，有些手机发送固定时长，不能直接等同于手指按住屏幕的时间。
        report("DTMF_RX_END digit", event.digit, "duration_ms", event.duration_ms,
            "duration_ticks", event.duration_ticks, "clock_hz", event.clock_hz,
            "complete", event.complete)
    end
end

-- 非阻塞地推进“逗号暂停 → 发一个键 → 等确认”流程，每次只推进当前步骤。
local function progress(now)
    if not active then return end
    if now >= call_deadline then release("call limit reached", true); return end
    if request_id then
        if now >= request_deadline then release("DTMF confirmation timeout", true) end
        return
    end
    -- 等待期间直接返回，把运行机会留给 CC 状态和对端按键事件。
    if not audio_ready or state == "COMPLETE" or (due_ms and now < due_ms) then return end
    due_ms = nil
    if position > #postdial then
        -- 空序列也走这里；只结束自动发键，保持通话和 DTMF 接收。
        transition("COMPLETE")
        report("POSTDIAL_COMPLETE; keep speaking and receiving remote keys")
        return
    end
    local token = postdial:sub(position, position)
    position = position + 1
    if token == "," then
        -- 多个逗号逐个执行，等待时间可以累加。
        due_ms = now + pause_ms
        report("PAUSE ms", pause_ms)
        return
    end
    -- SIM 索引 0；每次只能发送一个键，不能把整个序列或逗号传给此接口。
    -- true, id 只代表加入异步发送任务，最终结果由 CC_DTMF_TX 通知。
    local ok, id_or_error = cc.sendDtmf(0, token, duration_ms)
    if not ok then release("DTMF submit rejected " .. tostring(id_or_error), true); return end
    if type(id_or_error) ~= "number" or id_or_error <= 0 then
        release("invalid DTMF request id", true)
        return
    end
    request_id, request_digit, request_deadline = id_or_error, token, now + tx_timeout_ms
    transition("WAIT_TX")
    report("DTMF_SUBMITTED digit", token, "request", request_id, "duration_ms", duration_ms)
end

-- 三类事件分别入队：通话状态、主动发送结果、对端按键。先订阅，再初始化通话。
sys.subscribe("CC_IND", function(status) enqueue("cc", status) end)
sys.subscribe("CC_DTMF_TX", function(id, ok, code)
    enqueue("tx", {id = id, ok = ok, code = code})
end)
sys.subscribe("CC_DTMF_RX", function(event) enqueue("rx", event) end)

sys.taskInit(function()
    -- audio_drv 配置 ES8311 和功放；cc.init 使用普通音频模式，声音通过板载麦克风/扬声器。
    -- DTMF 接收要在上面的 READY 分支开启，不能在此时提前调用。
    assert(audio_drv.initAudioDevice(), "Air8000 development-board ES8311 init failed")
    assert(cc.init(audio_drv.getMultimediaId()), "normal codec CC init failed")
    report("START version", VERSION, "normal_codec ES8311 RX waiting CC READY",
        "outgoing_once", outgoing_number ~= nil, "pause_ms", pause_ms,
        "duration_ms", duration_ms, "call_limit_ms", call_limit_ms)
    while true do
        -- 先取走当前一批事件。处理过程中到达的新事件进入新队列，留到下一轮。
        local batch = pending
        pending = {}
        for _, item in ipairs(batch) do
            if item.source == "cc" then
                on_cc(item.value)
            elseif item.source == "tx" then
                on_tx(item.value)
            else
                on_rx(item.value)
            end
        end
        if cc_ready and outgoing_number and not outgoing_attempted and not active then
            -- 每次开机最多主动拨一次；配置为空则跳过，但仍允许手机重复呼入。
            outgoing_attempted = true
            prepare_call(outgoing_postdial)
            report("DIAL main_number_only postdial_chars", #outgoing_postdial)
            if not cc.dial(0, outgoing_number) then release("dial rejected", true) end
        end
        progress(now_ms())
        -- 有事件时及时唤醒；无事件时最多等待 20ms，再检查暂停和超时期限。
        sys.waitUntil(wake, 20)
    end
end)

-- 启动 LuatOS 调度器；后续业务通过上面的任务和订阅回调运行。
sys.run()
