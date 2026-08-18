--[[
@module  battery
@summary 电池管理模块
@version 3.1
@date    2026.04.22
@usage
本模块的核心功能为：
1. 通过ADC0分压电路检测电池电压
2. 通过VBUS(WAKEUP1)引脚检测充电状态
3. 提供电池电压、电量和充电状态查询接口

硬件连接：
- ADC0: 分压中点，BAT → 1MΩ → ADC0 → 300kΩ → GND
- VBUS: USB充电检测脚，上升沿=插入，下降沿=拔出
]]

local battery = {}
local config = require "config"
local kvstore = require "kvstore"

-- 电池状态
local battery_state = {
    voltage = 0,          -- 电池电压（mV）
    level = 100,          -- 电池电量（%）
    charging = false,     -- 充电状态
    last_check_time = 0
}

-- VBUS充电状态回调
local function vbus_callback(level)
    if level == 1 then
        battery_state.charging = true
        log.info("battery", "USB插入，开始充电")
        sys.publish("CHARGING_START")
    else
        battery_state.charging = false
        log.info("battery", "USB拔出，停止充电")
        sys.publish("CHARGING_STOP")
    end
end

-- 读取电池电压（多次采样取平均）
-- @return number|nil 电池电压(mV)，失败返回nil
local function read_battery_voltage()
    local bTable = {}
    local sample_count = config.BATTERY_CONFIG.ADC_SAMPLE_COUNT or 5
    local sample_interval = config.BATTERY_CONFIG.ADC_SAMPLE_INTERVAL or 10
    local r1 = config.BATTERY_CONFIG.DIVIDER_R1 or 1000
    local r2 = config.BATTERY_CONFIG.DIVIDER_R2 or 300
    local compensate = config.BATTERY_CONFIG.COMPENSATE or 140
    
    for i = 1, sample_count do
        adc.setRange(adc.ADC_RANGE_MIN)
        adc.open(0)
        local vadc0 = adc.get(0)
        adc.close(0)
        
        if vadc0 then
            local vbat1 = vadc0 * (r1 + r2) / r2
            local vbat = vbat1 + compensate
            table.insert(bTable, vbat)
        end
        
        sys.wait(sample_interval)
    end
    
    if #bTable < 3 then
        log.error("battery", "采样失败，有效数据不足")
        return nil
    end
    
    -- 计算最大值、最小值和总和
    local max_val = bTable[1]
    local min_val = bTable[1]
    local sum = 0
    
    for i = 1, #bTable do
        if bTable[i] > max_val then
            max_val = bTable[i]
        end
        if bTable[i] < min_val then
            min_val = bTable[i]
        end
        sum = sum + bTable[i]
    end
    
    -- 去掉最大值和最小值，取剩下的平均值
    local avg_voltage = (sum - max_val - min_val) / (#bTable - 2)
    return math.floor(avg_voltage + 0.5)
end

-- 计算电池电量百分比
-- @param voltage_mv 电池电压(mV)
-- @return number 电量百分比(0-100)
local function calculate_level(voltage_mv)
    local full = config.BATTERY_CONFIG.FULL_VOLTAGE or 4200
    local empty = config.BATTERY_CONFIG.LOW_VOLTAGE or 3300
    
    if voltage_mv >= full then return 100 end
    if voltage_mv <= empty then return 0 end
    
    return math.floor((voltage_mv - empty) / (full - empty) * 100)
end

-- 检测电池电压并更新状态
local function check_battery()
    local voltage = read_battery_voltage()
    
    if voltage then
        battery_state.voltage = voltage
        battery_state.level = calculate_level(voltage)
        battery_state.last_check_time = os.time()
        
        -- 保存到kvstore供其他模块使用
        kvstore.set_vbat(voltage)
        
        log.debug("battery", "电池电压:", voltage, "mV, 电量:", battery_state.level, "%, 充电:", battery_state.charging)
    end
end

-- 初始化电池管理模块
function battery.init()
    log.info("battery", "电池管理模块初始化")

    if gpio.WAKEUP1 then
        -- 配置VBUS(WAKEUP1)引脚检测充电状态
        -- 配置200ms防抖，双边沿中断
        gpio.debounce(gpio.WAKEUP1, 200)
        gpio.setup(gpio.WAKEUP1, vbus_callback, gpio.PULLDOWN, gpio.BOTH)

        -- 立即读取当前VBUS状态
        local current_level = gpio.get(gpio.WAKEUP1)
        if current_level then
            battery_state.charging = current_level == 1
            log.info("battery", "初始充电状态:", battery_state.charging)
        end
    else
        log.warn("battery", "gpio.WAKEUP1不可用，跳过充电检测配置")
    end

    -- 立即检测一次电池
    check_battery()
    
    log.info("battery", "电池管理模块初始化完成")
end

-- 获取电池数据
-- @return table 包含电压、电量、充电状态和检测时间的表
function battery.get_data()
    return {
        voltage = battery_state.voltage,
        level = battery_state.level,
        charging = battery_state.charging,
        last_check_time = battery_state.last_check_time
    }
end

-- 获取电池电量
-- @return number 电量百分比（0-100）
function battery.get_level()
    return battery_state.level
end

-- 获取电池电压
-- @return number 电池电压（mV）
function battery.get_voltage()
    return battery_state.voltage
end

-- 获取充电状态
-- @return boolean 充电状态，true表示正在充电，false表示未充电
function battery.is_charging()
    return battery_state.charging
end

-- 强制检测电池状态
-- @return table 最新的电池状态信息
function battery.force_check()
    check_battery()
    return battery.get_data()
end

return battery
