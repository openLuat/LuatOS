--[[
@module  factory_config
@summary Air8000 出厂固件版本配置模块（集中管理3个型号的差异）
@version 1.2
@date    2026.10.22
@usage
本模块集中管理 Air8000 系列出厂固件 3 个型号的全部差异，各业务模块从这里读取配置，
烧录时只需调整 DEVICE_VER 一个变量即可切换型号。

型号列表（对应 OTP 中 PROD 型号 / hmeta.model() 硬件型号）：
  1. "8000A"：传感器+GNSS 组合版（默认），开机即打开内置 GNSS，每30秒采集一次
              I2C 传感器数据并与 GPS 定位一起上报；无 GPS 定位时回退 LBS 基站定位
  2. "8000D"：纯 GNSS 定位版，开机打开 GPS，每30秒上报一次定位（基本同 Air8780G，
              GPS 失败回退 LBS），不采集 I2C 传感器
  3. "8000T"：单 4G 传感器传输版（同 Air8780P/Air8780 基准版），不开 GPS，
              I2C 传感器数据按周期（默认180秒）定时上报，定位走 LBS

三个型号均为 4G 网卡（socket.LWIP_GP）。

引脚分配依据 demo/pins/pins_Air8000.json，已规避：
  - LCD 屏 pin25~29 / pin36（LCD_RST）
  - I2S pin18~22
  - 开发板音频功放 pa_ctrl=162 / dac_ctrl=164（核心板为 17/16）
]]

local factory_config = {}

-- ==================== 【唯一需要手动调整】型号选择 ====================
-- 可选值："8000A" / "8000D" / "8000T"
-- 本工程默认 "8000A"（传感器+GNSS 组合版）；烧录其他型号时改为对应值，
-- 同时把 main.lua 顶部 PROJECT 切为 "Air8000A" / "Air8000D" / "Air8000T"。
factory_config.DEVICE_VER = "8000A"
-- ====================================================================

-- ==================== 各型号差异配置 ====================

-- 传感器 I2C 总线
-- Air8000 硬件 I2C0 = pin80(SCL)/pin81(SDA)；8000D 不采集但保留配置
factory_config.sensor_i2c = {
    ["8000A"] = { mode = "hw", hw_id = 0 }, -- 硬件I2C id=0（pin80/81）
    ["8000D"] = { mode = "hw", hw_id = 0 }, -- 硬件I2C id=0
    ["8000T"] = { mode = "hw", hw_id = 0 }, -- 硬件I2C id=0
}

-- 传感器采集总开关（false=禁用，sensor_task.get_env 直接返回 nil）
factory_config.sensor_enable = {
    ["8000A"] = true,  -- 组合版：每30秒采集温湿度/VOC 与 GPS 一起上报
    ["8000D"] = false, -- 纯定位版主打定位，不采集 I2C 传感器（同 8780G）
    ["8000T"] = true,  -- 单4G传感器版：定时采集上报（同 8780P 基准版）
}

-- LBS 基站定位开关（GNSS 失锁时回退 LBS，三个型号均开启）
factory_config.lbs_enable = {
    ["8000A"] = true,
    ["8000D"] = true,
    ["8000T"] = true,
}

-- TTS 播报（三个型号均不启用；如后续出 TTS 型号再加 enable=true 项）
factory_config.tts = {
    ["8000A"] = { enable = false },
    ["8000D"] = { enable = false },
    ["8000T"] = { enable = false },
}

-- GNSS 上报
-- 8000A/8000D 均开机常开 GNSS（默认串口2/115200），每30秒一帧；
-- combo=true 时该帧同时携带 I2C 传感器数据（仅 8000A）；8000T 不启用 GNSS
factory_config.gps = {
    ["8000A"] = { enable = true, interval = 30, uart = 2, uartbaud = 115200, combo = true }, -- 30秒：传感器+GPS组合帧（无GPS走LBS）
    ["8000D"] = { enable = true, interval = 30, uart = 2, uartbaud = 115200, combo = false }, -- 30秒纯定位帧（同8780G）
    ["8000T"] = { enable = false },
}

-- 网卡选择（供 netdrv_device.lua 分流）：三个型号均为 4g
factory_config.netdev = {
    ["8000A"] = "4g", -- Air8000 内核默认网卡 socket.LWIP_GP
    ["8000D"] = "4g",
    ["8000T"] = "4g",
}

