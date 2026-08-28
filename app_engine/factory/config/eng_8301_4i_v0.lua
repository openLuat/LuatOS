--[[
@module  config.eng_8301_4i_v0
@summary Air8301 引擎主机 4.3寸480x272 SPI屏(ST6201) + WiFi + 4G + 双以太网(CH390H) + NAND Flash 配置文件
@version 1.0
@date    2026.08.24
@author  江访
@usage
所有 boolean 字段只写 = true 表示开启，不写即视为关闭（无需写 = false）
具体包含哪些参数，如何填写参考：template.lua

注意：
1. Air8301 基于 Air8000W 主控（4G + WiFi + BLE + SPI屏），屏幕和触摸与 Air1780H 4.3寸一致。
2. 引脚接线参考 module/Air8000/project/Air8301/hardware_test。
3. 以太网使用双 CH390H SPI 模式，共用 SPI1 总线（CS 脚不同）。
4. 无 SD 卡槽，仅 NAND Flash 存储。
]]
return {
    -- ===== 顶层信息 =====
    name = "Engine_Air8301_4inch_480x272_000_V000",  -- 项目命名: {类型}_{芯片}_{尺寸}_{分辨率}_{版本}
    chip = "Air8000W",                                 -- 主控芯片: Air8000W（4G + WiFi + BLE + SPI屏）
    baseboard = "合宙引擎 AIR8301 V000 4.3寸",         -- 底板型号

    -- ===== 引脚功能复用（填引脚号，不填 GPIO 号）=====
    pins = {
        { pin = 1,  func = "PWM0"      },  -- 背光 PWM0 调光（GPIO1_PWM0）
    },

    -- ===== GPIO 上电时序: 外设供电使能 + SPI1 CS 初始化 =====
    power_on = {
        { pin = 28, dir = 0, level = 1 },  -- LCD_EN = GPIO28 拉高使能 LCD 供电
        -- SPI1 总线 CS 脚全部拉高（空闲态），各驱动在 SPI 事务中自行控制
        { pin = 12, dir = 0, level = 1 },  -- SPI1_CS0 = GPIO12 拉高（以太网1 CH390H）
        { pin = 5,  dir = 0, level = 1 },  -- SPI1_CS1 = GPIO5  拉高（以太网2 CH390H）
        { pin = 4,  dir = 0, level = 1 },  -- SPI1_CS2 = GPIO4  拉高（NAND Flash）
        { pin = 140, dir = 0, level = 1 }, -- FLASH_3V3 = GPIO140 拉高使能 NAND Flash 供电
        -- 状态灯默认熄灭（GPIO21=4G_STATUS, GPIO141=WIFI_STATUS）
        { pin = 21,  dir = 0, level = 0 }, -- 4G_STATUS = GPIO21 默认熄灭
        { pin = 141, dir = 0, level = 0 }, -- WIFI_STATUS = GPIO141 默认熄灭
    },

    -- ===== 硬件配置 =====
    hw = {
        -- 屏幕: ST6201 SPI 4.3寸 480×272（与 Air1780H 4.3寸屏一致）
        lcd = {
            model = "lcd_st6201",
            params = {
                port = lcd.HWID_0,       -- 专用 LCD SPI 接口
                pin_rst = 36,            -- LCD_RST = GPIO36
                direction = 0,           -- 0° 方向
                w = 480,                 -- 水平分辨率
                h = 272,                 -- 竖直分辨率
                bus_speed = 80 * 1000 * 1000,  -- SPI 时钟 80MHz
                rb_swap = true,          -- 红蓝交换（与参考工程一致）
            },
            need_buffer = false,         -- SPI 屏不需要帧缓冲，直刷更快
            screen_size = 4.3,           -- 4.3寸屏
            font = { size = 16 },        -- 低分屏用 16 号字（固件内置字库，最低字号）
            backlight = {
                pwm_ch = 0,              -- PWM 通道 0（GPIO1_PWM0）
                pwm_freq = 1000,         -- 1kHz（SPI 屏推荐）
            },
        },
        -- 触摸: GT911 I2C0（Air8301 使用 I2C0，与 Air1780H 的 I2C1 不同）
        tp = {
            model = "tp_gt911",
            params = {
                port = 0,                -- I2C 端口 0（Air8301 硬件测试接线）
                pin_rst = 26,            -- TP_RESET = GPIO26
                pin_int = gpio.WAKEUP0,  -- TP_INT = WAKEUP0
                int_type = tp.FALLING,   -- 下降沿触发
                i2c_speed = i2c.SLOW,    -- 低速 I2C（推荐）
            },
        },
    },

    -- ===== 功能开关（只写 = true 的项）=====
    features = {
        net_4g = true,                   -- 启用 4G 蜂窝网络（Air8000W 内置 4G）
        wifi = true,                     -- 启用 WiFi（Air8000W 内置 WiFi）
        ethernet = true,                 -- 启用以太网（双 CH390H SPI 模式）
        buzzer = true,                   -- 启用蜂鸣器（触摸反馈音，PWM2=PIN98）
        nand_flash = true,               -- 启用 NAND Flash（需配 storage.nand_flash）
    },

    -- ===== 统一网络配置（优先级从高到低）=====
    network = {
        { type = "wifi_native" },        -- 自带 WiFi 优先
        { type = "4g_native" },          -- 自带 4G 兜底
        { type = "eth_spi",              -- 以太网1: CH390H SPI1/CS=GPIO12
          chip = "CH390", spi_id = 1, cs_pin = 12, irq_pin = 20, pwr_pin = 32 },
        { type = "eth_spi",              -- 以太网2: CH390H SPI1/CS=GPIO5
          chip = "CH390", spi_id = 1, cs_pin = 5, irq_pin = 0xff, pwr_pin = 33 },
    },

    -- ===== UI 显示控制（只写 = true 的项）=====
    ui = {
        show_4g_icon = true,             -- 桌面顶栏 4G 图标 ← 配 net_4g 时打开
        show_wifi_icon = true,           -- 桌面顶栏 WiFi 图标 ← 配 wifi 时打开
        show_ethernet_settings = true,   -- 设置页以太网设置入口 ← 配 ethernet 时打开
        show_brightness_slider = true,   -- 设置页亮度滑块
        show_storage_settings = true,    -- 设置页存储空间入口
        show_buzzer_settings = true,     -- 设置页蜂鸣器开关 ← 配 buzzer 时打开
    },

    -- ===== 存储设备: NAND Flash =====
    storage = {
        -- NAND Flash（SPI1_CS2 = GPIO4，供电 GPIO140 已由 power_on 处理）
        nand_flash = {
            spi_id = 1,                  -- SPI 接口 ID
            pin_cs = 4,                  -- SPI1_CS2 = GPIO4
            speed = 25600000,            -- SPI 时钟频率 Hz（对齐 hardware_test 25.6MHz）
        },
    },
}
