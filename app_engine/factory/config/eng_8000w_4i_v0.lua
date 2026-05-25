--[[
@module  config.eng_8000w_4i_v0
@summary 合宙引擎主机 Air8000W 4寸SPI屏 配置文件
@version 1.1
@date    2026.05.22
@author  江访
]]
return {
    name = "Engine_Air8000W_4inch_320x480_000_V000",
    chip = "Air8000W",
    baseboard = "合宙引擎主机8000W_V000",
    -- 引脚配置（示例，实际根据设计文档填写）
    pins = {
        { pin = 31, func = "PWM0" },
        { pin = 35, func = "PWM4" },
    },

    hw = {
        lcd = {
            model = "lcd_st7796",
            params = {
                port = lcd.HWID_0,
                pin_rst = 36,
                pin_pwr = 28,
                direction = 0,
                w = 320,
                h = 480,
            },
            need_buffer = false,
            screen_size = 4.0,
            font = { size = 14 },
            backlight = { pwm_ch = 0, pwm_freq = 1000 },
        },
        tp = {
            model = "tp_gt911",
            params = {
                port = 0,
                pin_rst = 26,
                pin_int = gpio.WAKEUP0,
                i2c_speed = i2c.SLOW,
            },
        },
    },

    features = {
        net_4g = true,
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
        show_4g_icon = true,
        show_wifi_icon = true,
        show_buzzer_settings = true,
        show_brightness_slider = true,
        show_ethernet_settings = false,
        show_storage_settings = true,
        show_camera_preview = false,
        show_sensor_panel = false,
    },
}
