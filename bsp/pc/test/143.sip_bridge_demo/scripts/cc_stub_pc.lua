--[[
@module cc_stub_pc
@summary PC模拟器用的CC库Stub，用于测试状态机
@version 1.0

模拟合宙4G模组的cc库行为，不实际拨打电话，
只触发对应的CC_IND事件来验证Lua脚本的状态机逻辑。
]]

local cc_stub = {}

-- 模拟状态
local g_inited = false
local g_state = "idle"  -- idle, dialing, ringing, connected
local g_last_number = ""
local g_next_dial_fail = false

-- 触发CC事件
local function emit_cc_event(event, value, extra)
    sys.publish("CC_IND", event, value, extra)
end

-- 模拟拨号流程
local function simulate_dial_flow(number)
    g_state = "dialing"
    g_last_number = number
    
    -- 模拟拨号请求已发送
    sys.timerStart(function()
        emit_cc_event("MAKE_CALL_OK", nil, nil)
    end, 200)

    sys.timerStart(function()
        if g_next_dial_fail then
            g_next_dial_fail = false
            g_state = "idle"
            emit_cc_event("MAKE_CALL_FAILED", nil, nil)
            emit_cc_event("DISCONNECTED", nil, nil)
            return
        end
        emit_cc_event("PLAY", 2, nil)
    end, 500)
    
    -- 模拟对方响铃后接听
    sys.timerStart(function()
        if g_state ~= "dialing" then
            return
        end
        g_state = "connected"
        emit_cc_event("AUDIO_START", nil, nil)
        emit_cc_event("CONNECTED", nil, nil)
    end, 1500)
end

-- 模拟来电流程
local function simulate_incoming_flow(number, delay_ms)
    delay_ms = delay_ms or 100
    
    sys.timerStart(function()
        g_state = "ringing"
        g_last_number = number
        emit_cc_event("INCOMINGCALL", nil, nil)
    end, delay_ms)
end

-- 模拟挂断
local function simulate_hangup()
    g_state = "idle"
    emit_cc_event("DISCONNECTED", nil, nil)
end

-- ==================== 公共API（与真机cc库一致） ====================

function cc_stub.init(id)
    if g_inited then
        return true
    end
    g_inited = true
    -- 触发READY事件
    sys.timerStart(function()
        emit_cc_event("READY", nil, nil)
    end, 100)
    return true
end

function cc_stub.dial(id, number)
    if not g_inited then
        log.error("cc_stub", "未初始化")
        return false
    end
    if g_state ~= "idle" then
        log.warn("cc_stub", "忙状态，无法拨号:", g_state)
        return false
    end
    log.info("cc_stub", "模拟拨号:", number)
    simulate_dial_flow(number)
    return true
end

function cc_stub.accept(id)
    if not g_inited then
        return false
    end
    if g_state ~= "ringing" then
        log.warn("cc_stub", "没有来电可接听:", g_state)
        return false
    end
    log.info("cc_stub", "模拟接听")
    g_state = "connected"
    emit_cc_event("AUDIO_START", nil, nil)
    emit_cc_event("CONNECTED", nil, nil)
    return true
end

function cc_stub.hangUp(id)
    if not g_inited then
        return false
    end
    log.info("cc_stub", "模拟挂断")
    simulate_hangup()
    return true
end

function cc_stub.lastNum()
    return g_last_number
end

function cc_stub.bridgeTone(on)
    log.info("cc_stub", "bridgeTone", on)
    return true
end

-- 测试用的额外接口
function cc_stub.simulate_incoming(number, delay_ms)
    simulate_incoming_flow(number or "13800138000", delay_ms)
end

function cc_stub.get_state()
    return g_state
end

function cc_stub.reset()
    g_inited = false
    g_state = "idle"
    g_last_number = ""
    g_next_dial_fail = false
end

function cc_stub.simulate_next_dial_fail()
    g_next_dial_fail = true
end

-- 注册为全局 cc（如果 _G.cc 不存在）
if not _G.cc then
    _G.cc = cc_stub
    log.info("cc_stub", "已注册为全局 cc")
end

return cc_stub
