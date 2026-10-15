--[[
@module  config.eng_8605b_10i_v0
@summary Air8605B 引擎主机 10寸1024x600 RGB屏 + WiFi(SPI2/6205) + 4G(UART3/780ER2)双网 + Air1103语音(UART6) + NAND + USB摄像头 + 双RS485 + SD卡 配置文件
@version 1.0
@date    2026.10.14
@author  江访
@usage
所有 boolean 字段只写 = true 表示开启，不写即视为关闭（无需写 = false）
具体包含哪些参数，如何填写参考：template.lua

注意：
1. Air8605B 主控平台为 Air1602。双网并存：WiFi（Air6205，SPI2）+ 4G（Air780ER2，UART3），
   可同时启用（与 evb_1601_7i_v12 双网并存同款写法）。WiFi_RESET 与 4G_RESET 共用
   PIN4 = GPIO64（先高维持低），上电一次复位脉冲同时释放两个模组。
2. 【音频 = Air1103 语音芯片】UART6（固定 2M 波特率），单芯片集成 MIC + 喇叭 + AEC，
   exaudio 走 model="air1103" + audio_mode="new" 新框架（参考 module/Air8784/project/factory）。
   AUDIOPA_EN = PIN55 = GPIO73 是 Air1103 的**供电脚**（非本地功放）：power_on 拉高常供电，
   hw.audio 不写 pa_ctrl（air1103 模式 exaudio 跳过 PA 控制）。
   语音芯片上电到就绪需数百 ms（参考工程 boot_ms=1500），setup 时由 exaudio/air1103 库自行等就绪。
   消费方透传 uart_id 的接线点：app/common/tts_app.lua、app/factory/llm_chat.lua、
   app/factory/factory_rec.lua、ui/video_util.lua（四处 exaudio.setup 白名单）。
3. 【WiFi_RESET = 4G_RESET 先高维持低】PIN4 = GPIO64：上电先拉高 50ms 再拉低 120ms 使能
   （与 eng_1602_10i_v10421 的 airlink 模组复位写法一致）。
4. LCD 为 RGB 10寸 1024×600（免序列四合一），走统一 RGB 驱动 lcd_display_rgb；
   LCD_DISP = PIN80 = GPIO15 作 pin_rst；时序用 1024×600 生态实测组
   hbp=140 hspw=20 hfp=160 vbp=20 vspw=3 vfp=12 @50MHz；背光 PWM3 调光。
5. 触摸 GT911 走 I2C1：TP_RST = PIN8 = GPIO72，TP_INT = PIN36 = GPIO51
   （Air1602 的 eng_1602 系列 pins 无特殊复用需求，留空）。
6. SD 卡走 SPI1 总线，SPI_CS0 = PIN38 = GPIO8，SD_EN = PIN9 = GPIO74。
   NAND Flash 走 SPI2 总线，SPI2_CS1 = PIN66 = GPIO47（与 WiFi 的 SPI2_CS0 = PIN62 = GPIO4
   共用 SPI2，CS 不同）；WiFi_RDY = PIN67 = GPIO42。
7. 【看门狗 153D】WG_OUT = PIN47 = GPIO57 是看门狗芯片的复位输出（接系统复位），
   本工程无喂狗/监听消费方，固件不配置该脚；若量产固件被看门狗复位，需补喂狗逻辑。
8. 485_EN = GPIO14 / 485_EN1 = PIN51 = GPIO65 / 485_EN2 = PIN65 = GPIO49：
   power_on 拉高使能 485 收发供电。features.rs485 目前在 app/ 与 ui/ 里查不到消费方，
   仅作能力声明。
9. 上电供电轨：5V_EN = GPIO12、9V_EN = PIN46 = GPIO56、12V_EN = PIN72 = GPIO44、
   5VOUT_EN = PIN73 = GPIO52（对外 5V 输出使能）。
   5V_EN 与 usb_hid_app 的 VBUS_GPIO=12 是同一物理脚（USB 供电使能），开启 usb_hid 时
   由该应用按需上下电；若 5V 轨还给非 USB 负载供电，需改 usb_hid_app 的硬编码。
]]

