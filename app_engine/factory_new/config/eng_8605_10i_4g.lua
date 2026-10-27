--[[
@module  config.eng_8605_10i_4g
@summary Air8605 引擎主机 10寸1024x600 RGB屏 + Airlink UART 4G(780ER2) + USB摄像头 + 非隔离RS485 + SD卡 配置文件（4G 版）
@version 1.1
@date    2026.10.26
@author  江访
@usage
所有 boolean 字段只写 = true 表示开启，不写即视为关闭（无需写 = false）
具体包含哪些参数，如何填写参考：template.lua

注意：
1. Air8605 基于 Air1601 主控模组；本型号为 4G 版（Air780ER2 模组，UART3）。
   WiFi 出货型号已并入 8605W（config/eng_8605w_10i_v0.lua，主控 Air1602），本型号只出 4G 版。
2. 【串口分配】UART1 = 非隔离485、UART2 = 人脸识别 UVC 摄像头串口、UART3 = 4G（Air780ER2）。
   UART1 被非隔离 485 占用，本型号无 Air1103 语音（hw.audio 不配），"功能测试"里也没有
   「录音播放」项 —— 那是 8605W/8605M 的 UART6 接 Air1103 才有的（见 eng_8605w_10i_v0.lua）。
3. 【4G_RESET 先高维持低】PIN4 = GPIO64：上电先拉高 50ms 再拉低 120ms 使能
   （与 eng_1602_10i_v10421 的 airlink 模组复位写法一致）。
4. LCD 为 RGB 10寸 1024×600（免序列四合一），走统一 RGB 驱动 lcd_display_rgb；
   LCD_DISP = PIN80 = GPIO15 作 pin_rst；时序用 1024×600 生态实测组
   hbp=140 hspw=20 hfp=160 vbp=20 vspw=3 vfp=12 @50MHz；背光 PWM3 调光。
5. 触摸 GT911 走 I2C1（PIN33/PIN32 复用，Air1601 复用表写作 CLK/SDA）：
   TP_INT = PIN36 = GPIO51。TP_RST = PIN8 = GPIO72 **不传给 tp.init**：
   传了会真复位且复位期间 C 驱动把 INT 拉低锁 0x5D，本板实测 INT 输出卡死
   （2.79V 恒定、触摸不拉低）；不传则芯片保持上电锁定的 0x14 状态（detect 走
   0x5D→0x14 回退），与实测可用的 demo 序列一致。
   若仍无触摸：把 pin_int 改传 255（LUAT_GPIO_NONE），走 C 层 20ms 轮询兜底（不依赖 INT）。
6. SD 卡走 SPI1 总线，SPI_CS0 = PIN38 = GPIO8，SD_EN = PIN9 = GPIO74。
7. 【看门狗 153D】PIN47 = GPIO57 是喂狗信号输出，经三极管拉地驱动 Air153D 的 WTDOG。
   开关 features.wdt = true、喂狗脚 hw.wdt = { pin = 57 }，watchdog_app 加载后自动喂狗。
   芯片侧 WTDOG 是喂狗输入、PWR_OFF 是复位输出（接系统复位），固件不配置 PWR_OFF。
   超时档位由 STRAP 硬件配置（10分钟 / 60分钟 / 12小时 / 24小时），软件层不参与。
8. 485：485_EN = GPIO14 是 485 收发供电（power_on 拉高常供电），485_EN1 = PIN51 = GPIO65 是
   非隔离 485 的 DE 方向脚。本型号 UART1 只挂非隔离 485 这一路，不配隔离 485。
   features.rs485 目前在 app/ 与 ui/ 里查不到消费方，仅作能力声明。
9. 上电供电轨：5V_EN = GPIO12、9V_EN = PIN46 = GPIO56、12V_EN = PIN72 = GPIO44（本型号专有）。
   5V_EN 与 usb_hid_app 的 VBUS_GPIO=12 是同一物理脚（USB 供电使能），开启 usb_hid 时
   由该应用按需上下电；若 5V 轨还给非 USB 负载供电，需改 usb_hid_app 的硬编码。
]]

