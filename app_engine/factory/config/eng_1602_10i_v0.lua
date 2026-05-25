--[[
@module  config.eng_1602_10i_v0
@summary Air1602引擎主机 10.1寸1024x600 RGB屏 配置文件
@version 1.1
@date    2026.05.22
@author  江访
]]
return {
    name = "Engine_Air1602_10inch1_1024x600_001_V000",
    chip = "Air1602",
    baseboard = "合宙引擎AIR1602 V001",

    pins = {},

    -- GPIO 供电上电时序（Air1602 airlink WiFi 模组: GPIO55 拉低→延时→拉高）
    power_on = {
        { pin = 55, dir = 0, level = 0, delay = 50 },
        { pin = 55, dir = 0, level = 1, delay = 120 },
    },

    hw = {
        lcd = {
            model = "lcd_custom_10in",
            params = {
                port = lcd.RGB,
                pin_rst = 15,
                direction = 0,
                w = 1024,
                h = 600,
            },
            need_buffer = true,
            screen_size = 10.0,
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
    },

    features = {
        net_4g = false,
        wifi = true,
        ethernet = false,
        buzzer = true,
        speaker = false,
        mic = false,
        sd_card = false,
        nand_flash = false,
        gnss = false,
        bluetooth = false,
        can = false,
        rs485 = false,
        usb_camera = false,
        spi_camera = false,
        i2c_sensor = false,
    },

    ui = {
        show_4g_icon = false,
        show_wifi_icon = true,
        show_buzzer_settings = true,
        show_brightness_slider = true,
        show_ethernet_settings = false,
        show_storage_settings = true,
        show_camera_preview = false,
        show_sensor_panel = false,
    },
}
