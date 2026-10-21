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
    name = "EVB_Air1601_7inch_1024x600_000_V011",  -- 项目命名: {类型}_{芯片}_{尺寸}_{版本}
    chip = "Air1601",                                   -- 主控芯片: RGB屏 + 以太网 + 4G(Airlink UART3)，WiFi 与 4G 二选一
    baseboard = "Air1601 EVB V011",                     -- 底板型号

    -- ===== 引脚功能复用（Air1601 无特殊复用需求，留空）=====
    pins = {},

    -- ===== GPIO 上电时序: 模组使能 / 5V 供电 =====
    -- V1.1 底板 GPIO12 = PA_EN / 5V_EN / 6205 EN（同一脚，高电平有效）
    -- 插 4G 模组时该脚同样保持高电平；若模组另有 PWRKEY/复位脚，再按模组手册补一条
    -- 拉低→延时→拉高使能（高电平有效）
    power_on = {
        { pin = 12, dir = 0, level = 1, delay = 120 },  -- 拉高 120ms 使能
    },

    -- ===== 硬件配置 =====
    hw = {
        -- 屏幕: AirLCD_1070 7寸 1024×600 RGB，驱动 IC 为 JD9165BA（免初始化 IC，无 SPI 引脚/寄存器序列）
        -- 时序 140/20/160/20/3/12 @50MHz 为实测正常值（总 1344×635），规格书参考时序会横向偏移，勿替换
        -- 背光: 不支持 PWM 调光，GPIO2 直接控制亮灭
        lcd = {
            model = "lcd_display_rgb",
            params = {
                interface = "rgb",        -- RGB 接口
                pin_rst = 15,            -- 复位引脚
                pin_bl = 2,              -- 背光使能 GPIO2（init 压低延后，首帧后由 backlight_on 点亮，防 RGB 残影）
                w = 1024,                -- 水平分辨率
                h = 600,                 -- 竖直分辨率
                hbp = 140,               -- 水平后沿
                hspw = 20,               -- 水平同步脉宽
                hfp = 160,               -- 水平前沿
                vbp = 20,                -- 垂直后沿
                vspw = 3,                -- 垂直同步脉宽
                vfp = 12,                -- 垂直前沿
                bus_speed = 50 * 1000 * 1000,  -- RGB 总线时钟 50MHz
            },
            need_buffer = true,          -- RGB 屏必须启用帧缓冲防撕裂
            screen_size = 7.0,           -- 7寸屏
            font = { size = 20 },        -- 高分屏用 20 号字
            -- 不配 backlight 表：本板只有 GPIO 背光（pin_bl），无 PWM 通道，不支持亮度调节；
            -- backlight_on 会回落到 params.pin_bl 直接点亮
        },
        -- 触摸: GT911 I2C 端口1，大屏带尺寸参数
        tp = {
            model = "tp_gt911",
            params = {
                port = 1,                -- I2C 端口 1
                pin_rst = 3,             -- 复位引脚
                pin_int = 51,            -- 中断引脚
                int_type = tp.FALLING,   -- 下降沿触发（大屏推荐）
                w = 1024,                -- 触摸面板宽度
                h = 600,                 -- 触摸面板高度
                gpio_reset = 3,          -- 额外复位 GPIO（Air1601 常用）
            },
        },
        -- 音频: Air1601 只有内置 DAC，无 I2S（不能录音，录音需 Air1602 或外挂 Air1103）
        -- 播放统一由 exaudio 走 DAC 输出，本表存在即启用音频（TTS/视频音轨/音量设置）
        -- 注意: V1.1 的 PA_EN 与 5V_EN 同为 GPIO12（高电平有效），
        --       该脚已由 power_on 常拉高供电，此处不写 pa_ctrl，
        --       避免 exaudio 空闲时把 GPIO12 拉低，误关外挂模组（WiFi/4G）与 5V 供电。
        audio = {
            model = "dac",           -- 内置 DAC 模式
            dac_delay = 6,           -- DAC 启动前冗余时间（单位 100ms）
            play_vol = 70,           -- 默认播放音量 0~100
        },
    },

    -- ===== 功能开关（只写 = true 的项）=====
    -- 网络逐项验证：当前启用 以太网 + 4G（AirLink UART3）；WiFi 与 4G 共用 UART3，二者互斥
    features = {
        ethernet = true,                 -- 启用 SPI 以太网（CH390H，SPI1_CS=GPIO14）
        net_4g = true,                   -- 启用 4G（Airlink 模式，Air780EPM/Air780ER2 外挂模组 UART3）
        -- wifi = true,                  -- × WiFi 与 4G 共用 UART3，切回 WiFi 时与下面 network/ui 两处注释互换
        sd_card = true,                  -- 启用 SD/TF 卡（需配 storage.sd_card）
        speaker = true,                  -- 启用喇叭（DAC 播放；Air1601 无 I2S，不能开 mic）
        ai_chat = true,                  -- 启用"AI助手"内置应用（WebSocket 对话 + TTS 播报，需联网）
        cloud_disk = true,               -- 启用"合宙网盘"内置应用（IoT 登录取 space_key → 文件列表 → 下载）
        app_factory = true,              -- 启用"应用工厂"内置应用（录音→识别→生成；Air1601 无 ADC，录音链路受限）
        file_transfer = true,            -- 启用"文件传输"内置应用（hzadb 日志口：PC↔设备互传文件/共享清单）
        aircloud = true,                 -- 启用 AirCloud 数据上报（PROJECT_KEY 鉴权）；不配 ui.show_aircloud 即不在设置页显示入口
    },

    -- ===== 统一网络配置（数组顺序即优先级，从高到低）=====
    -- 当前启用 以太网 + 4G：插网线时走以太网，网线不通时自动回落 4G。
    -- WiFi(6205) 与 4G 都占用 UART3，硬件上只能二选一，当前保持注释。
    -- 切回 WiFi 时三处互换：features.wifi / features.net_4g、network 两条、ui 图标
    network = {

        -- SPI 以太网（CH390H，SPI1，片选 GPIO14）—— 最高优先级
        { type = "eth_spi", chip = "CH390", spi_id = 1, cs_pin = 14 },

        -- Airlink UART 4G（Air780EPM/Air780ER2，占用 UART3）—— 第二优先级（以太网不通时回落）
        { type = "4g_airlink_uart",
          uart_id = 3, baud = 2000000,
          adapter = socket.LWIP_GP_GW },   -- Air1601 外挂 4G 的网卡标识

        -- Airlink UART WiFi（6205 模组，同样占用 UART3，与 4G 互斥）
        -- { type = "wifi_airlink_uart",
        --   uart_id = 3, baud = 2000000, irq = 13, adapter = socket.LWIP_STA },

    },

    -- ===== UI 显示控制（只写 = true 的项）=====
    ui = {
        show_4g_icon = true,             -- 桌面顶栏 4G 信号图标（features.net_4g 开启时才有数据）
        show_storage_settings = true,    -- 设置页存储空间入口
        show_ai_chat = true,             -- 桌面显示"AI助手"入口 ← 配 ai_chat 时打开
        show_cloud_disk = true,          -- 桌面显示"合宙网盘"入口 ← 配 cloud_disk 时打开
        show_app_factory = true,         -- 桌面显示"应用工厂"入口 ← 配 app_factory 时打开
        show_file_transfer = true,       -- 文件管理页显示"与PC互传"入口 ← 配 file_transfer 时打开
    },

    -- ===== 存储设备: SD/TF 卡（SPI1, CS=GPIO8）=====
    storage = {
        sd_card = {
            spi_id = 1,                  -- SPI 接口 ID
            pin_cs = 8,                  -- 片选 CS 引脚 GPIO8
            speed = 40000000,            -- SPI 时钟频率 Hz（高速卡推荐 20MHz+）
        },
    },
}
