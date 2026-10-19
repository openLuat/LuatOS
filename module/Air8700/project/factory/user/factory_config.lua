--[[
@module  factory_config
@summary Air8700 出厂固件版本配置模块（纯透传版，基于 Air8780 工程拆分）
@version 1.0
@date    2026.09.21
@author  李源龙
@usage
Air8700 独立工程配置。Air8700P 板载 Air700ECP（与 Air780EPM 同固件系列，代码可复用），
本版定位：串口透传 + AirCloud 连接（基础心跳上报 + LBS 基站定位上报），
不做传感器采集、不做 TTS、不做 GPS、无外置看门狗。
各业务模块从这里读取配置，烧录时如需调整只需改 DEVICE_VER。
]]

local factory_config = {}

-- ==================== 【唯一需要手动调整】版本选择 ====================
-- 本工程固定 Air8700P（Air700ECP）。如需切换回 878x，请改用 Air8780/Air8781/Air8782 工程。
factory_config.DEVICE_VER = "8700"
-- ====================================================================

-- ==================== 各版本差异配置 ====================

-- LBS 基站定位开关（Air8700 已启用基站定位上报）
factory_config.lbs_enable = {
    ["8780"]  = true,
    ["8780V"] = true,
    ["8780G"] = true,
    ["8781"]  = true,
    ["8782"]  = true,
    ["8700"]  = true,  -- 启用 LBS 基站定位上报
}

-- GPS 上报（仅 8780G 启用）
factory_config.gps = {
    ["8780"]  = { enable = false },
    ["8780V"] = { enable = false },
    ["8780G"] = { enable = true, interval = 30 }, -- 每30秒上报一次GPS（无GPS回退LBS）
    ["8781"]  = { enable = false },
    ["8782"]  = { enable = false },
    ["8700"]  = { enable = false },  -- Air700ECP 无内置GNSS
}

-- 串口配置（8782 的串口1 配置为 RS485；其他版本保持普通TTL串口）
-- uconf[i][6]=方向脚(pioXX格式)、uconf[i][7]=485超时us
factory_config.uart485 = {
    ["8780"]  = { enable = false },
    ["8780V"] = { enable = false },
    ["8780G"] = { enable = false },
    ["8781"]  = { enable = false },
    ["8782"]  = { enable = true, dir_pin = "pio26", timeout_us = 200 }, -- 方向脚GPIO26（按实际板子修改）
    ["8700"]  = { enable = false },
}

-- 周期结构化上报间隔（秒），web端 cycle:N 可覆盖
factory_config.report_cycle = {
    ["8780"]  = 180,
    ["8780V"] = 180,
    ["8780G"] = 180,
    ["8781"]  = 180,
    ["8782"]  = 180,
    ["8700"]  = 180,
}

-- ==================== 外置硬件看门狗（Air153C/Air153D） ====================
-- 5个版本板子均带 Air153 外置看门狗芯片：GPIO → NPN → WTDOG
-- 喂狗引脚：默认 AGPIO24（8202G系列/江访8780工程均用GPIO24），
--           8781/8782 成品板请按实际原理图确认（若不同请修改 pin）
-- 喂狗周期：exair153x_wdt 要求 >=150s（Air153C默认180s；Air153D超时240s由硬件STRAP决定）
-- 注意：Air8700 板载【无】外置看门狗，wdt 配置 disable（仅保留软狗）
factory_config.wdt = {
    ["8780"]  = { enable = true, pin = 24, period = 180 },
    ["8780V"] = { enable = true, pin = 24, period = 180 },
    ["8780G"] = { enable = true, pin = 24, period = 180 },
    ["8781"]  = { enable = true, pin = 24, period = 180 },
    ["8782"]  = { enable = true, pin = 24, period = 180 },
    ["8700"]  = { enable = false, pin = 24, period = 180 }, -- 无外置看门狗
}

-- ==================== 便捷读取接口 ====================

-- 当前版本
function factory_config.get_ver()
    return factory_config.DEVICE_VER
end

-- 当前版本是否是指定版本
function factory_config.is(ver)
    return factory_config.DEVICE_VER == ver
end

-- LBS 定位是否启用
function factory_config.get_lbs_enable()
    return factory_config.lbs_enable[factory_config.DEVICE_VER] ~= false
end

-- 获取当前版本GPS配置
function factory_config.get_gps()
    return factory_config.gps[factory_config.DEVICE_VER]
end

-- 获取当前版本485配置
function factory_config.get_uart485()
    return factory_config.uart485[factory_config.DEVICE_VER]
end

-- 获取当前版本上报周期
function factory_config.get_report_cycle()
    return factory_config.report_cycle[factory_config.DEVICE_VER]
end

-- 获取当前版本外置看门狗配置
function factory_config.get_wdt()
    return factory_config.wdt[factory_config.DEVICE_VER]
end

log.info("factory_config", "当前版本:", factory_config.DEVICE_VER)

return factory_config
