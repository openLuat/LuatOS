--[[
@module tools
@summary 工具模块
@version 2.0
@date    2026.04.13
@author  孟伟
@usage
工具模块，提供功耗模式切换、网络检查、文件操作、电源状态管理等功能
]]

local tools = {}

local config = require("config")

-- LED引脚定义
local LED_PINS = {
    red = 16,
    blue = 1
}

-- 设备状态管理
local device_state = {
    -- 硬件引脚
    vbus_pin = config.HARDWARE_PINS.VBUS_PIN,

    -- 电源状态
    vbus_state = 0,
    is_charge = 0,

    -- 业务状态
    device_mode = 0,
    position_active_report = 0,
    device_restart = ""
}

-- 初始化LED，设置为输出模式并关闭所有LED
function tools.init_led()
    log.info("[tools]", "初始化LED")

    for color, pin in pairs(LED_PINS) do
        gpio.setup(pin, 0)
        gpio.set(pin, 0)
    end
end

-- 打开红灯，关闭蓝灯
function tools.redLed_ON()
    gpio.set(LED_PINS.red, 1)
    gpio.set(LED_PINS.blue, 0)
    log.debug("[tools]", "红灯亮")
end

-- 打开蓝灯，关闭红灯
function tools.blueLed_ON()
    gpio.set(LED_PINS.red, 0)
    gpio.set(LED_PINS.blue, 1)
    log.debug("[tools]", "蓝灯亮")
end

-- 关闭所有LED
function tools.allLed_OFF()
    gpio.set(LED_PINS.red, 0)
    gpio.set(LED_PINS.blue, 0)
    log.debug("[tools]", "所有灯关闭")
end

-- ============================================
-- 电源状态管理
-- ============================================

-- 获取VBUS状态
function tools.get_vbus_state()
    return device_state.vbus_state
end

-- 获取充电状态
function tools.is_charging()
    return device_state.is_charge
end

-- 设置充电状态
function tools.set_charging(state)
    device_state.is_charge = state
end

-- 更新VBUS和充电状态（从硬件读取）
function tools.update_power_state()
    device_state.vbus_state = gpio.get(device_state.vbus_pin) or 0

    if device_state.vbus_state == 0 then
        device_state.is_charge = 0
    elseif device_state.vbus_state == 1 then
        device_state.is_charge = 1
    else
        device_state.is_charge = 0
    end

    return device_state.vbus_state, device_state.is_charge
end

-- ============================================
-- 业务状态管理
-- ============================================

-- 获取设备模式
function tools.get_device_mode()
    return device_state.device_mode
end

-- 设置设备模式
function tools.set_device_mode(mode)
    device_state.device_mode = mode
end

-- 获取定位激活上报标志
function tools.get_position_active_report()
    return device_state.position_active_report
end

-- 设置定位激活上报标志
function tools.set_position_active_report(value)
    device_state.position_active_report = value
end

-- ============================================
-- 调试接口
-- ============================================

-- 获取所有状态（用于调试）
function tools.get_all_state()
    return {
        vbus_pin = device_state.vbus_pin,
        vbus_state = device_state.vbus_state,
        is_charge = device_state.is_charge,
        device_mode = device_state.device_mode,
        position_active_report = device_state.position_active_report,
    }
end

-- 步数编码字符集（60个字符，对应数字1~60）
local STEP_CHARS = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz12345678"

-- 编码步数为 MQTT 上报格式：时+分+步数
-- 例如：13:34 80步 → "Mh80"
function tools.encode_step(step_count)
    local dt = os.date("*t")
    local hour_char = STEP_CHARS:sub(dt.hour, dt.hour)
    local min_char = STEP_CHARS:sub(dt.min + 1, dt.min + 1)
    return hour_char .. min_char .. tostring(step_count or 0)
end

-- 订阅充电状态变化事件（由 battery 模块发布），实时更新内部缓存
sys.subscribe("CHARGING_START", function()
    device_state.vbus_state = 1
    device_state.is_charge = 1
end)
sys.subscribe("CHARGING_STOP", function()
    device_state.vbus_state = 0
    device_state.is_charge = 0
end)

return tools