return {
    -- ===== 顶层信息 =====
    name = "Engine_Air8605B_10inch_1024x600_000_V000", -- 项目命名: {类型}_{芯片}_{尺寸}_{分辨率}_{版本}
    chip = "Air1602", -- 主控芯片（RGB 屏 + WiFi(SPI2)/4G(UART3) Airlink 外挂）
    baseboard = "合宙引擎 AIR8605B V000 10寸", -- 底板型号

    -- ===== 引脚功能复用 =====
    -- Air1602 无特殊复用需求（与 eng_1602 系列一致，留空）
    pins = {},

    -- ===== GPIO 上电时序 =====
    -- 按顺序初始化各外设供电和复位（顺序即依赖：电源轨→SD→模组复位→UVC→LCD→1103→485）
    -- 【共用复位】WiFi_RESET = 4G_RESET = PIN4 = GPIO64，一次脉冲同时释放两个模组
    power_on = {
        { pin = 72, dir = 0, level = 0, delay = 20 },  -- TP_RST 拉低 20ms，干净复位触摸芯片
        { pin = 72, dir = 0, level = 1, delay = 60 },  -- 释放复位：INT 上拉锁 0x14 干净启动，INT 输出可恢复
        { pin = 12, dir = 0, level = 1 }, -- 5V_EN 拉高，5V 供电
        -- { pin = 15, dir = 0, level = 1 }, -- LCD_DISP 拉高使能 LCD 显示
        { pin = 73, dir = 0, level = 1 }, -- AUDIOPA_EN = Air1103 供电，拉高常供电（见文件头第 2 条）
        { pin = 56, dir = 0, level = 1 }, -- 9V_EN 拉高，等 100ms 就绪
        { pin = 44, dir = 0, level = 1 }, -- 12V_EN 拉高，12V 供电
        { pin = 52, dir = 0, level = 1 }, -- 5VOUT_EN 拉高，对外 5V 输出使能
        { pin = 74, dir = 0, level = 1 }, -- SD_EN 拉高，SD 卡供电
        { pin = 64, dir = 0, level = 1 }, -- WiFi_RESET = 4G_RESET 先拉高 50ms（见文件头第 3 条）
        { pin = 64, dir = 0, level = 0 }, -- 维持低 120ms，WiFi/4G 模组复位释放
        { pin = 58, dir = 0, level = 1, }, -- UVC_EN 拉高，等 200ms 摄像头就绪
        { pin = 14, dir = 0, level = 1 }, -- 485_EN 拉高使能 485 收发（见文件头第 8 条）
        { pin = 65, dir = 0, level = 1 }, -- 485_EN1 拉高使能 485 收发（见文件头第 8 条）
        { pin = 49, dir = 0, level = 1 }, -- 485_EN2 拉高使能 485 收发（见文件头第 8 条）
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
                pin_int = 255,         -- 255=LUAT_GPIO_NONE → C 层 20ms 轮询模式，不依赖 INT 线（本板 INT 实测卡死）
                i2c_polling = false,   -- I2C 中断模式（对齐 demo 实测可用路径，见文件头第 5 条）
                w = 1024,              -- 触摸面板宽度
                h = 600,               -- 触摸面板高度
                direction = 0,          -- 不旋转（由 AirUI set_rotation 统一处理）
            },
        },
        -- 音频: Air1103 外置语音芯片（UART6，内置 MIC/喇叭/AEC），见文件头第 2 条
        -- 供电脚 AUDIOPA_EN = GPIO73 已在 power_on 拉高常供电，此处不写 pa_ctrl
        audio = {
            model = "air1103",        -- Air1103 语音芯片（exaudio 新框架 UART 驱动）
            uart_id = 6,              -- Air1103 接 UART6（固定 2M 波特率）
            audio_mode = "new",       -- 拉起 audio_v2 新框架（air1103 模式必须）
            play_vol = 70,            -- 默认播放音量(0~100)，llm_chat / video_util / factory_rec 统一读
            mic_vol = 70,             -- 默认录音音量(0~100)（AI 助手语音输入 / 应用工厂录音共用）
            record_format = "AMR_NB", -- 录音格式（AMR 体积小，上传 ASR 省内存）
            max_record_time = 30,     -- 最长录音时长(秒)，到时自动停止
        },
    },

    -- ===== 功能开关（只写 = true 的项）=====
    features = {
        wifi = true,          -- 启用 WiFi（Air6205，SPI2）—— 与 4G 双网并存
        net_4g = true,        -- 启用 4G（Air780ER2，UART3）—— 与 WiFi 双网并存
        speaker = true,       -- 启用喇叭（Air1103 内置功放）
        mic = true,           -- 启用麦克风（Air1103 内置 MIC）
        sd_card = true,       -- 启用 SD 卡（SPI1，CS=GPIO8）
        nand_flash = true,    -- 启用 NAND Flash（SPI2，CS=GPIO47）
        usb_camera = true,    -- USB 摄像头（UVC）—— 暂无消费方，仅作能力声明
        rs485 = true,         -- RS485 接口 —— 暂无消费方，仅作能力声明
        usb_hid = true,       -- USB 键盘鼠标（5V_EN=GPIO12 即 VBUS 供电，见文件头第 9 条）
        app_factory = true,   -- 启用"应用工厂"内置应用
        ai_chat = true,       -- 启用"AI聊天助手"内置应用（语音经 Air1103）
        cloud_disk = true,    -- 启用"合宙网盘"内置应用（IoT 登录取 space_key → 空间文件列表 → 下载）
        file_transfer = true, -- 启用"文件传输"内置应用（hzadb日志口：PC↔设备互传文件/共享清单）
        aircloud = true,      -- 启用 AirCloud 数据上报（通用能力探测：有接口就采，不绑定型号）
    },

    -- ===== AirCloud 数据上报参数 =====
    -- 仅在 features.aircloud = true 时生效
    aircloud = {
        report_cycle = 180, -- 默认上报周期（秒），云端可下发 "cycle:秒数" 改写并存 fskv
        min_cycle    = 5,   -- 允许的最小周期（秒），防止云端下发过密把流量打爆
    },

    -- ===== 统一网络配置（优先级从高到低）=====
    -- WiFi（AirLink SPI2）+ 4G（AirLink UART3）互不冲突，可同时开启
    network = {
        -- 最高优先级：WiFi（AirLink SPI2，6205 模组）
        {
            type = "wifi_airlink_spi",
            spi_id = 2,          -- SPI2
            cs_pin = 4,          -- SPI2_CS0 = PIN62 = GPIO4
            rdy_pin = 42,        -- WIFI_RDY = PIN67 = GPIO42
            speed = 8 * 1000000, -- 8MHz
        },

        -- 第二优先级：4G（AirLink UART3，Air780ER2）
        {
            type = "4g_airlink_uart",
            uart_id = 3,
            baud = 2 * 1000 * 1000,
            adapter = socket.LWIP_GP_GW,
        },
    },

    -- ===== 存储设备: SD/TF 卡（SPI1, CS=GPIO8）+ NAND Flash（SPI2, CS=GPIO47）=====
    storage = {
        sd_card = {
            spi_id = 1,               -- SPI1 总线
            pin_cs = 8,               -- SPI_CS0 = PIN38 = GPIO8 片选
            speed = 20 * 1000 * 1000, -- SD 卡 SPI 时钟 20MHz
        },
        nand_flash = {
            spi_id = 2,       -- SPI2 总线（与 WiFi 共用，CS 不同）
            pin_cs = 47,      -- SPI2_CS1 = PIN66 = GPIO47 片选
            speed = 40000000, -- SPI 时钟频率 40MHz
        },
    },

    -- ===== UI 显示控制（只写 = true 的项）=====
    ui = {
        show_wifi_icon = true,         -- 桌面顶栏 WiFi 图标
        show_4g_icon = true,           -- 桌面顶栏 4G 信号图标
        show_brightness_slider = true, -- 设置页亮度滑块
        show_storage_settings = true,  -- 设置页存储空间入口 ← 配 sd_card/nand_flash 时打开
        show_camera_preview = true,    -- 设置页摄像头预览入口（暂无消费方，仅作能力声明）
        show_cloud_disk = true,        -- 桌面显示"合宙网盘"入口 ← 配 cloud_disk 时打开
        show_ai_chat = true,           -- 桌面显示"AI助手"入口 ← 配 ai_chat 时打开
        show_app_factory = true,       -- 桌面显示"应用工厂"入口 ← 配 app_factory 时打开
        show_file_transfer = true,     -- 桌面显示"文件传输"入口 ← 配 file_transfer 时打开
        show_aircloud = true,          -- 设置页显示"数据上报"入口 ← 配 aircloud 时打开
    },
}
