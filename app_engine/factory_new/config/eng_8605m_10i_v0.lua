--[[
@module  config.eng_8605m_10i_v0
@summary Air8605M 引擎主机 10寸1024x600 RGB屏 + 4G(UART3/780ER2) + Air1103语音(UART6) + NAND + USB摄像头 + 隔离RS485 + SD卡 配置文件（4G 版）
@version 1.2
@date    2026.11.04
@author  江访
@usage
所有 boolean 字段只写 = true 表示开启，不写即视为关闭（无需写 = false）
具体包含哪些参数，如何填写参考：template.lua

注意：
1. Air8605M 主控平台为 Air1602，只出 4G 版（Air780ER2，UART3）。同底板另有两个出货型号：
   8605W（config/eng_8605w_10i_v0.lua，WiFi 版，UART6 同样接 Air1103）与
   8605B（config/eng_8605b_10i_v0.lua，4G 版，UART6 接第二路隔离 485）。
   三者硬件差异只在 UART1/UART6 的外设划分，屏/触摸/存储/供电完全一致。
2. 【串口分配】UART1 = 隔离485、UART2 = 人脸识别 UVC 摄像头串口、UART6 = Air1103 语音。
   「功能测试」里只有隔离 485，没有非隔离 485（那是 8605 的 UART1），
   但多一个「录音播放」项（Air1103，见下条）。
3. 【音频 = Air1103 录音 + 内置 DAC 播放】Air1103 挂 UART6（固定 2M 波特率），单芯片集成
   MIC + 喇叭 + AEC，**只用来录音**（exaudio 走 model="air1103" + audio_mode="new" 新框架，
   参考 module/Air8784/project/factory）；播放（TTS / 录音回放 / MP4 音轨）一律走芯片
   内置 DAC，由 hw.audio.play_model = "dac" 声明。
   录音与播放对 exaudio 的 model 要求互斥，通路切换由 app/common/audio_route.lua 按需
   重跑 exaudio.setup 完成：录音前切 model="air1103"，播放前切 model="dac"。
   AUDIOPA_EN = PIN55 = GPIO73：power_on 拉高常供电，hw.audio 不写 pa_ctrl
   （写上后 audio_v2 会在播完把它拉低，若该脚兼作 Air1103 供电，语音芯片会跟着掉电）。
   语音芯片上电到就绪约 1.4s（参考工程 boot_ms=1500）；录音每次都会复位芯片，
   恢复 MIC 上行前的静音段由 periph_audio 按 2 秒补时长抵消。
   Air1103 模式录音固定 PCM_16000（16kHz/16bit/单声道）。
   exaudio.setup 的入参（含 uart_id/audio_mode）统一由 app/common/audio_hw.lua 组装，
   六个消费方（tts_app / llm_chat / factory_rec / settings_display_app / video_util /
   periph_audio）都走它，任何一处都不会再漏传 uart_id。
   MP4 的声音走 mplayer → C 层音频框架 → 内置 DAC；若某支素材实测无声，可在 MP4 同目录
   放同名 .pcm 伴音（16kHz/16bit/单声道）由 ui/video_util.lua 经 app/common/pcm_play.lua
   补声，转法：ffmpeg -i xx.mp4 -ac 1 -ar 16000 -f s16le xx.pcm
4. 【4G_RESET 先高维持低】PIN4 = GPIO64：上电先拉高 50ms 再拉低 120ms 使能
   （与 eng_1602_10i_v10421 的 airlink 模组复位写法一致）。
5. LCD 为 RGB 10寸 1024×600（免序列四合一），走统一 RGB 驱动 lcd_display_rgb；
   LCD_DISP = PIN80 = GPIO15 作 pin_rst；时序用 1024×600 生态实测组
   hbp=140 hspw=20 hfp=160 vbp=20 vspw=3 vfp=12 @50MHz；背光 PWM3 调光。
6. 触摸 GT911 走 I2C1：TP_RST = PIN8 = GPIO72，TP_INT = PIN36 = GPIO51
   （Air1602 的 eng_1602 系列 pins 无特殊复用需求，留空）。
7. SD 卡走 SPI1 总线，SPI_CS0 = PIN38 = GPIO8，SD_EN = PIN9 = GPIO74。
   NAND Flash 走 SPI2 总线，SPI2_CS1 = PIN66 = GPIO47。
8. 【看门狗 153D】PIN47 = GPIO57 是喂狗信号输出，经三极管拉地驱动 Air153D 的 WTDOG。
   开关 features.wdt = true、喂狗脚 hw.wdt = { pin = 57 }，watchdog_app 加载后自动喂狗。
   芯片侧 WTDOG 是喂狗输入、PWR_OFF 是复位输出（接系统复位），固件不配置 PWR_OFF。
   超时档位由 STRAP 硬件配置（10分钟 / 60分钟 / 12小时 / 24小时），软件层不参与。
9. 485：485_EN = GPIO14 是 485 收发器总电源（power_on 拉高常供电）。
   本型号 UART1 只挂隔离 485 这一路（J21，收发器 U11）：485_EN1 = PIN51 = GPIO65 是它的
   **方向脚**（DE 与 /RE 并联，高=发 低=收），不是空置脚，必须交给 periph_rs485 翻转。
   J20（非隔离）与 J21（隔离）共用 UART1 和 GPIO65，只能二选一，靠改板切换
   （吹/贴 R104、R1104、R1105），软件改不了。
   features.rs485 目前在 app/ 与 ui/ 里查不到消费方，仅作能力声明。
10. 上电供电轨：5V_EN = GPIO12、9V_EN = PIN46 = GPIO56、12V_EN = PIN72 = GPIO44、
    5VOUT_EN = PIN73 = GPIO52（对外 5V 输出使能）。
    5V_EN = GPIO12 由 power_on 拉高常供电。usb_hid_app 的 VBUS_GPIO=12 也是这个脚，
    同开时会给 UVC 摄像头断电，故带 UVC 的型号不开 features.usb_hid。
]]