-- AirCloud 设备类型 device_type：4G=1 / WiFi(Air8101)=2 / PC模拟器=9
factory_config.device_type = {
    ["8000A"] = 1,
    ["8000D"] = 1,
    ["8000T"] = 1,
}

-- 串口配置（如需把串口1配置为 RS485，将对应型号置 enable=true）
-- uconf[i][6]=方向脚(pioXX格式)、uconf[i][7]=485超时us
-- 默认全型号关闭；485 方向脚选用 GPIO153(pin52)，规避前述占用
factory_config.uart485 = {
    ["8000A"] = { enable = false },
    ["8000D"] = { enable = false }, -- 如需 RS485：enable=true, dir_pin="pio153", timeout_us=200
    ["8000T"] = { enable = false },
}

-- 周期结构化上报间隔（秒），AirCloud 下行 cycle:秒数 可覆盖
-- 注意：8000A 为30秒组合帧（gps.combo=true），不再启动该180秒结构化定时器，
--       此值对 8000A 不生效；8000D/8000T 保持 180 秒周期结构化上报
factory_config.report_cycle = {
    ["8000A"] = 180,
    ["8000D"] = 180,
    ["8000T"] = 180,
}

-- ==================== 网络状态灯/网络就绪引脚（兜底） ====================
-- 仅当预置 irtu.cfg 的 pins 为空时生效；避开 LCD/I2S/音频占用
-- led=GPIO16(pin83)、ready=GPIO17(pin82)
factory_config.net_pin = {
    ["8000A"] = { led = 16, ready = 17 },
    ["8000D"] = { led = 16, ready = 17 },
    ["8000T"] = { led = 16, ready = 17 },
}

-- 状态指示 LED（factory_app 用）：GPIO21(pin24)，避开 pin27(LCD_RST)
factory_config.led_pin = {
    ["8000A"] = 21,
    ["8000D"] = 21,
    ["8000T"] = 21,
}

-- ==================== 外置硬件看门狗（Air153C/Air153D） ====================
-- 喂狗引脚：GPIO160(pin96)，经 exair153x_wdt.init 驱动
-- 喂狗周期：exair153x_wdt 要求 >=150s（Air153C默认180s；Air153D超时240s由硬件STRAP决定）
factory_config.wdt = {
    ["8000A"] = { enable = true, pin = 160, period = 180 },
    ["8000D"] = { enable = true, pin = 160, period = 180 },
    ["8000T"] = { enable = true, pin = 160, period = 180 },
}

-- ==================== 便捷读取接口 ====================

-- 当前型号
function factory_config.get_ver()
    return factory_config.DEVICE_VER
end

-- 当前型号是否是指定型号
function factory_config.is(ver)
    return factory_config.DEVICE_VER == ver
end

-- 获取当前型号I2C配置
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

-- 获取当前型号TTS配置
function factory_config.get_tts()
    return factory_config.tts[factory_config.DEVICE_VER]
end

-- 获取当前型号GNSS配置
function factory_config.get_gps()
    return factory_config.gps[factory_config.DEVICE_VER]
end

-- 获取当前型号网卡类型（4g/wifi/eth/multiple）
function factory_config.get_netdev()
    return factory_config.netdev[factory_config.DEVICE_VER]
end

-- 获取当前型号 AirCloud device_type
function factory_config.get_device_type()
    return factory_config.device_type[factory_config.DEVICE_VER]
end

-- 获取当前型号485配置
function factory_config.get_uart485()
    return factory_config.uart485[factory_config.DEVICE_VER]
end

-- 获取当前型号上报周期
function factory_config.get_report_cycle()
    return factory_config.report_cycle[factory_config.DEVICE_VER]
end

-- 获取当前型号网络状态灯/就绪引脚
function factory_config.get_net_pin()
    return factory_config.net_pin[factory_config.DEVICE_VER]
end

-- 获取当前型号状态指示 LED 引脚
function factory_config.get_led_pin()
    return factory_config.led_pin[factory_config.DEVICE_VER]
end

-- 获取当前型号外置看门狗配置
function factory_config.get_wdt()
    return factory_config.wdt[factory_config.DEVICE_VER]
end

log.info("factory_config", "当前型号:", factory_config.DEVICE_VER)

return factory_config
