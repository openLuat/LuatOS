--[[
@module  sensor_task
@summary 出厂固件 I2C 传感器采集模块（AirSHT30_1000 温湿度 / AirVOC_1000 TVOC）
@version 1.0
@date    2026.09.20
@author  李源龙
@usage
本模块为出厂固件的传感器采集模块，核心业务逻辑为：
1、支持硬件I2C（默认）与软件I2C（8781P/8782P成品板兜底）两种模式，配置项切换
2、定时/周期读取 SHT30 温湿度 与 AGS02MA(VOC) TVOC 数据
3、每个传感器独立容错：失败不阻断主数据上报，连续失败 MAX_FAIL 次后停止重试
4、采集失败返回 nil，由上层 build_report_tlv 跳过对应字段

数据流向：
- factory_app.build_report_tlv() → sensor_task.get_env() → (temp, hum, voc)

注意事项：
- 软件I2C需在 SCL/SDA 引脚外挂上拉电阻（典型4.7kΩ到3.3V）
- VOC 传感器（AGS02MA）含加热元件，VCC 必须接板载3.3V，禁止 GPIO 供电
- 同一路I2C可挂多个从设备：SHT30=0x44、AGS02MA=0x1A，地址不冲突
]]

local sensor_task = {}

local AirSHT30_1000 = require "AirSHT30_1000"
local AirVOC_1000 = require "AirVOC_1000"
-- 版本配置：I2C 模式/引脚 由 factory_config 集中管理
local factory_config = require "factory_config"
local i2c_cfg = factory_config.get_sensor_i2c()

-- 当前I2C总线（硬件id 或 软件I2C对象）
local bus
-- 各传感器连续失败计数与禁用标志
local sht30_fail, voc_fail = 0, 0
local sht30_disabled, voc_disabled = false, false

-- 容错参数
local MAX_FAIL = 10            -- 连续失败次数，超过后停止重试该传感器

-- 初始化I2C总线（按版本配置创建）
local function init_bus()
    if i2c_cfg.mode == "sw" then
        bus = i2c.createSoft(i2c_cfg.scl, i2c_cfg.sda, i2c_cfg.delay or 5)
        if not bus then
            log.error("sensor_task", "软件I2C创建失败", "SCL=", i2c_cfg.scl, "SDA=", i2c_cfg.sda)
            return false
        end
        log.info("sensor_task", "软件I2C就绪", "SCL=", i2c_cfg.scl, "SDA=", i2c_cfg.sda)
    else
        bus = i2c_cfg.hw_id or 1
        log.info("sensor_task", "硬件I2C就绪", "id=", bus)
    end
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
    local temp, hum = read_sht30()
    local voc = read_voc()
    return temp, hum, voc
end

return sensor_task
