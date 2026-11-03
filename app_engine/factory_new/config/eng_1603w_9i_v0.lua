--[[
@module  config.eng_1603w_9i_v0
@summary Air8607W 引擎主机 9寸1024x600 RGB屏(HX8282) + Airlink SPI WiFi(Air601S) + 非隔离RS485(UART1) + 人脸识别摄像头(UART2) + SD卡 + 内置DAC喇叭 + USB HID/UVC 二选一 配置文件（WiFi 版）
@version 1.0
@date    2026.11.03
@author  江访
@usage
所有 boolean 字段只写 = true 表示开启，不写即视为关闭（无需写 = false）
具体包含哪些参数，如何填写参考：template.lua

注意：
1. 【W_GPIO / W_UART 编号推算 · 上板前必核】本板规格表用 W_GPIO4 / W_GPIO7 / W_UART4 标注
   WiFi 芯片（Air601S，与 Air8000 内置 WiFi 同芯片）侧的资源。按 Air8000 的 WGPIO 换算规则
   （GPIO 口 ≥100 或 UART 口 ≥10 隶属 WiFi 芯片）推算到主机侧编号：
     W_GPIO4 → GPIO132   UVC 使能供电
     W_GPIO7 → GPIO135   非隔离 485 供电域
     W_UART4 → UART13    通用串口
   ★ 三个都是推算值，上板前必须对原理图核实一次。
   若实测这三路确实在 Air601S 芯片内部、并非主控可直驱的 GPIO，则 en_pin / power_pin 须改走
   Airlink 的 GPIO 指令（airlink 0x300 gpio_setup / 0x301 gpio_set）下发，uart_id 须改走 Airlink
   的 UART 通道；届时本文件只改这三个编号与取值，其余结构不变。
2. 【USB HID 与 UVC 二选一】两者共用 USB Host 与供电轨，互斥，模式写 fskv（键 usb_mode_config），
   默认 UVC 摄像头。切换入口在「设置 → 外设模式」，切换后重启生效（交互与网络设置页同款）。
   模式判定集中在 usb_mode 模块：HID 模式下不启动 usb_hid_app、UVC 使能脚拉低、
   外设清单里的 uvc 条目不登记（功能测试页也就没有摄像头行）。
3. 【GPIO12 是 Airlink RDY，不是 USB VBUS】Airlink SPI 的就绪脚 RDY = GPIO12。
   usb_hid_app 原本硬编码 VBUS_GPIO = 12（8605 系列是 USB 供电脚），在本板会与 Airlink RDY
   抢同一个脚，故 hw.usb.vbus_gpio 写 false 关掉该脚的驱动，VBUS 交由硬件常供电。
4. 【Airlink SPI WiFi】Air601S 走 SPI5：CS = GPIO56、RDY = GPIO12，SPI 时钟 25MHz。
   Airlink-UART 通路（UART3）本型号不开。
5. 【SD 卡】SPI1 总线，SPI_CS0 = GPIO8，SD_EN = GPIO74，SPI 时钟 20MHz。
   共享 SPI 总线的片选脚（SPI5 的 GPIO56、SPI1 的 GPIO8）在 power_on 里最先拉高，
   免得上电瞬间从设备被误选中把总线拉挂。
6. 【LCD】HX8282 RGB 9寸 1024×600（免序列四合一，无 SPI 初始化引脚），走统一 RGB 驱动
   lcd_display_rgb；LCD_DISP = GPIO15 作 pin_rst；时序用 1024×600 生态实测组
   hbp=140 hspw=20 hfp=160 vbp=20 vspw=3 vfp=12 @50MHz。
   背光 PWM3 调光，频率 10kHz，开机亮度 100；默认字号 20。
7. 【触摸 GT911】走 I2C1，速率 i2c.SLOW：TP_RST = GPIO14、TP_INT = GPIO51，下降沿触发，
   触摸面板 1024×600。本型号 pins 不需要显式复用（同 eng_8603 系列，留空）。
8. 【音频 = 内置 DAC + 直驱 PA】喇叭 PA 使能 = GPIO73，高电平使能（pa_on_level = 1），
   PA 延时 200ms，播放音量 70。power_on 先把 GPIO73 拉低关断功放，起播时 exaudio 拉高。
   本板无麦克风，不开 features.mic、不配录音相关字段。音频与触摸不共用 I2C
   （内置 DAC 无 codec，i2c_shared 不适用）。
9. 【非隔离 485】485-1 挂 UART1，DE = GPIO65，供电域 = W_GPIO7 = GPIO135，波特率 9600。
   该供电域不是常供电（不写 power_hold），由 periph_rs485 按引用计数上/下电；
   测试发送内容 "123"；进 485 测试页自动初始化（不写 manual_init）。
   DE 空闲停在低电平（接收态），发送窗口内才拉高。
10. 【串口分配】通用串口 = W_UART4 = UART13，115200/8N1，登记为 peripherals 的 uart 条目。
    人脸识别摄像头的控制串口 = UART2（115200/8N1，exfacecam 库内固定波特率），
    由 uvc 条目的 face.uart_id 独占，**不再**登记 uart 条目 —— 否则 periph_uart 会与
    exfacecam 重复 uart.setup 同一串口。
11. 【人脸识别摄像头】本板摄像头是 AirCAMERA_1034 人脸识别模组，不是纯 UVC 摄像头：
    同一颗模组出两条通路 —— USB 走 UVC 出 MJPEG 画面，UART2 走协议做人脸录入 / 验证 / 用户管理。
    供电 = W_GPIO4 = GPIO132，上电稳定延时 200ms；模组无独立复位脚（face.rst_pin 不填），
    录入 / 验证超时均 15 秒。
    ★ 首选出图档写 960×480 而不是规格表的 1280×720：同款模组在 eng_8601_7i_wifi.lua 上
    实测只报 960x480 / 864x480 / 800x480 / 480x320 / 320x240，没有 1280x720；写 1280x720 会
    匹配失败、按默认 format0/frame0 起流失败，预览页再关流重开，首帧从 ~1.4s 拖到 ~11s。
    max_pixels 保持缺省 921600（= 1280×720），若后续模组固件支持更大档位，只需改 w / h。
12. 【UVC 测试入口】config.peripherals 加 uvc 条目 + features.other_func = true +
    ui.show_other_func = true 三件套齐了才有「功能测试 → 摄像头」行；
    数据流由 ui/uvc_preview_win.lua 走 excamera 独占管理，periph_uvc 只管供电脚。
    不设 ui.show_camera_preview（避免两处入口）。
13. 【上电时序】先拉高两条共享 SPI 总线的片选（Airlink SPI5 的 GPIO56、SD SPI1 的 GPIO8），
   再开供电域：WIFI 供电 = GPIO72、SD 卡供电 = GPIO74、UVC 供电 = GPIO132（等 200ms 就绪），
   最后把功放使能 GPIO73 拉低关断（高电平使能，起播时 exaudio 拉高）。
   非隔离 485 的供电 GPIO135 不进上电序列，由 periph_rs485 按引用计数上/下电（见第 9 条）；
   USB HID 模式下 usb_mode 会把 GPIO132 再拉低断电（见第 2 条）。
]]

