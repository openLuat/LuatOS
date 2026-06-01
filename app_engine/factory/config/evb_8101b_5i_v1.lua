--[[
@module  config.evb_8101b_5i_v1
@summary Air8101核心板 5寸480x854 RGB屏(ST7701S) 配置文件
@version 1.2
@date    2026.06.01
@author  江访
@usage
所有 boolean 字段只写 = true 表示开启，不写即视为关闭（无需写 = false）
具体包含哪些参数，如何填写参考：template.lua
]]
return {
    -- ===== 顶层信息 =====
    name = "EVB_Air8101B_5inch_480x854_000_V010",  -- 项目命名: {类型}_{芯片}_{尺寸}_{版本}
    chip = "Air8101",                                 -- 主控芯片: WiFi(exnetif) + RGB屏
    baseboard = "合宙引擎 8101B V002",                -- 底板型号

    -- ===== 引脚功能复用（填引脚号，不填 GPIO 号） =====
    pins = {
        { pin = 11, func = "I2C1_SDA"  },  -- I2C1 数据线（触摸通信）
        { pin = 12, func = "I2C1_SCL"  },  -- I2C1 时钟线
        { pin = 14, func = "PWM1"      },  -- PWM1 背光调光
        { pin = 72, func = "SPI0_CLK"  },  -- SPI0 时钟（存储设备）
        { pin = 71, func = "SPI0_MOSI" },  -- SPI0 主机输出
        { pin = 6,  func = "SPI0_MISO" },  -- SPI0 主机输入
    },

    -- ===== 硬件配置 =====
    hw = {
        -- 屏幕: ST7701S RGB 5寸 480×854
        lcd = {
            model = "lcd_st7701s_5in",
            params = {
                port = lcd.RGB,          -- RGB 接口
                pin_clk = 2,             -- SPI 时钟引脚（初始化通信）
                pin_sda = 4,             -- SPI 数据引脚
                pin_cs = 3,              -- SPI 片选引脚
                pin_rst = 9,             -- 复位引脚
                direction = 0,           -- 0° 方向
                w = 480,                 -- 水平分辨率
                h = 854,                 -- 竖直分辨率
            },
            need_buffer = true,          -- RGB 屏必须启用帧缓冲防撕裂
            rotation = 180,              -- Air8101 st7701s 屏需额外旋转 180°
            screen_size = 5.0,           -- 5寸屏
            font = {
                size = 20,               -- 高分屏用 20 号字
                path = "/MiSans_gb2312.ttf",  -- 外部 ttf 字体（Air8101 从文件系统加载）
                global = true,           -- 注册为全局字体
            },
            backlight = {
                pwm_ch = 1,              -- PWM 通道 1
                pwm_freq = 10000,        -- 10kHz（RGB 屏推荐）
            },
        },
        -- 触摸: GT911 I2C 端口1
        tp = {
            model = "tp_gt911",
            params = {
                port = 1,                -- I2C 端口 1
                pin_rst = 28,            -- 复位引脚
                pin_int = 7,             -- 中断引脚
                int_type = tp.FALLING,   -- 下降沿触发
                i2c_speed = i2c.SLOW,    -- 低速 I2C（推荐）
            },
        },
    },

    -- ===== 功能开关（只写 = true 的项）=====
    features = {
        wifi = true,                     -- 启用 WiFi
    },

    -- ===== UI 显示控制（只写 = true 的项）=====
    ui = {
        show_wifi_icon = true,           -- 桌面顶栏 WiFi 图标
        show_brightness_slider = true,   -- 设置页亮度滑块
        show_storage_settings = true,    -- 设置页存储空间入口
    },
}
