--[[
@module  config.evb_8101_10i_v1
@summary Air8101核心板 10.1寸1024x600 RGB屏(HX8282) 配置文件
@version 1.1
@date    2026.05.22
@author  江访
]]
return {
    name = "EVB_Air8101_10inch1_1024x600_000_V010",
    chip = "Air8101",
    baseboard = "Air8101核心板V1.0",
    -- 引脚配置（示例，实际根据设计文档填写）
    pins = {
        { pin = 11, func = "I2C1_SDA" },
        { pin = 12, func = "I2C1_SCL" },
        { pin = 14, func = "PWM1" },
        { pin = 72, func = "SPI0_CLK" },
        { pin = 71, func = "SPI0_MOSI" },
        { pin = 6,  func = "SPI0_MISO" },
    },

    hw = {
        lcd = {
            model = "lcd_hx8282_10in",
            params = {
                port = lcd.RGB,
                pin_rst = 38,
                pin_pwr = 29,
                direction = 0,
                w = 1024,
                h = 600,
            },
            need_buffer = true,
            screen_size = 10.0,
            font = { size = 20, path = "/MiSans_gb2312.ttf", global = true },
            backlight = { pwm_ch = 1, pwm_freq = 10000 },
        },
        tp = {
            model = "tp_gt911",
            params = {
                port = 1,
                pin_rst = 28,
                pin_int = 7,
                int_type = tp.FALLING,
                i2c_speed = i2c.SLOW,
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
        show_4g_icon = false,
        show_wifi_icon = true,
        show_buzzer_settings = false,
        show_brightness_slider = true,
        show_ethernet_settings = false,
        show_storage_settings = true,
        show_camera_preview = false,
        show_sensor_panel = false,
    },
    -- 存储设备配置（如 NAND Flash）
    storage = {
        sd_card = { spi_id = 0, pin_cs = 32, speed = 40000000},
    },
}
