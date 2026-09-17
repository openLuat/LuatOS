--[[
@module  config.eng_1602_10i_v10421
@summary Air1602引擎主机 10寸1024x600 RGB屏(HX8282) + NAND Flash + NES + 电池 配置文件
@version 1.0
@date    2026.06.29
@author  江访
@usage
所有 boolean 字段只写 = true 表示开启，不写即视为关闭（无需写 = false）
具体包含哪些参数，如何填写参考：template.lua
]]
return {
    -- ===== 顶层信息 =====
    name = "Engine_Air1602_AirLCD_1100_10421_V000",  -- 项目命名
    chip = "Air1602",                                   -- 主控芯片: RGB屏 + WiFi(airlink)
    baseboard = "合宙引擎AIR1602 V10421 10寸",           -- 底板型号

    -- ===== 引脚功能复用（无特殊复用需求，留空）=====
    pins = {},

    -- ===== GPIO 上电时序: WiFi 模组复位 + 音频 ES8311 上电 =====
    -- V004 airlink WiFi 模组: GPIO55 先高后低（低电平有效，与 V000/V002/V003 相反）
    -- 音频 ES8311 上电（8311_EN=GPIO49，高电平有效），录音需经 I2C1 读芯片
    -- PA_EN=GPIO45 由 exaudio.setup 内部控制（防 pop 音时序），此处不提前拉高
    power_on = {
        { pin = 55, dir = 0, level = 1, delay = 50  },  -- 拉高 50ms
        { pin = 55, dir = 0, level = 0, delay = 120 },  -- 拉低 120ms 使能
        { pin = 43, dir = 0, level = 1 },               -- 8311_EN 拉高使能 ES8311
    },

    -- ===== 硬件配置 =====
    hw = {
        -- 屏幕: HX8282 RGB 10寸 1024×600
        lcd = {
            model = "lcd_display_rgb",
            params = {
                interface = "rgb",        -- RGB 接口
                pin_rst = 15,            -- 复位引脚
                w = 1024,                -- 水平分辨率
                h = 600,                 -- 竖直分辨率
                hbp = 140,               -- 水平后沿
                hspw = 20,               -- 水平同步脉宽
                hfp = 160,               -- 水平前沿
                vbp = 20,                -- 垂直后沿
                vspw = 3,                -- 垂直同步脉宽
                vfp = 12,                -- 垂直前沿
                bus_speed = 50 * 1000 * 1000,  -- RGB 总线时钟 50MHz
            },
            need_buffer = true,          -- RGB 屏必须启用帧缓冲防撕裂
            screen_size = 10.0,          -- 10寸屏
            font = { size = 20 },        -- 高分屏用 20 号字
            backlight = {
                pwm_ch = 3,              -- PWM 通道 3
                pwm_freq = 1000,         -- 1kHz
            },
        },
        -- 触摸: GT911 I2C 端口1，大屏带尺寸参数
        tp = {
            model = "tp_gt911",
            params = {
                port = 1,                -- I2C 端口 1
                pin_rst = 3,             -- 复位引脚
                pin_int = 51,            -- 中断引脚
                int_type = tp.FALLING,   -- 下降沿触发（大屏推荐）
                w = 1024,                -- 触摸面板宽度
                h = 600,                 -- 触摸面板高度
                gpio_reset = 3,          -- 额外复位 GPIO（Air1602 常用）
            },
        },
        -- 电池管理: ADC 通道7，USB 检测 GPIO52
        battery = {
            adc_channel = 7,             -- ADC 通道号
            usb_detect_gpio = 52,        -- USB 插入检测 GPIO
            voltage_divider = 2,         -- 分压比 2:1
            full_voltage = 4150,         -- 充满电压 4.15V
        },
        -- 音频硬件: ES8311 + I2S2（应用工厂-录音播放）
        -- 引擎板方案（参考 Air1602 录音 demo）：播放走内置 DAC0，录音走 I2S2 接 ES8311
        -- 8311_EN=GPIO49(dac_ctrl), PA_EN=GPIO45(pa_ctrl)，I2C1 控制(i2c_id=1)
        -- exaudio v2.8 通过 tx_bus_type/rx_bus_type 切换默认驱动：DAC0 播放 + I2S2 录音
        audio = {
            model = "es8311",            -- 音频编解码: ES8311（录音经 I2S2）
            i2c_id = 1,                  -- I2C1 控制总线（与触摸共用）
            -- 默认驱动切换：播放用内置 DAC0，录音用 I2S2（Air1602 引擎板）
            -- 数值对应 audio_v2.DRIVER_TYPE_*（NONE=0/I2S=1/DAC=2/ADC=3），
            -- 用字面量避免依赖 audio_v2 全局表（8000 等旧框架固件可能无此表）
            tx_bus_type = 2,               -- audio_v2.DRIVER_TYPE_DAC：发送(播放)总线=内置DAC
            tx_bus_id = 0,                 -- DAC0
            rx_bus_type = 1,               -- audio_v2.DRIVER_TYPE_I2S：接收(录音)总线=I2S
            rx_bus_id = 2,                 -- I2S2
            dac_ctrl = 49,               -- 8311_EN 编解码使能 GPIO
            pa_ctrl = 45,                -- PA_EN 功放使能 GPIO
            pa_on_level = 1,             -- PA 高电平使能
            pa_delay = 100,              -- PA 打开延迟(ms)
            i2s_sample = 8000,           -- I2S 采样率（AMR_NB=8k）
            bits_per_sample = 16,        -- 采样位深
            i2s_framebit = 16,           -- I2S 通道位宽
            channels = 1,                -- 声道数: 单声道
            play_vol = 70,               -- 默认播放音量(0~100)
            mic_vol = 70,                -- 默认录音音量(0~100)
            record_format = "AMR_NB",    -- 录音格式
            max_record_time = 30,        -- 最大录音时长(秒)，到时自动停止
        },
    },

    -- ===== 功能开关（只写 = true 的项）=====
    features = {
        wifi = true,                     -- 启用 WiFi
        nand_flash = true,               -- 启用 NAND Flash 存储
        nes = true,                      -- 启用 NES 游戏按键（需配 nes_keys）
        battery = true,                  -- 启用电池管理（需配 hw.battery + ui.show_battery_icon）
        app_factory = true,              -- 启用"应用工厂"内置应用
        ai_chat = true,                  -- 启用"AI聊天助手"内置应用
        speaker = true,                  -- 启用喇叭（DAC0 播放）
        mic = true,                      -- 启用麦克风（I2S2 + ES8311 录音）
    },

    -- ===== 统一网络配置（优先级从高到低）=====
    network = {
        { type = "wifi_airlink_spi",     -- Airlink SPI WiFi 外挂模组
          spi_id = 1, cs_pin = 8, rdy_pin = 14 },
    },

    -- ===== NES 游戏按键绑定（9寸/10寸型号: 方向键引脚与 V004 不同）=====
    -- 方向键: 支持 8 方向组合 + 持续按住
    -- 动作键: A 和 B，200ms 内先后按下触发 NES_COMBO("AB") 组合事件
    -- 控制键: RETURN/START/SELECT，按下沿触发 + 200ms 防抖，发布 NES_CTRL 事件
    nes_keys = {
        { pin = 46, key = "NES_KEY_UP"     },  -- 上
        { pin = 42, key = "NES_KEY_DOWN"   },  -- 下
        { pin = 47, key = "NES_KEY_LEFT"   },  -- 左
        { pin = 43, key = "NES_KEY_RIGHT"  },  -- 右
        { pin =  2, key = "NES_KEY_RETURN" },  -- 返回（退出 APP）
        { pin =  0, key = "NES_KEY_START"  },  -- 开始
        { pin = 22, key = "NES_KEY_SELECT" },  -- 选择
        { pin = 23, key = "NES_KEY_A"      },  -- A
        { pin =  1, key = "NES_KEY_B"      },  -- B
    },

    -- ===== UI 显示控制（只写 = true 的项）=====
    ui = {
        show_wifi_icon = true,           -- 桌面顶栏 WiFi 图标
        show_brightness_slider = true,   -- 设置页亮度滑块
        show_storage_settings = true,    -- 设置页存储空间入口
        show_battery_icon = true,        -- 桌面顶栏电池图标 ← 配 battery 时打开
        show_app_factory = true,         -- 桌面显示"应用工厂"入口 ← 配 app_factory 时打开
        show_ai_chat = true,             -- 桌面显示"AI助手"入口 ← 配 ai_chat 时打开
        ai_chat = true,                  -- 启用"AI聊天助手"内置应用
    },

    -- ===== 存储设备: NAND Flash =====
    storage = {
        nand_flash = {
            spi_id = 2,                  -- SPI 接口 ID，通常 spi2 用于外置存储
            pin_cs = 4,                  -- 片选 CS 引脚
            speed = 40000000,            -- SPI 时钟频率 Hz
            pin_pwr = 50,                -- 额外供电使能 GPIO
        },
    },
}
