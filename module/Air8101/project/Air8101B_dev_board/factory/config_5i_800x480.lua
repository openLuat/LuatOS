--[[
@module  config_5i_800x480
@summary 硬件配置：EVB_Air8101 V3.0 开发板 + 5 寸 800×480 RGB 屏（AirLCD_1050 / H050IWV）+ GT911
@version 1.0
@date    2026.10.15
@usage
配置驱动设计：换屏只在 platform_loader.lua 的 CONFIGS 表里加一行静态 require，
业务与产测代码不动。
]]

return {
    name      = "EVB_Air8101B_5inch_800x480_000",
    chip      = "Air8101B",
    baseboard = "EVB_Air8101 V3.0 开发板",

    -- 上电时序：按顺序执行，delay 单位 ms
    -- 说明：LCD 复位由 drv_lcd 经 lcd.init 的 pin_rst 控制，这里只负责屏幕供电
    power_on = {
        { pin = 55, level = 1, delay = 10 },   -- LCD_EN 屏幕供电
    },

    hw = {
        -- 显示屏：RGB 接口
        lcd = {
            model     = "h050iwv",   -- 800×480 RGB，与 AirLCD_1020/核心板 demo 同一驱动
            port      = "RGB",
            w         = 800,
            h         = 480,
            direction = 0,           -- 0:0° 1:90° 2:180° 3:270°（lcd 驱动层方向）
            -- 界面旋转（用户模式）：0 / 90 / 180 / 270，由 AirUI 处理，
            -- 显示与触摸映射一起生效，页面布局代码不用改。
            -- 注意：与上面的 direction 是两回事，改这个就够了。
            -- 当前 180°：屏幕倒装（排线从上走/人站在另一侧看）。
            -- 显示设置页点过方向后会写 fskv(ui_rotation)，那个值优先于这里；
            -- 想让本行生效，先在显示设置页切到 180°（或清掉 fskv 的 ui_rotation）。
            rotation  = 180,
            xoffset   = 0,
            yoffset   = 0,
            pin_rst   = 5,           -- LCD_RST（原理图 LCD_RST/GPIO5）
            pin_pwr   = 8,           -- 背光控制脚，已真机确认（板丝印 PWM1/BL）
        },

        -- 触摸：GT911
        -- soft_i2c = true：用软件 I2C（GPIO38/39 直控），不依赖 pinmux。
        --   原因：Air8101 硬件 I2C1 默认跑在 GPIO0/1（= UART1 的脚），
        --   pins.setup 切不过来，会同时导致"扫不到触摸 + 产测串口失效"。
        tp = {
            model    = "gt911",
            soft_i2c = true,
            i2c_id   = 1, scl = 38, sda = 39,
            -- 软 I2C 半周期延时 µs（不填用内核默认 5 ≈100kHz）；
            -- 杜邦线长/干扰大导致 CRC 老不过时，调到 10~20 更稳
            i2c_delay = nil,
            rst      = 28, int = 7,
            w = 800, h = 480,
        },

        -- 外设使能脚
        cam   = { en = 29 },   -- UVC 摄像头供电
        -- speaker 功放（内置 DAC + PA）
        --   pa_en       PA 使能脚（GPIO27）
        --   pa_on_level PA 使能电平，默认 1（高使能）；板上 PA 若是低使能就改 0 再重烧
        --   dac_chl     DAC 输出通道：0=AUD_LN（库默认）/ 1=AUD_LP / 2=双通道；
        --               播放在走、就是没声音时，先试着换成 1（喇叭可能接在另一路）
        -- vol：播放默认音量（0~100）。出厂 40：功放峰值电流小，避免供电不足时掉电复位；
        --      接稳压电源后可调回 60~70（界面里也能手动加）。
        audio = { pa_en = 27, pa_on_level = 1, dac_chl = 0, vol = 40 },
        sd    = { en = 50 },
        -- SPI NAND（AirSPINAND_1000 那类模块）
        --   en   NAND_EN 供电使能
        --   cs   硬件 CS 引脚 = GPIO15（官方 AirSPINAND_1000 demo 的 CS_PIN，内核日志也是 cs 15；
        --        is_hardware_cs=1 时以硬件 CS 为准，写别的值无效）
        --   ldo  GPIO13：官方 demo 用它控制 LDO 给配件板输出 3.3V，不拉高会导致"能读 ID、擦写失败"
        nand  = { en = 48, cs = 15, ldo = 13 },
        eth   = { en = 53, cs = 34, irq = 9 },
        -- RS485：en 收发器供电使能，dir 收发方向（高=发）；
        -- baud 仅产测项 U485_TEST# 使用，用户模式的继电器页固定按模块出厂 9600 8N1 通信
        rs485 = { en = 52, dir = 37, baud = 115200 },
        g4    = { rst = 51, uart_id = 1 },

        -- I2C 温湿度传感器（AirSHT30_1000 / SHT30，接板上 I2C 排针）
        --   i2c_id = nil  工程 I2C 总线（软 I2C，GPIO38/39，与 GT911 触摸同一排针）★默认
        --   i2c_id = 0    硬件 I2C0（官方 AirSHT30_1000 demo 的接法：SDA=38/R5、SCL=45/R6）
        --   addr          从机地址，默认 0x44（模块 ADDR 接地/悬空；ADDR 接高为 0x45）
        --   interval      采集间隔 ms，与触摸共用总线，不要小于 2000
        sensor = {
            i2c_id   = nil,
            addr     = 0x44,
            interval = 5000,
        },

        -- I2C 空气质量传感器（AirVOC_1000 / AGS02MA，地址固定 0x1A）
        --   i2c_id 同 sensor：nil = 工程软 I2C 排针（默认）；0 = 硬件 I2C0
        --   interval 采集间隔 ms，默认 5000（5 秒）：AGS02MA 数据约 1.5 秒更新一次，
        --            读再快也没意义，还白占与触摸共用的总线；代码下限 1500
        --   i2c_delay 软 I2C 半周期延时 µs（0.5 个 SCL 周期）：
        --     AGS02MA 手册规定主机 I2C 时钟 ≤ 30kHz（不少资料说必须 ≤ 20kHz，
        --     100kHz/400kHz 直接不响应），比 GT911/SHT30 苛刻得多。
        --     20 µs → 约 25kHz，是这条总线上所有器件都能接受的速度。
        --     选中的配件板是空气质量时，drv_i2c 会自动用这个值（整条总线一起变慢，
        --     触摸也走同一速率，帧率会略降，属正常）。
        voc = {
            i2c_id    = nil,
            interval  = 5000,
            i2c_delay = 20,
        },
    },

    -- 产测串口：换产测指令通道只改这里
    --   1 = UART1（接 780ER2 那路，当前使用）：用插针外接 USB-TTL 串口板，
    --       必须关掉 VBAT_4G（否则 780ER2 会驱动同一对线）。
    --       注意：4G_TEST# 会临时把本串口让给 780ER2，测试期间结果看日志（UART0/CH340），
    --       测完串口自动收回、再补发回包。
    --   2 = UART2（RS485 那路）：需关掉串口拨码并外接串口板，此模式下 U485_TEST# 不可用
    factory = {
        uart_id    = 1,
        baud       = 115200,
        -- 日志是否静默：产测口走 UART1 时日志仍从 UART0/CH340 输出，两者互不干扰，
        -- 保持 false 便于调试（4G 测试的结果主要看日志）。
        log_silent = false,
    },

    -- AirCloud 数据上报（aircloud_app.lua）
    --   enabled 且 auth_key 非空时，用户模式联网后自动连接并周期上报；
    --   auth_key 在 iot.openluat.com → AirCloud 项目获取（也可在 main.lua 设 _G.PROJECT_KEY）
    aircloud = {
        enabled      = true,
        auth_key     = "",
        report_cycle = 180,      -- 上报周期（秒）
        heartbeat    = 60,       -- 心跳（秒），平台离线窗口通常 60~180 秒
    },

    -- 多 WiFi 定位（airlbs_app.lua）：扫描周围 WiFi 上传合宙 LBS 平台
    --   project_id / project_key 在 iot.openluat.com/lbs 我的项目里拿（收费服务）
    --   interval 按套餐频次设置，太频繁会返回 qps 超限
    airlbs = {
        enabled      = true,
        project_id   = "sBvM02", -- 6 位项目 ID
        project_key  = "YRCzZaYgtrpGXuS3FMsvt9ZblPoFcrbS",
        interval     = 60,       -- 定位间隔（秒），代码下限 60
        scan_timeout = 10,       -- WiFi 扫描超时（秒）
    },

    -- FOTA 远程升级（fota_app.lua / libfota3，无界面后台升级）
    --   project_key 在 iot.openluat.com → 产品/项目（Turnkey）页面获取；
    --               留空 = 不参与远程升级（日志只打一条 warn，不联网）
    --   script_name 留空取 _G.PROJECT（main.lua），必须和平台上建的脚本名一致
    --   auto/interval 出厂默认每天自动检测一次；发现新版本直接下载 + 重启刷写
    --   fskv 可单项覆盖：fota_key / fota_auto("1"/"0") / fota_interval
    fota = {
        project_key = "dxIkiBi8DQwCFCQWPZAs6H3FQwaV3DiO",  -- 合宙 IOT 平台 Turnkey 密钥
        script_name = nil,       -- nil = 用 _G.PROJECT
        auto        = true,
        interval    = 86400,     -- 自动检测间隔（秒）
    },

    -- 产测项开关：true 表示该板型出厂时必须测这一项
    features = {
        lcd = true, tp = true, cam = true, audio = true,
        sd = true, nand = true, eth = true, rs485 = true,
        i2c_scan = true, wifi = true, g4 = true,
    },
}
