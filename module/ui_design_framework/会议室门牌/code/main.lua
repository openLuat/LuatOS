--[[
@module  main
@summary 会议室门牌 · 启动编排（硬件初始化 → 校时 → 背景 → 注册页面 → 打开门牌主页）
@version 1.1.0
@note 开机直接进入门牌主页，无开机动画、无多页轮询。
      硬件默认：Air8607(Air1603) + 官方 AirLCD_1100 10.1 寸（1024x600，JD9165BA + GT911）。
      换 Air8601 + 7 寸 HX8282：改 hardware.lua 顶部 M.profile = "air8601_7i"。
      外观：默认浅色，顶栏「浅色/深色」原地重建切换，偏好存 fskv。
      设置：门牌主页顶栏「设置」→ 会议室名称 / 离线手动校时（需管理员密码 8888）。
]]
PROJECT = "meeting_doorplate"
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
    local ok = hardware.init()              -- 上电 + 屏幕 + AirUI + 触摸
    hardware.init_density_scale()           -- 屏幕就绪后按实际分辨率再算一次
    if not ok then
        log.error("main", "硬件初始化失败")
        return
    end
    sys.wait(150)

    require("clock").init()                 -- 先定校时源：硬件 RTC / 上次手动基准
    local WP = require "wallpaper"
    WP.build()                              -- 屏幕级背景（照片 + 纱层），只建一次

    local R = require "router"
    local S = require "app_state"
    R.register("home", require "page_home")
    R.register("booking", require "page_booking")
    R.register("detail", require "page_detail")
    R.register("setup", require "page_setup")
    R.register("input", require "page_input")   -- 负责人 / 会议主题的词库键盘

    S.seed()                                -- 演示数据（接真实后端时换成拉取接口）
    R.go("home", nil, true)                 -- 首屏同步创建，不必等下一拍
    hardware.backlight_on()

    log.info("main", "会议室门牌已启动", WP.has_photo() and "照片背景" or "纯色背景")
end)

sys.run()
