--[[
@module  config.evb_1601_5i_v11
@summary EVB_Air1601_V1.1 5寸 800×480 RGB，底层用 display 库
@version 1.0
@date    2026.09.14
@usage
时序/引脚与 demo_800_480 lcd_drv 一致：GPIO2 背光、GPIO15 复位、GT911 I2C1。
]]
return {
    name = "EVB_Air1601_5inch_800x480_000_V011",
    chip = "Air1601",
    baseboard = "EVB_Air1601_V1.1 5寸 800×480 (display)",

    pins = {},

    power_on = {},

    hw = {
        lcd = {
            model = "lcd_display_rgb",
            params = {
                interface = "rgb",
                pin_rst = 15,
                pin_bl = 2,
                pin_pwr = 2,
                w = 800,
                h = 480,
                hbp = 140,
                hspw = 20,
                hfp = 160,
                vbp = 20,
                vspw = 3,
                vfp = 12,
                bus_speed = 50 * 1000 * 1000,
            },
            need_buffer = true,
            screen_size = 5.0,
            font = { size = 20 },
            backlight = {
                gpio_bl = 2,
            },
        },
        tp = {
            model = "tp_gt911",
            params = {
                port = 1,
                pin_rst = 3,
                pin_int = 51,
                int_type = tp.FALLING,
                w = 800,
                h = 480,
                gpio_reset = 3, -- 与 7/10 寸 EVB 及可用 button demo 相同：先拉低 RST 再交给 tp.init
            },
        },
    },

    features = {
        wifi = true,
        net_4g = true,
        ethernet = false, -- 未配 CH390 SPI 时 net_manager 会用空 spi 崩掉 Lua
        sd_card = true,
    },

    ui = {
        show_wifi_icon = true,
        show_4g_icon = true,
        show_storage_settings = true,
    },
}
