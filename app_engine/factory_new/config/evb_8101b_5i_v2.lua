--[[
@module  config.evb_8101b_5i_v2
@summary Air8101B核心板 5寸480x854 RGB屏(GC9503) 配置文件
@version 1.0
@date    2026.07.01
@author  江访
@usage
所有 boolean 字段只写 = true 表示开启，不写即视为关闭（无需写 = false）
具体包含哪些参数，如何填写参考：template.lua
]]
return {
    -- ===== 顶层信息 =====
    name = "EVB_Air8101B_5inch_480x854_000_V020",  -- 项目命名: {类型}_{芯片}_{尺寸}_{版本}
    chip = "Air8101",                                 -- 主控芯片: WiFi(exnetif) + RGB屏
    baseboard = "合宙引擎 8101B V020",                -- 底板型号

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
        -- 屏幕: GC9503 RGB 5寸 480×854
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
                hbp = 40,                -- 水平后廊
                hspw = 10,               -- 水平同步脉宽
                hfp = 40,                -- 水平前廊
                vbp = 10,                -- 垂直后廊
                vspw = 8,                -- 垂直同步脉宽
                vfp = 20,                -- 垂直前廊
                bus_speed = 30 * 1000 * 1000, -- RGB 总线时钟 30MHz
                -- GC9503 IC 寄存器初始化序列
                ic_init = function(params)
                    gpio.setup(params.pin_cs or 3, 0)
                    local rp = gpio.setup(params.pin_rst or 9, 1)
                    rp(1); sys.wait(20); rp(0); sys.wait(20); rp(1); sys.wait(120)
                    lcd.cmd(0xFE); lcd.cmd(0xEF)
                    lcd.cmd(0x36); lcd.data(0x48)
                    lcd.cmd(0x3A); lcd.data(0x10)
                    lcd.cmd(0xB0); lcd.data(0x01)
                    lcd.cmd(0xB1); lcd.data(0x26); lcd.data(0x23); lcd.data(0x22); lcd.data(0x21); lcd.data(0x20); lcd.data(0x1F); lcd.data(0x1E); lcd.data(0x1D); lcd.data(0x1C); lcd.data(0x18); lcd.data(0x02)
                    lcd.cmd(0xB2); lcd.data(0x01)
                    lcd.cmd(0xB3); lcd.data(0x00); lcd.data(0x00); lcd.data(0x00); lcd.data(0x00); lcd.data(0x22); lcd.data(0x21); lcd.data(0x20); lcd.data(0x1F); lcd.data(0x1E); lcd.data(0x1D); lcd.data(0x1C); lcd.data(0x18)
                    lcd.cmd(0xB4); lcd.data(0x41)
                    lcd.cmd(0xB5); lcd.data(0x02); lcd.data(0x08)
                    lcd.cmd(0xB6); lcd.data(0x80)
                    lcd.cmd(0xB8); lcd.data(0x45); lcd.data(0x09)
                    lcd.cmd(0xB9); lcd.data(0x41); lcd.data(0x08)
                    lcd.cmd(0xBA); lcd.data(0x00)
                    lcd.cmd(0xBC); lcd.data(0x43); lcd.data(0x00); lcd.data(0x00); lcd.data(0x00); lcd.data(0x0F); lcd.data(0x39); lcd.data(0x00)
                    lcd.cmd(0xBD); lcd.data(0x30); lcd.data(0x08); lcd.data(0x00); lcd.data(0x00); lcd.data(0x00)
                    lcd.cmd(0xBE); lcd.data(0x23); lcd.data(0x00); lcd.data(0x00); lcd.data(0x00); lcd.data(0x00)
                    lcd.cmd(0xBF); lcd.data(0x27); lcd.data(0x00); lcd.data(0x00); lcd.data(0x00); lcd.data(0x00)
                    lcd.cmd(0xC0); lcd.data(0x12); lcd.data(0x12)
                    lcd.cmd(0xC1); lcd.data(0x24); lcd.data(0x02)
                    lcd.cmd(0xC2); lcd.data(0x01); lcd.data(0x08)
                    lcd.cmd(0xCC); lcd.data(0x18)
                    lcd.cmd(0xCD); lcd.data(0x00)
                    lcd.cmd(0xD0); lcd.data(0x22); lcd.data(0x0A); lcd.data(0x0A); lcd.data(0xE0)
                    lcd.cmd(0xD1); lcd.data(0xC0); lcd.data(0x44); lcd.data(0x26); lcd.data(0x06)
                    lcd.cmd(0xD2); lcd.data(0x08); lcd.data(0x40); lcd.data(0x24); lcd.data(0x08)
                    lcd.cmd(0xD5); lcd.data(0x20); lcd.data(0x00); lcd.data(0x04); lcd.data(0x80)
                    lcd.cmd(0xE6); lcd.data(0x00); lcd.data(0x00); lcd.data(0x10); lcd.data(0x00)
                    lcd.cmd(0xD6); lcd.data(0xC0); lcd.data(0x44); lcd.data(0x26); lcd.data(0x06)
                    lcd.cmd(0xD7); lcd.data(0x22); lcd.data(0x0A); lcd.data(0x0A); lcd.data(0xE0)
                    lcd.cmd(0xD8); lcd.data(0x20); lcd.data(0x00); lcd.data(0x04); lcd.data(0x80)
                    lcd.cmd(0xE7); lcd.data(0x00); lcd.data(0x00); lcd.data(0x10); lcd.data(0x00)
                    lcd.cmd(0xE8); lcd.data(0x01); lcd.data(0x0A)
                    lcd.cmd(0xEC); lcd.data(0x3C); lcd.data(0x00)
                    lcd.cmd(0xED); lcd.data(0x00); lcd.data(0x00); lcd.data(0x20); lcd.data(0x5F)
                    lcd.cmd(0xEF); lcd.data(0x10); lcd.data(0x0D); lcd.data(0x04); lcd.data(0x08); lcd.data(0x3F); lcd.data(0x1F)
                    lcd.cmd(0x36); lcd.data(0x00)
                    lcd.cmd(0x11); sys.wait(120)
                    lcd.cmd(0x29); sys.wait(20)
                end,
            },
            need_buffer = true,          -- RGB 屏必须启用帧缓冲防撕裂
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
