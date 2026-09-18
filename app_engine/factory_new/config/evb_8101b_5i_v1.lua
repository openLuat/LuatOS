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
            model = "lcd_display_rgb",
            params = {
                interface = "rgb",        -- RGB 接口
                pin_rst = 9,             -- 复位引脚
                pin_clk = 2,             -- SPI 时钟引脚（IC 初始化通信）
                pin_sda = 4,             -- SPI 数据引脚
                pin_cs = 3,              -- SPI 片选引脚
                w = 480,                 -- 水平分辨率
                h = 854,                 -- 竖直分辨率
                hbp = 40,                -- 水平后沿
                hspw = 10,               -- 水平同步脉宽
                hfp = 40,                -- 水平前沿
                vbp = 10,                -- 垂直后沿
                vspw = 8,                -- 垂直同步脉宽
                vfp = 20,                -- 垂直前沿
                bus_speed = 30 * 1000 * 1000,  -- RGB 总线时钟 30MHz
                -- ST7701S IC 寄存器初始化序列（SPI 3-wire 9bit）
                ic_init = function(params)
                    gpio.setup(params.pin_cs or 3, 0)
                    local rp = gpio.setup(params.pin_rst or 9, 1)
                    rp(1); sys.wait(20); rp(0); sys.wait(20); rp(1); sys.wait(120)
                    lcd.cmd(0xFF); lcd.data(0x77); lcd.data(0x01); lcd.data(0x00); lcd.data(0x00); lcd.data(0x13)
                    lcd.cmd(0xEF); lcd.data(0x08)
                    lcd.cmd(0xFF); lcd.data(0x77); lcd.data(0x01); lcd.data(0x00); lcd.data(0x00); lcd.data(0x10)
                    lcd.cmd(0xC0); lcd.data(0xE9); lcd.data(0x03)
                    lcd.cmd(0xC1); lcd.data(0x11); lcd.data(0x02)
                    lcd.cmd(0xC2); lcd.data(0x01); lcd.data(0x08)
                    lcd.cmd(0xCC); lcd.data(0x18)
                    lcd.cmd(0xB0); lcd.data(0x00); lcd.data(0x0D); lcd.data(0x14); lcd.data(0x0D)
                    lcd.data(0x10); lcd.data(0x05); lcd.data(0x02); lcd.data(0x08); lcd.data(0x08)
                    lcd.data(0x1E); lcd.data(0x05); lcd.data(0x13); lcd.data(0x11); lcd.data(0xA3)
                    lcd.data(0x29); lcd.data(0x18)
                    lcd.cmd(0xB1); lcd.data(0x00); lcd.data(0x0C); lcd.data(0x14); lcd.data(0x0C)
                    lcd.data(0x10); lcd.data(0x05); lcd.data(0x03); lcd.data(0x08); lcd.data(0x07)
                    lcd.data(0x20); lcd.data(0x05); lcd.data(0x13); lcd.data(0x11); lcd.data(0xA4)
                    lcd.data(0x29); lcd.data(0x18)
                    lcd.cmd(0xFF); lcd.data(0x77); lcd.data(0x01); lcd.data(0x00); lcd.data(0x00); lcd.data(0x11)
                    lcd.cmd(0xB0); lcd.data(0x6C)
                    lcd.cmd(0xB1); lcd.data(0x43)
                    lcd.cmd(0xB2); lcd.data(0x87)
                    lcd.cmd(0xB3); lcd.data(0x80)
                    lcd.cmd(0xB5); lcd.data(0x47)
                    lcd.cmd(0xB7); lcd.data(0x85)
                    lcd.cmd(0xB8); lcd.data(0x20)
                    lcd.cmd(0xB9); lcd.data(0x10)
                    lcd.cmd(0xC1); lcd.data(0x78)
                    lcd.cmd(0xC2); lcd.data(0x78)
                    lcd.cmd(0xD0); lcd.data(0x88)
                    sys.wait(100)
                    lcd.cmd(0xE0); lcd.data(0x00); lcd.data(0x00); lcd.data(0x02)
                    lcd.cmd(0xE1); lcd.data(0x08); lcd.data(0x00); lcd.data(0x0A); lcd.data(0x00); lcd.data(0x07)
                    lcd.data(0x00); lcd.data(0x09); lcd.data(0x00); lcd.data(0x00); lcd.data(0x33); lcd.data(0x33)
                    lcd.cmd(0xE2); lcd.data(0x00); lcd.data(0x00); lcd.data(0x00); lcd.data(0x00); lcd.data(0x00)
                    lcd.data(0x00); lcd.data(0x00); lcd.data(0x00); lcd.data(0x00); lcd.data(0x00); lcd.data(0x00)
                    lcd.data(0x00); lcd.data(0x00)
                    lcd.cmd(0xE3); lcd.data(0x00); lcd.data(0x00); lcd.data(0x33); lcd.data(0x33)
                    lcd.cmd(0xE4); lcd.data(0x44); lcd.data(0x44)
                    lcd.cmd(0xE5); lcd.data(0x0E); lcd.data(0x60); lcd.data(0xA0); lcd.data(0xA0); lcd.data(0x10)
                    lcd.data(0x60); lcd.data(0xA0); lcd.data(0xA0); lcd.data(0x0A); lcd.data(0x60); lcd.data(0xA0)
                    lcd.data(0xA0); lcd.data(0x0C); lcd.data(0x60); lcd.data(0xA0); lcd.data(0xA0)
                    lcd.cmd(0xE6); lcd.data(0x00); lcd.data(0x00); lcd.data(0x33); lcd.data(0x33)
                    lcd.cmd(0xE7); lcd.data(0x44); lcd.data(0x44)
                    lcd.cmd(0xE8); lcd.data(0x0D); lcd.data(0x60); lcd.data(0xA0); lcd.data(0xA0); lcd.data(0x0F)
                    lcd.data(0x60); lcd.data(0xA0); lcd.data(0xA0); lcd.data(0x09); lcd.data(0x60); lcd.data(0xA0)
                    lcd.data(0xA0); lcd.data(0x0B); lcd.data(0x60); lcd.data(0xA0); lcd.data(0xA0)
                    lcd.cmd(0xEB); lcd.data(0x02); lcd.data(0x01); lcd.data(0xE4); lcd.data(0xE4); lcd.data(0x44)
                    lcd.data(0x00); lcd.data(0x40)
                    lcd.cmd(0xEC); lcd.data(0x02); lcd.data(0x01)
                    lcd.cmd(0xED); lcd.data(0xAB); lcd.data(0x89); lcd.data(0x76); lcd.data(0x54); lcd.data(0x01)
                    lcd.data(0xFF); lcd.data(0xFF); lcd.data(0xFF); lcd.data(0xFF); lcd.data(0xFF); lcd.data(0xFF)
                    lcd.data(0x10); lcd.data(0x45); lcd.data(0x67); lcd.data(0x98); lcd.data(0xBA)
                    lcd.cmd(0xEF); lcd.data(0x08); lcd.data(0x08); lcd.data(0x08); lcd.data(0x45)
                    lcd.data(0x3F); lcd.data(0x54)
                    lcd.cmd(0xFF); lcd.data(0x77); lcd.data(0x01); lcd.data(0x00); lcd.data(0x00); lcd.data(0x13)
                    lcd.cmd(0xE8); lcd.data(0x00); lcd.data(0x0E)
                    lcd.cmd(0xFF); lcd.data(0x77); lcd.data(0x01); lcd.data(0x00); lcd.data(0x00); lcd.data(0x00)
                    lcd.cmd(0x11); sys.wait(120)
                    lcd.cmd(0xFF); lcd.data(0x77); lcd.data(0x01); lcd.data(0x00); lcd.data(0x00); lcd.data(0x13)
                    lcd.cmd(0xE8); lcd.data(0x00); lcd.data(0x0C); sys.wait(10)
                    lcd.cmd(0xE8); lcd.data(0x00); lcd.data(0x00)
                    lcd.cmd(0xFF); lcd.data(0x77); lcd.data(0x01); lcd.data(0x00); lcd.data(0x00); lcd.data(0x00)
                    lcd.cmd(0x29)
                    lcd.cmd(0x3a); lcd.data(0x77)
                    lcd.cmd(0x36); lcd.data(0x08)
                    sys.wait(20)
                end,
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

    -- ===== 统一网络配置（优先级从高到低）=====
    network = {
        { type = "wifi_native" },        -- 自带 WiFi（Air8101B）
    },

    -- ===== UI 显示控制（只写 = true 的项）=====
    ui = {
        show_wifi_icon = true,           -- 桌面顶栏 WiFi 图标
        show_brightness_slider = true,   -- 设置页亮度滑块
        show_storage_settings = true,    -- 设置页存储空间入口
    },
}
