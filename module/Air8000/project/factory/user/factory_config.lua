--[[
@module  factory_config
@summary Air8000 出厂固件版本配置模块（集中管理6个版本的差异）
@version 1.0
@date    2026.10.16
@usage
本模块集中管理 Air8000 系列出厂固件 6 个版本的全部差异，各业务模块从这里读取配置，
烧录时只需调整 DEVICE_VER 一个变量即可切换版本。

版本列表（对应 OTP 中 PROD 型号族）：
  1. "8000"  ：Air8000/A/W/G/T/U/N/GU/GN/XB/DB，4G 默认网卡 + 硬件I2C0 + 定时上报（默认基准版）
  2. "8000T" ：TTS 播报版，在8000基础上 + 每10秒 exaudio 播报"上海合宙欢迎你"（es8311）
  3. "8000G" ：GNSS 定位版，在8000基础上 + 开机开GNSS（默认串口2/115200），每30秒上报
               （GNSS 定位失败自动回退 LBS 基站定位）
  4. "8000W" ：WiFi STA 网卡版（Air8101 WiFi 平台，exnetif 配 WIFI 优先）
  5. "8000D" ：SPI 外挂 CH390H 以太网版（exnetif 配 ETHERNET，pwrpin=140/spi1/cs=12）
  6. "8000M" ：多网融合版（以太网 → WiFi → 4G 按优先级自动切换）

引脚分配依据 demo/pins/pins_Air8000.json，已规避：
  - LCD 屏 pin25~29 / pin36（LCD_RST）
  - I2S pin18~22
  - 开发板音频功放 pa_ctrl=162 / dac_ctrl=164（核心板为 17/16）
  - CH390 以太网供电 pin140 / spi1 pin38,39 / cs=12
]]

local factory_config = {}

-- ==================== 【唯一需要手动调整】版本选择 ====================
-- 可选值："8000" / "8000T" / "8000G" / "8000W" / "8000D" / "8000M"
-- 本工程默认 "8000"（Air8000 4G 基准版）
-- 说明：无法靠 hmeta.model() 自动区分同一固件系列下的成品形态，统一手动指定版本。
factory_config.DEVICE_VER = "8000"
-- ====================================================================

-- ==================== 各版本差异配置 ====================

-- 传感器 I2C 总线
-- Air8000 硬件 I2C0 = pin80(SCL)/pin81(SDA)；I2C1 = pin66/pin67
-- 软件 I2C：Air8000 软I2C示例 GPIO1=pin31(SDA)/GPIO2=pin30(SCL)
factory_config.sensor_i2c = {
    ["8000"]  = { mode = "hw", hw_id = 0 },                       -- 硬件I2C id=0（pin80/81）
    ["8000T"] = { mode = "hw", hw_id = 0 },                       -- 硬件I2C id=0
    ["8000G"] = { mode = "hw", hw_id = 0 },                       -- 硬件I2C id=0
    ["8000W"] = { mode = "hw", hw_id = 0 },                       -- 硬件I2C id=0
    ["8000D"] = { mode = "hw", hw_id = 0 },                       -- 硬件I2C id=0
    ["8000M"] = { mode = "hw", hw_id = 0 },                       -- 硬件I2C id=0
}

-- 传感器采集总开关（false=禁用，sensor_task.get_env 直接返回 nil）
factory_config.sensor_enable = {
    ["8000"]  = true,
    ["8000T"] = false,  -- TTS 版主打播报，不采集 I2C 传感器
    ["8000G"] = false,  -- GNSS 版主打定位，不采集 I2C 传感器
    ["8000W"] = true,
    ["8000D"] = true,
    ["8000M"] = true,
}

-- LBS 基站定位开关（false=禁用，不做 LBS）
factory_config.lbs_enable = {
    ["8000"]  = true,
    ["8000T"] = true,
    ["8000G"] = true,
    ["8000W"] = true,
    ["8000D"] = true,
    ["8000M"] = true,
}

-- TTS 播报（仅 8000T 启用，es8311 + exaudio 新框架）
factory_config.tts = {
    ["8000"]  = { enable = false },
    ["8000T"] = { enable = true, text = "上海合宙欢迎你", interval = 10 }, -- 每10秒播报一次
    ["8000G"] = { enable = false },
    ["8000W"] = { enable = false },
    ["8000D"] = { enable = false },
    ["8000M"] = { enable = false },
}

-- GNSS 上报（仅 8000G 启用；Air8000 默认 uart=2/uartbaud=115200）
factory_config.gps = {
    ["8000"]  = { enable = false },
    ["8000T"] = { enable = false },
    ["8000G"] = { enable = true, interval = 30, uart = 2, uartbaud = 115200 }, -- 每30秒上报一次GNSS（失败回退LBS）
    ["8000W"] = { enable = false },
    ["8000D"] = { enable = false },
    ["8000M"] = { enable = false },
}

