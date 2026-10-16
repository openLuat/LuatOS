--[[
@module  factory_config
@summary Air780EGH/EGP/EGG 出厂固件固定硬件配置（内置 GNSS 核心板）
@version 2.0
@date    2026.10.14
@usage
本工程为 Air780EGH / Air780EGP / Air780EGG 核心板单一硬件配置，不再区分型号/版本：
  - 开机即打开模组内置 GNSS（固定 UART2 / 115200，open 时自动 pm.power(pm.GPS,true)）
  - 每 30 秒上报一次定位（GNSS 优先，无定位时回退 LBS 基站定位）
  - LBS 基站定位作为 GNSS 无定位时的兜底
  - 不采集 I2C 传感器（无 SHT30 / VOC）
  - 串口透传
  - 仅内核软狗（main.lua 中 wdt），无外置看门狗、无音频 codec
注意：本工程内置 GNSS 独占 UART2，main.lua 已置 _G.IRTU_DISABLE_UART2=true 防止 iRTU 抢占。
]]

local factory_config = {}

-- 传感器 I2C 总线配置（本工程禁用传感器，保留字段仅为模块接口兼容，不会初始化 I2C）
factory_config.sensor_i2c = { mode = "hw", hw_id = 1 }

-- 传感器采集总开关：EGH/EGP/EGG 出厂固件不采集 I2C 传感器
factory_config.sensor_enable = false

-- LBS 基站定位开关（GNSS 无定位时兜底）
factory_config.lbs_enable = true

-- 内置 GPS/GNSS：开机即开，每 30 秒上报定位
factory_config.gps = { enable = true, interval = 30 }

-- 周期结构化上报间隔（秒），web端 cycle:N 可覆盖
-- 该周期上报承载信号/IMEI/时间戳/CPU温度/LBS；GNSS 定位由 gps.interval 独立每 30 秒上报
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

log.info("factory_config", "Air780EGH/EGP/EGG 固定配置已加载（内置GNSS 30s，不采传感器）")

return factory_config
