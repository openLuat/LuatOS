--[[
@module  config.evb_1602_7i_v12
@summary Air1602 EVB 7寸1024x600 RGB屏 + PWM背光 + SD卡 + 4G + WiFi + 以太网 + RS485 + USB摄像头 + GNSS + 蓝牙 + CAN + 应用工厂(ES8311录音播放) 配置文件
@version 1.1
@date    2026.10.21
@author  江访
@usage
所有 boolean 字段只写 = true 表示开启，不写即视为关闭（无需写 = false）
具体包含哪些参数，如何填写参考：template.lua

Air1602 与 Air1601 封装兼容，底板引脚定义一致，差异仅在主控：
Air1602 具备 I2S2 + ES8311，可录音。

V1.2 底板要点:
1. 总供电 GPIO58
2. WiFi 支持两种接线：AirLink UART3（与 4G/GNSS/蓝牙复用）或 SPI2（CS=GPIO4, RDY=GPIO13），
   开机用哪条由「UART3口复用」通道决定，WiFi_EN=GPIO12
3. 4G 使用 AirLink UART3 (4G_EN=GPIO42, 4G_RST=GPIO65, 4G_IRQ=GPIO2)
4. 以太网 SPI1/CS=GPIO14, LAN_EN=GPIO52, LAN_INT=GPIO1
5. SD 卡 SPI1/CS=GPIO8, SD_EN=GPIO56
6. LCD_EN=GPIO57, LED 背光=PWM3（支持亮度调节）
7. 音频: ES8311 与触摸共用 I2C1（8311_EN=GPIO43 常供电，防钳位触摸总线）
   播放走内置 DAC0，录音走 I2S2；PA_EN=GPIO73 低电平使能
8. 4G / WiFi / GNSS / 蓝牙 四个模组全部引到 UART3，靠「UART3口复用」四选一（本配置默认 4G）；
   WiFi(6205) 另外还接了一路 SPI2，所以它的接法跟随通道自动切换：
   选 WiFi        → 6205 走 UART3（wifi_airlink_uart）
   选 GNSS / 蓝牙 → 6205 改走 SPI2（wifi_airlink_spi），UART3 让给对应测试页，WiFi 仍可用
   选 4G          → 4G 走 UART3，WiFi 不建网卡（4G 与 6205 同为 airlink 从机，只能跑一路）
9. RS485: 串口 UART2，方向脚(DE/RE)=GPIO64，收发器使能 485_EN=GPIO46（高有效）
10. USB 摄像头: 底板 USB 口，5V 使能跟总供电 GPIO58 同一路
11. 上面 9/10 与 V1.1 底板不同（V1.1 上 485 方向脚、USB 5V 都是 GPIO12）；
    本板 GPIO12 是 WiFi(6205) 的 EN，不可挪作他用
12. GNSS: UART3，模组常供电（无供电使能脚），故不配 en_pin ——
    exgnss 内部退回 pm.power(pm.GPS) 兜底；power_on 里也没有 GNSS 相关步骤
13. 蓝牙: UART3 + 模组供电使能 BLE_EN=GPIO47（高有效），与 GNSS_EN 同一套处理 ——
    开机 power_on 先显式拉低，进蓝牙测试页拉高并等模块启动，退出页面拉低。
    这样通道选 4G / WiFi / GNSS 时 5101 不上电，不会挂在 UART3 上干扰 airlink 通信
]]
return {
    -- ===== 顶层信息 =====
    name = "EVB_Air1602_7inch_1024x600_000_V012", -- 项目命名: {类型}_{芯片}_{尺寸}_{版本}
    chip = "Air1602",                             -- 主控芯片: RGB屏 + WiFi(airlink) + 4G(airlink)
    baseboard = "Air1602 EVB V012",               -- 底板型号

    -- ===== 引脚功能复用（Air1602 无特殊复用需求，留空）=====
    pins = {},

    -- ===== 外设清单（periph_loader 逐个登记，功能页取用时才打开）=====
    -- V1.2 底板的 RS485 / USB / 485_EN 引脚与 V1.1 不同（V1.1 上都在 GPIO12）：
    --   RS485 方向脚（DE/RE）= GPIO64（V1.1 是 GPIO12）
    --   485_EN（收发器使能，高电平有效）= GPIO46（V1.1 没有这个脚）
    --   USB 口 5V 使能 = GPIO58（V1.1 是 GPIO12；本板上 58 是总供电脚，power_on 已拉高）
    --   注意：GPIO12 在本底板是 WiFi(6205) 的 EN，绝不能再当 485 方向脚 / USB 5V 脚用，
    --        否则测一次 485 就把 WiFi 模组拉死。
    peripherals = {
        -- RS485：串口 UART2，9600 8N1，DE=GPIO64 专脚专用（不与其他功能复用）
        --   de_restore 不用写：64 是纯方向脚，退出页面保持低电平（接收态）就是正确状态。
        --   power_pin = 46 + power_hold = true：进页面先把 485_EN 拉高使能收发器，
        --     退出时保持高电平（power_hold），不把外挂模组供电带走。
        --   test_data 就是 RS485 测试页固定发送的内容（纯字符串，不做 HEX）。
        {
            type = "rs485",
            id = "rs485_1",
            name = "RS485",
            uart_id = 2,
            de_pin = 64,
            power_pin = 46,
            power_hold = true,
            baud = 9600,
            databits = 8,
            stopbits = 1,
            parity = "N",
            test_data = "RS485 test"
        },

        -- USB 摄像头（UVC）：接底板 USB 口（口号在代码里固定 1，无需在此配置）
        --   en_pin = 58：USB 口 5V 跟总供电同一路（GPIO58，power_on 已拉高）。
        --     power_hold：退出预览页不断电 —— 58 是整板总供电，拉低会把 WiFi/4G/SD 一起掉电。
        --   **不要开 power_cycle**：同 RS485 页共用的 5V 轨，且重新枚举的时机由代码控制 ——
        --     必须在 excamera.preview 注册完回调**之后**才掉电上电（见 settings_uvc_app 的
        --     cam_power_cycle）；开 power_cycle 会让 start() 在 preview 之前就掉电上电，
        --     设备提前枚举完，回调注册时 EV_CONNECT 早已发过，页面会一直卡在「等待摄像头连接」。
        --   w / h：首选 MJPEG 档，取 AirCAMERA_1034 实测支持的最高档 960×480；
        --     摄像头不支持该档时，预览流程会枚举实际档位并自动重开一次流。
        --     内存吃紧就往下调（864×480 / 800×480 / 480×320），相机侧开销约 4.25×w×h 字节。
        --   rotation：画面**顺时针**旋转，仅 0 / 90 / 180 / 270（airui.camera 的能力）。
        --     V1.2 底板 USB 口方向与 V1.1 不同，若画面歪着用页面上的「旋转」按钮当场试角度，
        --     定下来再改这里（改完必须重新烧录才生效）。
        --   若实测发现「进摄像头页掉一下总供电」会连累 WiFi/4G（58 是整板总供电），
        --     把 en_pin 这一行删掉即可退回「底板常供」：驱动全程不动 GPIO，靠热插拔自然重枚举。
        {
            type = "uvc",
            id = "uvc1",
            name = "USB摄像头",
            en_pin = 58,
            ready_delay = 200,
            power_hold = true,
            w = 960,
            h = 480,
            rotation = 90
        },

        -- GNSS 定位（Air510W 外挂模组）：UART3 + 115200
        --   模组常供电（VBAT 直供，无供电使能脚），故**不配 en_pin**：
        --   settings_gnss_app 不透传 gnss_volgpio，exgnss 内部退回
        --   pm.power(pm.GPS) 兜底；power_on 里也不动任何 GNSS 相关 GPIO。
        --   代价/好处：模组始终有电，没有冷启动等待，进页面即可开始收 NMEA；
        --   但也意味着通道选 4G / WiFi 时它仍挂在 UART3 上（硬件已切走那一路）。
        --   **UART3 与 4G / WiFi 模组复用**：本板四路模组都挂 UART3，要把设置页 →
        --     「UART3口复用」切成 GNSS（或蓝牙）并重启，开机才不会把 UART3 按 2Mbps
        --     开给 4G / WiFi，否则本页 uart.setup 会失败（串口已被占用）。
        --   gnssmode：1 = 卫星全定位，2 = 单北斗
        --   hz：定位输出频率，1 / 2 / 4 / 5（1hz = 每秒一条）
        --   agps_enable：本板**暂关**。开 true 会让 exgnss 走「下星历 → 基站定位」，
        --     基站定位那步 require("lbsLoc2")，而 lbsLoc2 在加载时就执行
        --     mobile.imei()。本板 mobile 是 airlink 代理、真实 4G 挂在 UART3，
        --     GNSS 占用 UART3 后跨核 RPC 超时返回 nil，直接把 VM 打崩。
        --     等硬件能保证 4G 与 GNSS 不抢 UART3，再改回 true 拿星历加速。
        --   debug：**临时打开**（排障用）。打开后 exgnss 会把每条 NMEA 原始报文
        --     刷进日志（1Hz 下每秒一大段），用来区分「串口没通」和「只是还没定上位」。
        --     确认正常后改回 false，不影响 hz 配置和页面数据解析
        { type = "gnss", id = "gnss_1", name = "GNSS",
          uart_id = 3, baud = 115200,
          -- 不写 en_pin：模组常供电，exgnss 走 pm.power(pm.GPS) 兜底
          gnssmode = 1, agps_enable = false, hz = 1, debug = true },

        -- 蓝牙（Air5101S 串口 BLE 模块）：UART3 + 9600，驱动是扩展库 exril_5101
        --   **UART3 与 4G / GNSS 复用**：先把「UART3口复用」切成蓝牙再重启，开机就不会
        --     把 UART3 开给 4G；页面打开时仍会先 uart.close 再按 9600 重开
        --     （不 close 的话 uart.setup 会被 C 层跳过，发指令没有任何回包）。
        --   dev_name：手机搜到的广播名（不超过 20 字符）
        --   test_data：蓝牙测试页固定发送的内容（AT 模式单包 ≤ 80 字节，本页按 60 字节截断）
        --   en_pin：模组供电使能 BLE_EN = GPIO47（高有效）。power_on 先拉低，进本页时
        --     由 settings_ble_app 拉高、退出页面拉低 —— 与 GNSS_EN 同一套处理，
        --     保证别的通道下 5101 不上电、不挂在 UART3 上干扰 airlink 通信。
        --   boot_delay：拉高后等模块启动完成的毫秒数，再发 AT 才有回包（缺省 800）
        --     ↑ 退出页面即断电，每次进页面都是冷启动；想常供电就删掉 en_pin 与 boot_delay
        --       （没有 BLE_EN 这根脚、模组 VBAT 直供的底板本来就不写这两项）
        {
            type = "ble",
            id = "ble_1",
            name = "蓝牙",
            uart_id = 3,
            baud = 9600,
            en_pin = 47,
            boot_delay = 800,
            dev_name = "Air1602_Test",
            mtu_len = 247,
            test_data = "BLE test"
        },
    },

    -- ===== CAN 测试参数（内置核心库，不进 peripherals）=====
    -- can 是核心库：固件带 CAN 时全局就有 can，设置页入口常驻，进页面才 init，
    -- 所以这里只放参数，不参与 periph_loader 的开机初始化，也不需要 features 开关。
    --   硬件：S3 拨码选 CAN2 通路，U17 拨码把 UART2 切到 CAN2（不能选 485）；
    --     收发器 S 脚已接地、VIO 接 VDD_EXT，软件不需要管 STB/参考电平脚。
    --   **can_id 在本版固件里是 1-based**：1 = CAN1（复用 UART1），2 = CAN2（复用 UART2）。
    --     CAN2 与 RS485 用同一个串口/同一组引脚，两页不能同时开；进 CAN 页会先 uart.close
    --     把 UART2 抢过来，退出页面会 deinit 总线（RS485 页再用时需要重新拨码并重开）。
    --   **不要调 can.node / can.filter**：本版固件非 FIFO 模式的过滤有 bug，调了会一帧都收不到，
    --     默认就是收全部帧，测试页也不做 ID 过滤。
    --   bitrate + pts/pbs1/pbs2/sjw：实际速率 = 基础时钟 / 分频 / (1+PTS+PBS1+PBS2)，
    --     125K / 250K / 500K / 1M 这一族共用 6,6,4,2（示例已验证 1Mbps）；接对端时改成对端速率。
    --   mode：进页面时的初始模式，normal 正常总线 / test 自收自发（单板自检，无需对端）/
    --     listen 只听。页面上的按钮可在 正常 ↔ 自收自发 之间随时切换。
    --   tx_id + ext：测试页发送帧的 ID 与帧格式（true = 扩展帧 29bit，false = 标准帧 11bit）
    --   need_ack：是否需要应答。正常模式接对端时留 true；无对端时会一直重试并涨错误计数。
    --   test_data：测试页固定发送内容，CAN 单帧最多 8 字节，超了按 8 字节截断。
    can = {
        id = "can_1",
        name = "CAN",
        can_id = 2,
        uart_id = 2,
        mode = "normal",
        bitrate = 1000000,
        pts = 6,
        pbs1 = 6,
        pbs2 = 4,
        sjw = 2,
        tx_id = 0x12345677,
        ext = true,
        need_ack = true,
        cache = 128,
        test_data = "CAN test",
    },

    -- ===== GPIO 上电时序 =====
    -- 按顺序初始化各外设供电和复位
    power_on = {
        -- 自定义 I/O：GPIO72 开机即配置为推挽输出并拉低（dir=0 输出 / level=0 低电平）
        --   本板该脚不接板载器件（V1.2 上 TP_RST 是 GPIO3），作为可自由使用的一般 GPIO；
        --   放在序列第一条，使上电瞬间就定死低电平，不让它悬空/默认高电平干扰外部电路。
        --   取用约定：需要时按 GPIO 直接读写即可，不要在此重复 setup（会覆盖本步方向）。
        { pin = 72, dir = 0, level = 0 },

        -- 总供电 (高电平有效)
        { pin = 58, dir = 0, level = 1 },
        -- SD 卡使能 (SD_EN=GPIO56)
        { pin = 56, dir = 0, level = 1 },
        -- LCD 使能 (LCD_EN=GPIO57)
        { pin = 57, dir = 0, level = 1 },
        -- 8311 使能 与触摸共用I2C1(8311_EN=GPIO43)
        { pin = 43, dir = 0, level = 1 },

        -- RS485 收发器使能 (485_EN=GPIO46，高电平有效)
        --   V1.1 底板没有这根脚；本板不拉高的话 RS485 收发器一直处于关断状态，
        --   串口能发能收但总线上一点信号都没有。常拉高即可，CAN2 复用 UART2 时它不影响。
        { pin = 46, dir = 0, level = 1 },

        -- GNSS 没有上电步骤：模组 VBAT 直供，这里不碰它的供电（也不占用 GPIO21）

        -- 蓝牙模组使能 (BLE_EN=GPIO47，高有效) —— 同样先**拉低**
        --   理由与 GNSS 相同：5101 与 4G 共用 UART3，非蓝牙通道时不能让模组上电
        --   挂在总线上。进蓝牙测试页由 settings_ble_app 按 en_pin（= 47）拉高，
        --   退出页面拉低（模块断电，下次进页面是冷启动，等 boot_delay 后可用）。
        { pin = 47, dir = 0, level = 0 },

        -- WiFi 模组(6205) 上电 (EN=GPIO12，数据线走 UART3)
        { pin = 12, dir = 0, level = 1, delay = 50 }, -- 拉高 50ms

        -- 4G 模组(Air780ER) 上电复位 (AirLink UART3, EN=GPIO42, RST=GPIO65)
        { pin = 42, dir = 0, level = 0, delay = 50 },   -- 拉低 EN 使能（低电平有效）
        { pin = 65, dir = 0, level = 1, delay = 100 },  -- 拉高 RST 复位
        { pin = 65, dir = 0, level = 0, delay = 1000 }, -- 拉低 RST 释放，等待模块启动

        -- 以太网 CH390 使能 (LAN_EN=GPIO52)
        { pin = 52, dir = 0, level = 1 },
    },

    -- ===== 硬件配置 =====
    hw = {
        -- 屏幕: 7寸 1024×600 RGB（免 IC 初始化，无 SPI 引脚/寄存器序列）
        -- 时序 140/20/160/20/3/12 @50MHz 为实测正常值（总 1344×635）
        -- 背光: PWM3 调光（支持亮度调节）
        -- LCD_EN: GPIO57 控制 LCD 供电
        lcd = {
            model = "lcd_display_rgb",
            params = {
                interface = "rgb",             -- RGB 接口
                pin_rst = 15,                  -- 复位引脚
                pin_pwr = 57,                  -- LCD 供电使能 GPIO57 (LCD_EN)
                w = 1024,                      -- 水平分辨率
                h = 600,                       -- 竖直分辨率
                hbp = 140,                     -- 水平后沿
                hspw = 20,                     -- 水平同步脉宽
                hfp = 160,                     -- 水平前沿
                vbp = 20,                      -- 垂直后沿
                vspw = 3,                      -- 垂直同步脉宽
                vfp = 12,                      -- 垂直前沿
                bus_speed = 50 * 1000 * 1000,  -- RGB 总线时钟 50MHz
            },
            need_buffer = true,                -- RGB 屏必须启用帧缓冲防撕裂
            screen_size = 7.0,                 -- 7寸屏
            font = { size = 20 },              -- 高分屏用 20 号字
            backlight = {
                pwm_ch = 3,                    -- LED 背光 PWM3（支持亮度调节）
                pwm_freq = 1000,               -- PWM 频率 1KHz
            },
        },
        -- 触摸: GT911 I2C 端口1，大屏带尺寸参数
        tp = {
            model = "tp_gt911",
            params = {
                port = 1,              -- I2C 端口 1
                pin_rst = 3,           -- 复位引脚
                pin_int = 51,          -- 中断引脚
                int_type = tp.FALLING, -- 下降沿触发（大屏推荐）
                w = 1024,              -- 触摸面板宽度
                h = 600,               -- 触摸面板高度
            },
        },
        -- 音频硬件: ES8311 + I2S2（应用工厂-录音播放）
        --   ES8311 与触摸共用 I2C1；8311_EN=GPIO43 保持常供电，防止钳位 I2C1 触摸总线
        --   播放走内置 DAC0，录音走 I2S2 接 ES8311
        --   PA_EN=GPIO73 低电平使能（pa_on_level=0），由 exaudio.setup 内部控制防 pop 音
        audio = {
            model = "es8311",         -- 音频编解码: ES8311（录音经 I2S2）
            i2c_id = 1,               -- I2C1 控制总线（与触摸共用）
            -- 数值对应 audio_v2.DRIVER_TYPE_*（NONE=0/I2S=1/DAC=2/ADC=3），
            -- 用字面量避免依赖 audio_v2 全局表
            tx_bus_type = 2,          -- 发送(播放)总线 = 内置 DAC
            tx_bus_id = 0,            -- DAC0
            rx_bus_type = 1,          -- 接收(录音)总线 = I2S
            rx_bus_id = 2,            -- I2S2
            dac_ctrl = 43,            -- 8311_EN 编解码使能 GPIO（已在 power_on 拉高）
            pa_ctrl = 73,             -- PA_EN 功放使能 GPIO
            pa_on_level = 0,          -- PA 低电平使能（Air160X V1.2 底板特性）
            pa_delay = 100,           -- PA 打开延迟(ms)
            i2s_sample = 8000,        -- I2S 采样率（AMR_NB=8k）
            bits_per_sample = 16,     -- 采样位深
            i2s_framebit = 16,        -- I2S 通道位宽
            channels = 1,             -- 声道数: 单声道
            play_vol = 70,            -- 默认播放音量(0~100)
            mic_vol = 70,             -- 默认录音音量(0~100)
            record_format = "AMR_NB", -- 录音格式（体积小，ASR 上传省内存）
            max_record_time = 30,     -- 最大录音时长(秒)，到时自动停止
        },
    },

    -- ===== 功能开关（只写 = true 的项）=====
    features = {
        -- 4G 与 WiFi 两个业务层都编进来，是否真正启用由「UART3口复用」的运行期配置决定：
        -- settings_channel_app.apply_to_config() 会按通道模式把它们收口成互斥状态，
        -- 所以这里必须都写 true（否则切到另一路时对应业务层根本没被加载）。
        wifi = true,        -- WiFi 业务层（AirLink UART3，6205 模组）
        net_4g = true,      -- 4G 业务层（AirLink UART3，Air780ER 模组）
        ethernet = true,    -- 启用 SPI 以太网（CH390，SPI1）
        sd_card = true,     -- 启用 SD/TF 卡（SPI1，CS=GPIO8）
        app_factory = true, -- 启用"应用工厂"内置应用
        ai_chat = true,     -- 启用"AI聊天助手"内置应用
        speaker = true,     -- 启用喇叭（DAC0 播放）
        mic = true,         -- 启用麦克风（I2S2 + ES8311 录音）
        usb_hid = true,     -- USB 键盘鼠标（USB Host 接口）
        cloud_disk = true,  -- 启用"合宙网盘"内置应用（IoT 登录取 space_key → 空间文件列表 → 下载）
        file_transfer = true, -- 启用"文件传输"内置应用（hzadb日志口：PC↔设备互传文件/共享清单）
        aircloud = true,      -- 启用 AirCloud 数据上报（PROJECT_KEY 鉴权）
        rs485 = true,         -- 启用 RS485 测试（UART2 + DE=GPIO64 + 485_EN=GPIO46，入口在设置页左侧）
        uvc = true,           -- 启用 USB 摄像头（UVC 预览，入口在设置页左侧）
        gnss = true,          -- 启用 GNSS 定位（Air510W 外挂模组 UART3，入口在设置页左侧）
        ble = true,           -- 启用 蓝牙测试（Air5101S 外挂模组 UART3，入口在设置页左侧；需先把通道切成蓝牙）
        -- CAN 不在这里开：内置核心库，设置页入口常驻，参数见上面的 can = {...}
    },

    -- ===== UART3 口复用缺省通道 =====
    -- fskv 里没有 uart3_mode 记录时（出厂首次开机）用这个值，可选 4g / wifi / gnss / ble。
    -- 本板四个模组都复用 UART3，缺省给 4G；即便不写这一行，按 network 表推断也是 4G。
    channel_default = "4g",

    -- ===== 统一网络配置（数组顺序即优先级，从高到低）=====
    -- 开机时按 fskv 的 uart3_mode（设置页 →「UART3口复用」，缺省见 channel_default）自动选择：
    --   4g        → 以太网 + 4G(UART3)
    --   wifi      → 以太网 + WiFi(6205 走 UART3)
    --   gnss/ble  → 以太网 + WiFi(6205 走 SPI2) + 对应测试页独占 UART3
    -- 4G 与 WiFi 同为 airlink 从机，固件同一时间只能跑一路，所以 4G 通道下不建 WiFi 网卡；
    -- 其余模式下 WiFi 没被剔除的条目（UART/SPI 二选一）由 net_manager 按通道自动挑。
    -- 以太网不占 UART3，任何模式下都保留，所以「以太网兜底」永远成立。
    network = {
        -- ===== 最高优先级：以太网（SPI1，不受通道影响）=====
        {
            type = "eth_spi",
            chip = "CH390",
            spi_id = 1,
            cs_pin = 14,
            irq_pin = 1,  -- LAN_INT = GPIO01（V1.2 底板）。不接或被占用就删掉本行 → 退回轮询
            pwr_pin = 52, -- LAN_EN = GPIO52（已在 power_on 处理，此处冗余以防遗漏）
        },

        -- ===== WiFi（6205，UART3 / SPI2 双接法：由「UART3口复用」自动二选一）=====
        -- 6205 同时支持 UART 和 SPI，本表两条都写，net_manager 按 uart3_mode 只保留一条：
        --   通道 = WiFi        → 用第一条（UART3，2Mbps），UART3 让给 6205
        --   通道 = GNSS / 蓝牙 → 用第二条（SPI2），UART3 留给对应测试页，WiFi 照常可用
        --   通道 = 4G          → 两条都不建：4G 占 UART3，且 4G 与 6205 同为 airlink 从机，
        --                        固件同一时间只支持跑一路（要 WiFi 就把通道切成 WiFi）
        {
            type = "wifi_airlink_uart",
            uart_id = 3,            -- UART3（与 4G / GNSS / 蓝牙复用）
            baud = 2 * 1000 * 1000, -- 2Mbps（UART 模式只用 uart_id / baud，不配 irq）
            adapter = socket.LWIP_STA,
        },
        {
            type = "wifi_airlink_spi",
            spi_id = 2,          -- SPI2（与 SPI1 上的以太网 / SD 卡不冲突）
            cs_pin = 4,          -- CS = GPIO4
            rdy_pin = 13,        -- AirLink_RDY = GPIO13
            speed = 8 * 1000000, -- 8MHz
        },

        -- ===== 4G（AirLink UART3，Air780ER）—— 通道选「4G」时生效（此时上面两条 WiFi 都不建）=====
        {
            type = "4g_airlink_uart",
            uart_id = 3,            -- UART3
            baud = 2 * 1000 * 1000, -- 2Mbps
            adapter = socket.LWIP_GP_GW,
        },
    },

    -- ===== UI 显示控制（只写 = true 的项）=====
    ui = {
        show_wifi_icon = true,           -- 桌面顶栏 WiFi 图标
        show_4g_icon = true,             -- 桌面顶栏 4G 信号图标
        show_ethernet_settings = true,   -- 设置页以太网设置入口
        show_storage_settings = true,    -- 设置页存储空间入口
        show_app_factory = true,         -- 桌面显示"应用工厂"入口 ← 配 app_factory 时打开
        show_ai_chat = true,             -- 桌面显示"AI助手"入口 ← 配 ai_chat 时打开
        ai_chat = true,                  -- 启用"AI聊天助手"内置应用
        show_cloud_disk = true,          -- 桌面显示"合宙网盘"入口 ← 配 cloud_disk 时打开
        show_file_transfer = true,       -- 文件管理页显示"与PC互传"入口
    },

    -- ===== 存储设备: SD/TF 卡（SPI1, CS=GPIO8）=====
    storage = {
        sd_card = {
            spi_id = 1,              -- SPI 接口 ID（与以太网共用 SPI1，CS 不同）
            pin_cs = 8,              -- 片选 CS 引脚 GPIO8
            speed = 8 * 1000 * 1000, -- SPI 时钟频率 Hz（高速卡推荐 8MHz+）
        },
    },

    -- ===== 注意: WIFI_IRQ / AirLink_WAKEUP 配置 =====
    -- 本板用不到下面这段：UART 模式不需要 IRQ；SPI 模式用 CS=GPIO4 / RDY=GPIO13 即可
    -- （exnetif 的 airlink SPI 分支只配 spi_id / cs / rdy）。以下是 6205 独立 SPI 方案的
    -- 遗留说明，仅当把 IRQ / WAKEUP 也接到 GPIO2 / GPIO0 时才需要在 net_manager 初始化前加：
    --
    --   airlink.config(airlink.CONF_SPI_IRQ, 2)       -- WIFI_IRQ = GPIO2
    --   airlink.irqmode(true, 2, 2)
    --   airlink.wakeupIrqmode(true, 0, 0, luat_gpio.RISING)  -- WAKEUP = GPIO0
    --
    -- 注: WIFI_IRQ 与 4G_IRQ 共用 GPIO2，UART 模式不需要 IRQ，无冲突
}
