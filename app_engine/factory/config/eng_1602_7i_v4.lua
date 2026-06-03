--[[
@module  config.eng_1602_7i_v4
@summary Air1602引擎主机 7寸1024x600 RGB屏(HX8282) + NAND Flash + NES + 电池 配置文件
@version 1.1
@date    2026.06.01
@author  江访
@usage
所有 boolean 字段只写 = true 表示开启，不写即视为关闭（无需写 = false）
具体包含哪些参数，如何填写参考：template.lua
]]
return {
    -- ===== 顶层信息 =====
    name = "Engine_Air1602_7inch_1024x600_004_V000",  -- 项目命名: {类型}_{芯片}_{尺寸}_{版本}
    chip = "Air1602",                                   -- 主控芯片: RGB屏 + WiFi(airlink)
    baseboard = "合宙引擎AIR1602 V004",                  -- 底板型号

    -- ===== 引脚功能复用（无特殊复用需求，留空）=====
    pins = {},

    -- ===== GPIO 上电时序: WiFi 模组复位 =====
    -- V004 airlink WiFi 模组: GPIO55 先高后低（低电平有效，与 V000/V002/V003 相反）
    power_on = {
        { pin = 55, dir = 0, level = 1, delay = 50  },  -- 拉高 50ms
        { pin = 55, dir = 0, level = 0, delay = 120 },  -- 拉低 120ms 使能
    },

    -- ===== 硬件配置 =====
    hw = {
        -- 屏幕: HX8282 RGB 7寸 1024×600（四合一芯片，无需 SPI 初始化引脚）
        lcd = {
            model = "lcd_hx8282_10in",
            params = {
                port = lcd.RGB,          -- RGB 接口
                pin_rst = 15,            -- 复位引脚
                direction = 0,           -- 0° 方向
                w = 1024,                -- 水平分辨率
                h = 600,                 -- 竖直分辨率
            },
            need_buffer = true,          -- RGB 屏必须启用帧缓冲防撕裂
            screen_size = 7.0,           -- 7寸屏
            font = { size = 20 },        -- 高分屏用 20 号字
            backlight = {
                pwm_ch = 3,              -- PWM 通道 3
                pwm_freq = 1000,         -- 1kHz
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

    -- ===== NES 游戏按键绑定（7寸型号: 功能键引脚与 5寸版不同）=====
    -- 方向键: 支持 8 方向组合 + 持续按住
    -- 动作键: A 和 B，200ms 内先后按下触发 NES_COMBO("AB") 组合事件
    -- 控制键: RETURN/START/SELECT，按下沿触发 + 200ms 防抖，发布 NES_CTRL 事件
    nes_keys = {
        { pin = 44, key = "NES_KEY_UP"     },  -- 上
        { pin = 48, key = "NES_KEY_DOWN"   },  -- 下
        { pin = 41, key = "NES_KEY_LEFT"   },  -- 左
        { pin = 40, key = "NES_KEY_RIGHT"  },  -- 右
        { pin =  1, key = "NES_KEY_RETURN" },  -- 返回（退出 APP）
        { pin =  0, key = "NES_KEY_START"  },  -- 开始
        { pin = 22, key = "NES_KEY_SELECT" },  -- 选择
        { pin = 23, key = "NES_KEY_A"      },  -- A
        { pin =  2, key = "NES_KEY_B"      },  -- B
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