return {
    -- ===== 顶层信息 =====
    name = "Engine_Air8605M_10inch_1024x600_000_4G_V000", -- 项目命名: {类型}_{芯片}_{尺寸}_{分辨率}_{版本}_{网络}
    chip = "Air1602", -- 主控芯片（RGB 屏 + 4G(UART3) Airlink 外挂）
    baseboard = "合宙引擎 AIR8605M V000 10寸", -- 底板型号

    -- ===== 引脚功能复用 =====
    -- Air1602 无特殊复用需求（与 eng_1602 系列一致，留空）
    pins = {},

    -- ===== GPIO 上电时序 =====
    -- 按顺序初始化各外设供电和复位（顺序即依赖：电源轨→SD→4G复位→UVC→LCD→1103→485）
    power_on = {
        { pin = 44, dir = 0, level = 1 }, -- 12V_EN 拉高，12V 供电
        { pin = 12, dir = 0, level = 1 }, -- 5V_EN 拉高，5V 供电
        { pin = 56, dir = 0, level = 1 }, -- 9V_EN 拉高，9V 供电
        { pin = 73, dir = 0, level = 1 }, -- AUDIOPA_EN = Air1103 供电，拉高常供电（见文件头第 3 条）
        { pin = 74, dir = 0, level = 1 }, -- SD_EN 拉高，SD 卡供电
        { pin = 64, dir = 1, level = 0},  -- 4G_RESET 拉高 50ms（见文件头第 4 条，不是 485_EN）
        { pin = 58, dir = 0, level = 1, delay = 200 }, -- UVC_EN 拉高，等 200ms 摄像头就绪
        { pin = 14, dir = 0, level = 1 }, -- 485_EN 拉高使能 485 收发（见文件头第 9 条）
    },

    -- ===== 外设清单（运行时可开关的控制脚，与 power_on 的开机默认供电同一物理脚）=====
    -- UVC_EN = PIN48 = GPIO58 / 485_EN = GPIO14（总电源）/ 485_EN1 = PIN51 = GPIO65（方向脚）
    -- UART1 = 隔离485、UART2 = 人脸识别 UVC 摄像头串口、UART6 = Air1103 语音（见文件头第 2 条）
    -- 本型号不出非隔离 485（那是 8605 的 UART1），故"功能测试"里没有该项
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
        { type = "rs485", id = "485_1",  name = "隔离485",   uart_id = 1, de_pin = 65, power_pin = 14, power_hold = true, baud = 9600 }, -- DE = 485_EN1 = GPIO65，供电域 485_EN
        { type = "audio", id = "audio1", name = "录音播放",   record_seconds = 5 }, -- Air1103（UART6），走 hw.audio
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
        -- 音频: Air1103 录音（UART6，内置 MIC）+ 内置 DAC 播放，见文件头第 3 条
        -- 供电脚 AUDIOPA_EN = GPIO73 已在 power_on 拉高常供电，此处不写 pa_ctrl
        audio = {
            model = "air1103",        -- 录音通路：Air1103 语音芯片（exaudio 新框架 UART 驱动）
            play_model = "dac",       -- 播放通路：芯片内置 DAC（TTS / 录音回放 / MP4 音轨）
            uart_id = 6,              -- Air1103 接 UART6（固定 2M 波特率）
            audio_mode = "new",       -- 拉起 audio_v2 新框架（air1103 模式必须）
            play_vol = 70,            -- 默认播放音量(0~100)，llm_chat / video_util / factory_rec 统一读
            mic_vol = 70,             -- 默认录音音量(0~100)（AI 助手语音输入 / 应用工厂录音共用）
            record_format = "PCM_16000", -- Air1103 仅支持 PCM_16000（16kHz/16bit/单声道）
            max_record_time = 30,     -- 最长录音时长(秒)，到时自动停止
        },
    },

    -- ===== 功能开关（只写 = true 的项）=====
    features = {
        net_4g = true,        -- 启用 4G（Air780ER2，UART3）—— 本型号固定为 4G 版
        speaker = true,       -- 启用喇叭（Air1103 内置功放）
        mic = true,           -- 启用麦克风（Air1103 内置 MIC）
        sd_card = true,       -- 启用 SD 卡（SPI1，CS=GPIO8）
        nand_flash = true,    -- 启用 NAND Flash（SPI2，CS=GPIO47）
        usb_camera = true,    -- USB 摄像头（UVC）—— 暂无消费方，仅作能力声明
        rs485 = true,         -- RS485 接口 —— 暂无消费方，仅作能力声明
        other_func = true,    -- 启用"功能测试"（peripherals 外设清单）
        -- usb_hid 不开：USB 键鼠与 UVC 摄像头共用 USB Host 与供电，带 UVC 的型号不启用
        app_factory = true,   -- 启用"应用工厂"内置应用
        ai_chat = true,       -- 启用"AI聊天助手"内置应用（语音经 Air1103）
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
    -- WiFi 出货型号见 config/eng_8605w_10i_v0.lua
    network = {
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
            spi_id = 2,       -- SPI2 总线
            pin_cs = 47,      -- SPI2_CS1 = PIN66 = GPIO47 片选
            speed = 40000000, -- SPI 时钟频率 40MHz
        },
    },

    -- ===== UI 显示控制（只写 = true 的项）=====
    ui = {
        show_4g_icon = true,           -- 桌面顶栏 4G 信号图标
        show_brightness_slider = true, -- 设置页亮度滑块
        show_storage_settings = true,  -- 设置页存储空间入口 ← 配 sd_card/nand_flash 时打开
        show_camera_preview = true,    -- 设置页摄像头预览入口（暂无消费方，仅作能力声明）
        show_other_func = true,        -- 桌面显示"功能测试"图标 ← 配 other_func 时打开
        show_cloud_disk = true,        -- 桌面显示"合宙网盘"入口 ← 配 cloud_disk 时打开
        show_ai_chat = true,           -- 桌面显示"AI助手"入口 ← 配 ai_chat 时打开
        show_app_factory = true,       -- 桌面显示"应用工厂"入口 ← 配 app_factory 时打开
        show_file_transfer = true,     -- 桌面显示"文件传输"入口 ← 配 file_transfer 时打开
        show_aircloud = true,          -- 设置页显示"数据上报"入口 ← 配 aircloud 时打开
    },
}
