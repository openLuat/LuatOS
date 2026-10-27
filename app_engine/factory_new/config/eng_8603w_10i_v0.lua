--[[
@module  config.eng_8603w_10i_v0
@summary Air8603W1 引擎主机 10寸1024x600 RGB屏 + Airlink UART WiFi(6205) + Air1103语音(UART6) + UVC摄像头 + 三路RS485 + UART2 + SD卡 配置文件（WiFi 版）
@version 1.0
@date    2026.10.23
@author  江访
@usage
所有 boolean 字段只写 = true 表示开启，不写即视为关闭（无需写 = false）
具体包含哪些参数，如何填写参考：template.lua

注意：
1. Air8603W1 主控平台为 Air1603。本型号为 WiFi 版（Air6205 模组，UART3），同底板另有
   4G 出货型号 Engine_Air8603M1_10inch_1024x600_000_4G_V000（config/eng_8603m_10i_v0.lua），
   两型号是同一底板网络模组切换的不同出货型号，配置只差 network / features / ui 三处，切勿混用。
2. 【音频 = Air1103 语音芯片】UART6（固定 2M 波特率），单芯片集成 MIC + 喇叭 + AEC，
   exaudio 走 model="air1103" + audio_mode="new" 新框架（与 config/eng_8605b_10i_v0.lua 同款）。
   AUDIOPA_EN = PIN55 = GPIO73 是 Air1103 的**供电脚**（非本地功放）：power_on 拉高常供电，
   hw.audio 不写 pa_ctrl（air1103 模式 exaudio 跳过 PA 控制）。
   消费方透传 uart_id 的接线点：app/common/tts_app.lua、app/factory/llm_chat.lua、
   app/factory/factory_rec.lua、ui/video_util.lua（四处 exaudio.setup 白名单）。
3. LCD 为 RGB 10寸 1024×600（免序列四合一，无 SPI 初始化引脚），走统一 RGB 驱动
   lcd_display_rgb；LCD_DISP = PIN80 = GPIO15 作 pin_rst；时序用 1024×600 生态实测组
   hbp=140 hspw=20 hfp=160 vbp=20 vspw=3 vfp=12 @50MHz；背光 PWM3 调光。
4. 触摸 GT911 走 I2C1：TP_RST = PIN8 = GPIO72，TP_INT = PIN36 = GPIO51。
   TP_RST 的复位脉冲在 power_on 里做（先拉低 20ms 再拉高 60ms），INT 上拉锁 0x14 干净启动。
5. SD 卡走 SPI1 总线，SPI_CS0 = PIN38 = GPIO8，SD_EN = PIN9 = GPIO74。
   本板无 NAND Flash，不配 storage.nand_flash、不开 features.nand_flash。
6. 【看门狗 153D】WG_OUT = PIN47 = GPIO57 是看门狗芯片的复位输出（接系统复位），
   本工程无喂狗/监听消费方，固件不配置该脚；若量产固件被看门狗复位，需补喂狗逻辑。
7. 【三路 RS485 + UART2 共用 UART2】485_EN = GPIO64 是 485 功能总供电，power_on 拉高使能，之后常供电不回落；
   故三路都写 power_hold = true，驱动只补高不关断（末路 stop 不拉低），
   否则关掉最后一路会把整组 485 的电一起掐掉。
   485_EN1 = PIN51 = GPIO65 是非隔离 485 的 DE，走 UART1；
   485_EN2 = GPIO58 是隔离 485 之二的 DE，走 UART2。
   三路 485 的分配：485_1 非隔离(UART1 + DE=GPIO65) / 485_2 隔离(UART1，DE 未引出) /
   485_3 隔离(UART2 + DE=GPIO58)。
   **485_3 与 uart2 是同一个物理 UART2**（板上 UART2 既接隔离 485 收发器又对外引出），
   两者都登记在 peripherals 里、功能测试列表都显示，但**不可同时打开**：
   periph_rs485 与 periph_uart 各自 uart.setup + uart.on("receive")，同时开会互相覆盖
   接收回调与波特率。逐项测试时请一次只开一个。
8. 【UVC_EN 与 485_EN2 共用 GPIO58】PIN48 = GPIO58 同时是 UVC 摄像头供电开启信号
   和 485_3 的 DE 引脚。这是底板设计如此，非配置错误：给 UVC 上电即把 485_3 的 DE
   置为发送态，关 UVC 则 485_3 回到接收态。peripherals 里两者都指向 en_pin/de_pin = 58，
   测试 485_3 收发前请先确认 UVC 那一路的电平状态符合预期。
9. 上电供电轨：5V_EN = GPIO12、9V_EN = PIN46 = GPIO56、12V_EN = PIN72 = GPIO44、
   5VOUT_EN = PIN73 = GPIO52（对外 5V 输出使能）。
   5V_EN 与 usb_hid_app 的 VBUS_GPIO=12 是同一物理脚（USB 供电使能），本型号不开 usb_hid
   （features.usb_hid 不写），故不会被该应用上下电；若后续开启 usb_hid，需先核实 5V 轨
   是否还给非 USB 负载供电。
10. UVC 摄像头数据流（预览/拍照/录像）由 ui/uvc_preview_win.lua 走 excamera 扩展库独占管理，
    外设开关只负责供电，不再重复 camera.init。
    预览入口按需求放在「功能测试」里，因此不设 ui.show_camera_preview（避免两处入口）。
    w / h 不写时用预览页默认档 1280×720，预览页会枚举摄像头真正支持的档位取可用档。
]]

