--[[
@module tools
@summary 工具模块
@version 2.1
@date    2026.09.02
@author  孟伟
@usage
工具模块，当前职责为 LED 状态机：
- 开机60s常亮 / GNSS关→开切换亮10s / 充电常亮（红，充满绿）
- 600s内收到过服务器下行（REMOTE_COMMAND）→ 常亮，否则500ms闪烁
- 充电器在位状态由 battery 模块轮询 YHM2712A 充电IC 后经 CHARGING_START/STOP 事件驱动

004.000.030 清理：删除旧 LED 兼容接口（greenLed_* 等）、电源状态管理（get_vbus_state/
update_power_state 等）、业务状态（device_mode/position_active_report）、调试接口
get_all_state、计步编码 encode_step —— 均随 unactive_mode 删除与 GNSS 三态上报重构后无调用者。
]]

local tools = {}

local config = require("config")

-- LED引脚定义（8202G：GPIO26 绿灯、GPIO27 红灯）
-- 注：GPIO27 硬件原为黄灯位，本版本起作红灯使用（映射约定：26=绿 / 27=红）
local LED_PINS = {
    green = config.HARDWARE_PINS.GREEN_LED,   -- 26 绿灯
    red   = config.HARDWARE_PINS.YELLOW_LED   -- 27 红灯
}

-- LED 状态机参数
local LED_BOOT_ON_SEC = 60     -- 开机前 60 秒亮（告知用户设备存活）
local LED_GNSS_ON_SEC = 10     -- GNSS 关→开切换后亮 10 秒
local LED_COMM_OK_SEC = 600    -- 600 秒内收到过服务器下行 → 通信正常（常亮），否则闪烁
local LED_BLINK_MS    = 500    -- 闪烁半周期：500ms 亮 / 500ms 灭

-- LED是否已初始化（惰性初始化兜底）
local led_inited = false

-- LED 状态机
local led = {
    boot_time = nil,        -- init_led 时刻（os.time），开机亮灯窗口基准
    gnss_on_until = 0,      -- GNSS 关→开切换亮灯截止时间戳
    last_rx_time = 0,       -- 最近一次收到服务器下行（REMOTE_COMMAND）的时间戳
    manual_on = false,      -- 远程 open_light 手动开灯（覆盖自动亮灭逻辑）
    blink_phase = false,    -- 闪烁相位
    timer = nil,            -- 500ms 刷新定时器
}

-- 读取电池电量（惰性加载 battery 模块，避免 require 顺序问题）
local function led_battery_level()
    local ok, battery = pcall(require, "battery")
    if ok and battery and battery.get_level then
        return battery.get_level() or 0
    end
    return 0
end

-- 电源状态（充电器在位状态由 battery 模块轮询 YHM2712A 充电IC 后，经 CHARGING_START/STOP 事件更新）
local device_state = {
    vbus_state = 0,    -- 1=充电器在位（含充满未拔），0=不在位
}

-- LED 状态机核心：每 500ms 由定时器调用，各事件也触发立即刷新
-- 规则（用户确认）：
--   亮：开机60s内 / GNSS关→开切换后10s内 / 充电(充电器在位，含充满未拔)；其余灭
--   常亮/闪烁：600s内收到过服务器下行→常亮；否则500ms亮/500ms灭（充电不影响闪烁逻辑）
--   颜色：充电中未充满→红；充满未拔→绿；其余亮灯场景→红
-- 充电判定：本硬件无 VBUS 检测脚（GPIO 直读已失效），充电器在位状态由
--   battery 模块轮询 YHM2712A 充电IC（exs_yhm2712a.status）得出，
--   经 CHARGING_START/CHARGING_STOP 事件更新 device_state.vbus_state
local function led_refresh()
    if not led_inited then return end
    local now = os.time()

    -- 1) 亮/灭判定（充电状态来自 battery 轮询缓存，开机即插着充电器时首次轮询后即点亮）
    local vbus = device_state.vbus_state
    local lit = led.manual_on
        or (led.boot_time and (now - led.boot_time) < LED_BOOT_ON_SEC)  -- 开机60s
        or (now < led.gnss_on_until)                                    -- GNSS切换10s
        or (vbus == 1)                                                  -- 充电

    -- 2) 常亮/闪烁判定
    local comm_ok = led.last_rx_time > 0 and (now - led.last_rx_time) <= LED_COMM_OK_SEC
    local on
    if not lit then
        on = false
    elseif comm_ok or led.manual_on then
        on = true
    else
        led.blink_phase = not led.blink_phase
        on = led.blink_phase
    end

    -- 3) 颜色判定：充满(电量>=99)且未拔充电器→绿，其余→红
    local color = "red"
    if vbus == 1 and led_battery_level() >= 99 then
        color = "green"
    end

    -- 4) 输出到引脚（任一时刻最多亮一盏）
    gpio.set(LED_PINS.green, (on and color == "green") and 1 or 0)
    gpio.set(LED_PINS.red,   (on and color == "red")   and 1 or 0)
end

-- 初始化LED：设置为输出模式并关闭所有LED，记录开机时间并启动状态机定时器
function tools.init_led()
    log.info("[tools]", "初始化LED状态机")
    for _, pin in pairs(LED_PINS) do
        if pin then
            gpio.setup(pin, 0)
            gpio.set(pin, 0)
        end
    end
    led_inited = true
    led.boot_time = os.time()
    led.blink_phase = false
    if not led.timer then
        led.timer = sys.timerLoopStart(led_refresh, LED_BLINK_MS)
    end
    led_refresh()
end

-- ============================================
-- LED 状态机对外接口
-- ============================================

-- GNSS 关→开切换：亮灯 10 秒（由 active_mode 主循环在切换瞬间调用）
function tools.led_gnss_switched_on()
    led.gnss_on_until = os.time() + LED_GNSS_ON_SEC
    led_refresh()
    log.info("[tools]", "GNSS开启，LED亮10秒")
end

-- 收到服务器下行：刷新通信正常时间戳
-- 本模块已自行订阅 REMOTE_COMMAND（含上报回应/远程指令等一切下行），业务侧无需调用
function tools.led_server_rx()
    led.last_rx_time = os.time()
    led_refresh()
end

-- 远程 open_light 手动开关灯（true=强制亮，false=回到自动状态机）
function tools.led_set_manual(on)
    led.manual_on = on and true or false
    led_refresh()
end

-- 订阅服务器下行：任何 REMOTE_COMMAND（上报回应/远程指令等一切下行）都视为通信正常的证据
-- 600 秒内收到过 → LED 常亮；超时 → 闪烁
sys.subscribe("REMOTE_COMMAND", function()
    tools.led_server_rx()
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
