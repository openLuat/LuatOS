--[[
@module  lcd_drv
@summary LCD 显示驱动（ST7796，320×480 竖屏）+ AirUI 初始化
@version 1.1
@date    2026.10.20
@usage
初始化 AirLCD_1000 显示 IC ST7796，竖屏 320×480，随后初始化 AirUI 并加载中文字体。
通过 HARDWARE_ENV 全局变量适配硬件环境（本工程固定 DEV_BOARD_780_V1.4）。

对外接口：
  lcd_drv.init() —— require 即执行，完成 lcd.init + airui.init + 字体加载
  成功后置 _G.airui_ready = true，ui_main 以此判断 UI 是否可以启动
]]

--[[
HARDWARE_ENV 参数说明：
  "CORE_BOARD":           核心板直连，不需要 GPIO 供电，背光 GPIO1 控制
  "DEV_BOARD_V1.2":       V1.2 开发板，GPIO28 控制 LCD 电源，无背光控制
  "DEV_BOARD_V1.3":       V1.3 开发板，GPIO29 控制 LCD 电源，GPIO30 控制背光
  "DEV_BOARD_780_V1.4":   V1.4 开发板，与 V1.3 相同（GPIO29 电源 + GPIO30 背光）
]]

local function lcd_drv_init()
    -- 固件未包含 lcd 核心库时直接退出，避免访问 nil 导致 VM 崩溃重启
    if not lcd then
        log.error("lcd", string.format("当前固件无 lcd 库, bsp=%s version=%s airui=%s",
            tostring(rtos.bsp()), tostring(rtos.version()), tostring(airui ~= nil)))
        return
    end

    local pin_pwr = nil  -- 默认不通过 lcd 库控制背光

    if HARDWARE_ENV == "DEV_BOARD_V1.2" then
        gpio.setup(28, 1) -- GPIO28 打开 LCD 电源供电，无需控制背光
    elseif HARDWARE_ENV == "DEV_BOARD_V1.3" or HARDWARE_ENV == "DEV_BOARD_780_V1.4" then
        gpio.setup(29, 1) -- GPIO29 打开 LCD 电源供电
        gpio.set(29, 1)
        gpio.setup(30, 0) -- GPIO30 拉低开启背光（拉高灭屏，拉低亮屏）
        gpio.set(30, 0)
    else
        pin_pwr = 1       -- 核心板使用 GPIO1 控制背光
    end

    local result = lcd.init("st7796",
        {
            pin_rst = 36,           -- 复位引脚
            pin_pwr = pin_pwr,      -- 背光控制引脚（V1.2 为 nil）
            port = lcd.HWID_0,      -- lcd 专用 SPI 接口
            direction = 0,          -- 0°（竖屏）
            w = 320,                -- 水平分辨率
            h = 480,                -- 竖直分辨率
            xoffset = 0,
            yoffset = 0,
            bus_speed = 80000000,
        })

    log.info("lcd.init", result)
    if not result then
        log.error("lcd.init", "init failed")
        return
    end

    if not airui then
        log.error("airui", "当前固件不支持 airui，UI 无法显示")
        return
    end

    -- AirUI 初始化：内部自行管理显示缓冲，不要再调用 lcd.setupBuff()
    local width, height = lcd.getSize()
    if not airui.init(width, height) then
        log.error("airui", "init failed")
        return
    end
    _G.airui_ready = true

    -- 加载中文字体：仅内置 hzfont 的固件可加载（支持12~255号中文）
    -- 本固件若未内置 hzfont，pcall 会失败，此时沿用主题字体（16号点阵），中文仍可正常显示
    local call_ok, err = pcall(airui.font_load, {
        type = "hzfont",   -- 字体类型，可选 "hzfont" 或 "bin"
        path = nil,        -- 字体路径，对于 "hzfont"，传 nil 则使用内置字库
        size = 20,         -- 字体大小，默认 16
        cache_size = 1048, -- 缓存字数大小，默认 2048
        antialias = 1,     -- 抗锯齿等级1-3，默认 1
    })
    if not call_ok then
        log.warn("airui", "hzfont 未加载，使用内置16号点阵字体", tostring(err))
    end

    log.info("airui", "version -> " .. airui.version())
end

lcd_drv_init()
