--[[
@module  config.evb_8101b_5i_v1
@summary Air8101核心板 5寸480x854 RGB屏(ST7701S) 配置文件
@version 1.1
@date    2026.05.22
@author  江访
]]
return {
    name = "EVB_Air8101B_5inch_480x854_000_V010",
    chip = "Air8101",
    baseboard = "合宙引擎 8101B V002",
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
            model = "lcd_st7701s_5in",
            params = {
                port = lcd.RGB, pin_clk = 2, pin_sda = 4, pin_cs = 3,
                pin_rst = 9, direction = 0, w = 480, h = 854,
            },
            need_buffer = true,
            rotation = 180,
            screen_size = 5.0,
            font = { size = 20, path = "/MiSans_gb2312.ttf", global = true },
            backlight = { pwm_ch = 1, pwm_freq = 10000 },
        },
        tp = {
            model = "tp_gt911",
            params = {
                port = 1, pin_rst = 28, pin_int = 7,
                int_type = tp.FALLING, i2c_speed = i2c.SLOW,
            },
        },
    },
    features = {
        net_4g = false, wifi = true, ethernet = false, buzzer = false,
        speaker = false, mic = false, sd_card = false, nand_flash = false,
        gnss = false, bluetooth = false, can = false, rs485 = false,
        usb_camera = false, spi_camera = false, i2c_sensor = false,
    },
    ui = {
        show_4g_icon = false, show_wifi_icon = true,
        show_buzzer_settings = false, show_brightness_slider = true,
        show_ethernet_settings = false, show_storage_settings = true,
        show_camera_preview = false, show_sensor_panel = false,
    },
}
