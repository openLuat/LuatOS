--[[
@module  config.eng_8602_9i_v0
@summary Air8601 引擎主机 9寸1024x600 RGB屏(HX8282) + Airlink UART WiFi(6205)/4G(780ER2)二选一 + USB摄像头 + 双RS485 + SD卡 + 喇叭 配置文件
@version 1.1
@date    2026.09.18
@author  江访
@usage
所有 boolean 字段只写 = true 表示开启，不写即视为关闭（无需写 = false）
具体包含哪些参数，如何填写参考：template.lua

注意：
1. Air8601 基于 Air1601 主控模组，搭配 Air6205 WiFi / Air780ER2 4G（二选一，通过电阻切换）。
2. UART3 连接 Airlink 模组（WiFi 或 4G），二者共享 UART3 不可同时使用。
3. LCD 为 HX8282 RGB 9寸 1024×600，走本工程统一 RGB 驱动 lcd_display_rgb，背光 PWM3 可调光。
4. 触摸 GT911 走 I2C1，需 pins 配置 I2C1 功能复用。
5. SD 卡走 SPI1 总线，CS = PIN38（GPIO 待确认）。
6. 双 RS485：UART1 = 485_1，UART2 = 485_2；485_EN1 = PIN51，485_EN2 = GPIO57（PIN47）。
7. 【默认组网】默认启用 WiFi（airlink UART3）；4G 相关项全部注释（features.net_4g /
   network 的 4g_airlink_uart / ui.show_4g_icon）。切到 4G 时把这三处按注释互换即可，
   切勿两组同时放开 —— 二者抢同一个 UART3。
8. 【LCD_DE = GPIO25】本板 LCD_DE 接 GPIO25（PIN58），但本工程统一 RGB 驱动 lcd_display_rgb
   只把白名单字段转给 display.init("custom", ...)，pin_de 不在白名单里 —— 写了也是空操作，
   故此处注释掉。若上板发现屏不亮/花屏，可考虑给 drv/lcd/lcd_display_rgb.lua 的 cfg 白名单
   补 pin_de 透传。
9. 【PIN55 双重映射】用户提供的引脚表中 AUDIOPA_EN = PIN55 与 UVC_EN = PIN55 = GPIO73
   共用同一物理引脚，存在冲突。此处按 7 寸版本（eng_8601_7i_v0）将 UVC_EN 设为 GPIO73，
   AUDIOPA_EN 设为 GPIO 输出（具体 GPIO 待确认）。若上板发现喇叭功放/摄像头无法同时使能，
   请核实原理图中 AUDIOPA_EN 的实际 GPIO 编号。
10. 【PIN51 双重映射】485_EN1 = PIN51 与 SD_EN = PIN51 = GPIO65 共用同一物理引脚，
    存在冲突。此处按 GPIO65 初始化（SD 供电优先），485_EN1 的 GPIO 待确认。若上板发现
    RS485_1 无法收发或 SD 卡无法识别，请核实原理图中 485_EN1 的实际 GPIO 编号。
11. features.usb_camera / rs485 与 ui.show_camera_preview 目前在 app/ 与 ui/ 里查不到消费方
    （与7寸配置一致），写了不报错也不生效，此处保留仅作能力声明。
12. 音频使用芯片内置 DAC 播放（非 ES8311 外挂芯片），PA 功放使能 = GPIO73（AUDIOPA_EN = PIN55），
    低电平有效。录音走线路输入（LINE_IN），格式 AMR_NB。参考 hzv_1024_display demo。
12. 本配置由7寸版本（config/eng_8601_7i_v0.lua）移植，差异：屏幕尺寸 7→9 寸、
    LCD_DE 新增 GPIO25（驱动暂不透传）、TP_RESET 改为 GPIO72、TP_INT 改为 GPIO51、
    SD_CS 改为 PIN38、新增双 RS485（UART1+UART2）。
]]
return {
    -- ===== 顶层信息 =====
    name = "Engine_Air8602_9inch_1024x600_010_V000", -- 项目命名: {类型}_{芯片}_{尺寸}_{分辨率}_{版本}
    chip = "Air1601", -- 主控芯片（RGB 屏 + Airlink UART 外挂 WiFi/4G）
    baseboard = "合宙引擎 AIR8601 V010 9寸", -- 底板型号

    -- ===== 引脚功能复用 =====
    -- Air8601 触摸走 I2C1，需把 PIN33/PIN32 复用成 I2C1（Air1601 复用表写作 CLK/SDA）
    pins = {
        { pin = 33, func = "I2C1_CLK" }, -- I2C1 时钟线（GT911 SCL）
        { pin = 32, func = "I2C1_SDA" }, -- I2C1 数据线（GT911 SDA）
    },

    -- ===== GPIO 上电时序 =====
    -- 按顺序初始化各外设供电和复位（顺序即依赖：喇叭→LCD→WiFi→UVC→4G→TP）
    -- 【PIN55 冲突】见文件头第 9 条：AUDIOPA_EN 与 UVC_EN 共用 PIN55，此处暂按 GPIO73（UVC_EN）初始化
    -- 【PIN51 冲突】见文件头第 10 条：485_EN1 与 SD_EN 共用 PIN51，此处暂按 GPIO65（SD_EN）初始化
    power_on = {
        { pin = 74, dir = 0, level = 1 },              -- SD_EN 拉高
        { pin = 15, dir = 1, level = 0, delay = 100 }, -- WIFI_RST 高电平拉地
        { pin = 55, dir = 0, level = 1 },              -- AUDIOPA_EN 拉高使能喇叭功放（具体 GPIO 待确认，见第 9 条）
        { pin = 15, dir = 0, level = 1 },              -- LCD_DISP 拉高使能 LCD 显示
        { pin = 73, dir = 0, level = 1, delay = 200 }, -- UVC_EN 拉高使能 USB 摄像头供电，等 200ms 就绪
        { pin = 58, dir = 0, level = 1, delay = 50 },  -- RESET_4G 拉高释放 4G 复位，等 50ms
    },

    -- ===== 硬件配置 =====
    hw = {
        -- 屏幕: HX8282 RGB 9寸 1024×600（四合一芯片，无需 SPI 初始化引脚）；背光 PWM3 调光
        lcd = {
            model = "lcd_display_rgb", -- 本工程统一 RGB 驱动（内部走 display.init）
            params = {
                interface = "rgb",     -- RGB 接口
                pin_rst = 15,          -- LCD_DISP = GPIO15（复位/显示使能）
                -- pin_de = 25,                -- LCD_DE = GPIO25 数据使能 —— 见文件头第 8 条，驱动不透传
                w = 1024,              -- 水平分辨率
                h = 600,               -- 竖直分辨率
                -- RGB 时序参数（与7寸 HX8282 一致，同款四合一芯片）
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
                pin_rst = 72,          -- TP_RESET = PIN8 = GPIO72
                pin_int = 51,          -- TP_INT = WAKEUP = GPIO51
                int_type = tp.FALLING, -- 下降沿触发
                w = 1024,              -- 触摸面板宽度
                h = 600,               -- 触摸面板高度
            },
        },
        -- 音频: 内置 DAC 播放 + 线路输入录音（非 ES8311 外挂芯片）
        -- PA(功放) 使能 = GPIO73（AUDIOPA_EN = PIN55），低电平有效；DAC 延时 6ms
        audio = {
            model = "dac",   -- 内置 DAC 模式（Air1601 芯片自带 DAC）
            pa_ctrl = 73,    -- PA(功放)使能引脚 = GPIO73（AUDIOPA_EN = PIN55）
            pa_on_level = 0, -- 低电平使能功放
            dac_delay = 6,   -- DAC 初始化延时 6ms
        },
    },

    -- ===== 功能开关（只写 = true 的项）=====
    features = {
        wifi = true,        -- 启用 WiFi（Air6205，与 4G 二选一）
        -- net_4g = true,                -- × 4G 未启用（与 WiFi 共享 UART3，默认走 WiFi）
        speaker = true,     -- 启用喇叭（DAC PIN18 接 LM4871 功放）
        sd_card = true,     -- 启用 SD 卡（SPI1，CS=PIN38）
        rs485 = true,       -- RS485 接口 —— 见文件头第 11 条：暂无消费方（UART1+UART2 双路）
        app_factory = true, -- 启用"应用工厂"内置应用
        ai_chat = true,     -- 启用"AI聊天助手"内置应用
        cloud_disk = true,  -- 启用"合宙网盘"内置应用（IoT 登录取 space_key → 空间文件列表 → 下载）
    },

    -- ===== 统一网络配置（优先级从高到低）=====
    -- Air6205 WiFi 与 Air780ER2 4G 共享 UART3，硬件上通过电阻二选一
    -- ⇒ 默认启用 WiFi；切 4G 时把下面两条的注释互换，切勿同时放开
    network = {
        -- Airlink UART WiFi（6205 模组，占用 UART3）—— 默认启用
        {
            type = "wifi_airlink_uart",
            uart_id = 3,
            baud = 2000000
        },

        -- Airlink UART 4G（Air780ER2，同样占用 UART3，与 WiFi 互斥）
        -- { type = "4g_airlink_uart",
        --   uart_id = 3, baud = 2000000,
        --   adapter = socket.LWIP_GP_GW },   -- Air1601 外挂 4G 的网卡标识
    },

    -- ===== 存储设备: SD/TF 卡（SPI1, CS=PIN38）=====
    storage = {
        sd_card = {
            spi_id = 1,               -- SPI1 总线
            pin_cs = 38,              -- SPI1_CS0 = PIN38（GPIO 待确认，见文件头第 5 条）
            speed = 20 * 1000 * 1000, -- SD 卡 SPI 时钟 20MHz
        },
    },

    -- ===== UI 显示控制（只写 = true 的项）=====
    ui = {
        show_wifi_icon = true,         -- 桌面顶栏 WiFi 图标 ← 配 wifi 时打开
        -- show_4g_icon = true,           -- × 桌面顶栏 4G 图标（net_4g 关闭时不要开，会显示假图标）
        show_brightness_slider = true, -- 设置页亮度滑块
        show_storage_settings = true,  -- 设置页存储空间入口 ← 配 sd_card 时打开
        show_camera_preview = true,    -- 设置页摄像头预览入口 ← 见文件头第 11 条
        show_cloud_disk = true,        -- 桌面显示"合宙网盘"入口 ← 配 cloud_disk 时打开
        show_ai_chat = true,           -- 桌面显示"AI助手"入口 ← 配 ai_chat 时打开
        show_app_factory = true,       -- 桌面显示"应用工厂"入口 ← 配 app_factory 时打开
    },
}
