--[[
@module  config.eng_8607a_10i_v0
@summary Air8607A 引擎主机 10寸1024x600 RGB触摸屏 + PWM背光 + 喇叭 + UVC摄像头 配置文件
@version 1.0
@date    2026.10.23
@author  江访
@usage
所有 boolean 字段只写 = true 表示开启，不写即视为关闭（无需写 = false）
具体包含哪些参数，如何填写参考：template.lua

与 Air8607（config/eng_8607_10i_v0.lua）的差异只有两点：
去掉了 SD 卡、增加了 UVC 摄像头。其余 LCD / 触摸 / 音频 / 背光完全一致。

注意：
1. Air8607A 主控平台为 Air1603（非 Air8601/8602 的 Air1601 内核）。
2. 本板无网络功能（无 WiFi/4G），不配置 network 段。
3. LCD 为 RGB 10寸 1024×600（免序列四合一，无 SPI 初始化引脚），走统一 RGB 驱动
   lcd_display_rgb；LCD_DISP = GPIO15 作 pin_rst；时序用 1024×600 生态实测组
   hbp=140 hspw=20 hfp=160 vbp=20 vspw=3 vfp=12 @50MHz。
4. 触摸 GT911 走 I2C1：I2C1_SCL = PIN42 = GPIO39，I2C1_SDA = PIN41 = GPIO38，
   TP_RST = GPIO14，TP_INT = WAKEUP = GPIO51。
5. 背光 PWM3 调光：背光 pin55 = PWM3 = GPIO13，pin55 复用为 PWM3。
6. 【去 SD 卡】本板无 SD 卡槽，不配 storage 段、不开 features.sd_card。
   落盘数据一律写 /ram/（掉电即失），工厂侧用文件传输应用取回。
7. 音频使用芯片内置 DAC 播放，PA 功放 HT6873，AUDIOPA_EN = GPIO73，
   高电平使能（pa_on_level = 1，power_on 初始拉低关断，起播时 exaudio 拉高）。
   本板无麦克风，不开启录音相关功能。
   hw.audio 字段消费方：app/common/tts_app.lua、ui/video_util.lua。
8. 【UVC 摄像头】AirCAMERA_1032（AirUVC_1000）USB 摄像头，UVC_EN = GPIO12。
   本板 GPIO12 是独立的摄像头使能脚，**不是** 8605 那种 VBUS 与 5V_EN 共轨脚
   （8605 上拉低 GPIO12 会断触摸供电，periph_uvc 因此默认禁用该脚）。
   本板经确认 GPIO12 可独立驱动，故按 pin12_free = true 显式解除禁用。
   摄像头数据流（预览/拍照/录像）由 ui/uvc_preview_win.lua 走 excamera 扩展库独占管理，
   外设开关只负责供电，不再重复 camera.init。
   预览入口按需求放在「功能测试」里，因此不设 ui.show_camera_preview（避免两处入口）。
]]

return {
    -- ===== 顶层信息 =====
    name = "Engine_Air8607A_10inch_1024x600_000_V000", -- 项目命名: {类型}_{芯片}_{尺寸}_{分辨率}_{版本}
    chip = "Air1603", -- 主控芯片平台
    baseboard = "合宙引擎 AIR8607A V000 10寸", -- 底板型号

    -- ===== 引脚功能复用 =====
    -- 背光 PWM3 与触摸 I2C1 需要引脚复用
    pins = {
        -- { pin = 55, func = "PWM3" },     -- 背光 PWM3（PIN55 = GPIO13）
        -- { pin = 42, func = "I2C1_SCL" }, -- I2C1 时钟线（GT911 SCL，GPIO39）
        -- { pin = 41, func = "I2C1_SDA" }, -- I2C1 数据线（GT911 SDA，GPIO38）
    },

    -- ===== GPIO 上电时序 =====
    -- 按顺序初始化各外设供电（顺序即依赖：功放关断→UVC 关断）
    power_on = {
        { pin = 73, dir = 0, level = 0 }, -- AUDIOPA_EN 初始拉低关断功放（HT6873 高电平使能）
        { pin = 12, dir = 0, level = 0 }, -- UVC_EN 初始拉低，摄像头默认不供电，由功能测试开关/预览页控制
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

    -- ===== 外设清单（功能测试页逐项开关 + 进子页测试）=====
    -- UVC_EN = GPIO12：pin12_free = true 声明本板该脚独立可控，解除 periph_uvc 的 GPIO12 禁用
    -- w / h 是首选 MJPEG 输出分辨率（AirCAMERA_1032 取 1280×720）；预览页会枚举摄像头
    -- 真正支持的档位取可用档，像素数上限由 max_pixels 控制（缺省 1280×720 = 921600）
    peripherals = {
        { type = "uvc", id = "uvc1", name = "UVC摄像头", en_pin = 12, ready_delay = 200,
          pin12_free = true, w = 1280, h = 720 },
    },

    -- ===== 功能开关（只写 = true 的项）=====
    features = {
        speaker = true,      -- 启用喇叭（内置 DAC + HT6873 功放）
        usb_camera = true,   -- 启用 USB 摄像头（UVC 协议，AirCAMERA_1032）；入口在「功能测试」
        other_func = true,   -- 启用「功能测试」页（UVC 预览 / 485 测试入口）
    },

    -- ===== UI 显示控制（只写 = true 的项）=====
    ui = {
        show_brightness_slider = true, -- 设置页亮度滑块
        show_other_func = true,        -- 桌面「功能测试」图标 ← 配 peripherals 时打开
        -- show_camera_preview 故意不写：UVC 预览入口在「功能测试」里，见文件头第 8 条
    },
}
