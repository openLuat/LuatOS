--[[
@module  config.evb_1601_10i_v11
@summary Air1601 EVB 10.1寸1024x600 RGB屏(HX8282) + GPIO背光 + SD卡 配置文件
@version 1.0
@date    2026.06.04
@author  江访
@usage
所有 boolean 字段只写 = true 表示开启，不写即视为关闭（无需写 = false）
具体包含哪些参数，如何填写参考：template.lua
]]
return {
    -- ===== 顶层信息 =====
    name = "EVB_Air1601_10inch1_1024x600_000_V011",  -- 项目命名: {类型}_{芯片}_{尺寸}_{版本}
    chip = "Air1601",                                   -- 主控芯片: RGB屏 + WiFi(airlink)，无4G
    baseboard = "Air1601 EVB V011",                     -- 底板型号

    -- ===== 引脚功能复用（Air1601 无特殊复用需求，留空）=====
    pins = {},

    -- ===== GPIO 上电时序: WiFi 模组(6205)复位 =====
    -- 6205 WiFi 模组: GPIO12 EN 引脚，使用 AIRLINK_UART3 通信
    -- 拉低→延时→拉高使能（高电平有效）
    power_on = {
        { pin = 12, dir = 0, level = 0, delay = 50  },  -- 拉低 50ms 复位
        { pin = 12, dir = 0, level = 1, delay = 120 },  -- 拉高 120ms 使能
    },

    -- ===== 硬件配置 =====
    hw = {
        -- 屏幕: HX8282 RGB 10.1寸 1024×600（四合一芯片，无需 SPI 初始化引脚）
        -- 背光: 不支持 PWM 调光，GPIO2 直接控制亮灭
        lcd = {
            model = "lcd_hx8282_10in",
            params = {
                port = lcd.RGB,          -- RGB 接口
                pin_rst = 15,            -- 复位引脚
                pin_pwr = 2,             -- LCD 供电使能 GPIO2（同时控制背光）
                direction = 0,           -- 0° 方向
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
            screen_size = 10.0,          -- 10.1寸屏
            font = { size = 20 },        -- 高分屏用 20 号字
            backlight = {
                gpio_bl = 2,             -- GPIO2 控制背光亮灭（不支持 PWM 调光）
            },
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
    },

    -- ===== 功能开关（只写 = true 的项）=====
    features = {
        wifi = true,                     -- 启用 WiFi（airlink 模式，6205 芯片 AIRLINK_UART3）
        sd_card = true,                  -- 启用 SD/TF 卡（需配 storage.sd_card）
        ethernet = true,                 -- 启用 SPI 以太网（CH390H，SPI0_CS0=GPIO34）
        -- net_4g = true,                   -- × 4G未启用，但UI会显示4G信号图标
    },

    -- ===== 统一网络配置（优先级从高到低）=====
    -- Air1601 的 Airlink WiFi 和 Airlink 4G 都使用 UART3，硬件上二者只能开启一个
    -- 启用 WiFi 时注释 4G，启用 4G 时注释 WiFi
    network = {
        -- Airlink UART WiFi（6205 模组，占用 UART3）
        { type = "wifi_airlink_uart",
          uart_id = 3, baud = 2000000 },

        -- Airlink UART 4G（外挂 Air780EPM，也使用 UART3，与 WiFi 互斥）
        {
            type = "4g_airlink_uart",
            uart_id = 3, baud = 2000000,
            adapter = socket.LWIP_GP_GW,
        },

        { type = "eth_spi", chip = "CH390",              -- SPI 以太网兜底
          spi_id = 1, cs_pin = 14 },
    },

    -- ===== UI 显示控制（只写 = true 的项）=====
    ui = {
        show_wifi_icon = true,           -- 桌面顶栏 WiFi 图标
        show_storage_settings = true,    -- 设置页存储空间入口
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
