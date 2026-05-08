--[[
@module  settings_buzz_app
@summary 蜂鸣器(触摸反馈)业务逻辑层
@version 1.0
@date    2026.04.24
@author  江访
@usage
本模块为蜂鸣器(触摸反馈)业务逻辑层，管理PWM蜂鸣器的开关、发声时长、音量，订阅触摸事件驱动反馈。
]]
-- naming: fn(2-5char), var(2-4char)

-- ==================== 配置常量 ====================
local CK = {
    ENABLED    = "buzzer_enabled",
    DURATION   = "buzzer_duration",
    VOLUME     = "buzzer_volume"
}

-- 默认值
local DE = true
local DD = 50
local DV = 50

-- PWM 参数
local PC = 4
local PF = 2700

-- ==================== 局部变量 ====================
local be  = DE
local bd  = DD
local bv  = DV

-- ==================== 工具函数 ====================

-- 音量值(10-100) 映射到占空比(20-50)
local function v2d(vol)
    vol = vol or bv
    if vol < 10 then vol = 10 end
    if vol > 100 then vol = 100 end
    return 20 + (vol - 10) * (50 - 20) / (100 - 10)
end

-- ==================== PWM 控制 ====================

local function bon(duty)
    pwm.open(PC, PF, math.floor(duty))
end

local function bof()
    pwm.open(PC, PF, 0)
end

-- ==================== 触摸反馈处理 ====================

local tti = nil

local function ot(state, x, y, track_id, timestamp)
    if not be then
        return
    end
    if state == airui.TP_DOWN then
        local duty = v2d(bv)
        bon(duty)
        if tti then
            sys.timerStop(tti)
        end
        tti = sys.timerStart(function()
            bof()
            tti = nil
        end, bd)
    end
end

-- ==================== 外部接口 ====================

local function gen()
    return be
end

local function sen(val)
    if be == val then return end
    be = val
    fskv.set(CK.ENABLED, val)
    sys.publish("BUZZER_ENABLED_CHANGED", val)
end

local function gdur()
    return bd
end

local function sdur(val)
    val = tonumber(val) or DD
    if val < 20 then val = 20 end
    if val > 500 then val = 500 end
    bd = val
    fskv.set(CK.DURATION, val)
    sys.publish("BUZZER_DURATION_CHANGED", val)
end

local function gvol()
    return bv
end

local function svol(val)
    val = tonumber(val) or DV
    if val < 10 then val = 10 end
    if val > 100 then val = 100 end
    bv = val
    fskv.set(CK.VOLUME, val)
    sys.publish("BUZZER_VOLUME_CHANGED", val)
end

-- ==================== 初始化 ====================

local function init()
    pwm.setup(PC, PF, 0)

    be  = fskv.get(CK.ENABLED)
    if be == nil then be = DE end

    bd = fskv.get(CK.DURATION)
    if bd == nil then bd = DD end

    bv = fskv.get(CK.VOLUME)
    if bv == nil then bv = DV end

    -- 延迟注册触摸回调，等待tp_drv初始化完成
    sys.taskInit(function()
        sys.wait(500)
        airui.touch_subscribe(ot)
        log.info("sbz", "触摸回调注册完成")
    end)

    log.info("sbz", "初始化完成",
        "enabled:", be,
        "duration:", bd,
        "volume:", bv)
end

sys.subscribe("SETTINGS_APP_INIT", init)

-- ==================== 事件订阅 ====================

sys.subscribe("BUZZER_GET_ENABLED", function()
    sys.publish("BUZZER_ENABLED_VALUE", be)
end)

sys.subscribe("BUZZER_SET_ENABLED", function(val)
    sen(val == true)
end)

sys.subscribe("BUZZER_GET_DURATION", function()
    sys.publish("BUZZER_DURATION_VALUE", bd)
end)

sys.subscribe("BUZZER_SET_DURATION", function(val)
    sdur(val)
end)

sys.subscribe("BUZZER_GET_VOLUME", function()
    sys.publish("BUZZER_VOLUME_VALUE", bv)
end)

sys.subscribe("BUZZER_SET_VOLUME", function(val)
    svol(val)
end)

-- 播放一次测试音
sys.subscribe("BUZZER_PLAY_TEST", function()
    if not be then return end
    local duty = v2d(bv)
    bon(duty)
    sys.timerStart(function()
        bof()
    end, bd)
end)

sys.subscribe("BUZZER_DURATION_DECREASE", function()
    sdur(bd - 10)
end)

sys.subscribe("BUZZER_DURATION_INCREASE", function()
    sdur(bd + 10)
end)

sys.subscribe("BUZZER_VOLUME_DECREASE", function()
    svol(bv - 10)
end)

sys.subscribe("BUZZER_VOLUME_INCREASE", function()
    svol(bv + 10)
end)
