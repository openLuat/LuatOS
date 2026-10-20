--[[
@module  config.eng_8602_7i_v1
@summary Air8602 引擎主机 7寸1024x600 RGB屏(JD9165BA) + Airlink UART 4G(780ER2) + 双RS485 + SD卡 + 喇叭 配置文件（4G 版）
@version 1.0
@date    2026.10.14
@author  江访
@usage
所有 boolean 字段只写 = true 表示开启，不写即视为关闭（无需写 = false）
具体包含哪些参数，如何填写参考：template.lua

注意：
1. Air8602 基于 Air1601 主控（烧录 LuatOS-SoC_Vxxxx_Air1602 固件），搭配 Air6205 WiFi / Air780ER2 4G（二选一，通过电阻切换）。
   本文件为【4G 版】：UART3 连接 Air780ER2。WiFi 版见 eng_8602_7i_v0.lua。
2. Air8602 与 Air8601 硬件差异（新建本配置时已按 8602 校准）：
   ▪ 7寸屏驱动 IC 为 JD9165BA（免初始化 IC），非 9寸的 HX8282；RGB 时序同为 140/20/160/20/3/12 @50MHz，复用统一驱动 lcd_display_rgb。
   ▪ 无 UVC 摄像头（8601 有）→ 不声明 usb_camera / show_camera_preview。
   ▪ 双路隔离 RS485（8601 单路）→ features.rs485 仅作能力声明，业务侧暂无消费方。
   ▪ 无 I2C / UART 扩展接口、USB 转串口为 CH347F（双串口）。
3. 触摸 GT911 走 I2C1（pins 复用 33/32），RST=GPIO72、INT=GPIO51，下降沿触发。
4. 背光 PWM3 @1kHz；LCD_DISP = GPIO15（兼复位脚，display.init 内部做复位时序，power_on 里额外拉高作显示使能）。
5. SD 卡走 SPI1，CS0=GPIO8，SD_EN=GPIO74（高有效），24MHz。
6. 音频：内置 DAC 播放 + 线路输入录音，PA(功放) 使能 = GPIO73（AUDIOPA_EN），低电平有效。
7. 485 方向脚 = GPIO65（由 uart.setup 第 8 参数自动切换，【不能】进 power_on）；485_EN2 = GPIO57。
8. 4G 版：Air780ER2 走 UART3 airlink，4G_RST=GPIO58 拉低（参考官方 factory main.lua 的 gpio.setup(58,0,PULLDOWN)，
   power_on 里以 dir=1 输出低电平等效处理）。
9. 主控 chip 填 "Air1601"（8601/8602 均基于 Air1601 主控；固件名仍为 Air1602）。
10. 本配置由 eng_8602_7i_v0.lua（WiFi 版）派生，差异：PROJECT 版本号 010→011、
    power_on 增加 4G_RST、features wifi→net_4g、network 段 WiFi→4G、ui show_wifi_icon→show_4g_icon。
]]

