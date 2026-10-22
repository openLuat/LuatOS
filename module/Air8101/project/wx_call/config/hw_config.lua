--[[
@module  hw_config
@summary 智能门禁系统 - 硬件与业务配置（唯一需要按整机实际修改的文件）
@version 1.1.0
@date    2026.10.21
@usage
  本文件参数来自 Air8101B SIP 整机 10 寸工程（lib/config/evb_8101b_sip_10i.lua）：
    屏幕 HX8282 RGB 1024x600 / GT911 触摸（I2C1）/ PWM 背光 / Air1103 音频
  换屏、换底板时只改本文件。
]]

local cfg = {}

-- ============ 显示屏（lcd 核心库） ============
cfg.lcd = {
    model  = "hx8282",                 -- HX8282，10.1 寸 1024x600 RGB
    params = {
        port      = (lcd and lcd.RGB) or 0,
        pin_rst   = 5,                 -- V3.0 底板：LCD_RST = GPIO5
        direction = 0,                 -- 0 / 90 / 180 / 270
        w         = 1024,
        h         = 600,
    },
    need_buffer = true,                -- RGB 屏必须开帧缓冲，防撕裂
    -- 背光：GPIO8 使能 + PWM1(pin14) 调光。固件无 pwm 库时自动只用 GPIO
    backlight   = { pwm_ch = 1, pwm_freq = 10000, gpio = 8 },
}

-- ============ 触摸（tp 核心库） ============
cfg.tp = {
    enable       = true,
    model        = "gt911",
    port         = 1,                  -- I2C1 控制器
    pin_rst      = 28,                 -- GPIO28
    pin_int      = 7,                  -- GPIO7
    w            = 1024,
    h            = 600,
    refresh_rate = 5,                  -- 5~20，越小扫描越快
    tp_num       = 1,                  -- 单点触摸，减少 I2C 读取量
    swap_xy      = false,
    direction    = 0,
    debug        = false,              -- 触摸事件日志，排查时改 true
    -- 硬件 I2C1 不可用（固件缺 pins 库 / 引脚被占用）时，自动退回软件 I2C
    fallback     = { scl = 38, sda = 39, delay_us = 5 },
}

-- ============ 引脚功能复用（pins 核心库） ============
cfg.pins = {
    { pin = 69, func = "I2C1_SDA"  },  -- 触摸 I2C1 SDA (GPIO39)
    { pin = 7,  func = "I2C1_SCL"  },  -- 触摸 I2C1 SCL (GPIO38)
    { pin = 14, func = "PWM1"      },  -- 背光调光
    { pin = 72, func = "SPI0_CLK"  },  -- 以太网 CH390H
    { pin = 71, func = "SPI0_MOSI" },
    { pin = 6,  func = "SPI0_MISO" },
}

-- ============ 上电时序（必须在 LCD/触摸初始化前完成） ============
-- 27: PA_EN 拉低关板载功放（整机用外置 Air1103 音频，防回音）
--     若改用板载喇叭放提示音，这里要改成 level = 1
-- 52: RS485_EN 拉低；53: LAN_EN 拉高；34: SPI0_CS0 拉高
-- 55: LCD_EN 拉高后等 LDO 稳定 200ms，否则触摸 I2C 浮空、触摸初始化失败
cfg.power_on = {
    { pin = 27, dir = 0, level = 0 },
    { pin = 52, dir = 0, level = 0 },
    { pin = 55, dir = 0, level = 1, delay = 200 },
    { pin = 53, dir = 0, level = 1 },
    { pin = 34, dir = 0, level = 1 },
}

-- ============ 字体（airui hzfont） ============
cfg.font = {
    path       = "/MiSans_gb2312.ttf",   -- 固件内置优先，失败自动退回 /luadb 同名文件
    size       = 20,
    cache_size = 1024,
    antialias  = 1,
    global     = true,
}

-- ============ WiFi（wlan 核心库） ============
-- 注意：Air8101 只支持 2.4GHz！热点必须开 2.4G 频段，5G SSID 永远扫不到（日志 reason 257）
cfg.wifi = {
    ssid     = "YOUR_SSID",                      -- 现场热点名称，留空则只显示未连接
    password = "YOUR_PASSWORD",
}

-- ============ USB(UVC) 摄像头（camera 核心库） ============
cfg.camera = {
    enable         = true,              -- 只做状态检测，通话时业务层再 start
    usb_port       = 1,
    sensor_width   = 640,
    sensor_height  = 480,
    probe_interval = 30000,             -- 未接入时重新探测间隔(ms)，探测一次约 4s
}

-- ============ 通话业务 ============
cfg.call = {
    peer    = "门口机访客",              -- 对端显示名称（tc 模式可被信令覆盖）
    ring_ms = 1200,                     -- 本地演示模式的接通延时（tc 模式不使用）
}

-- ============ 微信通话（tc_iot 腾讯云） ============
-- 凭证在 tc_iot_config.lua；固件不含 tc_iot 或凭证未填时无法真正呼叫
cfg.wechat = {
    enable            = true,
    auto_answer       = false,          -- 来电自动接听（台架测试用）
    video_on_incoming = true,           -- 来电默认按视频通话界面显示
    -- 无 tc 后端时是否允许"假接通"演示（会自己计时）。量产保持 false
    local_demo        = false,

    -- 外呼登记后端（call_status_url）不可用时怎么办：
    --   false = 跳过登记，直接发 SDK 呼叫（小程序仍会收到 voip 来电，但没有“设备呼叫中”提示）
    --   true  = 严格模式，登记失败就取消呼叫（与 demo 一致）
    require_register  = false,
}

-- demo_mode = true：顶栏/首页用模拟数据展示（无 WiFi、无摄像头也能看完整界面）
cfg.demo_mode = false

cfg.version = "001.000.000"

return cfg
