--[[
@module  config.eng_8603m2_10i_v0
@summary Air8603M2 引擎主机 10寸1024x600 RGB屏 + Airlink UART 4G(780ER2) + 非隔离RS485(UART1) + UVC摄像头(UART2控制串口) + SD卡 配置文件（4G 版）
@version 1.2
@date    2026.11.04
@author  江访
@usage
所有 boolean 字段只写 = true 表示开启，不写即视为关闭（无需写 = false）
具体包含哪些参数，如何填写参考：template.lua

注意：
1. 【Air8603 系列十型号】同一块底板、同一套供电与屏，只按 UART1 / UART2 的用途分十型号
   （W = WiFi 版，M = 4G 版，各五档），出货型号即配置型号，切勿混用：
     W1 / M1  UART1 = 隔离485    UART2 = UVC 摄像头控制串口
     W2 / M2  UART1 = 非隔离485  UART2 = UVC 摄像头控制串口
     W3 / M3  UART1 = 隔离485    UART2 = 隔离485
     W4 / M4  UART1 = 非隔离485  UART2 = 隔离485
     W5 / M5  UART1 = TTL 串口   UART2 = 隔离485
   本文件是 Air8603M2：UART1 = 非隔离485、UART2 = UVC 摄像头控制串口。
   同一串口划分的 WiFi 出货型号见 config/eng_8603w2_10i_v0.lua，两者只差 network / features / ui 三处。
2. 【音频 = 内置 DAC + 直驱 PA】本系列不出 Air1103 语音芯片版本（UART6 空闲）。
   声音由芯片内置 DAC 播放，PA 功放使能脚直驱控制：
   AUDIOPA_EN = GPIO73，HT6873 高电平使能（pa_on_level = 1），
   power_on 初始拉低关断，起播时 exaudio 拉高。
   本板无麦克风，不开录音相关功能；peripherals 不配 type="audio"（那是「录音播放」测试页），
   故「功能测试」里没有「音频」组。播放由 ui/video_util.lua 读 hw.audio 出声。
3. 【串口分配细则】UART2 是摄像头 / 人脸识别模组的控制串口，画面走 USB，两者互不占用。
   GPIO58 的归属见文件头第 5 条。
4. 【RS485 供电域与方向脚】485_EN = GPIO64 是 485 功能总供电，power_on 拉高使能，之后常供电不回落；
   故各路都写 power_hold = true，驱动只补高不关断（末路 stop 不拉低），
   否则关掉最后一路会把整组 485 的电一起掐掉。
   DE 空闲停在低电平（接收态），发送窗口内才拉高，由 periph_rs485 统一驱动。
   UART1 那路 485 的 DE = 485_EN1 = PIN51 = GPIO65（隔离与非隔离共用）；
   隔离 485（UART2）的 DE = 485_EN2 = PIN48 = GPIO58。
   本型号 UART1 是非隔离 485，power_on 把 485_EN1 拉低停在接收态。
5. 【UVC 摄像头】UVC_EN = PIN48 = GPIO58 是摄像头供电开启信号，power_on 拉高后 200ms 就绪。
   摄像头画面走 USB 数据流，UART2 是这颗摄像头 / 人脸识别模组的控制串口，两者互不占用。
   预览 / 拍照 / 录像由 ui/uvc_preview_win.lua 走 excamera 扩展库独占管理，外设开关只负责供电，
   不再重复 camera.init。预览入口按需求放在「功能测试」里，因此不设 ui.show_camera_preview
   （避免两处入口）。w / h 不写时用预览页默认档 1280×720，预览页会枚举摄像头真正支持的档位取可用档。
6. LCD 为 RGB 10寸 1024×600（免序列四合一，无 SPI 初始化引脚），走统一 RGB 驱动
   lcd_display_rgb；LCD_DISP = PIN80 = GPIO15 作 pin_rst；时序用 1024×600 生态实测组
   hbp=140 hspw=20 hfp=160 vbp=20 vspw=3 vfp=12 @50MHz；背光 PWM3 调光。
7. 触摸 GT911 走 I2C1：TP_RST = PIN8 = GPIO72，TP_INT = PIN36 = GPIO51。
   TP_RST 的复位脉冲在 power_on 里做（先拉低 20ms 再拉高 60ms），INT 上拉锁 0x14 干净启动。
8. SD 卡走 SPI1 总线，SPI_CS0 = PIN38 = GPIO8，SD_EN = PIN9 = GPIO74。
   本板无 NAND Flash，不配 storage.nand_flash、不开 features.nand_flash。
9. 【看门狗 153D】PIN47 = GPIO57 是喂狗信号输出，经三极管拉地驱动 Air153D 的 WTDOG。
   开关 features.wdt = true、喂狗脚 hw.wdt = { pin = 57 }，watchdog_app 加载后自动喂狗。
   芯片侧 WTDOG 是喂狗输入、PWR_OFF 是复位输出（接系统复位），固件不配置 PWR_OFF。
   超时档位由 STRAP 硬件配置（10分钟 / 60分钟 / 12小时 / 24小时），软件层不参与。
   芯片侧 WTDOG 是喂狗输入、PWR_OFF 是复位输出（接系统复位），固件不配置 PWR_OFF。
   超时档位由 STRAP 硬件配置（10分钟 / 60分钟 / 12小时 / 24小时），软件层不参与。
10. 上电供电轨：5V_EN = GPIO12、9V_EN = PIN46 = GPIO56、12V_EN = PIN72 = GPIO44、
   5VOUT_EN = PIN73 = GPIO52（对外 5V 输出使能）。
   5V_EN 与 usb_hid_app 的 VBUS_GPIO=12 是同一物理脚（USB 供电使能），本型号不开 usb_hid
   （features.usb_hid 不写），故不会被该应用上下电；若后续开启 usb_hid，需先核实 5V 轨
   是否还给非 USB 负载供电。
11. 【4G 版不切 STA 网卡】app/ntp/ntp_app.lua 只对 Air1601/1602/1780 且存在 WiFi 网络配置时
   才 socket.dft(socket.LWIP_STA)。本型号 network 只有 4g_airlink_uart，不会触发切换 ——
   与 eng_8605m_10i_v0 的教训一致：4G 桥接型号没有 STA 网卡，盲切会把默认网卡切到无效的
   STA(2)，NTP/天气/FOTA 全部报 adapter index invalid。
]]