return {
    -- ===== 顶层信息 =====
    name = "Engine_Air8602_7inch_1024x600_011_V000", -- 项目命名: {类型}_{芯片}_{尺寸}_{分辨率}_{版本}（011 = 4G 版）
    chip = "Air1601", -- 主控芯片（RGB 屏 + Airlink UART 外挂 WiFi/4G）
    baseboard = "合宙引擎 AIR8602 V011 7寸", -- 底板型号

    -- ===== 引脚功能复用 =====
    -- 触摸走 I2C1，需把 PIN33/PIN32 复用成 I2C1（Air1601 复用表写作 CLK/SDA）
    pins = {
        { pin = 33, func = "I2C1_CLK" }, -- I2C1 时钟线（GT911 SCL）
        { pin = 32, func = "I2C1_SDA" }, -- I2C1 数据线（GT911 SDA）
    },

    -- ===== GPIO 上电时序 =====
    -- 按顺序初始化各外设供电（dir=1 表示输出，dir=0 表示输入 —— LuatOS gpio.setup 语义）
    -- 顺序即依赖：SD 卡供电 → 4G 复位释放 → 屏幕显示使能。
    -- 注意：LCD 复位由 display.init 的 pin_rst=15 处理、TP 复位由 tp.init 的 pin_rst=72 处理、
    --       PA 功放由 exaudio 的 pa_ctrl=73 管理，均不在本序列中重复操作。
    power_on = {
        { pin = 74, dir = 1, level = 1 },              -- SD_EN 拉高使能 SD 卡供电
        { pin = 58, dir = 1, level = 0, delay = 50 },  -- 4G_RST 拉低（释放复位，参考官方 factory 语义），等 50ms
        { pin = 15, dir = 1, level = 1 },              -- LCD_DISP 拉高使能 LCD 显示（兼复位脚，display.init 会再复位）
    },

    -- ===== 硬件配置 =====
    hw = {
        -- 屏幕: JD9165BA RGB 7寸 1024×600（免初始化 IC，无寄存器序列）；背光 PWM3 调光
        lcd = {
            model = "lcd_display_rgb", -- 本工程统一 RGB 驱动（内部走 display.init）
            params = {
                interface = "rgb",     -- RGB 接口
                pin_rst = 15,          -- LCD_DISP = GPIO15（复位/显示使能）
                w = 1024,              -- 水平分辨率
                h = 600,               -- 竖直分辨率
                -- RGB 时序参数（JD9165BA 7寸实测正常值，与 9寸 HX8282 一致）
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
                pin_rst = 72,          -- TP_RESET = GPIO72
                pin_int = 51,          -- TP_INT = GPIO51
                int_type = tp.FALLING, -- 下降沿触发
                w = 1024,              -- 触摸面板宽度
                h = 600,               -- 触摸面板高度
            },
        },
        -- 音频: 内置 DAC 播放 + 线路输入录音（非 ES8311 外挂芯片）
        -- ⚠️ 主控音频能力差异：Air1601 只支持【放音】(DAC 输出)；Air1602 才支持
        --    【对讲】(放音 DAC + 录音 LINE_IN→ADC)。当前 8601/8602 主控为 Air1601，
        --    故下面 mic_vol/record_format/max_record_time 等录音字段仅为【能力声明】，
        --    实际录不到有效声音（板子无板载 MIC，且 Air1601 无 ADC 录音链路）。
        --    若后续主控更换为 Air1602，语音生成/录音即可直接生效，无需改本段。
        -- PA(功放) 使能 = GPIO73（AUDIOPA_EN），低电平有效
        audio = {
            model = "dac",          -- 内置 DAC 模式（Air1601 芯片自带 DAC）
            pa_ctrl = 73,           -- PA(功放)使能引脚 = GPIO73（AUDIOPA_EN）
            pa_on_level = 0,        -- 低电平使能功放
            dac_delay = 6,          -- DAC 启动前冗余时间（旧框架用；新框架 audio_v2 不消费）
            pa_delay = 10,          -- PA 在播放开始后延迟打开的时间(ms)，透传 config_pa_power_ctrl()
            play_vol = 70,          -- 默认播放音量(0~100)，llm_chat / video_util / factory_rec 统一读
            mic_vol = 70,           -- 默认录音音量(0~100)（AI 助手语音输入 / 应用工厂录音共用）
            record_format = "AMR_NB", -- 录音格式（AMR 体积小，上传 ASR 省内存）
            max_record_time = 30,   -- 最长录音时长(秒)，到时自动停止
        },
    },

    -- ===== 功能开关（只写 = true 的项）=====
    features = {
        -- wifi = true,        -- × WiFi 未启用（4G 版）
        net_4g = true,         -- 启用 4G（Air780ER2，UART3 airlink）
        speaker = true,     -- 启用喇叭（内置 DAC 接 LM4871 功放）
        mic = true,         -- 启用麦克风（板载 LINE_IN → 内置 ADC 录音）
                            --   ⚠️ Air1601 只放音、无 ADC 录音输入，此项为能力声明；
                            --   语音生成 APP 的「录音→识别」在 Air1601 上录不到有效声音，
                            --   需 Air1602（对讲）才真正可用。功能保留，勿删。
        sd_card = true,     -- 启用 SD 卡（SPI1，CS=GPIO8）
        rs485 = true,       -- 双路隔离 RS485 —— 能力声明，暂无业务消费方（UART1+UART2）
        app_factory = true, -- 启用"应用工厂"内置应用
        ai_chat = true,     -- 启用"AI聊天助手"内置应用
        cloud_disk = true,  -- 启用"合宙网盘"内置应用（IoT 登录取 space_key → 空间文件列表 → 下载）
        file_transfer = true, -- 启用"文件传输"内置应用（hzadb日志口：PC↔设备互传文件/共享清单）
    },

    -- ===== 统一网络配置（优先级从高到低）=====
    -- 4G 版：Air780ER2 走 UART3 airlink
    network = {
        -- Airlink UART 4G（Air780ER2，占用 UART3）
        { type = "4g_airlink_uart",
          uart_id = 3, baud = 2000000,
          adapter = socket.LWIP_GP_GW },   -- Air1601 外挂 4G 的网卡标识
    },

    -- ===== 存储设备: SD/TF 卡（SPI1, CS=GPIO8）=====
    storage = {
        sd_card = {
            spi_id = 1,               -- SPI1 总线
            pin_cs = 8,               -- SPI1_CS0 = GPIO8 片选
            speed = 24 * 1000 * 1000, -- SD 卡 SPI 时钟 24MHz
        },
    },

    -- ===== UI 显示控制（只写 = true 的项）=====
    ui = {
        -- show_wifi_icon = true,         -- × 桌面顶栏 WiFi 图标（4G 版不显示）
        show_4g_icon = true,            -- 桌面顶栏 4G 图标 ← 配 net_4g 时打开
        show_brightness_slider = true,  -- 设置页亮度滑块
        show_storage_settings = true,   -- 设置页存储空间入口 ← 配 sd_card 时打开
        show_cloud_disk = true,         -- 桌面显示"合宙网盘"入口 ← 配 cloud_disk 时打开
        show_ai_chat = true,            -- 桌面显示"AI助手"入口 ← 配 ai_chat 时打开
        show_app_factory = true,        -- 桌面显示"应用工厂"入口 ← 配 app_factory 时打开
        show_file_transfer = true,      -- 桌面显示"文件传输"入口 ← 配 file_transfer 时打开
    },
}
