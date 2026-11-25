-- AIR8607C1_V0_20261112_1500.pdf，第 1～4 页。GPIO 使用 CCM4211 的 Lua 编号。
return {
    name = "Air8607C1",
    chip = "Air1101",
    baseboard = "Air8607C1",
    -- 引脚功能复用：Air1603 上背光 PWM3 与触摸 I2C1 无需显式复用（与 Air8603 一致留空）
    pins = {},
    -- GPIO 上电时序（结构同 Air8603 power_on，内容为 C1 板级 init_outputs 的等效动作）：
    --   GPIO73 BUZ1/AUDIOPA_EN 低电平关断 → GPIO72 Air6205 电源拉高（W 系列底板）→ GPIO65 USB VBUS 默认关
    -- 背光 PWM3 由 platform_loader 在序列开始前统一压灭（占空比 0），boot_ui 首帧后再点亮。
    power_on = {
        { pin = 73, dir = 0, level = 0 },
        { pin = 72, dir = 0, level = 1, delay = 50 },
        { pin = 65, dir = 0, level = 0 },
    },
    default_expansion_model = "Air8607W1",
    -- AIR8607W1_V0 第 2 页的装配表。SD/TF、UVC 和隔离 RS485 为共用测试。
    -- dac = 该底板另有 J102 喇叭通路，可与本机蜂鸣器并存（audio 仍为其主音频器件）
    expansion_models = {
        {name = "Air8607W1", wifi = true,  uart2 = "ttl",   audio = "buzzer", dac = true},
        {name = "Air8607W2", wifi = true,  uart2 = "rs232", audio = "buzzer"},
        {name = "Air8607W3", wifi = true,  uart2 = "rs232", audio = "dac"},
        {name = "Air8607W4", wifi = true,  uart2 = "rs232", audio = "dac"},
        {name = "Air8607S1", wifi = false, uart2 = "ttl",   audio = "buzzer"},
        {name = "Air8607S2", wifi = false, uart2 = "rs232", audio = "buzzer"},
    },
    -- Air8603 桌面/设置/应用市场/网盘/文件传输等非测试功能所需的统一网络配置。
    -- 这里仍用 C1 的 SPI5 + Air6205；wifi_airlink_spi 由 net_manager 初始化。
    network = {
        { type = "wifi_airlink_spi", spi_id = 5, cs_pin = 56, rdy_pin = 12,
          speed = 4000000 },
    },
    features = {
        wifi = true,
        sd_card = true,
        other_func = true,       -- 保留 C1 原功能测试，由 air8607c1_test_win 接管
        ai_chat = true,
        cloud_disk = true,
        file_transfer = true,
        iot = true,
        -- Air8607C1 还没有在合宙云平台分配到机型密钥（main.lua 的 PROJECT_KEY），
        -- 打开会每次都报「缺少 project_key / auth_key 无效」。拿到密钥后把这两项
        -- 与下面 ui.show_fota/show_aircloud 一起改成 true。
        fota = false,
        aircloud = false,
        buzzer = false,
        nand_flash = false,
        usb_hid = false,
        net_4g = false,
        ethernet = false,
        battery = false,
        wdt = false,
        app_factory = true,
    },
    ui = {
        show_wifi_icon = true,
        show_brightness_slider = true,
        show_storage_settings = true,
        show_other_func = true,
        show_ai_chat = true,
        show_cloud_disk = true,
        show_file_transfer = true,
        show_iot = true,
        show_fota = false,       -- 与 features.fota 同步（缺 PROJECT_KEY）
        show_aircloud = false,   -- 与 features.aircloud 同步（缺 PROJECT_KEY）
        show_autostart = true,
        show_app_factory = true,     -- 桌面/Dock 显示「应用工厂」入口
        show_buzzer_settings = false,
        show_ethernet_settings = false,
        show_battery_icon = false,
        show_video_area = false,
    },
    -- 外部存储：SD/TF 走 SPI1，和 C1 功能测试同一组引脚。
    storage = {
        sd_card = { spi_id = 1, pin_cs = 8, pin_power = 22, speed = 10000000 },
    },
    -- 外设清单给「设置 → 外设模式」和 Air8603 业务层判断能力用；
    -- C1 自己的功能测试仍然走 air8607w1_factory，不依赖这里。
    peripherals = {
        { type = "uvc", id = "uvc1", name = "UVC摄像头", title = "摄像头",
          w = 480, h = 320, rotation = 0 },
    },
    hw = {
        -- 50 针 FPC；RGB 时序与 GT911 型号沿用 Air8606 工装屏。
        lcd = {
            model = "lcd_display_rgb", screen_size = 10,
            params = {interface = "rgb", pin_rst = 15, w = 1024, h = 600,
                hbp = 140, hspw = 20, hfp = 160, vbp = 20, vspw = 3, vfp = 12,
                pclk_hz = 50000000},
            font = {size = 20},
            backlight = {pwm_ch = 3, pwm_freq = 1000, level = 70},
        },
        tp = {
            model = "tp_gt911",
            params = {port = 1, pin_rst = 14, pin_int = 51, w = 1024, h = 600,
                int_type = tp and tp.FALLING, i2c_speed = i2c and i2c.SLOW},
        },
        -- W3/W4 为内置 DAC + PA；W1/W2 是蜂鸣器，C1 功能测试仍按底板型号自行处理。
        audio = {
            model = "dac",
            pa_ctrl = 73,
            pa_on_level = 1,
            dac_delay = 6,
            pa_delay = 10,
            play_vol = 9,
        },
    },
    buzzer = {pin = 73, hz = 2700, duration_ms = 100},
    pwm_test = {channel = 1, pin = 65, connector = "J100-25", hz = 1000, duty = 50, duration_ms = 2000},
    -- 根文件系统在外置启动 Flash 的 SPI6 映射区。
    flash_test = {mount_point = "/", size = 8192},
    -- Air8607W1 第 2～7 页的共用接线。电源及功放使能均为高有效。
    w1 = {
        wifi = {spi = 5, cs = 56, rdy = 12, power = 72, hz = 4000000,
            url = "https://httpbin.luatos.com/bytes/2048"},
        sd = {spi = 1, cs = 8, clk = 9, miso = 10, mosi = 11,
            power = 22, hz = 10000000, mount_point = "/sd", size = 8192},
        serial = {power = 23, baud = 9600, ttl = {id = 2},
            rs232 = {id = 2}, rs485 = {id = 1, de = 74}},
        uvc = {model = "AirCAMERA_1034", bus = 0, w = 480, h = 320},
        dac = {pa = 73, volume = 50, text = "音频播放测试"},
        wifi_dl = {connector = "J21", pin1 = "VBAT_5V", pin2 = "GND",
            pin3 = "W_DBG_RX", pin4 = "W_DBG_TX", pin5 = "WIFI_RESET"},
        vrtc = {key = "air8607c1_vrtc_base", off_seconds = 15},
    },
}