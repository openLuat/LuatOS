--[[
@module  sensor_task
@summary Air780EPM 出厂固件 I2C 传感器采集模块（AirSHT30_1000 温湿度 / AirVOC_1000 TVOC）
@version 2.0
@date    2026.10.14
@author  李源龙
@usage
本模块为 Air780EPM 出厂固件的传感器采集模块，固定硬件 I2C1（PIN66=SDA / PIN67=SCL，外部上拉）：
1、定时/周期读取 SHT30 温湿度 与 AGS02MA(VOC) TVOC 数据
2、每个传感器独立容错：失败不阻断主数据上报，连续失败 MAX_FAIL 次后停止重试
3、采集失败返回 nil，由上层 build_report_tlv 跳过对应字段
4、sensor_enable=false 时整体不采集（供无传感器的 GNSS 工程复用）

数据流向：
- factory_app.build_report_tlv() → sensor_task.get_env() → (temp, hum, voc)

注意事项：
- 硬件 I2C1 的 SCL/SDA 需外部上拉（典型4.7kΩ到3.3V），禁用内部上拉
- VOC 传感器（AGS02MA）含加热元件，VCC 必须接板载3.3V，禁止 GPIO 供电
- 同一路I2C可挂多个从设备：SHT30=0x44、AGS02MA=0x1A，地址不冲突
]]

local sensor_task = {}

local AirSHT30_1000 = require "AirSHT30_1000"
local AirVOC_1000 = require "AirVOC_1000"
-- 固定硬件配置
local factory_config = require "factory_config"
local i2c_cfg = factory_config.get_sensor_i2c()
-- 传感器采集总开关（false=整体不采集）
local sensor_enabled = factory_config.get_sensor_enable()

-- 当前硬件 I2C 总线 id
local bus
-- 各传感器连续失败计数与禁用标志
local sht30_fail, voc_fail = 0, 0
local sht30_disabled, voc_disabled = false, false

-- 容错参数
local MAX_FAIL = 10            -- 连续失败次数，超过后停止重试该传感器

-- 初始化硬件 I2C 总线
local function init_bus()
    if not sensor_enabled then
        log.info("sensor_task", "未启用传感器采集，跳过I2C初始化")
        return false
    end
    bus = i2c_cfg.hw_id or 1
    log.info("sensor_task", "硬件I2C就绪", "id=", bus)
    return true
end

-- 初始化失败也要继续（get_env 会返回nil，不阻断上报）
init_bus()

-- 记录单传感器连续失败，超过阈值则禁用该传感器
local function record_fail(name, fail, disabled)
    fail = fail + 1
    if fail >= MAX_FAIL then
        disabled = true
        log.warn("sensor_task", name, "连续失败", fail, "次，停止重试")
    end
    return fail, disabled
end

-- 读取 SHT30 温湿度（独立容错，失败返回nil，不影响其他数据）
-- 注意：AirSHT30_1000.read() 内部有 sys.wait，必须在本协程（任务）中调用
local function read_sht30()
    if sht30_disabled then
        return nil
    end
    if not AirSHT30_1000.open(bus) then
        sht30_fail, sht30_disabled = record_fail("SHT30", sht30_fail, sht30_disabled)
        return nil
    end
    local t, h = AirSHT30_1000.read()
    AirSHT30_1000.close()
    if t then
        sht30_fail = 0
        log.info("sensor_task", string.format("SHT30 温度:%.2f℃ 湿度:%.2f%%", t, h))
        return t, h
    else
        sht30_fail, sht30_disabled = record_fail("SHT30", sht30_fail, sht30_disabled)
        return nil
    end
end

-- 读取 VOC(TVOC) 数据（独立容错，失败返回nil，不影响其他数据）
local function read_voc()
    if voc_disabled then
        return nil
    end
    if not AirVOC_1000.open(bus) then
        voc_fail, voc_disabled = record_fail("VOC", voc_fail, voc_disabled)
        return nil
    end
    local v = AirVOC_1000.get_ppb()
    AirVOC_1000.close()
    if v then
        voc_fail = 0
        log.info("sensor_task", string.format("VOC TVOC:%d ppb", v))
        return v
    else
        voc_fail, voc_disabled = record_fail("VOC", voc_fail, voc_disabled)
        return nil
    end
end

--[[
采集全部传感器数据

@return number|nil 温度（摄氏度），失败返回nil
@return number|nil 湿度（百分比），失败返回nil
@return number|nil TVOC（ppb），失败返回nil
@usage
local temp, hum, voc = sensor_task.get_env()
]]
function sensor_task.get_env()
    -- 传感器采集禁用时直接返回 nil
    if not sensor_enabled then
        return nil, nil, nil
    end
    local temp, hum = read_sht30()
    local voc = read_voc()
    return temp, hum, voc
end

return sensor_task
