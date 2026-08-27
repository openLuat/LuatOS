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

-- LED引脚定义（8202G：GPIO26 绿灯、GPIO27 黄灯）
-- 绿灯：充电完成常亮 / GPS定位模式慢闪(1Hz,10s后自动灭)
-- 黄灯：插入充电器常亮（充满或拔电灭）
local LED_PINS = {
    green = config.HARDWARE_PINS.GREEN_LED,   -- 26
    yellow = config.HARDWARE_PINS.YELLOW_LED  -- 27
}

-- LED是否已初始化（惰性初始化兜底）
local led_inited = false

-- 绿灯慢闪控制（1Hz 翻转定时器 + 截止定时器）
local green_blink_timer = nil
local green_blink_stop_timer = nil

-- 停止绿灯慢闪（保留当前电平不动）
function tools.greenLed_stop_blink()
    if green_blink_timer then
        sys.timerStop(green_blink_timer)
        green_blink_timer = nil
    end
    if green_blink_stop_timer then
        sys.timerStop(green_blink_stop_timer)
        green_blink_stop_timer = nil
    end
end

-- 绿灯是否正在慢闪
function tools.greenLed_is_blinking()
    return green_blink_timer ~= nil
end

-- 绿灯慢闪(1Hz)：持续 sec 秒后自动灭；期间再次调用则重新计时
function tools.greenLed_blink(sec)
    tools.greenLed_stop_blink()
    if not led_inited then tools.init_led() end
    sec = sec or 10
    local blink_state = false
    green_blink_timer = sys.timerLoopStart(function()
        blink_state = not blink_state
        gpio.set(LED_PINS.green, blink_state and 1 or 0)
    end, 500)  -- 500ms 翻转 = 1Hz 慢闪
    green_blink_stop_timer = sys.timerStart(function()
        tools.greenLed_stop_blink()
        gpio.set(LED_PINS.green, 0)
    end, sec * 1000)
    log.info("[tools]", "绿灯慢闪启动，持续", sec, "秒")
end

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

    tools.greenLed_stop_blink()
    for color, pin in pairs(LED_PINS) do
        if pin then
            gpio.setup(pin, 0)
            gpio.set(pin, 0)
        end
    end
    led_inited = true
end

-- 打开绿灯（常亮），自动停止慢闪
function tools.greenLed_ON()
    if not led_inited then tools.init_led() end
    tools.greenLed_stop_blink()
    gpio.set(LED_PINS.green, 1)
    log.debug("[tools]", "绿灯常亮")
end

-- 关闭绿灯
function tools.greenLed_OFF()
    if not led_inited then tools.init_led() end
    tools.greenLed_stop_blink()
    gpio.set(LED_PINS.green, 0)
    log.debug("[tools]", "绿灯关闭")
end

-- 打开黄灯（常亮）
function tools.yellowLed_ON()
    if not led_inited then tools.init_led() end
    gpio.set(LED_PINS.yellow, 1)
    log.debug("[tools]", "黄灯常亮")
end

-- 关闭黄灯
function tools.yellowLed_OFF()
    if not led_inited then tools.init_led() end
    gpio.set(LED_PINS.yellow, 0)
    log.debug("[tools]", "黄灯关闭")
end

-- 关闭所有LED（绿灯/黄灯）
function tools.allLed_OFF()
    tools.greenLed_OFF()
    tools.yellowLed_OFF()
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

-- 订阅充电状态变化事件（由 battery 模块发布），实时更新内部缓存并控制黄灯
-- 黄灯 GPIO27：插入充电器常亮；拔电灭（充满后由上报逻辑灭）
sys.subscribe("CHARGING_START", function()
    device_state.vbus_state = 1
    device_state.is_charge = 1
    tools.yellowLed_ON()
end)
sys.subscribe("CHARGING_STOP", function()
    device_state.vbus_state = 0
    device_state.is_charge = 0
    tools.yellowLed_OFF()
    -- 拔电：绿灯充满常亮解除；若 GPS 定位模式慢闪中则保留（与USB无关）
    if not tools.greenLed_is_blinking() then
        tools.greenLed_OFF()
    end
end)

return tools
