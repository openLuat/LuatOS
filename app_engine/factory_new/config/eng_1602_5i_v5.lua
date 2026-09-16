--[[
@module  config.eng_1602_5i_v5
@summary Air1602引擎主机 5寸480x854 RGB屏(ST7701S) + NAND Flash + WiFi(airlink低电平)
@version 1.1
@date    2026.06.01
@author  江访
@usage
所有 boolean 字段只写 = true 表示开启，不写即视为关闭（无需写 = false）
具体包含哪些参数，如何填写参考：template.lua
]]
return {
    -- ===== 顶层信息 =====
    name = "Engine_Air1602_5inch_480x854_005_V000",  -- 项目命名: {类型}_{芯片}_{尺寸}_{版本}
    chip = "Air1602",                                  -- 主控芯片: RGB屏 + WiFi(airlink)
    baseboard = "合宙引擎AIR1602 V005",                -- 底板型号

    -- ===== 引脚功能复用（无特殊复用需求，留空）=====
    pins = {},

    -- ===== GPIO 上电时序: WiFi 模组保持低电平 =====
    -- Air1602 V005 airlink WiFi 模组: GPIO55 保持低电平（低电平有效）
    power_on = {
        { pin = 55, dir = 0, level = 0, delay = 50 },  -- 保持低电平 50ms
    },

    -- ===== 硬件配置 =====
    hw = {
        -- 屏幕: ST7701S RGB 5寸 480×854
        lcd = {
            model = "lcd_display_rgb",
            params = {
                interface = "rgb",             -- RGB 接口
                pin_rst = 15,                  -- 复位引脚
                pin_clk = 23,                  -- SPI 时钟引脚（IC 初始化通信）
                pin_sda = 2,                   -- SPI 数据引脚
                pin_cs = 22,                   -- SPI 片选引脚
                w = 480,                       -- 水平分辨率
                h = 854,                       -- 竖直分辨率
                hbp = 40,                      -- 水平后沿
                hspw = 10,                     -- 水平同步脉宽
                hfp = 40,                      -- 水平前沿
                vbp = 10,                      -- 垂直后沿
                vspw = 8,                      -- 垂直同步脉宽
                vfp = 20,                      -- 垂直前沿
                bus_speed = 30 * 1000 * 1000,  -- RGB 总线时钟 30MHz
                -- ST7701S IC 寄存器初始化序列（与 evb_8101b_5i_v1 相同）
                ic_init = function(params)
                    gpio.setup(params.pin_cs or 22, 0)
                    local rp = gpio.setup(params.pin_rst or 15, 1)
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
                gpio_reset = 3,          -- 额外复位 GPIO（Air1602 常用）
            },
        },
        -- 电池管理: ADC 通道7，USB 检测 GPIO52
        battery = {
            adc_channel = 7,             -- ADC 通道号
            usb_detect_gpio = 52,        -- USB 插入检测 GPIO
            voltage_divider = 2,         -- 分压比 2:1
            full_voltage = 4150,         -- 充满电压 4.15V
        },
    },

    -- ===== 功能开关（只写 = true 的项）=====
    features = {
        wifi = true,                     -- 启用 WiFi
        nand_flash = true,               -- 启用 NAND Flash 存储
        nes = true,                      -- 启用 NES 游戏按键（需配 nes_keys）
        battery = true,                  -- 启用电池管理（需配 hw.battery + ui.show_battery_icon）
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
        show_battery_icon = true,        -- 桌面顶栏电池图标 ← 配 battery 时打开
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
