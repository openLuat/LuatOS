--[[
@module  config.eng_1780h_4i_v1
@summary Air1780H 引擎主机 4寸320x480 SPI屏(ST7796) + WiFi(airlink/6205) + ES8311 + SD + NAND 配置文件
@version 1.0
@date    2026.08.19
@author  江访
@usage
所有 boolean 字段只写 = true 表示开启，不写即视为关闭（无需写 = false）
具体包含哪些参数，如何填写参考：template.lua

注意：
1. Air1780H 为纯 MCU（Air780E 系列去 4G），无内置 WiFi，WiFi 依赖外挂 6205 模组经 AirLink over SPI0。
2. AIRLINK_IRQ/WAKEUP 引脚需在 net_manager 初始化前经 airlink.config 单独配置。
3. 与 eng_1780h_4i_v0 的区别：LCD 从 ST6201(480x272) 换为 ST7796(320x480)，新增 I2S/9按键/电池。
]]
return {
    -- ===== 顶层信息 =====
    name = "Engine_Air1780H_4inch_320x480_000_V001",  -- 项目命名: {类型}_{芯片}_{尺寸}_{分辨率}_{版本}
    chip = "Air1780H",                             -- 主控芯片: 纯MCU(Air780E系列去4G) + SPI屏 + 外挂WiFi
    baseboard = "合宙引擎 AIR1780H V001 4寸",      -- 底板型号

    -- ===== 引脚功能复用（填引脚号，不填 GPIO 号）=====
    pins = {
        -- I2C1: 触摸(GT911) + 音频(ES8311) 共用（8311 保持常供电，防止钳位 I2C1）
        { pin = 66, func = "I2C1_SDA"  },  -- I2C1 数据线（8311 + 触摸）
        { pin = 67, func = "I2C1_SCL"  },  -- I2C1 时钟线（8311 + 触摸）
        -- 背光: PWM0（PIN22）
        { pin = 22, func = "PWM0"      },  -- 背光 PWM0 调光
        -- SPI1: SD 卡 + NAND Flash 共用（CS 脚由各存储驱动作为 GPIO 管理）
        { pin = 7,  func = "SPI1_CLK"  },  -- SPI1 时钟（SD + NAND）
        { pin = 58, func = "SPI1_MISO" },  -- SPI1 主机输入（SD + NAND）
        { pin = 29, func = "SPI1_MOSI" },  -- SPI1 主机输出（SD + NAND）
        -- 蜂鸣器: PWM4（PIN16）
        { pin = 16, func = "PWM4"      },  -- 蜂鸣器 PWM4
        -- I2S: ES8311 音频数据总线
        { pin = 32, func = "I2S_DOUT"  },  -- I2S 数据输出（DAC → 喇叭）
        { pin = 31, func = "I2S_DIN"   },  -- I2S 数据输入（MIC → ADC）
        { pin = 30, func = "I2S_LRCK"  },  -- I2S 左右声道时钟
        { pin = 29, func = "I2S_BCK"   },  -- I2S 位时钟（与 SPI1_MOSI 共用 GPIO29）
    },

    -- ===== GPIO 上电时序: 外设供电使能 + SPI1 CS 初始化 =====
    -- SPI1 由 SD 卡 + NAND Flash 共用，CS 先初始化为高电平（SPI 空闲态），各驱动自行接管
    power_on = {
        { pin = 4,  dir = 0, level = 0 },  -- WIFI_EN = GPIO4 拉高使能 6205 WiFi 模组
        { pin = 18, dir = 0, level = 1 },  -- FLASH_EN = GPIO18 拉高使能 NAND Flash
        { pin = 24, dir = 0, level = 1 },  -- 8311_EN = GPIO24 拉高使能音频供电（ES8311）
        { pin = 22, dir = 0, level = 1 },  -- PA_EN = GPIO22 拉低使能功放（低电平有效）
        -- SPI1 总线 CS 脚全部拉高（空闲态），各驱动在 SPI 事务中自行控制
        { pin = 12, dir = 0, level = 1 },  -- SPI1_CS1 = GPIO12 拉高（NAND Flash 片选）
        { pin = 5,  dir = 0, level = 1 },  -- SPI1_CS2 = GPIO5 拉高（SD 卡片选）
    },

    -- ===== 硬件配置 =====
    hw = {
        -- 屏幕: ST7796 SPI 4寸 320×480
        lcd = {
            model = "lcd_st7796",
            params = {
                port = lcd.HWID_0,       -- 专用 LCD SPI 接口（Air1780H 支持）
                pin_rst = 36,            -- LCD_RST = GPIO36
                direction = 0,           -- 0° 方向
                w = 320,                 -- 水平分辨率
                h = 480,                 -- 竖直分辨率
                bus_speed = 80 * 1000 * 1000,  -- SPI 时钟 80MHz
            },
            need_buffer = false,         -- SPI 屏不需要帧缓冲，直刷更快
            screen_size = 4.0,           -- 4寸屏
            font = { size = 14 },        -- 低分屏用 14 号字（固件内置字库，最低字号）
            backlight = {
                pwm_ch = 0,              -- PWM 通道 0（PIN22）
                pwm_freq = 1000,         -- 1kHz（SPI 屏推荐）
            },
        },
        -- 触摸: GT911 I2C1
        tp = {
            model = "tp_gt911",
            params = {
                port = 1,                -- I2C 端口 1（与 8311 共用）
                pin_rst = 26,            -- TP_RESET = GPIO26
                pin_int = gpio.WAKEUP0,  -- TP_INT = WAKEUP0
                int_type = tp.FALLING,   -- 下降沿触发
                i2c_speed = i2c.SLOW,    -- 低速 I2C（推荐）
            },
        },
        -- 音频硬件: ES8311 编解码 + 功放（应用工厂-录音播放）
        -- 8311 与触摸(GT911)共用 I2C1：8311 保持常供电（factory_rec 会禁用 C 层 codec 电源管理），
        -- 防止 8311 掉电把共享 I2C1 总线钳位导致触摸失灵
        -- PA_EN=GPIO22 低电平使能功放
        audio = {
            model = "es8311",          -- 音频编解码芯片
            i2c_id = 1,                -- I2C1 控制总线（与触摸共用）
            pa_ctrl = 22,              -- PA_EN 功放使能 GPIO
            dac_ctrl = 24,             -- 8311_EN 音频供电/编解码使能 GPIO
            pa_on_level = 0,           -- PA 低电平使能
            dac_on_level = 1,          -- CODEC 高电平使能
            audio_mode = "auto",       -- auto 在 780E 系列默认旧框架(audio)
            i2s_sample = 16000,        -- I2S 采集采样率（对齐 demo，C 层转 AMR_NB 8k）
            bits_per_sample = 16,      -- 采样位深（对齐 demo）
            i2s_framebit = 16,         -- I2S 通道位宽（对齐 demo）
            dac_delay = 6,             -- DAC 启动前冗余时间；固件≥V2026 单位100ms 填6
            play_vol = 70,             -- 默认播放音量(0~100)
            mic_vol = 70,              -- 默认录音音量(0~100)
            record_format = "AMR_NB",  -- 录音格式
            max_record_time = 60,      -- 最大录音时长(秒)
        },
        -- 电池管理: ADC0 = PIN9
        battery = {
            adc_channel = 0,             -- ADC0 = PIN9，用于读取电池电压
            voltage_divider = 2,         -- 电池电压分压比
            full_voltage = 4150,         -- 充满判定电压 mV
        },
    },

    -- ===== 功能开关（只写 = true 的项）=====
    features = {
        wifi = true,                     -- 启用 WiFi（airlink SPI，6205 模组）
        buzzer = true,                   -- 启用蜂鸣器（触摸反馈音，PWM4=PIN16）
        sd_card = true,                  -- 启用 SD/TF 卡（需配 storage.sd_card）
        nand_flash = true,               -- 启用 NAND Flash（需配 storage.nand_flash）
        app_factory = true,              -- 启用"应用工厂"内置应用
        ai_chat = true,                  -- 启用"AI聊天助手"内置应用
        speaker = true,                  -- 启用喇叭（ES8311 播放）
        mic = true,                      -- 启用麦克风（ES8311 录音）
        battery = true,                  -- 启用电池管理（ADC 检测 + 充电检测）
    },

    -- ===== 统一网络配置（优先级从高到低）=====
    -- Air1780H 无内置 WiFi，6205 模组经 AirLink over SPI0（SPI0 为默认组 PIN83/84/85/86）
    network = {
        { type = "wifi_airlink_spi",
          spi_id = 0,                    -- SPI0
          cs_pin = 8,                    -- SPI0_CS = GPIO8
          rdy_pin = 3,                   -- AIRLINK_RDY = GPIO3
          speed = 20 * 1000000,          -- 20MHz
        },
    },

    -- ===== UI 显示控制（只写 = true 的项）=====
    ui = {
        show_wifi_icon = true,           -- 桌面顶栏 WiFi 图标
        show_brightness_slider = true,   -- 设置页亮度滑块
        show_storage_settings = true,    -- 设置页存储空间入口
        show_app_factory = true,         -- 桌面显示"应用工厂"入口 ← 配 app_factory 时打开
        show_ai_chat = true,             -- 桌面显示"AI助手"入口 ← 配 ai_chat 时打开
        ai_chat = true,                  -- 启用"AI聊天助手"内置应用
        show_buzzer_settings = true,     -- 设置页蜂鸣器开关 ← 配 buzzer 时打开
        show_battery_icon = true,        -- 桌面顶栏电池图标 ← 配 battery 时打开
    },

    -- ===== 存储设备: SD 卡 + NAND Flash（共用 SPI1）=====
    -- 注意: SD 与 NAND 共用 SPI1 总线，速率统一 20MHz 避免混挂不同速率导致的总线重配问题
    storage = {
        -- NAND Flash（SPI1_CS1 = GPIO12）
        nand_flash = {
            spi_id = 1,                  -- SPI 接口 ID
            pin_cs = 12,                 -- SPI1_CS1 = GPIO12
            speed = 20000000,            -- SPI 时钟频率 Hz（与 SD 统一 20MHz）
        },
        -- SD/TF 卡（SPI1_CS2 = GPIO5）
        sd_card = {
            spi_id = 1,                  -- SPI 接口 ID（与 NAND 共用 SPI1，CS 不同）
            pin_cs = 5,                  -- SPI1_CS2 = GPIO5
            speed = 20000000,            -- SPI 时钟频率 Hz（与 NAND 统一 20MHz）
        },
    },

    -- ===== 注意: AIRLINK_IRQ / AIRLINK_WAKEUP 配置 =====
    -- IRQ 和 WAKEUP 引脚需在 net_manager 初始化前通过 airlink API 单独配置：
    --
    --   airlink.config(airlink.CONF_SPI_IRQ, 6)       -- AIRLINK_IRQ = GPIO6
    --   airlink.irqmode(true, 6, 6)
    --   airlink.wakeupIrqmode(true, 7, 7, luat_gpio.RISING)  -- AIRLINK_WAKEUP = GPIO7
    --
    -- 6205 供电由 power_on 的 WIFI_EN = GPIO4 控制（高电平有效）
}