return {
    -- ===== 顶层信息 =====
    name = "Engine_Air8607W_9inch_1024x600_000_V000", -- 项目命名: {类型}_{芯片}_{尺寸}_{分辨率}_{硬件类型}_{硬件版本}
    chip = "Air1603", -- 主控芯片平台
    baseboard = "Air8603W", -- 底板型号

    -- ===== 引脚功能复用 =====
    -- 本型号无引脚功能复用（背光 PWM3 与触摸 I2C1 走默认功能，与 eng_8603 系列一致）
    pins = { },

    -- ===== GPIO 上电时序 =====
    -- 共享 SPI 总线的片选脚先拉高，再开各供电域（顺序即依赖）
    power_on = {
        { pin = 56, dir = 0, level = 1 }, -- Airlink SPI5 CS 空闲拉高（共享总线先拉片选）
        { pin = 8,  dir = 0, level = 1 }, -- SD SPI1 CS 空闲拉高（共享总线先拉片选）
        { pin = 72, dir = 0, level = 1 }, -- WIFI 供电开启
        { pin = 74, dir = 0, level = 1 }, -- SD 卡供电开启
        { pin = 132, dir = 0, level = 1, delay = 200 }, -- UVC_EN 拉高，等 200ms 摄像头就绪
        { pin = 73, dir = 0, level = 0 }, -- AUDIOPA_EN 初始拉低关断功放（高电平使能，起播时拉高）
    },

    -- ===== 外设清单（功能测试页逐项开关 + 进子页测试）=====
    -- uvc 是 AirCAMERA_1034 人脸识别模组（UVC 出图 + UART2 人脸协议），见文件头第 11 条
    -- face 子表只声明人脸模组的串口与超时，带它才在摄像头测试页出「人脸识别」页签
    -- UART2 由 face.uart_id 独占，不再登记 uart 条目（见文件头第 10 条）
    peripherals = {
        {
            type = "uvc",
            id = "uvc1",
            name = "人脸识别摄像头",
            title = "摄像头",
            en_pin = 132,        -- UVC_EN = W_GPIO4 = GPIO132（推算值，见文件头第 1 条）
            ready_delay = 200,   -- 上电稳定延时 200ms
            w = 960,             -- 首选出图档（实测档位见文件头第 11 条）
            h = 480,
            face = {
                uart_id = 2,         -- 人脸模组串口 = UART2（115200/8N1，库内固定）
                rst_pin = nil,       -- 无独立复位脚，留空
                register_timeout = 15, -- 录入超时（秒）
                verify_timeout = 15,   -- 验证超时（秒）
            },
        },
        {
            type = "rs485",
            id = "485_1",
            name = "非隔离485",
            uart_id = 1,
            de_pin = 65,         -- DE = GPIO65，空闲低电平（接收态）
            power_pin = 135,     -- 供电域 = W_GPIO7 = GPIO135（推算值，见文件头第 1 条）
            baud = 9600,
            test_data = "123",   -- 测试发送内容
            -- 不写 power_hold：该供电域非常供电，由驱动按引用计数上/下电
            -- 不写 manual_init：进 485 测试页自动初始化
        },
        {
            type = "uart",
            id = "uart4",
            name = "UART4",
            uart_id = 13,        -- 通用串口 = W_UART4 = UART13（推算值，见文件头第 1 条）
            baud = 115200,
            databits = 8,
            parity = "N",
            stopbits = 1,
        },
    },

    -- ===== 硬件配置 =====
    hw = {
        -- 屏幕: HX8282 RGB 9寸 1024×600（免序列四合一，无需 SPI 初始化引脚）；背光 PWM3 调光
        lcd = {
            model = "lcd_display_rgb", -- 本工程统一 RGB 驱动（内部走 display.init）
            params = {
                interface = "rgb",     -- RGB 接口
                pin_rst = 15,          -- LCD_DISP = GPIO15（显示使能）
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
            need_buffer = true,               -- RGB 屏必须启用帧缓冲防撕裂
            screen_size = 9.0,                -- 9寸屏
            font = {
                size = 20,               -- 高分屏用 20 号字
            },
            backlight = {
                pwm_ch = 3,                   -- PWM3 背光调光
                pwm_freq = 10000,             -- 10kHz
                level = 100,                  -- 开机亮度（用户调节后存 fskv 优先）
            },
        },
        -- 触摸: GT911 I2C 端口1
        tp = {
            model = "tp_gt911",
            params = {
                port = 1,              -- I2C 端口 1
                pin_rst = 14,          -- TP_RST = GPIO14
                pin_int = 51,          -- TP_INT = GPIO51
                int_type = tp.FALLING, -- 下降沿触发（大屏推荐）
                i2c_speed = i2c.SLOW,  -- I2C 速率 SLOW
                w = 1024,              -- 触摸面板宽度
                h = 600,               -- 触摸面板高度
            },
        },
        -- 音频: 芯片内置 DAC 播放 + 直驱 PA（无麦克风，见文件头第 8 条）
        audio = {
            model = "dac",          -- 内置 DAC 模式
            pa_ctrl = 73,           -- PA(功放)使能引脚 = GPIO73（AUDIOPA_EN）
            pa_on_level = 1,        -- 高电平使能功放
            pa_delay = 200,         -- PA 使能后到起播的等待 ms（防 pop 音）
            play_vol = 70,          -- 默认播放音量(0~100)
        },
        -- USB: 本板 GPIO12 是 Airlink RDY 而非 USB VBUS，关掉 usb_hid_app 对该脚的驱动
        usb = {
            vbus_gpio = false,      -- false = 本板无 VBUS 控制脚，VBUS 由硬件常供电（见文件头第 3 条）
        },
    },

    -- ===== 功能开关（只写 = true 的项）=====
    features = {
        wifi = true,        -- 启用 WiFi（Air601S，Airlink SPI5）—— 本型号固定为 WiFi 版
        sd_card = true,     -- 启用 SD 卡（SPI1，CS=GPIO8）
        speaker = true,     -- 启用喇叭（内置 DAC + 直驱 PA）
        other_func = true,  -- 启用"功能测试"（peripherals 外设清单）
        usb_camera = true,  -- 启用 USB 摄像头（UVC）能力声明
        rs485 = true,       -- 启用 RS485 接口能力声明
        ai_chat = true,     -- 启用"AI聊天助手"内置应用
        app_factory = true, -- 启用"应用工厂"内置应用
        cloud_disk = true,  -- 启用"合宙网盘"内置应用
        file_transfer = true, -- 启用"文件传输"内置应用
        aircloud = true,    -- 启用 AirCloud 数据上报
        usb_hid = true,     -- 启用 USB HID 键鼠能力（与 UVC 二选一，见文件头第 2 条）
    },

    -- ===== AirCloud 数据上报参数 =====
    -- 仅在 features.aircloud = true 时生效
    aircloud = {
        report_cycle = 180, -- 默认上报周期（秒），云端可下发 "cycle:秒数" 改写并存 fskv
        min_cycle    = 5,   -- 允许的最小周期（秒），防止云端下发过密把流量打爆
    },

    -- ===== 统一网络配置（优先级从高到低）=====
    -- 本型号为 WiFi 版：Airlink SPI WiFi（Air601S）挂 SPI5，见文件头第 4 条
    network = {
        {
            type = "wifi_airlink_spi",
            spi_id = 5,             -- SPI5 总线
            cs_pin = 56,            -- SPI5 CS = GPIO56
            rdy_pin = 12,           -- WIFI_RDY = GPIO12（见文件头第 3 条）
            speed = 25 * 1000000,   -- Airlink SPI 时钟 25MHz
        },
    },

    -- ===== 存储设备: SD/TF 卡（SPI1, CS=GPIO8）=====
    storage = {
        sd_card = {
            spi_id = 1,               -- SPI1 总线
            pin_cs = 8,               -- SPI_CS0 = GPIO8 片选
            speed = 20 * 1000 * 1000, -- SD 卡 SPI 时钟 20MHz
        },
    },

    -- ===== UI 显示控制（只写 = true 的项）=====
    ui = {
        show_app_factory = true,     -- 桌面"应用工厂"图标 ← 配 app_factory 时打开
        show_ai_chat = true,         -- 桌面"AI助手"图标 ← 配 ai_chat 时打开
        show_cloud_disk = true,      -- 桌面"合宙网盘"图标 ← 配 cloud_disk 时打开
        show_other_func = true,      -- 桌面"功能测试"图标 ← 配 other_func 时打开
        show_file_transfer = true,   -- 文件管理内"与PC互传"入口 ← 配 file_transfer 时打开
        show_storage_settings = true,-- 设置页存储空间入口 ← 配 sd_card 时打开
        show_video_area = true,      -- 桌面竖屏播放器区
        -- 故意不写 show_wifi_icon / show_brightness_slider / show_camera_preview /
        -- show_sensor_panel / show_aircloud：这几个开关当前不生效，写了无效
    },
}
