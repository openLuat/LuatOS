--[[
@module  config.eng_8607_10i_v0
@summary Air8607 引擎主机 10寸1024x600 RGB触摸屏 + PWM背光 + 喇叭 + SD卡 配置文件
@version 1.0
@date    2026.10.13
@author  江访
@usage
所有 boolean 字段只写 = true 表示开启，不写即视为关闭（无需写 = false）
具体包含哪些参数，如何填写参考：template.lua

注意：
1. Air8607 主控平台为 Air1603（非 Air8601/8602 的 Air1601 内核）。
2. 本板无网络功能（无 WiFi/4G），不配置 network 段。
3. LCD 为 RGB 10寸 1024×600（免序列四合一，无 SPI 初始化引脚），走统一 RGB 驱动
   lcd_display_rgb；LCD_DISP = GPIO15 作 pin_rst；时序用 1024×600 生态实测组
   hbp=140 hspw=20 hfp=160 vbp=20 vspw=3 vfp=12 @50MHz。
4. 触摸 GT911 走 I2C1：I2C1_SCL = PIN42 = GPIO39，I2C1_SDA = PIN41 = GPIO38，
   TP_RST = GPIO14，TP_INT = WAKEUP = GPIO51。
5. 背光 PWM3 调光：背光 pin55 = PWM3 = GPIO13，pin55 复用为 PWM3。
6. SD 卡走 SPI1 总线，SPI1_CS = GPIO8，SD_EN = GPIO74（power_on 拉高供电）。
7. 音频使用芯片内置 DAC 播放，PA 功放 HT6873，AUDIOPA_EN = GPIO73，
   高电平使能（pa_on_level = 1，power_on 初始拉低关断，起播时 exaudio 拉高）。
   本板无麦克风，不开启录音相关功能。
   hw.audio 字段消费方：app/common/tts_app.lua、ui/welcome_win.lua、ui/video_util.lua。
]]

return {
    -- ===== 顶层信息 =====
    name = "Engine_Air8607_10inch_1024x600_000_V000", -- 项目命名: {类型}_{芯片}_{尺寸}_{分辨率}_{版本}
    chip = "Air1603", -- 主控芯片平台
    baseboard = "合宙引擎 AIR8607 V000 10寸", -- 底板型号

    -- ===== 引脚功能复用 =====
    -- 背光 PWM3 与触摸 I2C1 需要引脚复用
    pins = {
        -- { pin = 55, func = "PWM3" },     -- 背光 PWM3（PIN55 = GPIO13）
        -- { pin = 42, func = "I2C1_SCL" }, -- I2C1 时钟线（GT911 SCL，GPIO39）
        -- { pin = 41, func = "I2C1_SDA" }, -- I2C1 数据线（GT911 SDA，GPIO38）
    },

    -- ===== GPIO 上电时序 =====
    -- 按顺序初始化各外设供电（顺序即依赖：SD→功放关断）
    power_on = {
        { pin = 74, dir = 0, level = 1 }, -- SD_EN 拉高使能 SD 卡供电
        { pin = 73, dir = 0, level = 0 }, -- AUDIOPA_EN 初始拉低关断功放（HT6873 高电平使能）
    },

    -- ===== 硬件配置 =====
    hw = {
        -- 屏幕: RGB 10寸 1024×600（免序列四合一，无需 SPI 初始化引脚）；背光 PWM3 调光
        lcd = {
            model = "lcd_display_rgb", -- 本工程统一 RGB 驱动（内部走 display.init）
            params = {
                interface = "rgb",     -- RGB 接口
                pin_rst = 15,          -- LCD_DISP = GPIO15（复位/显示使能）
                w = 1024,              -- 水平分辨率
                h = 600,               -- 竖直分辨率
                -- RGB 时序参数（1024×600 生态实测组，与同族 HX8282 板一致）
                hbp = 140,
                hspw = 20,
                hfp = 160,
                vbp = 20,
                vspw = 3,
                vfp = 12,
                bus_speed = 50 * 1000 * 1000, -- RGB 总线时钟 50MHz
            },
            need_buffer = true,               -- RGB 屏启用帧缓冲防撕裂
            screen_size = 10.0,               -- 10寸屏
            font = { size = 20 },             -- 高分屏用 20 号字
            backlight = {
                pwm_ch = 3,                   -- PWM3 背光调光（PIN55 = GPIO13）
                pwm_freq = 1000,              -- 1kHz
            },
        },
        -- 触摸: GT911 I2C 端口1，大屏带尺寸参数
        tp = {
            model = "tp_gt911",
            params = {
                port = 1,              -- I2C 端口 1
                pin_rst = 14,          -- TP_RST = GPIO14
                pin_int = 51,          -- TP_INT = WAKEUP = GPIO51
                int_type = tp.FALLING, -- 下降沿触发（大屏推荐）
                w = 1024,              -- 触摸面板宽度
                h = 600,               -- 触摸面板高度
            },
        },
        -- 音频: 内置 DAC 播放 + HT6873 功放（无麦克风）
        audio = {
            model = "dac",          -- 内置 DAC 模式
            pa_ctrl = 73,           -- PA(功放)使能引脚 = GPIO73（AUDIOPA_EN）
            pa_on_level = 1,        -- 高电平使能功放（HT6873）
            dac_delay = 6,          -- DAC 启动前冗余时间（旧框架用）
            pa_delay = 10,          -- PA 在播放开始后延迟打开的时间(ms)，透传 config_pa_power_ctrl()
            play_vol = 70,          -- 默认播放音量(0~100)
        },
    },

    -- ===== 功能开关（只写 = true 的项）=====
    features = {
        speaker = true,     -- 启用喇叭（内置 DAC + HT6873 功放）
        sd_card = true,     -- 启用 SD 卡（SPI1，CS=GPIO8）
    },

    -- ===== 存储设备: SD/TF 卡（SPI1, CS=GPIO8）=====
    storage = {
        sd_card = {
            spi_id = 1,               -- SPI1 总线
            pin_cs = 8,               -- SPI1_CS = GPIO8 片选
            speed = 20 * 1000 * 1000, -- SD 卡 SPI 时钟 20MHz
        },
    },

    -- ===== UI 显示控制（只写 = true 的项）=====
    ui = {
        show_brightness_slider = true, -- 设置页亮度滑块
        show_storage_settings = true,  -- 设置页存储空间入口 ← 配 sd_card 时打开
    },
}
