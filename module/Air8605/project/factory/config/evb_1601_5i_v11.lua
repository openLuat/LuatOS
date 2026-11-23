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
                -- GPIO2 供电/背光一体（同脚）：无 ic_init，整体延后到 backlight_on
                -- 一起开电+背光（首帧已入帧缓冲，无残影），策略见 lcd_display_rgb
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
        app_factory = true,  -- 启用"应用工厂"（录音 → 生成 → 安装，需联网）
        ai_chat = true,      -- 启用"AI 助手"（WebSocket 会话 + STT/TTS，需联网）
        cloud_disk = true,   -- 启用"合宙网盘"（IoT 登录 → 云端文件，需联网）
        other_func = true,   -- 启用"功能测试"（peripherals 外设清单）
        iot = true,          -- 启用 IoT 账号登录（合宙平台，需联网）
        fota = true,         -- 启用固件在线升级（需联网）
    },

    ui = {
        show_wifi_icon = true,
        show_4g_icon = true,
        show_storage_settings = true,
        show_app_factory = true,  -- 桌面显示"应用工厂"图标
        show_ai_chat = true,      -- 桌面显示"AI 助手"图标
        show_cloud_disk = true,   -- 桌面显示"合宙网盘"图标
        show_other_func = true,   -- 桌面显示"功能测试"图标
        show_iot = true,          -- 设置页显示"IOT账号"
        show_fota = true,         -- 设置页显示"系统更新"
        show_autostart = true,    -- 设置页显示"后装APP自启"
    },

    -- ===== 存储设备: SD/TF 卡（SPI1, CS=GPIO8）=====
    -- 接线取同底板 EVB_Air1601 的另三份配置（7i_v11 / 7i_v12 / 10i_v11 均为 spi_id=1、pin_cs=8），
    -- SD 插槽在底板上、与屏无关；上板请核对一次 SPI1 与 CS=GPIO8。
    storage = {
        sd_card = {
            spi_id = 1,                  -- SPI 接口 ID
            pin_cs = 8,                  -- 片选 CS 引脚 GPIO8
            speed = 40000000,            -- SPI 时钟频率 Hz（高速卡推荐 20MHz+）
        },
    },
}
