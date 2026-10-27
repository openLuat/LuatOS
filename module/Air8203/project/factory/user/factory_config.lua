--[[
@module  factory_config
@summary Air8203V 出厂固件固定配置模块（单版本，集中管理硬件差异）
@version 1.0.0
@date    2026.10.23
@usage
本模块集中管理 Air8203V 出厂固件的固定硬件配置（单一版本，无需版本切换）。
各业务模块（factory_app / driver）从这里读取配置。

固定配置：
- 不采集 I2C 环境传感器（DA221 仅产测读 ID，业务不轮询）
- 开机即开外置 Air510w GNSS（UART2/115200，供电 GPIO25 高电平开机）
- GNSS 无定位回退 LBS 基站定位
- 每 30s 上报一次 AirCloud 结构化 TLV（web 端 cycle:N 可覆盖）
- 无外置看门狗（Air5101 蓝牙硬件看门狗 + main.lua 内核软狗，不在此配置）
]]

local factory_config = {}

-- ==================== 固定配置（Air8203V 单版本） ====================

-- DA221 加速度 I2C（业务不采集，仅保留定义供参考；产测在 factory.lua 内）
factory_config.sensor_i2c = { mode = "hw", hw_id = 1 }
factory_config.sensor_enable = false   -- 业务不采集 I2C 环境传感器

-- LBS 基站定位：GNSS 无定位时兜底
factory_config.lbs_enable = true

-- 外置 Air510w GNSS：开机即开（常开），30s 上行统一读取
factory_config.gps = { enable = true, interval = 30, uart = 2, uartbaud = 115200 }

-- 周期结构化上报间隔（秒），web 端 cycle:N 可覆盖（最小 5s）
factory_config.report_cycle = 30

-- iRTU 网络状态灯 / 网络就绪引脚（预置 irtu.cfg 的 pins 为空时兜底）
-- 8203 板上唯一网络灯 NET_LED=GPIO27（与 factory.lua/factory_app 硬件权威一致），netled 必须复用 27；
-- netready 用 GPIO18（非专用脚）。GPIO17 为空脚、GPIO26 为音频 PA，均不可用作灯。
factory_config.net_pin = { led = 27, ready = 18 }

-- ====================================================================

-- 兼容多版本框架的接口（单版本固定返回上述值）
function factory_config.get_ver()
    return "8203"
end

function factory_config.is(ver)
    return ver == "8203"
end

function factory_config.get_sensor_i2c()
    return factory_config.sensor_i2c
end

function factory_config.get_sensor_enable()
    return factory_config.sensor_enable
end

function factory_config.get_lbs_enable()
    return factory_config.lbs_enable
end

function factory_config.get_gps()
    return factory_config.gps
end

function factory_config.get_uart485()
    return { enable = false }
end

function factory_config.get_report_cycle()
    return factory_config.report_cycle
end

function factory_config.get_net_pin()
    return factory_config.net_pin
end

function factory_config.get_wdt()
    -- Air8203V 无独立外置看门狗（蓝牙硬件看门狗由 exril_5101 在 main.lua 管理）
    return { enable = false }
end

log.info("factory_config", "Air8203V 固定配置加载完成, GNSS=开, 上报周期(s)=", factory_config.report_cycle)

return factory_config