return {
    -- ===== 顶层信息 =====
    name = "Engine_Air8603W1_10inch_1024x600_000_WiFi_V000", -- 项目命名: {类型}_{芯片}_{尺寸}_{分辨率}_{版本}_{网络}
    chip = "Air1603", -- 主控芯片平台（同 config/eng_8607a_10i_v0.lua）
    baseboard = "合宙引擎 AIR8603W1 V000 10寸", -- 底板型号

    -- ===== 引脚功能复用 =====
    -- Air1603 上背光 PWM3 与触摸 I2C1 无需显式复用（与 eng_8607 系列一致，留空）
    pins = {
        -- { pin = 55, func = "PWM3" },     -- 背光 PWM3
        -- { pin = 33, func = "I2C1_CLK" }, -- I2C1 时钟线（GT911 SCL）
        -- { pin = 32, func = "I2C1_SDA" }, -- I2C1 数据线（GT911 SDA）
    },

    -- ===== GPIO 上电时序 =====
    -- 按顺序初始化各外设供电和复位（顺序即依赖：触摸复位→电源轨→SD→UVC→485→Air1103）
    power_on = {
        { pin = 12, dir = 0, level = 1 },              -- 5V_EN 拉高，5V 供电
        { pin = 56, dir = 0, level = 1, delay = 100 }, -- 9V_EN 拉高，等 100ms 就绪
        { pin = 44, dir = 0, level = 1 },              -- 12V_EN 拉高，12V 供电
        { pin = 52, dir = 0, level = 1 },              -- 5VOUT_EN 拉高，对外 5V 输出使能
        { pin = 74, dir = 0, level = 1 },              -- SD_EN 拉高，SD 卡供电
        { pin = 58, dir = 0, level = 1, delay = 200 }, -- UVC_EN 拉高，等 200ms 摄像头就绪（同一脚也是 485_EN2，见文件头第 8 条）
        { pin = 64, dir = 0, level = 1 },              -- 485_EN 拉高，485 功能总供电
        { pin = 73, dir = 0, level = 1 },              -- AUDIOPA_EN = Air1103 供电，拉高常供电（见文件头第 2 条）
    },

    -- ===== 外设清单（功能测试页逐项开关 + 进子页测试）=====
    -- 485_3 与 uart2 共用物理 UART2，不可同时打开，见文件头第 7 条
    -- UVC_EN 与 485_3 的 DE 共用 GPIO58，见文件头第 8 条
    -- manual_init = true：485 测试页进页面不自动上电开串口，点该路按钮才初始化
    peripherals = {
        { type = "uvc",   id = "uvc1",  name = "UVC摄像头", en_pin = 58, ready_delay = 200 }, -- UVC_EN，200ms 就绪
        { type = "rs485", id = "485_1", name = "非隔离485", uart_id = 1, de_pin = 65, power_pin = 64, power_hold = true, baud = 9600, manual_init = true }, -- DE = 485_EN1，供电域 485_EN
        { type = "rs485", id = "485_2", name = "隔离485",   uart_id = 1, de_pin = nil, power_pin = 64, power_hold = true, baud = 9600 }, -- DE 脚未引出，供电域 485_EN
        { type = "rs485", id = "485_3", name = "隔离485",   uart_id = 2, de_pin = 58, power_pin = 64, power_hold = true, baud = 9600 }, -- DE = 485_EN2 = UVC_EN，供电域 485_EN
        { type = "uart",  id = "uart2", name = "UART2",     uart_id = 2, baud = 115200, databits = 8, parity = "N", stopbits = 1 }, -- 与 485_3 共用 UART2
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
                pin_rst = 72,          -- TP_RST = PIN8 = GPIO72
                pin_int = 51,          -- TP_INT = WAKEUP = GPIO51
                int_type = tp.FALLING, -- 下降沿触发（大屏推荐）
                w = 1024,              -- 触摸面板宽度
                h = 600,               -- 触摸面板高度
            },
        },
        -- 音频: Air1103 外置语音芯片（UART6，内置 MIC/喇叭/AEC），见文件头第 2 条
        -- 供电脚 AUDIOPA_EN = GPIO73 已在 power_on 拉高常供电，此处不写 pa_ctrl
        audio = {
            model = "air1103",        -- Air1103 语音芯片（exaudio 新框架 UART 驱动）
            uart_id = 6,              -- Air1103 接 UART6（固定 2M 波特率，与 eng_8605b 同款）
            audio_mode = "new",       -- 拉起 audio_v2 新框架（air1103 模式必须）
            play_vol = 70,            -- 默认播放音量(0~100)
            mic_vol = 70,             -- 默认录音音量(0~100)
            record_format = "AMR_NB", -- 录音格式（AMR 体积小，上传 ASR 省内存）
            max_record_time = 30,     -- 最长录音时长(秒)，到时自动停止
        },
    },

    -- ===== 功能开关（只写 = true 的项）=====
    features = {
        wifi = true,        -- 启用 WiFi（Air6205，独占 UART3）—— 本型号固定为 WiFi 版，见文件头第 1 条
        speaker = true,     -- 启用喇叭（Air1103 内置功放）
        mic = true,         -- 启用麦克风（Air1103 内置 MIC）
        sd_card = true,     -- 启用 SD 卡（SPI1，CS=GPIO8）
        usb_camera = true,  -- 启用 USB 摄像头（UVC）—— 入口在「功能测试」
        rs485 = true,       -- 启用 RS485 接口（三路，见文件头第 7 条）
        other_func = true,  -- 启用"功能测试"（peripherals 外设清单）
    },

    -- ===== 统一网络配置（优先级从高到低）=====
    -- 本型号为 WiFi 版：Airlink UART WiFi（6205）独占 UART3
    -- 4G 版见 config/eng_8603m_10i_v0.lua（同一底板的另一出货型号）
    network = {
        { type = "wifi_airlink_uart",
          uart_id = 3,
          baud = 2000000 },
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
        show_wifi_icon = true,         -- 桌面顶栏 WiFi 图标
        show_brightness_slider = true, -- 设置页亮度滑块
        show_storage_settings = true,  -- 设置页存储空间入口 ← 配 sd_card 时打开
        show_other_func = true,        -- 桌面显示"功能测试"图标 ← 配 other_func 时打开
        -- show_camera_preview 故意不写：UVC 预览入口在「功能测试」里，见文件头第 10 条
    },
}
