--[[
@module  config.evb_8000a_3i5_v0
@summary Air8000A trunkey 开发板 3.5寸480x320 SPI屏 配置文件
@version 1.1
@date    2026.06.01
@author  江访
@usage
所有 boolean 字段只写 = true 表示开启，不写即视为关闭（无需写 = false）
具体包含哪些参数，如何填写参考：template.lua
]]
return {
    -- ===== 顶层信息 =====
    name = "EVB_Air8000A_3inch5_480x320_000_V020",  -- 项目命名: {类型}_{芯片}_{尺寸}_{版本}
    chip = "Air8000",                                 -- 主控芯片: 4G + WiFi + GPS + SPI屏（兼容 Air8000A/D）
    baseboard = "Air8000A trunkey 开发板 V020",       -- 底板型号

    -- ===== 引脚功能复用 =====
    pins = {
        { pin = 31, func = "PWM0" },  -- PWM0: 背光调光
    },

    -- ===== GPIO 上电时序: LCD供电 + I2C0总线供电 + TP上拉 =====
    -- 注意: GPIO164 是 I2C0 总线供电使能脚(TP/音频/摄像头共用 I2C0)，也是 ES8311 的 AUDIO_EN
    -- 必须先输出高拉亮，否则 TP/音频/摄像头都无法初始化
    power_on = {
        { pin = 141, dir = 0, level = 1              },  -- LCD 供电开
        { pin = 147, dir = 1, level = 1              },  -- TP I2C SDA 上拉
        { pin = 164, dir = 0, level = 1, delay = 100 }, -- I2C0总线供电开(输出高) + AUDIO_EN，等待稳定
        { pin = 17,  dir = 1, level = 1              },
        { pin = 16,  dir = 1, level = 1              },  -- 最后一步等外设稳定
        -- PA_EN=GPIO162 由 exaudio.setup 内部控制（防 pop 音时序），此处不提前拉高
    },

    -- ===== 硬件配置 =====
    hw = {
        -- 屏幕: ST7796 SPI 3.5寸 480×320 横屏
        lcd = {
            model = "lcd_st7796",
            params = {
                port = lcd.HWID_0,       -- SPI 端口 0
                pin_rst = 36,            -- 复位引脚
                direction = 1,           -- 90° 旋转（横屏）
                w = 480,                 -- 水平分辨率
                h = 320,                 -- 竖直分辨率
                xoffset = 0,             -- X 像素偏移
                yoffset = 0,             -- Y 像素偏移
                bus_speed = 80000000,    -- SPI 时钟 80MHz
            },
            need_buffer = false,         -- SPI 屏不需要帧缓冲，直刷更快
            screen_size = 3.5,           -- 3.5寸屏
            font = { size = 14 },        -- 低分屏用 14 号字
            backlight = {
                pwm_ch = 0,              -- PWM 通道 0
                pwm_freq = 1000,         -- 1kHz
            },
        },
        -- 触摸: GT911 I2C 端口0，不复位
        tp = {
            model = "tp_gt911",
            params = {
                port = 0,                -- I2C 端口 0
                pin_rst = 0xff,          -- 0xff 表示不复位（底板无需复位引脚）
                pin_int = gpio.WAKEUP0,  -- 唤醒引脚用作中断
                i2c_speed = i2c.SLOW,    -- 低速 I2C（推荐）
                pwr_delay = 100,         -- I2C 上电后等待 100ms
            },
        },
        -- 音频硬件: ES8311 编解码 + 功放（应用工厂-录音播放）
        -- AUDIO_EN=GPIO164(dac_ctrl), PA_EN=GPIO162(pa_ctrl)
        -- I2C0 控制(i2c_id=0), I2S 数据
        -- Air8000 使用旧框架(audio)，AMR_NB 录音无需 audio_v2（audio_mode 不填，走默认）
        audio = {
            model = "es8311",          -- 音频编解码芯片
            i2c_id = 0,                -- I2C0 控制总线
            pa_ctrl = 162,             -- PA_EN 功放使能 GPIO
            dac_ctrl = 164,            -- AUDIO_EN 编解码使能 GPIO
            pa_on_level = 1,           -- PA 高电平使能
            dac_on_level = 1,          -- CODEC 高电平使能
            -- audio_mode 留空: Air8000 默认旧框架(audio)，AMR_NB 录音可直接用
            i2s_sample = 8000,         -- I2S 采样率（AMR_NB=8k）
            bits_per_sample = 16,      -- 采样位深
            play_vol = 70,             -- 默认播放音量(0~100)
            mic_vol = 70,              -- 默认录音音量(0~100)
            record_format = "AMR_NB",  -- 录音格式
            max_record_time = 60,      -- 最大录音时长(秒)
        },
    },

    -- ===== 功能开关（只写 = true 的项）=====
    features = {
        net_4g = true,                   -- 启用 4G 蜂窝网络（Air8000A 内置 4G）
        wifi = true,                     -- 启用 WiFi
        sd_card = true,                  -- 启用 SD/TF 卡（需配 storage.sd_card）
        app_factory = true,              -- 启用"应用工厂"内置应用
        speaker = true,                  -- 启用喇叭（ES8311 播放）
        mic = true,                      -- 启用麦克风（ES8311 录音）
    },

    -- ===== 统一网络配置（优先级从高到低）=====
    network = {
        { type = "wifi_native" },        -- 自带 WiFi 优先
        { type = "4g_native" },          -- 自带 4G 兜底
    },

    -- ===== UI 显示控制（只写 = true 的项）=====
    ui = {
        show_4g_icon = true,             -- 桌面顶栏 4G 图标 ← 配 net_4g 时打开
        show_wifi_icon = true,           -- 桌面顶栏 WiFi 图标 ← 配 wifi 时打开
        show_brightness_slider = true,   -- 设置页亮度滑块
        show_storage_settings = true,    -- 设置页存储空间入口
        show_app_factory = true,         -- 桌面显示"应用工厂"入口 ← 配 app_factory 时打开
    },

    -- ===== 存储设备: SD/TF 卡 =====
    storage = {
        sd_card = {
            spi_id = 1,                  -- SPI 接口 ID
            pin_cs = 20,                 -- 片选 CS 引脚
            speed = 40000000,            -- SPI 时钟频率 Hz
        },
    },
}
