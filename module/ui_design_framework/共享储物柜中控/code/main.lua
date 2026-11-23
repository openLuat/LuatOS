--[[
@module  main
@summary 共享储物柜中控 · 真机入口
@version 1.0.0
@note 与 docs/共享储物柜中控UI.html 同一套视觉令牌（暖橙取件 / 青绿存件 + 米白底）。
      硬件默认：Air8607(Air1603) + 官方 AirLCD_1100 10.1 寸（1024×600，JD9165BA + GT911）。
      换 Air8601 + 7 寸 HX8282：改 hardware.lua 顶部 M.profile = "air8601_7i"。
      启动流程：硬件就绪 → 按实际分辨率算密度缩放 → 建首页 → 开背光。
]]
PROJECT = "locker_hmi"
VERSION = "1.0.0"

log.info("main", PROJECT, VERSION)

local hardware = require "hardware"
local T = require "ui_theme"

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

    -- hzfont 只按已加载档位出字：界面用到的字号必须一次载齐，漏载会回退到主题点阵字库（中文变方框）。
    -- cache_size / antialias 必须与 hardware.lua 里的首档一致，否则会打 "already configured" 告警。
    for _, sz in ipairs(T.f.sizes) do
        airui.font_load({ type = "hzfont", size = sz, cache_size = 2048, antialias = 1 })
    end

    local P = require "page_locker"
    P.start()
    hardware.backlight_on()

    log.info("main", "共享储物柜中控已启动")
end)

sys.run()
