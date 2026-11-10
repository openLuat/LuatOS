--[[
@module  config.eng_8601_7i_4g
@summary Air8601 引擎主机 7寸1024x600 RGB屏(HX8282) + Airlink UART 4G(780ER2) + 人脸识别摄像头 + RS485 + SD卡 + 喇叭 配置文件（4G 版）
@version 1.6
@date    2026.10.30
@author  江访
@usage
所有 boolean 字段只写 = true 表示开启，不写即视为关闭（无需写 = false）
具体包含哪些参数，如何填写参考：template.lua

注意：
1. Air8601 基于 Air1601 主控模组，搭配 Air6205 WiFi / Air780ER2 4G（二选一，通过电阻切换）。
2. UART3 连接 Airlink 模组（WiFi 或 4G），二者共享 UART3 不可同时使用。
3. LCD 为 HX8282 RGB 7寸 1024×600，走本工程统一 RGB 驱动 lcd_display_rgb，背光 PWM3 可调光。
4. 触摸 GT911 走 I2C1，需 pins 配置 I2C1 功能复用。
5. SD 卡走 SPI1 总线，CS = GPIO8。
6. 【固定组网 · 4G 版】本型号固定启用 Airlink UART 4G（Air780ER2，独占 UART3）。
   同底板另有 WiFi 出货型号 Engine_Air8601_7inch_1024x600_010_WiFi_V000（config/eng_8601_7i_wifi.lua），
   两型号是同一底板电阻切换的不同出货型号，配置只差 features / network / ui 三处，切勿混用。
   （原 eng_8601_7i_v0.lua 单文件注释互换两组网络配置的做法已废弃，2026.10.14 拆分为两个独立型号。）
7. 【LCD_DE 待确认】原厂 Air8601 样例（module/Air1601_Air1602/project/Air8601_deposit_cabinet/
   hardware.lua）写的是 pin_de = 25，但那条路径是 lcd.init("hx8282", params)（params 整体透传）；
   本工程统一 RGB 驱动 lcd_display_rgb 只把白名单字段转给 display.init("custom", ...)，
   pin_de 不在白名单里 —— 写了也是空操作，故此处注释掉。本工程同款 HX8282 板
   （evb_1601_7i_v11 / evb_1601_7i_v12）均未设 pin_de 且能正常显示。
   若上板发现屏不亮/花屏，给 drv/lcd/lcd_display_rgb.lua 的 cfg 白名单补 pin_de 透传。
   （原"改用 HX8282 专用屏驱动"这条退路已废弃：本工程已整体移除依赖 lcd 库的 SPI 屏驱动。）
8. 【与官方样例不一致处，均按本板原理图填写】① 官方 TP 是 pin_rst=72 / pin_int=51，本配置是
   pin_rst=56 / pin_int=gpio.WAKEUP0；② 官方背光是 GPIO38 直驱（其注释写明"勿用 GPIO13"），
   本配置是 PWM3 调光。上板前请再核对一次。
9. 本配置由 factory 工程同名配置（factory/config/eng_8601_7i_v0.lua）移植，硬件参数一致；
   差异只在驱动模型（本工程走 lcd_display_rgb）与 UI 段（桌面入口开关）。
10. features.usb_camera / rs485 与 ui.show_camera_preview 在 app/ 与 ui/ 里没有直接消费方，
    写了不报错也不生效，保留仅作能力声明。UVC 的实际开关与测试走 config.peripherals
    （见第 12 条）；RS485 同理，配了 peripherals 里的 rs485 条目才会出现在功能测试页。
11. 音频使用芯片内置 DAC 播放（非 ES8311 外挂芯片），PA 功放使能 = GPIO74（AUDIOPA_EN），
    **低电平有效**（pa_on_level = 0 → 播放时 exaudio 把 GPIO74 拉低使能，空闲/关机拉高）。
    录音走线路输入（LINE_IN），格式 AMR_NB。参考 hzv_1024_display demo。
    本表字段的消费方（全部在通用模块里，型号差异只允许体现在这里）：
      ▪ app/factory/llm_chat.lua（TTS 播报 / STT 语音输入）：
        model / pa_ctrl / pa_on_level / dac_delay / dac_ctrl / i2c_id / i2s_sample /
        bits_per_sample / i2s_framebit / channels / pa_delay / tx_bus_type / rx_bus_type /
        audio_mode / play_vol
      ▪ app/factory/factory_rec.lua（应用工厂录音）：
        同上 + record_format / max_record_time / mic_vol
      ▪ ui/video_util.lua（桌面视频配套音轨）：
        model / pa_ctrl / pa_on_level / dac_delay / play_vol
    注意 dac_delay 只在旧音频框架 audio_setup() 里被消费；新框架 audio_v2 的 DAC 通路
    实际只把 pa_delay 透传给 audio_v2.config_pa_power_ctrl()，dac_delay 不起作用（保留仅为兼容）。
12. 【UVC 测试】UVC_EN = GPIO73（power_on 里已拉高常供电），测试入口三件套缺一不可：
    config.peripherals 加 uvc 条目 + features.other_func = true + ui.show_other_func = true。
    桌面「功能测试」→ 摄像头行（可通断电）→ 点行进摄像头测试页（ui/uvc_preview_win.lua），
    数据流由该页独占走 excamera，periph_uvc 只管供电脚。
    摄像头 MJPEG 分辨率由预览页按摄像头实际支持的档位自适应选取（像素数上限 max_pixels，
    缺省 921600 = 1280×720，超了会挤爆内存导致预览无画面），条目里的 w / h 只是首选档。
13. 【RS485】485_RE_DE = PIN8 = GPIO72，485_UART_TXD / 485_UART_RXD 都在 UART1，
    无独立 485 供电脚（peripherals 的 rs485 条目不写 power_pin）。本板只有 1 路 485，
    测试页只记收发、不做两路互接判定。
    power_on 里 GPIO72 已拉高（该行注释写作「TP I2C 上拉」，与 485_RE_DE 是同一物理脚）；
    进「485」测试页后由 periph_rs485 把 DE 置接收态再收发。
    本路写 manual_init = true：进 485 测试页不自动上电开串口，点该路按钮才初始化。
14. 【人脸识别摄像头】本板摄像头是 AirCAMERA_1034 人脸识别模组，不是纯 UVC 摄像头：
    同一颗模组出两条通路 —— USB 走 UVC 出 MJPEG 画面，UART2 走协议做人脸录入 / 验证 / 用户管理。
    供电共用 UVC_EN = GPIO73，断电会同时杀掉画面与人脸识别。录入 / 验证前测试页会把 GPIO73
    断电重枚举一次（模组出完图停流后停在出图模式，录入指令不回包），再重开人脸串口。
    人脸模组接线：Air1601 UART2 TX/RX → 模组 RX/TX，115200/8N1（exfacecam 库内固定波特率），
    无独立复位脚（face.rst_pin 不填）。UART2 在本板不与别的外设共用（485 是 UART1，Airlink 是 UART3）。
    摄像头条目带 face 子表即在测试页多出「人脸识别」页签（录入 / 验证 / 删除全部 / 版本）；
    不写 face 子表的型号测试页与原来完全一致，只有「UVC 测试」。
]]

