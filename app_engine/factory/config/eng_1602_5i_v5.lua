--[[
@module  config.eng_1602_5i_v5
@summary Air1602引擎主机 5寸480x854 RGB屏(ST7701S) + NAND Flash + WiFi(airlink低电平)
@version 1.0
@date    2026.05.26
@author  江访
]]
return {
    name = "Engine_Air1602_5inch_480x854_005_V000",
    chip = "Air1602",
    baseboard = "合宙引擎AIR1602 V005",
    pins = {},

    -- GPIO 供电上电时序（Air1602 airlink WiFi 模组: GPIO55 保持低电平）
    power_on = {
        { pin = 55, dir = 0, level = 0, delay = 50 },
    },

    -- 硬件配置（LCD 和 TP 驱动及参数）
    hw = {
        lcd = {
            model = "lcd_st7701s_5in",
            params = {
                port = lcd.RGB,
                pin_clk = 23,
                pin_sda = 2,
                pin_cs = 22,
                pin_rst = 15,
                direction = 0,
                w = 480,
                h = 854,
                bus_speed = 30 * 1000 * 1000,
            },
            need_buffer = true,
            screen_size = 5.0,
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
                gpio_reset = 3,
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
        nand_flash = true,
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
    storage = {
        nand_flash = { spi_id = 2, pin_cs = 4, speed = 40000000, pin_pwr = 50 },
    },
}
