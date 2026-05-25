--[[
@module  config.pc_default
@summary PC模拟器默认配置文件（当 PROJECT 无对应配置时回退）
@version 1.1
@date    2026.05.22
@author  江访
]]
return {
    name = "PC",
    chip = "PC",
    baseboard = "PC",

    pins = {},

    hw = {
        lcd = {
            model = "lcd_st7796",
            params = {
                port = lcd.HWID_0,
                pin_rst = 36,
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
            },
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
        show_buzzer_settings = false,
        show_brightness_slider = true,
        show_ethernet_settings = false,
        show_storage_settings = true,
        show_camera_preview = false,
        show_sensor_panel = false,
    },
}
