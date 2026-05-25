--[[
@module  config.eng_1602_5i_v2
@summary Air1602引擎主机 5寸720x1280 RGB屏(NV3052C) 配置文件
@version 1.1
@date    2026.05.22
@author  江访
]]
return {
    name = "Engine_Air1602_5inch_720x1280_002_V000",
    chip = "Air1602",
    baseboard = "合宙引擎AIR1602 V002",
    -- 引脚配置（示例，实际根据设计文档填写）
    pins = {},

    -- GPIO 供电上电时序（Air1602 airlink WiFi 模组: GPIO55 拉低→延时→拉高）
    power_on = {
        { pin = 55, dir = 0, level = 0, delay = 50 },
        { pin = 55, dir = 0, level = 1, delay = 120 },
    },

    -- 硬件配置（LCD 和 TP 驱动及参数）
    hw = {
        lcd = {
            model = "lcd_nv3052c_5in",
            params = {
                port = lcd.RGB,
                pin_clk = 23,
                pin_sda = 22,
                pin_cs = 2,
                pin_rst = 15,
                direction = 0,
                w = 720,
                h = 1280,
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
    -- 功能特性选项（影响系统服务和 UI 显示，非硬件能力限制）
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
    -- UI 显示选项
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
