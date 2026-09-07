--[[
@module tools
@summary 工具模块
@version 3.0
@date    2026.09.06
@author  孟伟
@usage
工具模块，当前职责为双灯独立状态机（004.000.038 规则重写，两灯可同时点亮）：

黄灯 = 充电指示（由 battery 模块 YHM2712A 充电IC 状态驱动）：
- 充电中（充电器在位、未充满）→ 常亮
- 充满电（充电器在位 + charge_complete：电池在位且充电阶段=7）→ 闪烁 600ms 亮 / 400ms 灭
- 充电器不在位 → 灭

绿灯 = 网络指示（优先级从高到低）：
- 收到服务器任何下行消息后 60s 内 → 常亮（REMOTE_COMMAND 覆盖一切下行，每次收到刷新窗口；
  开机闪烁期间收到第一条下行即"停止闪烁、改为常亮"）
- 开机后 20s 内 → 闪烁 200ms 亮 / 200ms 灭（开机存活指示）
- GNSS 关→开切换后 10s 内 → 常亮（由 active_mode 调 led_gnss_switched_on 触发）
- 以上均不满足 → 灭

实现：100ms 刷新定时器 + mcu.ticks() 毫秒相位计算（两种闪烁节奏共用一个定时器，
不受 NTP 校时跳变影响；ticks 为 32 位毫秒，约 49.7 天回绕，回绕后窗口以最近一次事件重置）。
充电状态来自 battery 轮询缓存（默认 30s 刷新，充满检测延迟上限约 30s）。

历史版本：
- 004.000.030 清理：删除旧 LED 兼容接口、电源状态管理、业务状态、调试接口、计步编码等死代码
- 004.000.034 重写：单灯三条件常亮/闪烁（充电中黄灯、不充电绿灯互斥切换；本版废弃）
]]

local tools = {}

local config = require("config")

-- LED引脚定义（8202G：GPIO26 绿灯、GPIO27 黄灯）
local LED_PINS = {
    green  = config.HARDWARE_PINS.GREEN_LED    -- 26 绿灯（网络指示）
    ,yellow = config.HARDWARE_PINS.YELLOW_LED  -- 27 黄灯（充电指示）
}

-- 绿灯（网络）参数
local LED_BOOT_BLINK_SEC = 20    -- 开机绿灯闪烁窗口（秒）
local LED_NET_ON_SEC     = 60    -- 收到服务器下行后绿灯常亮时长（秒）
local LED_GNSS_ON_SEC    = 10    -- GNSS 关→开切换后绿灯常亮时长（秒）
local LED_NET_BLINK_MS   = 200   -- 开机闪烁半周期：200ms 亮 / 200ms 灭

-- 黄灯（充电）参数
local LED_FULL_ON_MS     = 600   -- 充满闪烁：600ms 亮
local LED_FULL_OFF_MS    = 400   -- 充满闪烁：400ms 灭

-- LED是否已初始化（惰性初始化兜底）
local led_inited = false

-- LED 状态机（窗口基准全部用 mcu.ticks() 毫秒 tick，不受 NTP 校时跳变影响）
local led = {
    boot_ticks = 0,      -- init_led 时刻的 tick，开机闪烁窗口基准
    gnss_on_ticks = -1,  -- GNSS 关→开切换时刻 tick（-1=尚未触发）
    last_rx_ticks = -1,  -- 最近一次收到服务器任何下行时刻 tick（-1=尚未收到）
    timer = nil,         -- 100ms 刷新定时器
}

-- 电源状态（充电器在位状态由 battery 模块轮询 YHM2712A 充电IC 后，经 CHARGING_START/STOP 事件更新）
local device_state = {
    vbus_state = 0,    -- 1=充电器在位（含充满未拔），0=不在位
}

-- 读取电池缓存中的"充电完成"标志（battery.get_data 纯读缓存非阻塞，可直接在定时器里调用）
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