return {
    -- ===== 顶层信息 =====
    name = "Engine_Air8605_10inch_1024x600_000_4G_V000", -- 项目命名: {类型}_{芯片}_{尺寸}_{分辨率}_{版本}_{网络}
    chip = "Air1601", -- 主控芯片（RGB 屏 + Airlink UART 外挂 WiFi/4G）
    baseboard = "合宙引擎 AIR8605 V000 10寸", -- 底板型号

    -- ===== 引脚功能复用 =====
    -- Air8605 触摸走 I2C1，需把 PIN33/PIN32 复用成 I2C1（Air1601 复用表写作 CLK/SDA）
    pins = {
        { pin = 33, func = "I2C1_CLK" }, -- I2C1 时钟线（GT911 SCL）
        { pin = 32, func = "I2C1_SDA" }, -- I2C1 数据线（GT911 SDA）
    },

    -- ===== GPIO 上电时序 =====
    -- 按顺序初始化各外设供电和复位（顺序即依赖：电源轨→SD→4G复位→UVC→485）
    power_on = {
        { pin = 44, dir = 0, level = 1 }, -- 12V_EN 拉高，12V 供电
        { pin = 12, dir = 0, level = 1 }, -- 5V_EN 拉高，5V 供电
        { pin = 56, dir = 0, level = 1 }, -- 9V_EN 拉高，9V 供电
        { pin = 74, dir = 0, level = 1 }, -- SD_EN 拉高，SD 卡供电
        { pin = 64, dir = 0, level = 1 },  -- WiFi_RESET = 4G_RESET 拉高 50ms（见上方【共用复位】，不是 485_EN）
        { pin = 58, dir = 0, level = 1, delay = 200 }, -- UVC_EN 拉高，等 200ms 摄像头就绪
        { pin = 14, dir = 0, level = 1 }, -- 485_EN 拉高使能 485 收发（见文件头第 8 条）
    },

    -- ===== 外设清单（运行时可开关的控制脚，与 power_on 的开机默认供电同一物理脚）=====
    -- UVC_EN = PIN48 = GPIO58 / 485_EN = GPIO14 / 485_EN1 = PIN51 = GPIO65
    -- UART1 = 非隔离485、UART2 = 人脸识别 UVC 摄像头串口（见文件头第 2 条）
    peripherals = {
        { type = "uvc",   id = "uvc1",  name = "UVC摄像头", en_pin = 58, ready_delay = 200 }, -- UVC_EN，200ms 就绪
        { type = "rs485", id = "485_1", name = "非隔离485", uart_id = 1, de_pin = 65, power_pin = 14, power_hold = true, baud = 9600, manual_init = true }, -- DE = 485_EN1，供电域 485_EN
        { type = "uart",  id = "uart2", name = "UART2",     uart_id = 2, baud = 115200, databits = 8, parity = "N", stopbits = 1 }, -- 人脸识别 UVC 摄像头串口
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
                pin_rst = 72,          -- TP_RST = GPIO72
                pin_int = 51,          -- TP_INT = WAKEUP = GPIO51
                int_type = tp.FALLING, -- 下降沿触发
                w = 1024,              -- 触摸面板宽度
                h = 600,               -- 触摸面板高度
            },
        },
        -- 看门狗: Air153D 外置硬件看门狗，GPIO57 经三极管拉地喂狗（见文件头看门狗条）
        wdt = {
            pin = 57,               -- PIN47 = GPIO57 → 三极管 → WTDOG
        },
        -- 音频: 本型号 UART1 被非隔离 485 占用，无 Air1103，不配 hw.audio
        -- （有语音的型号见 eng_8605w_10i_v0.lua / eng_8605m_10i_v0.lua 的 UART6 Air1103）
    },

    -- ===== 功能开关（只写 = true 的项）=====
    features = {
        net_4g = true,        -- 启用 4G（Air780ER2，独占 UART3）—— 本型号固定为 4G 版
        sd_card = true,       -- 启用 SD 卡（SPI1，CS=GPIO8）
        usb_camera = true,    -- USB 摄像头（UVC）—— 暂无消费方，仅作能力声明
        rs485 = true,         -- RS485 接口 —— 暂无消费方，仅作能力声明
        other_func = true,    -- 启用"功能测试"（peripherals 外设清单）
        usb_hid = true,       -- USB 键盘鼠标（5V_EN=GPIO12 即 VBUS 供电，见文件头第 9 条）
        app_factory = true,   -- 启用"应用工厂"内置应用
        ai_chat = true,       -- 启用"AI聊天助手"内置应用
        cloud_disk = true,    -- 启用"合宙网盘"内置应用（IoT 登录取 space_key → 空间文件列表 → 下载）
        file_transfer = true, -- 启用"文件传输"内置应用（hzadb日志口：PC↔设备互传文件/共享清单）
        aircloud = true,      -- 启用 AirCloud 数据上报（通用能力探测：有接口就采，不绑定型号）
        wdt = true,           -- 启用外部看门狗（Air153D 喂狗脚见 hw.wdt）
    },

    -- ===== AirCloud 数据上报参数 =====
    -- 仅在 features.aircloud = true 时生效
    aircloud = {
        report_cycle = 180, -- 默认上报周期（秒），云端可下发 "cycle:秒数" 改写并存 fskv
        min_cycle    = 5,   -- 允许的最小周期（秒），防止云端下发过密把流量打爆
    },

    -- ===== 统一网络配置（优先级从高到低）=====
    -- 本型号为 4G 版：Airlink UART 4G（Air780ER2）独占 UART3
    -- WiFi 出货型号见 config/eng_8605w_10i_v0.lua（8605W，主控 Air1602）
    network = {
        {
            type = "4g_airlink_uart",
            uart_id = 3,
            baud = 2000000,
            adapter = socket.LWIP_GP_GW
        },                               -- Air1601 外挂 4G 的网卡标识
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
        show_camera_preview = true,    -- 设置页摄像头预览入口（暂无消费方，仅作能力声明）
        show_other_func = true,        -- 桌面显示"功能测试"图标 ← 配 other_func 时打开
        show_cloud_disk = true,        -- 桌面显示"合宙网盘"入口 ← 配 cloud_disk 时打开
        show_ai_chat = true,           -- 桌面显示"AI助手"入口 ← 配 ai_chat 时打开
        show_app_factory = true,       -- 桌面显示"应用工厂"入口 ← 配 app_factory 时打开
        show_file_transfer = true,     -- 桌面显示"文件传输"入口 ← 配 file_transfer 时打开
        show_aircloud = true,          -- 设置页显示"数据上报"入口 ← 配 aircloud 时打开
    },
}
