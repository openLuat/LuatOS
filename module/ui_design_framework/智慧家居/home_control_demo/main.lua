--[[
@module  main
@summary 全屋智能中控 · 多页面轮询启动编排（Air8607 + 10.1寸 1024x600）
@version 3.0.0
@note 页面：page_clock(息屏待机) / page_glass(方案D玻璃拟态) / page_ring(方案A环形中枢) / page_bento(方案B磁贴) / page_dock(方案C Dock)。
      运行期切换接口：ui_page.show(id)、ui_page.next()、ui_page.start_rotation(ms)、ui_page.set_interval(ms)。
]]
PROJECT = "home_control_demo"
VERSION = "3.0.0"

log.info("main", PROJECT, VERSION)

local hardware = require "hardware"

-- 官方顺序：界面模块加载前先确定密度缩放
hardware.init_density_scale()

if wdt then
    wdt.init(60000)
    sys.timerLoopStart(wdt.feed, 3000)
end

sys.taskInit(function()
    hardware.init()
    hardware.init_density_scale()          -- 屏幕就绪后按实际分辨率再算一次
    sys.wait(150)

    local P = require "ui_page"
    P.register("clock", "息屏·待机",       require "page_clock")
    P.register("glass", "方案D·玻璃拟态", require "page_glass")
    P.register("ring",  "方案A·环形中枢", require "page_ring")
    P.register("bento", "方案B·Bento磁贴", require "page_bento")
    P.register("dock",  "方案C·底部Dock", require "page_dock")

    P.build()
    P.show("clock")                        -- 起始页：息屏时钟
    P.start_rotation(5000)                 -- 默认 5 秒轮询所有页面

    log.info("main", "初始化完成，共", #P.list(), "页，5 秒轮询")
end)

sys.run()
