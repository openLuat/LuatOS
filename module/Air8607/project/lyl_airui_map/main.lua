--[[
@module  main
@summary Air8607 真机 airui.map 测试：离线瓦片地图 + 启动自检
@version 001.000.000
@date    2026.10.28
@usage
屏和上电顺序对齐 projects/airui_button，瓦片行为对齐
LuatOS bsp/pc/test/157.airui_map 的交互演示。
顺序不能颠倒：
1、PWM3 背光先压灭，SD_EN 拉高，功放关断
2、display.init + airui.init（不要再调 display.on）
3、等 100ms 后初始化 GT911 并绑定 AirUI，顺序与 airui_button 相同
4、挂载 TF 卡。瓦片在 /sd/tiles/{z}/{x}/{y}.jpg，z14 到 z17
5、创建地图。界面出来后自动跑一轮自检，日志里找 MAP_TEST_PASS
6、最后把 PWM3 背光拉到 100%

中心点是开封市区 114.312376,34.801142（WGS84）。输入当 WGS84，卡上的高德瓦片是 GCJ02。
固件需要带 airui.map。没有该组件时只显示提示，不会创建地图。
]]

PROJECT = "AIRUI_MAP"
VERSION = "001.000.000"

log.info("main", PROJECT, VERSION)

local lcd_drv = require "lcd_drv"
local tp_drv = require "tp_drv"
local sd_mount = require "sd_mount"

local function power_on()
    if rtos.bsp() == "PC" then
        return
    end
    -- 背光 PWM3（PIN55 = GPIO13）默认高电平会在帧缓冲就绪前把残影点亮
    pcall(pwm.setup, 3, 1000, 0)
    pcall(pwm.start, 3)
    local steps = {
        { pin = 74, level = 1 }, -- SD_EN 拉高，SD 卡供电
        { pin = 73, level = 0 }, -- AUDIOPA_EN 拉低，HT6873 功放关断
    }
    for _, s in ipairs(steps) do
        gpio.setup(s.pin, s.level)
        gpio.set(s.pin, s.level)
    end
    log.info("main", "GPIO 上电完成")
end

local function show_message(text)
    local w = _G.screen_w or 1024
    local h = _G.screen_h or 600
    airui.label({
        x = 40, y = math.floor(h / 2) - 40,
        w = w - 80, h = 80,
        text = text,
        font_size = 28,
        color = 0xB42318,
        align = airui.TEXT_ALIGN_CENTER,
    })
end

sys.taskInit(function()
    power_on()

    if not lcd_drv.init() then
        log.error("main", "屏幕初始化失败")
        return
    end

    -- 先显示、后触摸，和 airui_button 一样。中间不插 SD 挂载，
    -- 否则 RGB 初始化会拆掉触摸中断。
    sys.wait(100)
    if not tp_drv.init() then
        log.warn("main", "触摸不可用，地图无法拖动")
    end

    local sd_ok, sd_err = sd_mount.mount()
    if not sd_ok then
        log.error("main", "SD 挂载失败", sd_err)
    end

    if type(airui.map) ~= "function" then
        show_message("当前固件没有 airui.map")
        lcd_drv.backlight_on()
        log.error("map.test", "MAP_TEST_FAIL", "airui.map 不存在")
        return
    end

    if not sd_ok then
        show_message("SD 卡挂载失败，无法读取 /sd/tiles")
        lcd_drv.backlight_on()
        log.error("map.test", "MAP_TEST_FAIL", sd_err)
        return
    end

    local demo = require "map_demo"
    local ok_ui, ui = pcall(demo.run)
    lcd_drv.backlight_on()
    if not ok_ui then
        show_message("地图创建失败")
        log.error("map.test", "MAP_TEST_FAIL", ui)
        return
    end

    local check = require "map_check"
    local ok, err = xpcall(function()
        check.run(ui)
    end, debug.traceback)
    if ok then
        ui.set_note("自检通过，可以拖动、缩放、打开定位")
        log.info("main", "MAP_TEST_PASS")
    else
        local first = tostring(err):match("([^\n]+)") or tostring(err)
        ui.set_note("自检失败 " .. first)
        log.error("map.test", "MAP_TEST_FAIL", err)
    end
    ui.start()
end)

sys.run()
