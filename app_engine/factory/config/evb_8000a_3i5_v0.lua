--[[
@module  config.evb_8000a_3i5_v0
@summary Air8000A trunkey 开发板 3.5寸480x320 SPI屏 配置文件
@version 1.0
@date    2026.05.25
@author  江访
]]
return {
    name = "EVB_Air8000A_3inch5_480x320_000_V020",
    chip = "Air8000",
    baseboard = "Air8000A trunkey 开发板 V020",

    pins = {
        { pin = 31, func = "PWM0" },
        { pin = 35, func = "PWM4" },
    },

    -- GPIO 上电时序: LCD供电 + TP I2C上拉 + 100ms稳定等待
    power_on = {
        { pin = 141, dir = 0, level = 1 },
        { pin = 147, dir = 1, level = 1 },
        { pin = 164, dir = 1, level = 1 },
        { pin = 17,  dir = 1, level = 1 },
        { pin = 16,  dir = 1, level = 1, delay = 100 },
    },

    hw = {
        lcd = {
            model = "lcd_st7796",
            params = {
                port = lcd.HWID_0,
                pin_rst = 36,
                direction = 1,
                w = 480,
                h = 320,
                xoffset = 0,
                yoffset = 0,
                bus_speed = 80000000,
            },
            need_buffer = false,
            screen_size = 3.5,
            font = { size = 14 },
            backlight = { pwm_ch = 0, pwm_freq = 1000 },
        },
        tp = {
            model = "tp_gt911",
            params = {
                port = 0,
                pin_rst = 0xff,
                pin_int = gpio.WAKEUP0,
                i2c_speed = i2c.SLOW,
                pwr_delay = 100,
            },
        },
    },

    features = {
        net_4g = true,
        wifi = true,
        ethernet = false,
        buzzer = false,
        speaker = false,
        mic = false,
        sd_card = true,
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
        show_4g_icon = true,
        show_wifi_icon = true,
        show_buzzer_settings = false,
        show_brightness_slider = true,
        show_ethernet_settings = false,
        show_storage_settings = true,
        show_camera_preview = false,
        show_sensor_panel = false,
    },

    storage = {
        sd_card = { spi_id = 1, pin_cs = 20, speed = 40000000 },
    },
}
