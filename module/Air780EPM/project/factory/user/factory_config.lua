--[[
@module  factory_config
@summary Air780EPM 出厂固件固定硬件配置
@version 2.0
@date    2026.10.14
@usage
本工程为 Air780EPM 开发板单一硬件配置，不再区分型号/版本：
  - 硬件 I2C1 外接 SHT30(0x44) 温湿度 + VOC(0x1A)，外部上拉、禁用内部上拉
  - LBS 基站定位
  - 每 180 秒结构化上报（web 端 cycle:N 可覆盖）
  - 串口透传
  - 仅内核软狗（main.lua 中 wdt），无外置看门狗、无音频 codec、无 GNSS
]]

local factory_config = {}

-- 传感器 I2C 总线：Air780EPM 开发板使用硬件 I2C1（PIN66=SDA / PIN67=SCL，外部上拉）
factory_config.sensor_i2c = { mode = "hw", hw_id = 1 }

-- 传感器采集总开关（false=禁用，sensor_task.get_env 直接返回 nil）
factory_config.sensor_enable = true

-- LBS 基站定位开关
factory_config.lbs_enable = true

-- GPS/GNSS 上报（Air780EPM 无内置 GNSS，关闭）
factory_config.gps = { enable = false }

-- 周期结构化上报间隔（秒），web端 cycle:N 可覆盖
factory_config.report_cycle = 180

-- ==================== iRTU 网络状态灯/网络就绪引脚（兜底） ====================
-- 仅当预置 irtu.cfg 的 pins 为空时生效（预置 cfg 已配置 netled=17/netready=26，正常走预置值）
factory_config.net_pin = { led = 17, ready = 26 }

-- ==================== 便捷读取接口 ====================

-- 获取当前 I2C 配置
function factory_config.get_sensor_i2c()
    return factory_config.sensor_i2c
end

-- 传感器采集是否启用
function factory_config.get_sensor_enable()
    return factory_config.sensor_enable ~= false
end

-- LBS 定位是否启用
function factory_config.get_lbs_enable()
    return factory_config.lbs_enable ~= false
end

-- 获取 GPS/GNSS 配置
function factory_config.get_gps()
    return factory_config.gps
end

-- 获取上报周期
function factory_config.get_report_cycle()
    return factory_config.report_cycle
end

-- 获取网络状态灯/就绪引脚
function factory_config.get_net_pin()
    return factory_config.net_pin
end

log.info("factory_config", "Air780EPM 固定配置已加载")

return factory_config
