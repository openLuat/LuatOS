--[[
@module  config.eng_1602_5i_v5
@summary Air1602引擎主机 5寸480x854 RGB屏(ST7701S) + NAND Flash + WiFi(airlink低电平)
@version 1.1
@date    2026.06.01
@author  江访
@usage
所有 boolean 字段只写 = true 表示开启，不写即视为关闭（无需写 = false）
具体包含哪些参数，如何填写参考：template.lua
]]
return {
    -- ===== 顶层信息 =====
    name = "Engine_Air1602_5inch_480x854_005_V000",  -- 项目命名: {类型}_{芯片}_{尺寸}_{版本}
    chip = "Air1602",                                  -- 主控芯片: RGB屏 + WiFi(airlink)
    baseboard = "合宙引擎AIR1602 V005",                -- 底板型号

    -- ===== 引脚功能复用（无特殊复用需求，留空）=====
    pins = {},

    -- ===== GPIO 上电时序: WiFi 模组保持低电平 =====
    -- Air1602 V005 airlink WiFi 模组: GPIO55 保持低电平（低电平有效）
    power_on = {
        { pin = 55, dir = 0, level = 0, delay = 50 },  -- 保持低电平 50ms
        { pin = 49, dir = 1, level = 1, delay = 50 },  -- 拉高释放 50ms
    },

    -- ===== 硬件配置 =====
    hw = {
        -- 屏幕: ST7701S RGB 5寸 480×854
        lcd = {
            model = "lcd_display_rgb",
            params = {
                interface = "rgb",             -- RGB 接口
                pin_clk = 23,                 -- SPI 时钟引脚（初始化通信）
                pin_sda = 2,                  -- SPI 数据引脚
                pin_cs = 22,                  -- SPI 片选引脚
                pin_rst = 15,                 -- 复位引脚
                w = 480,                       -- 水平分辨率
                h = 854,                       -- 竖直分辨率
                hbp = 40,                      -- 水平后沿
                hspw = 10,                     -- 水平同步脉宽
                hfp = 40,                      -- 水平前沿
                vbp = 10,                      -- 垂直后沿
                vspw = 8,                      -- 垂直同步脉宽
                vfp = 20,                      -- 垂直前沿
                bus_speed = 30 * 1000 * 1000,  -- RGB 总线时钟 30MHz
                -- ST7701S IC 寄存器初始化序列（引用 lcd_st7701s_5in 驱动）
                ic_init = require("lcd_st7701s_5in").ic_init,
            },
            need_buffer = true,          -- RGB 屏必须启用帧缓冲防撕裂
            screen_size = 5.0,           -- 5寸屏
            font = { size = 20 },        -- 高分屏用 20 号字
            backlight = {
                pwm_ch = 3,              -- PWM 通道 3
                pwm_freq = 1000,         -- 1kHz
            },
        },
        -- 触摸: GT911 I2C 端口1
        tp = {
            model = "tp_gt911",
            params = {
                port = 1,                -- I2C 端口 1
                pin_rst = 3,             -- 复位引脚
                pin_int = 51,            -- 中断引脚
                int_type = tp.FALLING,   -- 下降沿触发
                w = 480,                 -- 触摸面板宽度（与 LCD 一致）
                h = 854,                 -- 触摸面板高度
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
        -- 参考 Air1602 录音 demo（record_amr_file.lua，Air1602_V1.2 开发板）：
        --   ES8311 与触摸共用 I2C1；8311_EN=GPIO43 保持常供电，防止钳位 I2C1 触摸总线
        --   播放走内置 DAC0，录音走 I2S2 接 ES8311（exaudio v2.8 tx/rx_bus_type 默认驱动切换）
        --   PA_EN=GPIO73 低电平使能（pa_on_level=0），由 exaudio.setup 内部控制防 pop 音
        audio = {
            model = "es8311", -- 音频编解码: ES8311（录音经 I2S2）
            i2c_id = 1,       -- I2C1 控制总线（与触摸共用）
            -- 默认驱动切换：播放用内置 DAC0，录音用 I2S2（Air1601/1602 引擎板）
            -- 数值对应 audio_v2.DRIVER_TYPE_*（NONE=0/I2S=1/DAC=2/ADC=3），
            -- 用字面量避免依赖 audio_v2 全局表（8000 等旧框架固件可能无此表）
            tx_bus_type = 2,          -- audio_v2.DRIVER_TYPE_DAC：发送(播放)总线=内置DAC
            tx_bus_id = 0,            -- DAC0
            rx_bus_type = 1,          -- audio_v2.DRIVER_TYPE_I2S：接收(录音)总线=I2S
            rx_bus_id = 2,            -- I2S2
            dac_ctrl = 49,            -- 8311_EN 编解码使能 GPIO（已在 power_on 拉高）
            pa_ctrl = 45,             -- PA_EN 功放使能 GPIO
            pa_on_level = 1,          -- PA 低电平使能（Air1602_V1.2 开发板特性）
            pa_delay = 100,           -- PA 打开延迟(ms)
            i2s_sample = 8000,        -- I2S 采样率（AMR_NB=8k）
            bits_per_sample = 16,     -- 采样位深
            i2s_framebit = 16,        -- I2S 通道位宽
            channels = 1,             -- 声道数: 单声道
            play_vol = 70,            -- 默认播放音量(0~100)
            mic_vol = 70,             -- 默认录音音量(0~100)
            record_format = "AMR_NB", -- 录音格式（与 Air1601/1602 一致，体积小，ASR 上传省内存）
            max_record_time = 30,     -- 最大录音时长(秒)，到时自动停止
        },
    },

    -- ===== 功能开关（只写 = true 的项）=====
    features = {
        wifi = true,                     -- 启用 WiFi
        nand_flash = true,               -- 启用 NAND Flash 存储
        nes = true,                      -- 启用 NES 游戏按键（需配 nes_keys）
        battery = true,                  -- 启用电池管理（需配 hw.battery + ui.show_battery_icon）
        cloud_disk = true,               -- 启用"合宙网盘"内置应用（IoT 登录取 space_key → 空间文件列表 → 下载）
    },

    -- ===== 统一网络配置（优先级从高到低）=====
    network = {
        { type = "wifi_airlink_spi",     -- Airlink SPI WiFi 外挂模组
          spi_id = 1, cs_pin = 8, rdy_pin = 14 },
    },

    -- ===== NES 游戏按键绑定 =====
    -- 方向键: 支持 8 方向组合 + 持续按住
    -- 动作键: A 和 B，200ms 内先后按下触发 NES_COMBO("AB") 组合事件
    nes_keys = {
        { pin = 44, key = "NES_KEY_UP"    },  -- 上
        { pin = 48, key = "NES_KEY_DOWN"  },  -- 下
        { pin = 41, key = "NES_KEY_LEFT"  },  -- 左
        { pin = 40, key = "NES_KEY_RIGHT" },  -- 右
        { pin =  0, key = "NES_KEY_A"     },  -- A
        { pin =  1, key = "NES_KEY_B"     },  -- B
    },

    -- ===== UI 显示控制（只写 = true 的项）=====
    ui = {
        show_wifi_icon = true,           -- 桌面顶栏 WiFi 图标
        show_brightness_slider = true,   -- 设置页亮度滑块
        show_storage_settings = true,    -- 设置页存储空间入口
        show_battery_icon = true,        -- 桌面顶栏电池图标 ← 配 battery 时打开
        show_cloud_disk = true,          -- 桌面显示"合宙网盘"入口 ← 配 cloud_disk 时打开
        --[[桌面播放器区域（竖屏纵向堆叠）

        打开后桌面纵向排布变为：状态栏 → 时钟 → 播放器 → 已安装应用 → Dock
        （**不带天气卡**：那块高度让给播放器的独立控制栏）。
        播放器卡 = 画面 480×320（素材原生尺寸，airui 播放器控件不支持缩放，卡比素材矮只会裁画面）
        + 控制栏一行 —— 控制栏独占一行不压画面，否则会被硬解视频图层盖住。
        播放器与应用卡各拿刚需后，**剩下的纵向空间全给 Dock（内置应用栏）**：
        480×854 实测 播放器 364 / 已安装应用 158 / Dock 96（1 行 4 个/页，右上角分页器可翻页）。
        不写此项时该机型桌面与本改动前完全一致。]]
        show_video_area = true,          -- 桌面内置播放器区域（竖屏：时钟下方通栏，含独立控制栏）
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
