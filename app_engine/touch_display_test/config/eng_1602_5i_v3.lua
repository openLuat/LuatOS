--[[
@module  config.eng_1602_5i_v3
@summary Air1602引擎主机 5寸720x1280 RGB屏(NV3052C) + NAND Flash 配置文件
@version 1.2
@date    2026.06.01
@author  江访
@usage
所有 boolean 字段只写 = true 表示开启，不写即视为关闭（无需写 = false）
具体包含哪些参数，如何填写参考：template.lua
]]
return {
    -- ===== 顶层信息 =====
    name = "Engine_Air1602_5inch_720x1280_003_V000",  -- 项目命名: {类型}_{芯片}_{尺寸}_{版本}
    chip = "Air1602",                                   -- 主控芯片: RGB屏 + WiFi(airlink)
    baseboard = "合宙引擎AIR1602 V003",                  -- 底板型号

    -- ===== 引脚功能复用（无特殊复用需求，留空）=====
    pins = {},

    -- ===== GPIO 上电时序: WiFi 模组复位 =====
    -- Air1602 airlink WiFi 模组: GPIO55 拉低→延时→拉高（高电平有效）
    power_on = {
        { pin = 55, dir = 0, level = 0, delay = 50  },  -- 拉低 50ms 复位
        { pin = 55, dir = 0, level = 1, delay = 120 },  -- 拉高 120ms 使能
    },

    -- ===== 硬件配置 =====
    hw = {
        -- 屏幕: NV3052C RGB 5寸 720×1280
        lcd = {
            model = "lcd_display_rgb",
            params = {
                interface = "rgb",             -- RGB 接口
                pin_rst = 15,                  -- 复位引脚
                pin_clk = 23,                  -- SPI 时钟引脚（IC 初始化通信）
                pin_sda = 22,                  -- SPI 数据引脚
                pin_cs = 2,                    -- SPI 片选引脚
                w = 720,                       -- 水平分辨率
                h = 1280,                      -- 竖直分辨率
                hbp = 30,                      -- 水平后沿（NV3052C 720x1280 参考值）
                hspw = 10,                     -- 水平同步脉宽
                hfp = 30,                      -- 水平前沿
                vbp = 12,                      -- 垂直后沿
                vspw = 4,                      -- 垂直同步脉宽
                vfp = 20,                      -- 垂直前沿
                bus_speed = 60 * 1000 * 1000,  -- RGB 总线时钟 60MHz
                -- NV3052C IC 寄存器初始化序列（与 eng_1602_5i_v2 相同）
                ic_init = function(params)
                    local rp = gpio.setup(params.pin_rst or 15, 1)
                    rp(1); sys.wait(20); rp(0); sys.wait(20); rp(1); sys.wait(120)
                    lcd.cmd(0xFF, 0x30); lcd.cmd(0xFF, 0x52); lcd.cmd(0xFF, 0x01); lcd.cmd(0xE3, 0x00)
                    lcd.cmd(0x0A, 0x01); lcd.cmd(0x23, 0xA2); lcd.cmd(0x24, 0x10); lcd.cmd(0x25, 0x0A)
                    lcd.cmd(0x26, 0x3C); lcd.cmd(0x27, 0x46); lcd.cmd(0x38, 0x9C); lcd.cmd(0x39, 0xA7)
                    lcd.cmd(0x3A, 0x47); lcd.cmd(0x91, 0x77); lcd.cmd(0x92, 0x77); lcd.cmd(0x99, 0x51)
                    lcd.cmd(0x9B, 0x59); lcd.cmd(0xA0, 0x55); lcd.cmd(0xA1, 0x50); lcd.cmd(0xA4, 0x9C)
                    lcd.cmd(0xA7, 0x02); lcd.cmd(0xA8, 0x01); lcd.cmd(0xA9, 0x01); lcd.cmd(0xAA, 0xFC)
                    lcd.cmd(0xAB, 0x28); lcd.cmd(0xAC, 0x06); lcd.cmd(0xAD, 0x06); lcd.cmd(0xAE, 0x06)
                    lcd.cmd(0xAF, 0x03); lcd.cmd(0xB0, 0x08); lcd.cmd(0xB1, 0x26); lcd.cmd(0xB2, 0x28)
                    lcd.cmd(0xB3, 0x28); lcd.cmd(0xB4, 0x03); lcd.cmd(0xB5, 0x08); lcd.cmd(0xB6, 0x26)
                    lcd.cmd(0xB7, 0x08); lcd.cmd(0xB8, 0x26)
                    lcd.cmd(0xFF, 0x30); lcd.cmd(0xFF, 0x52); lcd.cmd(0xFF, 0x02)
                    lcd.cmd(0xB0, 0x01); lcd.cmd(0xB1, 0x12); lcd.cmd(0xB2, 0x09); lcd.cmd(0xB3, 0x2B)
                    lcd.cmd(0xB4, 0x2F); lcd.cmd(0xB5, 0x30); lcd.cmd(0xB6, 0x19); lcd.cmd(0xB7, 0x35)
                    lcd.cmd(0xB8, 0x0D); lcd.cmd(0xB9, 0x03); lcd.cmd(0xBA, 0x12); lcd.cmd(0xBB, 0x12)
                    lcd.cmd(0xBC, 0x14); lcd.cmd(0xBD, 0x15); lcd.cmd(0xBE, 0x18); lcd.cmd(0xBF, 0x0F)
                    lcd.cmd(0xC0, 0x17); lcd.cmd(0xC1, 0x08); lcd.cmd(0xD0, 0x0F); lcd.cmd(0xD1, 0x12)
                    lcd.cmd(0xD2, 0x1A); lcd.cmd(0xD3, 0x38); lcd.cmd(0xD4, 0x36); lcd.cmd(0xD5, 0x3a)
                    lcd.cmd(0xD6, 0x22); lcd.cmd(0xD7, 0x40); lcd.cmd(0xD8, 0x0D); lcd.cmd(0xD9, 0x03)
                    lcd.cmd(0xDA, 0x11); lcd.cmd(0xDB, 0x10); lcd.cmd(0xDC, 0x12); lcd.cmd(0xDD, 0x13)
                    lcd.cmd(0xDE, 0x18); lcd.cmd(0xDF, 0x10); lcd.cmd(0xE0, 0x17); lcd.cmd(0xE1, 0x08)
                    lcd.cmd(0xFF, 0x30); lcd.cmd(0xFF, 0x52); lcd.cmd(0xFF, 0x03)
                    lcd.cmd(0x00, 0x2A); lcd.cmd(0x01, 0x2A); lcd.cmd(0x02, 0x2A); lcd.cmd(0x03, 0x2A)
                    lcd.cmd(0x08, 0x02); lcd.cmd(0x09, 0x03); lcd.cmd(0x0A, 0x04); lcd.cmd(0x0B, 0x05)
                    lcd.cmd(0x30, 0x2A); lcd.cmd(0x31, 0x2A); lcd.cmd(0x32, 0x2A); lcd.cmd(0x33, 0x2A)
                    lcd.cmd(0x34, 0x81); lcd.cmd(0x35, 0x26); lcd.cmd(0x37, 0x13)
                    lcd.cmd(0x40, 0x03); lcd.cmd(0x41, 0x04); lcd.cmd(0x42, 0x05); lcd.cmd(0x43, 0x06)
                    lcd.cmd(0x45, 0x08); lcd.cmd(0x46, 0x09); lcd.cmd(0x48, 0x0a); lcd.cmd(0x49, 0x0b)
                    lcd.cmd(0x50, 0x07); lcd.cmd(0x51, 0x08); lcd.cmd(0x52, 0x09); lcd.cmd(0x53, 0x0a)
                    lcd.cmd(0x55, 0x0c); lcd.cmd(0x56, 0x0d); lcd.cmd(0x58, 0x0e); lcd.cmd(0x59, 0x0f)
                    lcd.cmd(0x80, 0x00); lcd.cmd(0x81, 0x00); lcd.cmd(0x82, 0x04); lcd.cmd(0x83, 0x02)
                    lcd.cmd(0x84, 0x0E); lcd.cmd(0x85, 0x10); lcd.cmd(0x86, 0x0A); lcd.cmd(0x87, 0x0C)
                    lcd.cmd(0x91, 0x00); lcd.cmd(0x92, 0x00); lcd.cmd(0x93, 0x00); lcd.cmd(0x94, 0x1f)
                    lcd.cmd(0x95, 0x1F); lcd.cmd(0x96, 0x00); lcd.cmd(0x97, 0x00)
                    lcd.cmd(0x98, 0x03); lcd.cmd(0x99, 0x01); lcd.cmd(0x9A, 0x0D); lcd.cmd(0x9B, 0x0F)
                    lcd.cmd(0x9C, 0x09); lcd.cmd(0x9D, 0x0B)
                    lcd.cmd(0xA7, 0x00); lcd.cmd(0xA8, 0x00); lcd.cmd(0xA9, 0x00); lcd.cmd(0xAA, 0x1F)
                    lcd.cmd(0xAB, 0x1F); lcd.cmd(0xB0, 0x00); lcd.cmd(0xB1, 0x1F)
                    lcd.cmd(0xB2, 0x01); lcd.cmd(0xB3, 0x03); lcd.cmd(0xB4, 0x0B); lcd.cmd(0xB5, 0x09)
                    lcd.cmd(0xB6, 0x0F); lcd.cmd(0xB7, 0x0D)
                    lcd.cmd(0xC1, 0x00); lcd.cmd(0xC2, 0x00); lcd.cmd(0xC3, 0x00); lcd.cmd(0xC4, 0x1F)
                    lcd.cmd(0xC5, 0x00); lcd.cmd(0xC6, 0x00); lcd.cmd(0xC7, 0x1F)
                    lcd.cmd(0xC8, 0x02); lcd.cmd(0xC9, 0x04); lcd.cmd(0xCA, 0x0C); lcd.cmd(0xCB, 0x0A)
                    lcd.cmd(0xCC, 0x10); lcd.cmd(0xCD, 0x0E)
                    lcd.cmd(0xD7, 0x00); lcd.cmd(0xD8, 0x00); lcd.cmd(0xD9, 0x00); lcd.cmd(0xDA, 0x1F)
                    lcd.cmd(0xDB, 0x00); lcd.cmd(0xFF, 0x30); lcd.cmd(0xFF, 0x52); lcd.cmd(0xFF, 0x00)
                    lcd.cmd(0x36, 0x0A)
                    lcd.cmd(0x11, 0x00); sys.wait(200)
                    lcd.cmd(0x29, 0x00); sys.wait(100)
                end,
            },
            need_buffer = true,          -- RGB 屏必须启用帧缓冲防撕裂
            screen_size = 5.0,           -- 5寸屏
            font = { size = 20 },        -- 高分屏用 20 号字
            backlight = {
                pwm_ch = 3,              -- PWM 通道 3
                pwm_freq = 1000,         -- 1kHz
            },
        },
        -- 触摸: GT911 I2C 端口1
        tp = {
            model = "tp_gt911",
            params = {
                port = 1,                -- I2C 端口 1
                pin_rst = 3,             -- 复位引脚
                pin_int = 51,            -- 中断引脚
                int_type = tp.FALLING,   -- 下降沿触发
                w = 720,                 -- 触摸面板宽度（与 LCD 一致）
                h = 1280,                -- 触摸面板高度
                gpio_reset = 3,          -- 额外复位 GPIO（Air1602 常用）
            },
        },
    },

    -- ===== 功能开关（只写 = true 的项）=====
    features = {
        wifi = true,                     -- 启用 WiFi
        nand_flash = true,               -- 启用 NAND Flash 存储
        nes = true,                      -- 启用 NES 游戏按键（需配 nes_keys）
    },

    -- ===== 统一网络配置（优先级从高到低）=====
    network = {
        { type = "wifi_airlink_spi",     -- Airlink SPI WiFi 外挂模组
          spi_id = 1, cs_pin = 8, rdy_pin = 14 },
    },

    -- ===== NES 游戏按键绑定 =====
    -- 方向键: 支持 8 方向组合 + 持续按住
    -- 动作键: A 和 B，200ms 内先后按下触发 NES_COMBO("AB") 组合事件
    nes_keys = {
        { pin = 44, key = "NES_KEY_UP"    },  -- 上
        { pin = 48, key = "NES_KEY_DOWN"  },  -- 下
        { pin = 41, key = "NES_KEY_LEFT"  },  -- 左
        { pin = 40, key = "NES_KEY_RIGHT" },  -- 右
        { pin =  0, key = "NES_KEY_A"     },  -- A
        { pin =  1, key = "NES_KEY_B"     },  -- B
    },

    -- ===== UI 显示控制（只写 = true 的项）=====
    ui = {
        show_wifi_icon = true,           -- 桌面顶栏 WiFi 图标
        show_brightness_slider = true,   -- 设置页亮度滑块
        show_storage_settings = true,    -- 设置页存储空间入口
    },

    -- ===== 存储设备: NAND Flash =====
    storage = {
        nand_flash = {
            spi_id = 2,                  -- SPI 接口 ID，通常 spi2 用于外置存储
            pin_cs = 4,                  -- 片选 CS 引脚
            speed = 40000000,            -- SPI 时钟频率 Hz
            pin_pwr = 50,                -- 额外供电使能 GPIO
        },
    },
}