-- 网卡选择（供 netdrv_device.lua 分流）：4g/wifi/eth/multiple
factory_config.netdev = {
    ["8000"]  = "4g",       -- Air8000 内核默认网卡 socket.LWIP_GP
    ["8000T"] = "4g",
    ["8000G"] = "4g",
    ["8000W"] = "wifi",     -- WiFi STA：socket.LWIP_STA
    ["8000D"] = "eth",      -- SPI 外挂 CH390H：socket.LWIP_ETH
    ["8000M"] = "multiple", -- 多网优先级：ETHERNET → WIFI → LWIP_GP
}

-- AirCloud 设备类型 device_type：4G(Air8000)=1 / WiFi(Air8101)=2 / PC模拟器=9
factory_config.device_type = {
    ["8000"]  = 1,
    ["8000T"] = 1,
    ["8000G"] = 1,
    ["8000W"] = 2,
    ["8000D"] = 1,
    ["8000M"] = 1,
}

-- 串口配置（如某成品板需把串口1配置为 RS485，将对应版本置 enable=true）
-- uconf[i][6]=方向脚(pioXX格式)、uconf[i][7]=485超时us
-- 默认全版本关闭；485 方向脚选用 GPIO153(pin52)，规避前述占用
factory_config.uart485 = {
    ["8000"]  = { enable = false },
    ["8000T"] = { enable = false },
    ["8000G"] = { enable = false },
    ["8000W"] = { enable = false },
    ["8000D"] = { enable = false },
    ["8000M"] = { enable = false }, -- 如需 RS485：enable=true, dir_pin="pio153", timeout_us=200
}

-- 周期结构化上报间隔（秒），AirCloud 下行 cycle:秒数 可覆盖
factory_config.report_cycle = {
    ["8000"]  = 180,
    ["8000T"] = 180,
    ["8000G"] = 180,
    ["8000W"] = 180,
    ["8000D"] = 180,
    ["8000M"] = 180,
}

-- ==================== 网络状态灯/网络就绪引脚（兜底） ====================
-- 仅当预置 irtu.cfg 的 pins 为空时生效；避开 LCD/I2S/音频/CH390 占用
-- led=GPIO16(pin83)、ready=GPIO17(pin82)
factory_config.net_pin = {
    ["8000"]  = { led = 16, ready = 17 },
    ["8000T"] = { led = 16, ready = 17 },
    ["8000G"] = { led = 16, ready = 17 },
    ["8000W"] = { led = 16, ready = 17 },
    ["8000D"] = { led = 16, ready = 17 },
    ["8000M"] = { led = 16, ready = 17 },
}

-- 产测/状态指示 LED（factory_app 用）：GPIO21(pin24)，避开 pin27(LCD_RST)
factory_config.led_pin = {
    ["8000"]  = 21,
    ["8000T"] = 21,
    ["8000G"] = 21,
    ["8000W"] = 21,
    ["8000D"] = 21,
    ["8000M"] = 21,
}

-- ==================== 外置硬件看门狗（Air153C/Air153D） ====================
-- 喂狗引脚：GPIO160(pin96)，经 exair153x_wdt.init 驱动
-- 喂狗周期：exair153x_wdt 要求 >=150s（Air153C默认180s；Air153D超时240s由硬件STRAP决定）
factory_config.wdt = {
    ["8000"]  = { enable = true, pin = 160, period = 180 },
    ["8000T"] = { enable = true, pin = 160, period = 180 },
    ["8000G"] = { enable = true, pin = 160, period = 180 },
    ["8000W"] = { enable = true, pin = 160, period = 180 },
    ["8000D"] = { enable = true, pin = 160, period = 180 },
    ["8000M"] = { enable = true, pin = 160, period = 180 },
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

-- 获取当前版本GNSS配置
function factory_config.get_gps()
    return factory_config.gps[factory_config.DEVICE_VER]
end

-- 获取当前版本网卡类型（4g/wifi/eth/multiple）
function factory_config.get_netdev()
    return factory_config.netdev[factory_config.DEVICE_VER]
end

-- 获取当前版本 AirCloud device_type
function factory_config.get_device_type()
    return factory_config.device_type[factory_config.DEVICE_VER]
end

-- 获取当前版本485配置
function factory_config.get_uart485()
    return factory_config.uart485[factory_config.DEVICE_VER]
end

-- 获取当前版本上报周期
function factory_config.get_report_cycle()
    return factory_config.report_cycle[factory_config.DEVICE_VER]
end

-- 获取当前版本网络状态灯/就绪引脚
function factory_config.get_net_pin()
    return factory_config.net_pin[factory_config.DEVICE_VER]
end

-- 获取当前版本产测LED引脚
function factory_config.get_led_pin()
    return factory_config.led_pin[factory_config.DEVICE_VER]
end

-- 获取当前版本外置看门狗配置
function factory_config.get_wdt()
    return factory_config.wdt[factory_config.DEVICE_VER]
end

log.info("factory_config", "当前版本:", factory_config.DEVICE_VER)

return factory_config
