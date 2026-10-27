--[[
@module tools
@summary 双灯独立状态机（两灯可同时点亮）
黄灯 = 充电指示（battery 模块轮询充电状态，CHARGING_START/STOP 事件驱动）：
  充电中常亮 / 充满闪 600ms 亮 400ms 灭 / 充电器不在位灭
绿灯 = 网络指示（优先级从高到低）：
  服务器 led 指令(on/off/blink) > 手动覆盖(open_light)常亮 >
  收到任何下行 60s 内常亮 > 开机 20s 内闪 200ms > 灭
对外接口：
  tools.init_led()         初始化并启动灯效状态机（开机调用一次）
  tools.led_force(cmd,s)   led:on / led:off / led:blink（服务器下行）
  tools.led_set_manual(e)  远程命令 open_light 手动覆盖网络灯
]]

local tools = {}

local config = require("config")

-- LED 引脚（8202：26绿/27黄；8201G,H：12红/1蓝）
local LED_PINS = {
    green  = config.HARDWARE_PINS.GREEN_LED,
    yellow = config.HARDWARE_PINS.YELLOW_LED,
}

local LED_BOOT_BLINK_SEC = 20    -- 开机绿灯闪烁窗口（秒）
local LED_NET_ON_SEC     = 60    -- 收到下行后绿灯常亮时长（秒）
local LED_NET_BLINK_MS   = 200   -- 开机闪烁半周期（毫秒）
local LED_FULL_ON_MS     = 600   -- 充满闪烁亮（毫秒）
local LED_FULL_OFF_MS    = 400   -- 充满闪烁灭（毫秒）

-- mcu.ticks() 为平台 tick，经 mcu.hz() 换算成毫秒，避免非 1ms tick 平台灯效失真
local TICK_HZ = mcu.hz() or 1000
local function T(ms_value)
    return math.floor(ms_value * TICK_HZ / 1000)
end

local led_inited = false
local manual_on = false      -- open_light 手动覆盖（仅网络灯，充电灯不受影响）
local led_force = nil        -- nil / "on" / "off" / "blink"
local led_blink_until = 0    -- blink 到期 tick

local led = {
    boot_ticks = 0,      -- 开机 tick，闪烁窗口基准
    last_rx_ticks = -1,  -- 最近一次收到下行 tick（-1=未收到）
    timer = nil,
}

local device_state = {
    vbus_state = 0,    -- 1=充电器在位（含充满未拔），0=不在位
}

-- 读 battery 缓存的"充满"标志（纯读缓存，非阻塞）
local function is_charge_complete()
    local ok, battery = pcall(require, "battery")
    if not ok or not battery or not battery.get_data then
        return false
    end
    local ok2, data = pcall(battery.get_data)
    if ok2 and type(data) == "table" then
        return data.charge_complete and true or false
    end
    return false
end

-- 服务器 led 指令优先级最高：命中直接驱动两灯并跳过自动状态机
-- blink 为亮1s灭1s，到期（默认5s）自动交还
local function led_force_apply(t)
    if not led_force then return false end
    if led_force == "blink" and t >= led_blink_until then
        led_force = nil
        return false
    end
    local green_on, yellow_on
    if led_force == "on" then
        green_on, yellow_on = true, true
    elseif led_force == "off" then
        green_on, yellow_on = false, false
    else
        local on = (t % T(2000)) < T(1000)
        green_on, yellow_on = on, on
    end
    if LED_PINS.green then gpio.set(LED_PINS.green, green_on and 1 or 0) end
    if LED_PINS.yellow then gpio.set(LED_PINS.yellow, yellow_on and 1 or 0) end
    return true
end

-- 100ms 刷新：闪烁相位与窗口均用 mcu.ticks()，不受 NTP 校时跳变影响
local function led_refresh()
    if not led_inited then return end
    if led_force_apply(mcu.ticks()) then return end
    local t = mcu.ticks()

    -- 黄灯：充电指示
    local yellow_on = false
    if device_state.vbus_state == 1 then
        if is_charge_complete() then
            yellow_on = (t % T(LED_FULL_ON_MS + LED_FULL_OFF_MS)) < T(LED_FULL_ON_MS)
        else
            yellow_on = true
        end
    end

    -- 绿灯：网络指示
    local net_hold = led.last_rx_ticks >= 0
        and (t - led.last_rx_ticks) < T(LED_NET_ON_SEC * 1000)
    local boot_blink = (t - led.boot_ticks) < T(LED_BOOT_BLINK_SEC * 1000)
    local green_on = false
    if manual_on then
        green_on = true
    elseif net_hold then
        green_on = true
    elseif boot_blink then
        green_on = (t % T(LED_NET_BLINK_MS * 2)) < T(LED_NET_BLINK_MS)
    end

    -- 无该路指示灯时引脚为 nil，跳过
    if LED_PINS.green then gpio.set(LED_PINS.green, green_on and 1 or 0) end
    if LED_PINS.yellow then gpio.set(LED_PINS.yellow, yellow_on and 1 or 0) end
end

-- 初始化：引脚设为输出并熄灭，记录开机 tick，启动 100ms 刷新定时器
function tools.init_led()
    log.info("[tools]", "初始化LED状态机，tick基准:", TICK_HZ, "Hz")
    for _, pin in pairs(LED_PINS) do
        if pin then
            gpio.setup(pin, 0)
            gpio.set(pin, 0)
        end
    end
    led_inited = true
    led.boot_ticks = mcu.ticks()
    if not led.timer then
        led.timer = sys.timerLoopStart(led_refresh, 100)
    end
    led_refresh()
end

-- 服务器 led 下行：on/off/blink（blink 默认 5 秒）
-- @return boolean 成功 true；命令非法返回 false
function tools.led_force(cmd, seconds)
    if cmd ~= "on" and cmd ~= "off" and cmd ~= "blink" then
        return false, "未知的 LED 命令: " .. tostring(cmd)
    end
    led_force = cmd
    if cmd == "blink" then
        led_blink_until = mcu.ticks() + T((seconds or 5) * 1000)
    end
    led_refresh()
    return true
end

-- open_light 手动覆盖网络灯：true 强制常亮，false 交还自动状态机
function tools.led_set_manual(enable)
    manual_on = enable and true or false
    led_refresh()
    log.info("[tools]", "LED 手动覆盖:", manual_on and "开" or "关")
end

-- 收到任何服务器下行：刷新绿灯 60s 常亮窗口（开机闪烁期间收到即改常亮）
sys.subscribe("REMOTE_COMMAND", function()
    led.last_rx_ticks = mcu.ticks()
    led_refresh()
end)

-- 充电状态变化（battery 后台轮询发布）：更新缓存并立即刷新
sys.subscribe("CHARGING_START", function()
    device_state.vbus_state = 1
    led_refresh()
end)
sys.subscribe("CHARGING_STOP", function()
    device_state.vbus_state = 0
    led_refresh()
end)

return tools