-- LED 状态机核心：每 100ms 由定时器调用，闪烁相位用 mcu.ticks() 毫秒计算
-- 规则（用户确认，2026.09.06）：
--   黄灯=充电：充电中常亮 / 充满（充电器在位+charge_complete）闪 600/400 / 充电器不在位灭
--   绿灯=网络：收到任何下行 60s 内常亮 > 开机 20s 内闪 200/200 > GNSS切换 10s 常亮 > 灭
--   两灯独立判定、可同时点亮（不再互斥单灯切换）
-- 充电判定：本硬件无 VBUS 检测脚（GPIO 直读已失效），充电器在位状态由
--   battery 模块轮询 YHM2712A 充电IC（exs_yhm2712a.status）得出，
--   经 CHARGING_START/CHARGING_STOP 事件更新 device_state.vbus_state
local function led_refresh()
    if not led_inited then return end
    local t = mcu.ticks()  -- 毫秒 tick（闪烁相位与窗口判定）

    -- ===== 黄灯：充电指示 =====
    local charging = (device_state.vbus_state == 1)
    local yellow_on = false
    if charging then
        if is_charge_complete() then
            -- 充满电：600ms 亮 / 400ms 灭
            yellow_on = (t % (LED_FULL_ON_MS + LED_FULL_OFF_MS)) < LED_FULL_ON_MS
        else
            yellow_on = true  -- 充电中：常亮
        end
    end
    -- 充电器不在位：yellow_on 保持 false（不亮）

    -- ===== 绿灯：网络指示（优先级：下行常亮 > 开机闪烁 > GNSS切换常亮 > 灭） =====
    local net_hold = led.last_rx_ticks >= 0
        and (t - led.last_rx_ticks) < LED_NET_ON_SEC * 1000          -- 收到下行 60s 内
    local boot_blink = (t - led.boot_ticks) < LED_BOOT_BLINK_SEC * 1000  -- 开机 20s 内
    local gnss_hold = led.gnss_on_ticks >= 0
        and (t - led.gnss_on_ticks) < LED_GNSS_ON_SEC * 1000         -- GNSS 切换 10s 内
    local green_on = false
    if net_hold then
        green_on = true                                              -- 收到下行：常亮（覆盖开机闪烁）
    elseif boot_blink then
        green_on = (t % (LED_NET_BLINK_MS * 2)) < LED_NET_BLINK_MS   -- 开机：200ms 亮 / 200ms 灭
    elseif gnss_hold then
        green_on = true                                              -- GNSS 切换：常亮 10s
    end

    -- 输出（两灯独立，可同时点亮）
    gpio.set(LED_PINS.green,  green_on and 1 or 0)
    gpio.set(LED_PINS.yellow, yellow_on and 1 or 0)
end

-- 初始化LED：设置为输出模式并关闭所有LED，记录开机 tick 并启动状态机定时器
function tools.init_led()
    log.info("[tools]", "初始化LED状态机（绿=网络 黄=充电）")
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

-- ============================================
-- LED 状态机对外接口
-- ============================================

-- GNSS 关→开切换：绿灯常亮 10 秒（由 active_mode 主循环在切换瞬间调用）
function tools.led_gnss_switched_on()
    led.gnss_on_ticks = mcu.ticks()
    led_refresh()
    log.info("[tools]", "GNSS开启，绿灯常亮10秒")
end

-- 订阅一切服务器下行消息：REMOTE_COMMAND 覆盖 TCP/MQTT 原样 JSON 与 AirCloud 逐 TLV 的全部下行
-- （鉴权回复17/上报回应18/远程指令/命令应答等），收到即启动/刷新绿灯 60s 常亮窗口——
-- 开机闪烁期间收到第一条下行即"停止闪烁、改为常亮"
sys.subscribe("REMOTE_COMMAND", function(msg)
    led.last_rx_ticks = mcu.ticks()
    led_refresh()
end)

-- 订阅充电状态变化事件（由 battery 模块轮询 YHM2712A 充电IC 后发布）：更新内部缓存并立即刷新 LED
-- （充电器在位状态由 battery 后台任务默认 30s 轮询一次，插拔检测延迟上限即为此值）
sys.subscribe("CHARGING_START", function()
    device_state.vbus_state = 1
    led_refresh()
end)
sys.subscribe("CHARGING_STOP", function()
    device_state.vbus_state = 0
    led_refresh()
end)

return tools
