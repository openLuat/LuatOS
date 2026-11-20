--[[
@module  main
@summary 净界洗车 · 自助洗车机（1024x600 / 晨曦白·夜青双主题 · 单页三段式）
@version 1.0.0
@note 与 docs/方案A_水光玻璃.html 对应：开机直接进入选方案页，
      选套餐 + 附加服务 → 扫码支付 → 洗车进度 → 完成评价/小票，全程单页无轮询。
      硬件：Air8607（Air1603）+ 官方 AirLCD_1100 10.1 寸（JD9165BA + GT911）。
]]
PROJECT = "car_wash_demo"
VERSION = "1.0.0"

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

    local P = require "page_wash"
    P.create(airui.screen)
    hardware.backlight_on()

    log.info("main", "净界洗车 · 自助洗车机已启动")
end)

sys.run()