return {
    -- ===== 顶层信息 =====
    name = "Engine_Air8603M2_10inch_1024x600_000_4G_V000", -- 项目命名: {类型}_{芯片}_{尺寸}_{分辨率}_{版本}_{网络}
    chip = "Air1603", -- 主控芯片平台（同 config/eng_8607a_10i_v0.lua）
    baseboard = "合宙引擎 AIR8603M2 V000 10寸", -- 底板型号

    -- ===== 引脚功能复用 =====
    -- Air1603 上背光 PWM3 与触摸 I2C1 无需显式复用（与 eng_8607 系列一致，留空）
    pins = {
        -- { pin = 55, func = "PWM3" },     -- 背光 PWM3
        -- { pin = 33, func = "I2C1_CLK" }, -- I2C1 时钟线（GT911 SCL）
        -- { pin = 32, func = "I2C1_SDA" }, -- I2C1 数据线（GT911 SDA）
    },

    -- ===== GPIO 上电时序 =====
    -- 按顺序初始化各外设供电和复位（顺序即依赖：电源轨→SD→功放关断→摄像头/485方向脚→485总供电）
    power_on = {
        { pin = 12, dir = 0, level = 1 },              -- 5V_EN 拉高，5V 供电
        { pin = 56, dir = 0, level = 1, delay = 100 }, -- 9V_EN 拉高，等 100ms 就绪
        { pin = 44, dir = 0, level = 1 },              -- 12V_EN 拉高，12V 供电
        { pin = 52, dir = 0, level = 1 },              -- 5VOUT_EN 拉高，对外 5V 输出使能
        { pin = 72, dir = 1, level = 0 , delay = 20 }, -- 网络模组 RST 拉低 20ms
        { pin = 74, dir = 0, level = 1 },              -- SD_EN 拉高，SD 卡供电
        { pin = 73, dir = 0, level = 0 },              -- AUDIOPA_EN 初始拉低关断功放（HT6873 高电平使能）
        { pin = 58, dir = 0, level = 1, delay = 200 }, -- UVC_EN 拉高，等 200ms 摄像头就绪
        { pin = 64, dir = 0, level = 1 },              -- 485_EN 拉高，485 功能总供电
        { pin = 65, dir = 0, level = 0 },              -- 485_EN1 = 非隔离485 的 DE，空闲停在接收态
    },

    -- ===== 外设清单（功能测试页逐项开关 + 进子页测试）=====
    -- DE 空闲低电平（接收态），发送窗口内由 periph_rs485 拉高，见文件头第 4 条
    -- 摄像头是 AirCAMERA_1034 人脸识别模组（UVC 出图 + UART2 人脸协议）
    -- face 子表只声明人脸模组的串口与超时，带它才在测试页出「人脸识别」页签
    -- UART2 由 face.uart_id 独占，不再登记 uart 条目（否则 periph_uart 会与 exfacecam 抢串口）
    peripherals = {
        {
            type = "uvc",
            id = "uvc1",
            name = "人脸识别摄像头",
            title = "摄像头",
            en_pin = 58,
            ready_delay = 200,
            -- AirCAMERA_1034 实测档位：960x480 / 864x480 / 800x480 / 480x320 / 320x240
            -- 写不在表里的档（如 1280x720）会起流失败、关流重开，首帧拖到 ~11s
            w = 800,
            h = 480,
            -- 画面逆时针 90 度显示（airui.camera 只吃顺时针，270 = 逆时针 90）
            rotation = 270,
            face = {
                uart_id = 2,           -- 人脸模组串口 = UART2（115200/8N1，库内固定）
                rst_pin = nil,         -- 无独立复位脚，留空
                register_timeout = 15, -- 录入超时（秒）
                verify_timeout = 15,   -- 验证超时（秒）
            }
        },
        { type = "rs485", id = "485_1", name = "非隔离485", uart_id = 1, de_pin = 65, power_pin = 64, power_hold = true, baud = 9600 }, -- DE = 485_EN1 = GPIO65，供电域 485_EN
    },

    -- ===== 硬件配置 =====
    hw = {
        -- 屏幕: RGB 10寸 1024×600（免序列四合一，无需 SPI 初始化引脚）；背光 PWM3 调光
        lcd = {
            model = "lcd_display_rgb", -- 本工程统一 RGB 驱动（内部走 display.init）
            params = {
                interface = "rgb",     -- RGB 接口
                pin_rst = 15,          -- LCD_DISP = PIN80 = GPIO15（显示使能）
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
            screen_size = 10.0,               -- 10寸屏
            font = { size = 20 },             -- 高分屏用 20 号字
            backlight = {
                pwm_ch = 3,                   -- PWM3 背光调光
                pwm_freq = 1000,              -- 1kHz
            },
        },
        -- 触摸: GT911 I2C 端口1
        tp = {
            model = "tp_gt911",
            params = {
                port = 1,              -- I2C 端口 1
                pin_rst = 14,          -- TP_RST = PIN44 = GPIO14
                pin_int = 51,          -- TP_INT = WAKEUP = GPIO51
                int_type = tp.FALLING, -- 下降沿触发（大屏推荐）
                w = 1024,              -- 触摸面板宽度
                h = 600,               -- 触摸面板高度
            },
        },
        -- 看门狗: Air153D 外置硬件看门狗，GPIO57 经三极管拉地喂狗（见文件头第 9 条）
        wdt = {
            pin = 57,               -- PIN47 = GPIO57 → 三极管 → WTDOG
        },
        -- 音频: 芯片内置 DAC 播放 + HT6873 功放（AUDIOPA_EN = GPIO73 直驱，无麦克风）
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
        net_4g = true,      -- 启用 4G（Air780ER2，独占 UART3）—— 本型号固定为 4G 版，见文件头第 1 条
        speaker = true,     -- 启用喇叭（内置 DAC + HT6873 功放）
        sd_card = true,     -- 启用 SD 卡（SPI1，CS=GPIO8）
        usb_camera = true,  -- 启用 USB 摄像头（UVC）—— 入口在「功能测试」
        rs485 = true,       -- 启用 RS485 接口
        other_func = true,  -- 启用"功能测试"（peripherals 外设清单）
        wdt = true,         -- 启用外部看门狗（Air153D 喂狗脚见 hw.wdt）
    },

    -- ===== 统一网络配置（优先级从高到低）=====
    -- 本型号为 4G 版：Airlink UART 4G（Air780ER2）独占 UART3
    -- 同一串口划分的 WiFi 出货型号见 config/eng_8603w2_10i_v0.lua
    network = {
        {
            type = "4g_airlink_uart",
            uart_id = 3,
            baud = 2000000,
            adapter = socket.LWIP_GP_GW, -- Air1603 外挂 4G 的网卡标识
        },
    },

    -- ===== 存储设备: SD/TF 卡（SPI1, CS=GPIO8）=====
    storage = {
        sd_card = {
            spi_id = 1,               -- SPI1 总线
            pin_cs = 8,               -- SPI_CS0 = PIN38 = GPIO8 片选
            speed = 20 * 1000 * 1000, -- SD 卡 SPI 时钟 20MHz
        },
    },

    -- ===== UI 显示控制（只写 = true 的项）=====
    ui = {
        show_4g_icon = true,           -- 桌面顶栏 4G 图标
        show_brightness_slider = true, -- 设置页亮度滑块
        show_storage_settings = true,  -- 设置页存储空间入口 ← 配 sd_card 时打开
        show_other_func = true,        -- 桌面显示"功能测试"图标 ← 配 other_func 时打开
        -- show_camera_preview 故意不写：UVC 预览入口在「功能测试」里，见文件头第 5 条
    },
}