return {
    -- ===== 顶层信息 =====
    name = "Engine_Air8601_7inch_1024x600_010_4G_V000", -- 项目命名: {类型}_{芯片}_{尺寸}_{分辨率}_{版本}_{网络}
    chip = "Air1601", -- 主控芯片（RGB 屏 + Airlink UART 外挂 WiFi/4G）
    baseboard = "合宙引擎 AIR8601 V010 7寸", -- 底板型号

    -- ===== 引脚功能复用 =====
    -- Air8601 触摸走 I2C1，需把 PIN33/PIN32 复用成 I2C1（Air1601 复用表写作 CLK/SDA）
    pins = {
        { pin = 33, func = "I2C1_CLK" }, -- I2C1 时钟线（GT911 SCL）
        { pin = 32, func = "I2C1_SDA" }, -- I2C1 数据线（GT911 SDA）
    },

    -- ===== GPIO 上电时序 =====
    -- 按顺序初始化各外设供电和复位（顺序即依赖：喇叭→LCD→WiFi→UVC→4G→TP）
    power_on = {
        { pin = 65, dir = 1, level = 1, delay = 100 }, -- SD_EN 拉高，等 100ms 就绪
        { pin = 57, dir = 1, level = 0, delay = 100 }, -- WIFI_EN 拉高使能 WiFi 模组供电，等 100ms 就绪
        -- UVC_EN：上电常供电，功能测试页开关可再通断（见文件头第 12 条）
        -- 该脚同时供 UVC 出图与人脸识别模组（见文件头第 14 条），断电两者一起掉
        { pin = 73, dir = 0, level = 1, delay = 200 }, -- UVC_EN 拉高使能摄像头供电，等 200ms 就绪
        { pin = 64, dir = 1, level = 0, delay = 50 },  -- RESET_4G 拉高释放 4G 复位，等 50ms
        { pin = 15, dir = 0, level = 1 },              -- LCD_DISP 拉高使能 LCD 显示
        { pin = 72, dir = 0, level = 1 },              -- TP I2C 上拉（485_RE_DE 拉高，同时 TP I2C 就绪）
    },

    -- ===== 外设清单（功能测试页逐项开关 + 进子页测试）=====
    -- 摄像头是 AirCAMERA_1034 人脸识别模组（UVC 出图 + UART2 人脸协议，见文件头第 14 条）
    -- UVC_EN = GPIO73，上电序列已常供电，页内开关可再通断；点行进摄像头测试页
    -- 未配 w / h 时预览页自适应取档（见文件头第 12 条）
    -- face 子表只声明人脸模组的串口与超时，带它才在测试页出「人脸识别」页签
    -- 485_1 是本板唯一一路 485（见文件头第 13 条）
    -- manual_init = true：485 测试页进页面不自动上电开串口，点该路按钮才初始化
    peripherals = {
        {
            type = "uvc",
            id = "uvc1",
            name = "人脸识别摄像头",
            title = "摄像头",
            en_pin = 73,
            ready_delay = 200,
            -- 首选出图档必须落在摄像头真实支持的档位里：本模组只报
            -- 960x480 / 864x480 / 800x480 / 480x320 / 320x240，没有 1280x720。
            -- 写 1280x720 时 excamera 匹配不上会按默认 format0/frame0(raw 0x0) 起流，
            -- 必然失败，预览页再退回"改用实际支持分辨率"关流重开，首帧从 ~1.4s 拖到 ~11s
            -- （实测日志：11.63s 用 1280x720 起流失败 → 20.6s 才重新枚举成功出图）。
            -- 800x480 是其中像素数最大且匹配得上的档，故作为首选。
            w = 800,
            h = 480,                   -- UVC_EN，200ms 就绪；首选出图档（实测档位见上）
            -- 画面顺时针 90 度显示（airui.camera 只吃顺时针，90 = 顺时针 90）
            rotation = 90,
            face = {
                uart_id = 2,           -- 人脸模组串口 = UART2（115200/8N1，库内固定）
                rst_pin = nil,         -- 无独立复位脚，留空
                register_timeout = 15, -- 录入超时（秒）
                verify_timeout = 15,   -- 验证超时（秒）
                mode = "auto",         -- serial=停流; auto=不停流降帧识别、失败停流重试（默认）; concurrent=只并行
                busy_fps = 3,          -- 并行识别时 UVC 帧率
                live_timeout = 3000,   -- 等画面新帧超时(ms)，超时降级串行
            }
        },
        {
            type = "rs485",
            id = "485_1",
            name = "非隔离485",
            uart_id = 1,
            de_pin = 72,
            baud = 9600,
            manual_init = true
        }, -- DE = 485_RE_DE = PIN8 = GPIO72，无独立供电脚
    },

    -- ===== 硬件配置 =====
    hw = {
        -- 屏幕: HX8282 RGB 7寸 1024×600（四合一芯片，无需 SPI 初始化引脚）；背光 PWM3 调光
        lcd = {
            model = "lcd_display_rgb", -- 本工程统一 RGB 驱动（内部走 display.init）
            params = {
                interface = "rgb",     -- RGB 接口
                pin_rst = 15,          -- LCD_DISP = GPIO15（复位/显示使能）
                -- pin_de = 25,                -- LCD_DE = GPIO25 数据使能 —— 见文件头第 7 条，驱动不透传
                w = 1024,              -- 水平分辨率
                h = 600,               -- 竖直分辨率
                -- RGB 时序参数（Air8601 硬件实测值，与原厂样例完全一致）
                hbp = 140,
                hspw = 20,
                hfp = 160,
                vbp = 20,
                vspw = 3,
                vfp = 12,
                bus_speed = 50 * 1000 * 1000, -- RGB 总线时钟 50MHz
            },
            need_buffer = true,               -- RGB 屏必须启用帧缓冲防撕裂
            screen_size = 7.0,                -- 7寸屏
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
                pin_rst = 56,          -- TP_RESET = GPIO56
                pin_int = 51,          -- TP_INT = WAKEUP0
                int_type = tp.FALLING, -- 下降沿触发
                w = 1024,              -- 触摸面板宽度
                h = 600,               -- 触摸面板高度
            },
        },
        -- 音频: 内置 DAC 播放 + 线路输入录音（非 ES8311 外挂芯片）
        -- PA(功放) 使能 = GPIO74（AUDIOPA_EN），低电平有效
        audio = {
            model = "dac",   -- 内置 DAC 模式（Air1601 芯片自带 DAC，无 I2S 外挂 codec）
            pa_ctrl = 74,    -- PA(功放)使能引脚 = GPIO74（AUDIOPA_EN）
            pa_on_level = 0, -- 低电平使能功放（与本文件 power_on 里 GPIO74 初始给高电平互为配合）
            dac_delay = 6,   -- DAC 启动前冗余时间（旧框架用；新框架 audio_v2 不消费，见文件头第 11 条）
            pa_delay = 10,   -- PA 在播放开始后延迟打开的时间(ms)，透传给 config_pa_power_ctrl()
            --   不填时 exaudio 内部按 200ms 兜底；对齐同板可用的
            --   Air8601_deposit_cabinet 工程（user/audio_tts.lua）取 10
            play_vol = 70,            -- 默认播放音量(0~100)，llm_chat / video_util / factory_rec
            --   统一读 ac.play_vol or 70，这里显式写死便于各页面一致
            mic_vol = 70,             -- 默认录音音量(0~100)（AI 助手语音输入 / 应用工厂录音共用）
            record_format = "AMR_NB", -- 录音格式（AMR 体积小，上传 ASR 省内存；与 1601/1602/8101 一致）
            max_record_time = 30,     -- 最长录音时长(秒)，到时自动停止（AI 语音输入 / 应用工厂共用）
        },
    },

    -- ===== 功能开关（只写 = true 的项）=====
    features = {
        net_4g = true,  -- 启用 4G（Air780ER2，独占 UART3）—— 本型号固定为 4G 版，见文件头第 6 条
        speaker = true, -- 启用喇叭（DAC 接功放）
        mic = true,     -- 启用麦克风（板载 LINE_IN → 内置 ADC 录音）
        --   与 speaker 成对声明：同族已启 AI 助手/应用工厂的板型
        --   （evb_1601_7i_v12 / evb_8101_10i_v0 / eng_1602_5i_v5 …）都写了这一项，
        --   本板原缺失。当前 app/ 与 ui/ 里查不到消费方，属"能力声明"性质
        --   （与 usb_camera / rs485 同一类，见文件头第 10 条）。
        sd_card = true,       -- 启用 SD 卡（SPI1，CS=GPIO8）
        usb_camera = true,    -- USB 摄像头（UVC）—— 见文件头第 10 条：暂无消费方
        rs485 = true,         -- 启用 RS485 接口（1 路，条目在 peripherals，见文件头第 13 条）
        other_func = true,    -- 启用"功能测试"（peripherals 外设清单，UVC 预览测试入口）
        -- usb_hid 不开：USB 键鼠与 UVC 摄像头共用 USB Host 与供电，带 UVC 的型号不启用
        app_factory = true,   -- 启用"应用工厂"内置应用
        ai_chat = true,       -- 启用"AI聊天助手"内置应用
        cloud_disk = true,    -- 启用"合宙网盘"内置应用（IoT 登录取 space_key → 空间文件列表 → 下载）
        file_transfer = true, -- 启用"文件传输"内置应用（hzadb日志口：PC↔设备互传文件/共享清单）
        aircloud = true,      -- 启用 AirCloud 数据上报（通用能力探测：有接口就采，不绑定型号）
    },

    -- ===== AirCloud 数据上报参数 =====
    -- 仅在 features.aircloud = true 时生效
    -- 上报字段由运行时能力探测决定（mobile.csq / adc.CH_CPU / LBS 定位 / 电池 …）
    -- 采不到的一律跳过，不影响其他字段
    aircloud = {
        report_cycle = 180, -- 默认上报周期（秒），云端可下发 "cycle:秒数" 改写并存 fskv
        min_cycle    = 5,   -- 允许的最小周期（秒），防止云端下发过密把流量打爆
    },

    -- ===== 统一网络配置（优先级从高到低）=====
    -- 本型号为 4G 版：Airlink UART 4G（Air780ER2）独占 UART3，见文件头第 6 条
    -- WiFi 版见 config/eng_8601_7i_wifi.lua（同一底板电阻切换的另一出货型号）
    network = {
        {
            type = "4g_airlink_uart",
            uart_id = 3,
            baud = 2000000,
            adapter = socket.LWIP_GP_GW
        }, -- Air1601 外挂 4G 的网卡标识
    },

    -- ===== 存储设备: SD/TF 卡（SPI1, CS=GPIO8）=====
    storage = {
        sd_card = {
            spi_id = 1,               -- SPI1 总线
            pin_cs = 8,               -- SPI1_CS0 = PIN38 = GPIO8 片选
            speed = 20 * 1000 * 1000, -- SD 卡 SPI 时钟 20MHz
        },
    },

    -- ===== UI 显示控制（只写 = true 的项）=====
    ui = {
        show_4g_icon = true,           -- 桌面顶栏 4G 图标
        show_brightness_slider = true, -- 设置页亮度滑块
        show_storage_settings = true,  -- 设置页存储空间入口 ← 配 sd_card 时打开
        show_camera_preview = true,    -- 设置页摄像头预览入口 ← 见文件头第 10 条
        show_other_func = true,        -- 桌面"功能测试"图标 ← 配 other_func 时打开（UVC 测试入口）
        show_cloud_disk = true,        -- 桌面显示"合宙网盘"入口 ← 配 cloud_disk 时打开
        show_ai_chat = true,           -- 桌面显示"AI助手"入口 ← 配 ai_chat 时打开
        show_app_factory = true,       -- 桌面显示"应用工厂"入口 ← 配 app_factory 时打开
        show_file_transfer = true,     -- 桌面显示"文件传输"入口 ← 配 file_transfer 时打开
        show_aircloud = true,          -- 设置页显示"数据上报"入口 ← 配 aircloud 时打开
    },
}
