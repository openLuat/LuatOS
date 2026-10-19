--[[
@module  factory_config
@summary Air780EGH/EGP/EGG 出厂固件固定硬件配置（内置 GNSS 核心板）
@version 2.0
@date    2026.10.14
@usage
本工程为 Air780EGH / Air780EGP / Air780EGG 核心板单一硬件配置，不再区分型号/版本：
  - 开机即打开模组内置 GNSS（固定 UART2 / 115200，open 时自动 pm.power(pm.GPS,true)）
  - 仅一条上报通道：每 30 秒上报一次，含信号/模组型号(rtos.bsp)/IMEI/时间戳/CPU温度 + 定位
  - 定位 GNSS 优先，无定位时回退 LBS 基站定位
  - 无任何 I2C 传感器
  - 串口透传
  - 仅内核软狗（main.lua 中 wdt），无外置看门狗、无音频 codec
注意：本工程内置 GNSS 独占 UART2，main.lua 已置 _G.IRTU_DISABLE_UART2=true 防止 iRTU 抢占。
]]

local factory_config = {}

-- LBS 基站定位开关（GNSS 无定位时兜底）
factory_config.lbs_enable = true

-- 内置 GPS/GNSS：enable 决定开机是否打开内置 GNSS（常开）；上报周期统一由 report_cycle 承担
factory_config.gps = { enable = true }

-- 唯一周期上报间隔（秒），web端 cycle:N 可覆盖
-- 该通道承载：信号/模组型号/IMEI/时间戳/CPU温度 + GNSS/LBS 定位
factory_config.report_cycle = 30

-- ==================== iRTU 网络状态灯/网络就绪引脚（兜底） ====================
-- 仅当预置 irtu.cfg 的 pins 为空时生效（预置 cfg 已配置 netled=17/netready=26，正常走预置值）
factory_config.net_pin = { led = 17, ready = 26 }

-- ==================== 便捷读取接口 ====================

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

log.info("factory_config", "Air780EGH/EGP/EGG 固定配置已加载（内置GNSS常开，单通道30s上报）")

return factory_config
