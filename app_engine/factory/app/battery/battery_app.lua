--[[
@module  battery_app
@summary 电池管理模块，负责电池电压检测、电量计算、充放电状态判断
@version 1.0
@date    2026.05.28
@author  江访
@usage
  本模块为电池管理核心模块，主要功能包括：
  1、通过 ADC7 读取电池电压（分压比 1:2），映射为电量百分比
  2、通过 GPIO52 检测 USB 插入状态
  3、根据 USB 状态和电池电压推断 充电中 / 放电中 / 无电池 状态
  4、每 3 秒定时采集，状态变化时发布 BATTERY_STATUS 事件
  5、响应 REQUEST_STATUS_REFRESH 重新发布当前状态

  电池状态判定逻辑：
  - VBAT < 1.5V 且 USB 未插入 → 无电池
  - USB 插入 + VBAT < 充满电压(4.15V) → 充电中
  - USB 插入 + VBAT ≥ 充满电压 → 已充满
  - USB 未插入 + VBAT ≥ 1.5V → 放电中
]]

local has_battery = _G.project_config and _G.project_config.features and _G.project_config.features.battery
if not has_battery then
    return
end

local hw = _G.project_config.hw and _G.project_config.hw.battery
if not hw then
    log.warn("battery", "features.battery=true 但 hw.battery 未配置")
    return
end

local adc_channel = hw.adc_channel or 7
local usb_gpio = hw.usb_detect_gpio or 52
local voltage_divider = hw.voltage_divider or 2
local full_voltage = hw.full_voltage or 4150
local no_battery_threshold = 1500

-- 电池状态缓存
local battery_present = false
local battery_level = 0
local battery_voltage = 0
local is_charging = false
local usb_connected = false
local voltage_history = {}
local VOLTAGE_HISTORY_MAX = 10

-- 锂电池放电曲线 (电压V → 电量%)
local VOLTAGE_CURVE = {
    {4.20, 100}, {4.15, 95}, {4.10, 90}, {4.05, 82},
    {4.00, 75}, {3.95, 68}, {3.90, 60}, {3.85, 50},
    {3.80, 40}, {3.75, 30}, {3.70, 20}, {3.65, 15},
    {3.60, 10}, {3.50, 5}, {3.00, 0},
}

--[[
电压值 (mV) 转换为电量百分比
@param number voltage_mv 电池电压 (mV)
@return number percent 电量百分比 (0-100)
]]
local function voltage_to_percent(voltage_mv)
    local v = voltage_mv / 1000
    if v >= 4.2 then
        return 100
    end
    for i = 2, #VOLTAGE_CURVE do
        if v >= VOLTAGE_CURVE[i][1] then
            local v_high, p_high = VOLTAGE_CURVE[i - 1][1], VOLTAGE_CURVE[i - 1][2]
            local v_low, p_low = VOLTAGE_CURVE[i][1], VOLTAGE_CURVE[i][2]
            local ratio = (v - v_low) / (v_high - v_low)
            return math.floor(p_low + ratio * (p_high - p_low) + 0.5)
        end
    end
    return 0
end

--[[
读取电池状态 (ADC电压 + USB检测GPIO)，计算电量和充放电状态
状态变化时发布 BATTERY_STATUS 事件
]]
local function read_battery()
    local new_usb = false
    local new_voltage = 0

    -- 读取 USB 检测 GPIO
    local ok_gpio, level = pcall(gpio.get, usb_gpio)
    if ok_gpio then
        new_usb = (level == 1)
    end

    -- 读取电池电压 (ADC)
    local ok_adc, raw_mv = pcall(adc.open, adc_channel)
    if ok_adc then
        local ok_read, read_val = pcall(adc.get, adc_channel)
        pcall(adc.close, adc_channel)
        if ok_read and read_val and read_val > 0 then
            new_voltage = read_val * voltage_divider
        end
    end

    -- 滑动窗口平均滤波：保留最近 10 次采样，取平均值抑制 ADC 噪点
    if new_voltage > 0 then
        voltage_history[#voltage_history + 1] = new_voltage
        if #voltage_history > VOLTAGE_HISTORY_MAX then
            table.remove(voltage_history, 1)
        end
    end
    local avg_voltage = 0
    if #voltage_history > 0 then
        local sum = 0
        for _, v in ipairs(voltage_history) do
            sum = sum + v
        end
        avg_voltage = sum / #voltage_history
    end

    -- 判断电池是否存在
    local new_present = false
    if avg_voltage >= no_battery_threshold then
        new_present = true
    end

    -- 计算电量百分比
    local new_level = 0
    if new_present then
        new_level = voltage_to_percent(avg_voltage)
        if new_level > 100 then
            new_level = 100
        end
        if new_level < 0 then
            new_level = 0
        end
    end

    -- 判断充电状态
    local new_charging = false
    if new_present and new_usb then
        if avg_voltage < full_voltage then
            new_charging = true
        end
    end

    -- 检测状态是否发生变化
    local changed = (usb_connected ~= new_usb)
        or (battery_present ~= new_present)
        or (is_charging ~= new_charging)
        or (battery_level ~= new_level)

    usb_connected = new_usb
    battery_present = new_present
    battery_voltage = math.floor(avg_voltage + 0.5)
    is_charging = new_charging
    battery_level = new_level

    if changed then
        sys.publish("BATTERY_STATUS", {
            present = battery_present,
            level = battery_level,
            voltage = battery_voltage,
            charging = is_charging,
            usb = usb_connected,
        })
    end

    if not battery_present then
        log.info("battery", "电池未检测到")
    elseif is_charging then
        log.info("battery", string.format("充电中 电量:%d%% 电压:%dmV", battery_level, battery_voltage))
    else
        log.info("battery", string.format("放电中 电量:%d%% 电压:%dmV", battery_level, battery_voltage))
    end
end

-- 初始化 USB 检测 GPIO 为输入模式
gpio.setup(usb_gpio, nil, gpio.PULLDOWN)

-- 首次读取并启动 3 秒周期定时器
read_battery()
sys.timerLoopStart(read_battery, 10000)

-- 响应状态刷新请求（由 UI 失焦/获焦时触发）
sys.subscribe("REQUEST_STATUS_REFRESH", function()
    sys.publish("BATTERY_STATUS", {
        present = battery_present,
        level = battery_level,
        voltage = battery_voltage,
        charging = is_charging,
        usb = usb_connected,
    })
end)
