--[[
@module  config.evb_1601_7i_v11
@summary Air1601 EVB 7寸1024x600 RGB屏(AirLCD_1070/JD9165BA) + GPIO背光 + 以太网(CH390H) + 4G(AirLink UART3) + SD卡 配置文件
@version 1.1
@date    2026.10.21
@author  江访
@usage
所有 boolean 字段只写 = true 表示开启，不写即视为关闭（无需写 = false）
具体包含哪些参数，如何填写参考：template.lua
]]
return {
    -- ===== 顶层信息 =====
    name = "EVB_Air1601_7inch_1024x600_000_V011", -- 项目命名: {类型}_{芯片}_{尺寸}_{版本}
    chip = "Air1601",                             -- 主控芯片: RGB屏 + 以太网 + 4G(Airlink UART3)，WiFi 与 4G 二选一
    baseboard = "Air1601 EVB V011",               -- 底板型号

    -- ===== 引脚功能复用（Air1601 无特殊复用需求，留空）=====
    pins = {},

    -- ===== 外设清单（periph_loader 逐个登记，功能页取用时才打开）=====
    -- RS485：串口 UART2，方向脚（DE/RE）GPIO12，9600 8N1
    --   注意：GPIO12 在本底板上同时是 PA_EN / 5V_EN / 6205 EN（power_on 常拉高）。
    --   作为 485 方向脚后，驱动会在「接收态=低 / 发送态=高」之间切换它，空闲固定为低电平。
    --   de_restore = 1：退出测试页关串口时把该脚恢复成高电平，把 5V 轨还回去，
    --   否则测完一次 RS485 后 5V 负载（外挂模组 / PA）会一直掉电。
    --   test_data 就是 RS485 测试页固定发送的内容（纯字符串，不做 HEX）。
    peripherals = {
        {
            type = "rs485",
            id = "rs485_1",
            name = "RS485",
            uart_id = 2,
            de_pin = 12,
            baud = 9600,
            databits = 8,
            stopbits = 1,
            parity = "N",
            de_restore = 1,
            test_data = "RS485 test"
        },

        -- USB 摄像头（UVC）：接底板 USB 口（口号在代码里固定 1，无需在此配置）
        --   en_pin = 12 + pin12_free：USB 口 5V 就是 GPIO12（5V_EN），与 RS485 方向脚复用，
        --     但两者不同时使用，故按可控供电脚处理（pin12_free 是驱动要求的显式声明，
        --     不写会被拒绝登记）。power_hold：退出预览页不断电，该脚还带 PA / 6205 的 5V。
        --   **不要开 power_cycle**：重新枚举的时机由代码控制 —— 必须在 excamera.preview
        --     注册完回调**之后**才掉电上电（见 settings_uvc_app 的 cam_power_cycle）。
        --     开 power_cycle 会让 start() 在 preview 之前就掉电上电，设备提前枚举完，
        --     回调注册时 EV_CONNECT 早已发过，页面会一直卡在「等待摄像头连接」。
        --     cycle_low_ms / ready_delay 仍然有效：它们管的是那次重新枚举的拉低时长
        --     与上电后的稳定等待。
        --   w / h：首选 MJPEG 档，取本摄像头（AirCAMERA_1034）实测支持的最高档 960×480；
        --     摄像头不支持该档时，预览流程会枚举实际档位并自动重开一次流。
        --     内存吃紧就往下调（864×480 / 800×480 / 480×320），相机侧开销约 4.25×w×h 字节。
        --   rotation：画面**顺时针**旋转，仅 0 / 90 / 180 / 270（airui.camera 的能力）。
        --     摄像头物理摆正后画面还歪着就用它纠正；AirCAMERA_1034 在本板上画面偏左 90°，
        --     故取 90（顺时针转回来）。方向反了改成 270。改完必须重新烧录才生效，
        --     页面上的「旋转」按钮只能当场试角度（改不了预览区比例）。
        --   不写 max_pixels：用缺省的 1280×720 像素上限（超过的档位不取）
        {
            type = "uvc",
            id = "uvc1",
            name = "USB摄像头",
            en_pin = 12,
            pin12_free = true,
            ready_delay = 200,
            power_hold = true,
            w = 960,
            h = 480,
            rotation = 90
        },

        -- GNSS 定位（Air510W 外挂模组）：UART3 + 115200，模块 VBAT 直供
        --   没有可控供电脚，故不配 gnss_volgpio（exgnss 会走 pm.power(pm.GPS) 兜底）。
        --   **UART3 与 4G 模组复用**：本板由硬件切换，软件不做互斥。若 4G 模组在位、
        --     network 里的 4g_airlink_uart 已把 UART3 按 2Mbps 打开，本页再去开就会失败
        --     （uart3 已被占用）—— 属预期，把硬件切到 GNSS 那一路再测。
        --   gnssmode：1 = 卫星全定位，2 = 单北斗
        --   hz：定位输出频率，1 / 2 / 4 / 5（1hz = 每秒一条）
        --   agps_enable：本板**暂关**。开 true 会让 exgnss 走「下星历 → 基站定位」，
        --     基站定位那步 require("lbsLoc2")，而 lbsLoc2 在加载时就执行
        --     mobile.imei()。本板 mobile 是 airlink 代理、真实 4G 挂在 UART3，
        --     GNSS 占用 UART3 后跨核 RPC 超时返回 nil，直接把 VM 打崩。
        --     等硬件能保证 4G 与 GNSS 不抢 UART3，再改回 true 拿星历加速。
        --   debug：关。打开后 exgnss 会把每条 NMEA 原始报文刷进日志（1Hz 下每秒一大段），
        --     排障时临时改 true 即可，不影响 hz 配置和页面数据解析
        { type = "gnss", id = "gnss_1", name = "GNSS",
          uart_id = 3, baud = 115200,
          gnssmode = 1, agps_enable = false, hz = 1, debug = false },

        -- 蓝牙（Air5101S 串口 BLE 模块）：UART3 + 9600，驱动是扩展库 exril_5101
        --   **UART3 与 4G / WiFi / GNSS 复用**：net_manager 启动时就会按 2Mbps 把 UART3
        --     开给 4G，所以蓝牙测试页进页面时会先 uart.close 把口抢过来再按 9600 重开
        --     （不 close 的话 uart.setup 会被 C 层跳过，发指令没有任何回包）。
        --     代价：进过一次蓝牙测试页后 4G 的 UART3 不会自动恢复，要继续联网请重启设备。
        --     底板硬件要切到蓝牙那一路，否则模块本身收不到指令。
        --   dev_name：手机搜到的广播名（不超过 20 字符）
        --   test_data：蓝牙测试页固定发送的内容（AT 模式单包 ≤ 80 字节，本页按 60 字节截断）
        {
            type = "ble",
            id = "ble_1",
            name = "蓝牙",
            uart_id = 3,
            baud = 9600,
            dev_name = "Air1601_Test",
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

    -- ===== GPIO 上电时序: 模组使能 / 5V 供电 =====
    -- V1.1 底板 GPIO12 = PA_EN / 5V_EN / 6205 EN（同一脚，高电平有效）
    -- 插 4G 模组时该脚同样保持高电平；若模组另有 PWRKEY/复位脚，再按模组手册补一条
    -- 拉低→延时→拉高使能（高电平有效）
    power_on = {
        { pin = 12, dir = 0, level = 1, delay = 120 }, -- 拉高 120ms 使能
    },

    -- ===== 硬件配置 =====
    hw = {
        -- 屏幕: AirLCD_1070 7寸 1024×600 RGB，驱动 IC 为 JD9165BA（免初始化 IC，无 SPI 引脚/寄存器序列）
        -- 时序 140/20/160/20/3/12 @50MHz 为实测正常值（总 1344×635），规格书参考时序会横向偏移，勿替换
        -- 背光: 不支持 PWM 调光，GPIO2 直接控制亮灭
        lcd = {
            model = "lcd_display_rgb",
            params = {
                interface = "rgb",            -- RGB 接口
                pin_rst = 15,                 -- 复位引脚
                pin_bl = 2,                   -- 背光使能 GPIO2（init 压低延后，首帧后由 backlight_on 点亮，防 RGB 残影）
                w = 1024,                     -- 水平分辨率
                h = 600,                      -- 竖直分辨率
                hbp = 140,                    -- 水平后沿
                hspw = 20,                    -- 水平同步脉宽
                hfp = 160,                    -- 水平前沿
                vbp = 20,                     -- 垂直后沿
                vspw = 3,                     -- 垂直同步脉宽
                vfp = 12,                     -- 垂直前沿
                bus_speed = 50 * 1000 * 1000, -- RGB 总线时钟 50MHz
            },
            need_buffer = true,               -- RGB 屏必须启用帧缓冲防撕裂
            screen_size = 7.0,                -- 7寸屏
            font = { size = 20 },             -- 高分屏用 20 号字
            -- 不配 backlight 表：本板只有 GPIO 背光（pin_bl），无 PWM 通道，不支持亮度调节；
            -- backlight_on 会回落到 params.pin_bl 直接点亮
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
                gpio_reset = 3,        -- 额外复位 GPIO（Air1601 常用）
            },
        },
        -- 音频: Air1601 只有内置 DAC，无 I2S（不能录音，录音需 Air1602 或外挂 Air1103）
        -- 播放统一由 exaudio 走 DAC 输出，本表存在即启用音频（TTS/视频音轨/音量设置）
        -- 注意: V1.1 的 PA_EN 与 5V_EN 同为 GPIO12（高电平有效），
        --       该脚已由 power_on 常拉高供电，此处不写 pa_ctrl，
        --       避免 exaudio 空闲时把 GPIO12 拉低，误关外挂模组（WiFi/4G）与 5V 供电。
        audio = {
            model = "dac", -- 内置 DAC 模式
            dac_delay = 6, -- DAC 启动前冗余时间（单位 100ms）
            play_vol = 70, -- 默认播放音量 0~100
        },
    },

    -- ===== 功能开关（只写 = true 的项）=====
    -- 网络逐项验证：当前启用 以太网 + 4G（AirLink UART3）；WiFi 与 4G 共用 UART3，二者互斥
    features = {
        ethernet = true, -- 启用 SPI 以太网（CH390H，SPI1_CS=GPIO14）
        -- 4G 与 WiFi 两个业务层都编进来，是否真正启用由「UART3口复用」的运行期配置决定：
        -- settings_channel_app.apply_to_config() 会按通道模式把它们收口成互斥状态，
        -- 所以这里必须都写 true（否则切到另一路时对应业务层根本没被加载）。
        net_4g = true,                   -- 4G 业务层（Airlink 模式，Air780EPM/Air780ER2 外挂模组 UART3）
        wifi = true,                     -- WiFi 业务层（6205 外挂模组，与 4G 共用 UART3，二选一）
        sd_card = true,       -- 启用 SD/TF 卡（需配 storage.sd_card）
        speaker = true,       -- 启用喇叭（DAC 播放；Air1601 无 I2S，不能开 mic）
        ai_chat = true,       -- 启用"AI助手"内置应用（WebSocket 对话 + TTS 播报，需联网）
        cloud_disk = true,    -- 启用"合宙网盘"内置应用（IoT 登录取 space_key → 文件列表 → 下载）
        app_factory = true,   -- 启用"应用工厂"内置应用（录音→识别→生成；Air1601 无 ADC，录音链路受限）
        file_transfer = true, -- 启用"文件传输"内置应用（hzadb 日志口：PC↔设备互传文件/共享清单）
        aircloud = true,      -- 启用 AirCloud 数据上报（PROJECT_KEY 鉴权）；不配 ui.show_aircloud 即不在设置页显示入口
        rs485 = true,         -- 启用 RS485 测试（UART2 + DE=GPIO12，入口在设置页左侧）
        uvc = true,           -- 启用 USB 摄像头（UVC 预览，入口在设置页左侧）
        gnss = true,                     -- 启用 GNSS 定位（Air510W 外挂模组 UART3，入口在设置页左侧）
        ble = true,           -- 启用 蓝牙测试（Air5101S 板载模组 UART3，入口在设置页左侧；进页面会抢占 UART3）
        -- CAN 不在这里开：内置核心库，设置页入口常驻，参数见上面的 can = {...}
    },

    -- ===== 统一网络配置（数组顺序即优先级，从高到低）=====
    -- WiFi(6205) 与 4G 都占用 UART3，硬件上只能二选一，但两条都保留在本表里：
    -- 运行期由 fskv 的 uart3_mode（设置页 →「UART3口复用」）自动剔除互斥的那一条，
    -- 不再需要改注释来切换版本。首次开机（fskv 无记录）按本表推断默认值：
    -- 两条都在 → 默认 4G，与历史行为一致。
    -- 选 GNSS / 蓝牙 时两条都被剔除，UART3 空出来留给对应测试页独占。
    network = {

        -- SPI 以太网（CH390H，SPI1，片选 GPIO14）—— 最高优先级，不受 UART3 通道影响
        { type = "eth_spi", chip = "CH390", spi_id = 1, cs_pin = 14 },

        -- Airlink UART 4G（Air780EPM/Air780ER2，占用 UART3）—— 通道选「4G」时生效
        { type = "4g_airlink_uart",
          uart_id = 3, baud = 2000000,
          adapter = socket.LWIP_GP_GW },   -- Air1601 外挂 4G 的网卡标识

        -- Airlink UART WiFi（6205 模组，同样占用 UART3，与 4G 互斥）—— 通道选「WiFi」时生效
        { type = "wifi_airlink_uart",
          uart_id = 3, baud = 2000000, irq = 13, adapter = socket.LWIP_STA },

    },

    -- ===== UI 显示控制（只写 = true 的项）=====
    ui = {
        show_4g_icon = true,          -- 桌面顶栏 4G 信号图标（features.net_4g 开启时才有数据）
        show_storage_settings = true, -- 设置页存储空间入口
        show_ai_chat = true,          -- 桌面显示"AI助手"入口 ← 配 ai_chat 时打开
        show_cloud_disk = true,       -- 桌面显示"合宙网盘"入口 ← 配 cloud_disk 时打开
        show_app_factory = true,      -- 桌面显示"应用工厂"入口 ← 配 app_factory 时打开
        show_file_transfer = true,    -- 文件管理页显示"与PC互传"入口 ← 配 file_transfer 时打开
    },

    -- ===== 存储设备: SD/TF 卡（SPI1, CS=GPIO8）=====
    storage = {
        sd_card = {
            spi_id = 1,       -- SPI 接口 ID
            pin_cs = 8,       -- 片选 CS 引脚 GPIO8
            speed = 40000000, -- SPI 时钟频率 Hz（高速卡推荐 20MHz+）
        },
    },
}
