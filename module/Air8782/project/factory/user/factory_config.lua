--[[
@module  factory_config
@summary 出厂固件版本配置模块（集中管理6个版本的差异）
@version 1.1
@date    2026.09.21
@author  李源龙
@usage
本模块集中管理 Air878x/Air8700 出厂固件 6 个版本的全部差异，各业务模块从这里读取配置，
烧录时只需调整 DEVICE_VER 一个变量即可切换版本。

版本列表：
  1. "8780"  ：8780 全系（P/H/N/U），硬件I2C + 定时上报 + 串口透传（默认基准版）
  2. "8780V" ：8780V（Air780EHV），在8780基础上 + 每10秒TTS播报"上海合宙欢迎你"
  3. "8780G" ：8780G（Air780EGP/EGG），在8780基础上 + 开机开GPS，每30秒上报GPS
               （GPS定位失败自动回退 LBS 基站定位）
  4. "8781"  ：8781P 成品板，GPIO 模拟软件I2C（无硬件I2C引脚引出）
  5. "8782"  ：8782P 成品板，软件I2C + 串口1配置为 RS485
  6. "8700"  ：Air8700P（Air700ECP），仅串口透传 + AirCloud 基础心跳上报，
               不采集传感器、不做TTS/GPS/LBS、无外置看门狗
]]

local factory_config = {}

-- ==================== 【唯一需要手动调整】版本选择 ====================
-- 可选值："8780" / "8780V" / "8780G" / "8781" / "8782" / "8700"
-- 默认 "8782"
-- 说明：8780V=Air780EHV、8780G=Air780EGP/EGG，其余 8780 全系/8781/8782 主控均为 Air780EPM，
--       8700 板载 Air700ECP（与 Air780EPM 同固件系列），仅透传。
--       无法靠 hmeta.model() 自动区分 8781/8782，因此统一手动指定版本。
factory_config.DEVICE_VER = "8782"
-- ====================================================================

-- ==================== 各版本差异配置 ====================

-- 传感器 I2C 总线
factory_config.sensor_i2c = {
    ["8780"]  = { mode = "hw", hw_id = 1 },                    -- 硬件I2C id=1
    ["8780V"] = { mode = "hw", hw_id = 1 },                    -- 硬件I2C id=1
    ["8780G"] = { mode = "hw", hw_id = 1 },                    -- 硬件I2C id=1
    ["8781"]  = { mode = "sw", scl = 26, sda = 28, delay = 5 }, -- 软件I2C：GPIO26=SCL、GPIO28=SDA（按实际接线修改）
    ["8782"]  = { mode = "sw", scl = 27, sda = 21, delay = 5 }, -- 软件I2C：GPIO27=SCL、GPIO21=SDA（按实际接线修改）
    ["8700"]  = { mode = "disable" },                          -- 仅透传，不采集传感器
}

-- 传感器采集总开关（false=禁用，sensor_task.get_env 直接返回 nil）
factory_config.sensor_enable = {
    ["8780"]  = true,
    ["8780V"] = true,
    ["8780G"] = true,
    ["8781"]  = true,
    ["8782"]  = true,
    ["8700"]  = false,  -- 仅透传，不采集
}

-- LBS 基站定位开关（false=禁用，不做 LBS）
factory_config.lbs_enable = {
    ["8780"]  = true,
    ["8780V"] = true,
    ["8780G"] = true,
    ["8781"]  = true,
    ["8782"]  = true,
    ["8700"]  = false,  -- 仅透传，不做 LBS
}

-- TTS 播报（仅 8780V 启用）
factory_config.tts = {
    ["8780"]  = { enable = false },
    ["8780V"] = { enable = true, text = "上海合宙欢迎你", interval = 10 }, -- 每10秒播报一次
    ["8780G"] = { enable = false },
    ["8781"]  = { enable = false },
    ["8782"]  = { enable = false },
    ["8700"]  = { enable = false },  -- Air700ECP 无 TTS
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
-- 878x 板子均带 Air153 外置看门狗芯片：GPIO → NPN → WTDOG
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

-- 获取当前版本I2C配置
function factory_config.get_sensor_i2c()
    return factory_config.sensor_i2c[factory_config.DEVICE_VER]
end

-- 传感器采集是否启用
function factory_config.get_sensor_enable()
    return factory_config.sensor_enable[factory_config.DEVICE_VER] ~= false
end

-- LBS 定位是否启用
function factory_config.get_lbs_enable()
    return factory_config.lbs_enable[factory_config.DEVICE_VER] ~= false
end

-- 获取当前版本TTS配置
function factory_config.get_tts()
    return factory_config.tts[factory_config.DEVICE_VER]
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
