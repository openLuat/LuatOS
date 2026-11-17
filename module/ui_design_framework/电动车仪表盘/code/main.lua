--[[
@module  main
@summary 电动车仪表盘 · 启动编排（Air8607 + 10.1寸 1024x600 RGB 触摸屏）
@version 2.0.0
@date    2026.11.17
@board   Air8607 + 1024x600 RGB 屏（10.1 寸）+ GT911 电容触摸

=== 分层（源码分 app/drv/ui 子目录；设备端 LuatOS 会把脚本平铺，require 只写文件名）===
   目录只为人看：`require "app_state"` 里的模块名不带路径和点号。
   约束：main.lua 必须在根目录、全工程文件名唯一（平铺后同名会互相覆盖）。
  驱动层  drv_lcd 屏时序 / drv_power 供电背光亮度 / drv_tp GT911 触摸绑定
  应用层  app_config 配置+调色板 / app_state 状态+fskv / app_sim 数据仿真 / app_util 纯函数
  UI 层   ui_theme 主题与换算 / ui_icon 图标图元 / ui_widget 安全原语（唯一控件入口）
          ui_dial 车速表盘 / ui_indicators 指示灯卡片 / ui_cards 侧栏卡片
          ui_topbar 顶栏 / ui_bottom 底部数据带 / ui 总入口
  入口    main        只做启动顺序编排，不含业务逻辑

=== 启动顺序（有依赖，勿调整）===
1) power_on       供电 / 背光 PWM 归零
2) drv_lcd.setup  RGB 时序 + 帧缓冲
3) airui.init     分辨率
4) font_load      界面用到的 5 档字号一次载齐（漏载会渲染成方框）
5) drv_tp.init    GT911 触摸 + 绑定 airui（container on_click 生效）
6) app_state.init fskv 恢复主题 / 驾驶模式
7) ui.build       搭界面（顶栏/表盘/指示灯/卡片/数据带）
8) backlight_on   首帧余量后点亮背光
9) 主循环         33ms 节拍：仿真推进 → 各组件按自己的节奏刷新
]]
PROJECT = "ev_dashboard"
VERSION = "2.0.0"

local cfg   = require "app_config"
local state = require "app_state"
local sim   = require "app_sim"
local lcd   = require "drv_lcd"
local power = require "drv_power"
local tp    = require "drv_tp"
local ui    = require "ui"

local S = cfg.HW.screen
local SCREEN_W, SCREEN_H = S.panel_w, S.panel_h
local FRAME_MS = cfg.ANIM.frame_ms

-- 界面用到的字号（与 app_config.SIZES 一致），去重后逐档加载
local FONT_SIZES = {}
do
  local seen = {}
  for _, v in pairs(cfg.SIZES) do
    if not seen[v] then
      seen[v] = true
      FONT_SIZES[#FONT_SIZES + 1] = v
    end
  end
  table.sort(FONT_SIZES)
end

sys.taskInit(function()
    local is_pc = (rtos.bsp() == "PC")

    -- 1、供电 / 背光 PWM 先归零（黑屏，UI 搭好后再点亮）
    if not is_pc then power.power_on() end

    -- 2、显示初始化（面板实际分辨率 + 原生时序）
    local ok, backend = lcd.setup({
        pin_rst = S.pin_rst,
        w = S.panel_w, h = S.panel_h,
        hbp = S.hbp, hspw = S.hspw, hfp = S.hfp,
        vbp = S.vbp, vspw = S.vspw, vfp = S.vfp,
        bus_speed = S.bus_speed,
    })
    if not ok then
        log.error("main", "显示初始化失败", backend)
        return
    end
    log.info("main", "显示初始化完成", backend, SCREEN_W, SCREEN_H)

    -- 3、AirUI 初始化
    airui.init(SCREEN_W, SCREEN_H)
    airui.set_rotation(0)

    -- 4、字号一次载齐（hzfont 只按已加载字号出字，缺档会渲染成方框）
    -- cache_size 是「每个字号最多缓存多少个字形位图」，不是越大越好：
    -- 64 号一个字形约 16KB，2048 就是 32MB/档 × 5 档，远超可用堆；缓存被填满后
    -- 照样 LRU 淘汰、重新栅格化，白白把 LVGL 堆挤到边缘 → 分配变慢、碎片变多。
    -- 本界面固定文案约 60 个汉字 + 数字 + 少量英文，256 已够覆盖且不会反复淘汰。
    for _, sz in ipairs(FONT_SIZES) do
        airui.font_load({ type = "hzfont", size = sz, cache_size = 256, antialias = 1 })
    end

    -- 5、触摸：GT911 初始化并绑定 airui（container on_click 生效）
    if not is_pc then
        if not tp.init() then
            log.warn("main", "触摸不可用，界面仅展示")
        end
    end

    -- 6、业务状态（fskv 恢复主题 / 模式）
    --    注意：配色表要在建界面之前切好，否则恢复的是 light 但屏上是 dark 的色值
    state.init()
    cfg.set_theme(state.theme)
    sim.set_mode(state.mode)

    -- 7、搭界面
    ui.build()

    -- 8、背光：首帧余量后点亮（避免残留闪屏）
    if not is_pc then
        sys.wait(150)
        power.backlight_on(100)
    end

    -- 9、主循环：33ms 节拍（约 30fps）
    sys.taskInit(function()
        while true do
            sys.wait(FRAME_MS)
            local ok2, err = pcall(ui.tick, FRAME_MS / 1000)
            if not ok2 then log.error("main", "tick 异常", err) end
        end
    end)

    log.info("main", "电动车仪表盘 ready", VERSION)
end)

sys.run()
