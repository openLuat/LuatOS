--[[
@module  config.eng_1602_7i_v4
@summary Air1602引擎主机 7寸1024x600 RGB屏(HX8282) + NAND Flash 配置文件
@version 1.0
@date    2026.05.25
@author  江访
]]
return {
    name = "Engine_Air1602_7inch_1024x600_004_V000",
    chip = "Air1602",
    baseboard = "合宙引擎AIR1602 V004",

    pins = {},

    -- GPIO 供电上电时序（V004: airlink WiFi 模组 GPIO55 低电平有效）
    power_on = {
        { pin = 55, dir = 0, level = 1, delay = 50 },
        { pin = 55, dir = 0, level = 0, delay = 120 },
    },

    hw = {
        lcd = {
            model = "lcd_hx8282_10in",
            params = {
                port = lcd.RGB,
                pin_rst = 15,
                direction = 0,
                w = 1024,
                h = 600,
            },
            need_buffer = true,
            screen_size = 7.0,
            font = { size = 20 },
            backlight = { pwm_ch = 3, pwm_freq = 1000 },
        },
        tp = {
            model = "tp_gt911",
            params = {
                port = 1,
                pin_rst = 3,
                pin_int = 51,
                int_type = tp.FALLING,
                w = 1024,
                h = 600,
                gpio_reset = 3,
            },
        },
        battery = {
            adc_channel = 7,
            usb_detect_gpio = 52,
            voltage_divider = 2,
            full_voltage = 4150,
        },
    },

    features = {
        net_4g = false,
        wifi = true,
        ethernet = false,
        buzzer = false,
        speaker = false,
        mic = false,
        sd_card = false,
        nand_flash = true,
        gnss = false,
        bluetooth = false,
        can = false,
        rs485 = false,
        usb_camera = false,
        spi_camera = false,
        i2c_sensor = false,
        nes = true,
        battery = true,
    },

    -- NES游戏按键绑定（7寸型号：方向键同5寸，功能键引脚不同）
    nes_keys = {
        { pin = 44, key = "NES_KEY_UP"    },  -- 上
        { pin = 48, key = "NES_KEY_DOWN"  },  -- 下
        { pin = 41, key = "NES_KEY_LEFT"  },  -- 左
        { pin = 40, key = "NES_KEY_RIGHT" },  -- 右
        { pin =  1, key = "NES_KEY_RETURN" },  -- 返回键
        { pin =  0, key = "NES_KEY_START" },  -- 开始
        { pin = 22, key = "NES_KEY_SELECT"},  -- 选择
        { pin = 23, key = "NES_KEY_A"     },  -- A
        { pin = 13, key = "NES_KEY_B"     },  -- B
    },

    ui = {
        show_4g_icon = false,
        show_wifi_icon = true,
        show_buzzer_settings = false,
        show_brightness_slider = true,
        show_ethernet_settings = false,
        show_storage_settings = true,
        show_camera_preview = false,
        show_sensor_panel = false,
        show_battery_icon = true,
    },

    storage = {
        nand_flash = { spi_id = 2, pin_cs = 4, speed = 40000000, pin_pwr = 50 },
    },
}
