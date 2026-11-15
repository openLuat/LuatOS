--[[
@module  main
@summary 玻璃之家 · 全屋智能中控（玻璃拟态双主题 · 单页 Demo）
@version 1.1.0
@note 与 docs/方案D_玻璃拟态.html 同一套视觉令牌，开机直接进入，无多页轮询。
      硬件默认：Air8607(Air1603) + 官方 AirLCD_1100 10.1寸（1024x600，JD9165BA + GT911）。
      换 Air8601 + 7寸 HX8282：改 hardware.lua 顶部 M.profile = "air8601_7i"。
      主题：默认深色，顶栏「主题」按钮切换浅色/深色（fskv 记忆，重启生效）。
]]
PROJECT = "home_control_demo"
VERSION = "1.1.0"

log.info("main", PROJECT, VERSION)

local hardware = require "hardware"

-- 官方顺序：界面模块加载前先确定密度缩放
hardware.init_density_scale()

if wdt then
    wdt.init(60000)
    sys.timerLoopStart(wdt.feed, 3000)
end

sys.taskInit(function()
    local ok = hardware.init()          -- 上电 + 屏幕 + AirUI + 触摸
    hardware.init_density_scale()       -- 屏幕就绪后按实际分辨率再算一次
    if not ok then
        log.error("main", "硬件初始化失败")
        return
    end
    sys.wait(150)

    local P = require "page_glass"
    P.create(airui.screen)
    hardware.backlight_on()

    log.info("main", "玻璃之家 · 全屋中控已启动")
end)

sys.run()
