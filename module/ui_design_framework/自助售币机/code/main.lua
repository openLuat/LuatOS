--[[
@module  main
@summary 自助售币机 · 启动编排（Air8607 + 10.1 寸 1024x600 RGB + GT911）
@version 1.0.0
@date    2026.11.20

=== 分层（单向依赖） ===
  驱动  drv_lcd 屏时序 / drv_power 背光 / drv_tp GT911
  应用  app_config 色板+布局+节奏 / app_state 会员+档位+支付+fskv
  界面  ui_widget 安全原语（唯一控件入口）/ ui_icons 图元
        ui_topbar / ui_login / ui_tier / ui_pay / ui_kb / ui_toast / ui_theme
        ui 编排（切页 + 主题回调 + 巡检）
  入口  main 只排启动顺序

=== 启动顺序（有依赖） ===
1 背光归零 → 2 drv_lcd.setup → 3 airui.init → 4 字号载齐
→ 5 drv_tp.init → 6 fskv + app_state.init → 7 ui.build → 8 点亮背光 → 9 主循环

=== 为什么主循环 50ms 而不是 33ms ===
  界面是静态的：没有常驻动画，只有 1Hz 时钟 / 1Hz 倒计时 / 偶尔一次点击反馈。
  LVGL 的重绘由它自己的定时器驱动，和这里的巡检节拍无关。
  50ms 巡检 = 20 次/秒的整数比较，屏幕上没有东西要变的时候一个字节都不下发（P5）。
]]

PROJECT = "coin_kiosk"
VERSION = "1.0.0"

local cfg   = require "app_config"
local ST    = require "app_state"
local lcd   = require "drv_lcd"
local power = require "drv_power"
local tp    = require "drv_tp"
local ui    = require "ui"

local S = cfg.HW.screen
local POLL_MS = cfg.ANIM.poll_ms
local BUSY_MS = cfg.ANIM.busy_ms       -- 切页过渡期间的临时节拍

-- ==================== 毫秒时钟 ====================
-- mcu.ticks() 的节拍频率各固件不统一（1kHz / 1MHz 都见过），不能靠 mcu.hz() 猜：
-- hz() 既可能给节拍频率，也可能给主频，量纲差 1000 倍 —— 猜错的后果不是"慢一点"，
-- 而是时钟每秒跳 1000 秒、120s 倒计时 0.12s 走完。
-- 所以启动时做一次 100ms 实测标定：tick 差值 / 100 = 每毫秒 tick 数。
local WRAP_TICK = 4294967296
local TICKS_PER_MS = 1

local function now_ms()
  if mcu == nil or mcu.ticks == nil then return 0 end
  local v = mcu.ticks()
  if v < 0 then v = v + WRAP_TICK end
  return v / TICKS_PER_MS
end

local function diff_ms(a, b)
  local d = a - b
  if d < 0 then d = d + WRAP_TICK / TICKS_PER_MS end
  return d
end

local function init_timebase()
  local hz = (mcu ~= nil and mcu.hz ~= nil) and mcu.hz() or nil
  local dn = nil
  if mcu ~= nil and mcu.ticks ~= nil then
    local t0 = mcu.ticks()
    sys.wait(100)
    local t1 = mcu.ticks()
    dn = t1 - t0
    if dn < 0 then dn = dn + WRAP_TICK end
    -- 100ms 至少 45 个 tick 才可信：低于此值说明 ticks 没在走（或分辨率粗到没法用），
    -- 这时保持 1:1，主循环里的 dead 计数会兜底按名义帧长累加时间轴
    if dn >= 45 then TICKS_PER_MS = dn / 100 end
  end
  log.info("main", string.format("时间基准 hz=%s tick/100ms=%s tick/ms=%.3f",
    tostring(hz), tostring(dn), TICKS_PER_MS))
end

sys.taskInit(function()
  local is_pc = (rtos.bsp() == "PC")

  -- 1、供电 / 背光先归零（黑屏搭界面）
  if not is_pc then power.power_on() end

  -- 2、显示
  local ok, backend = lcd.setup({
    pin_rst = S.pin_rst, w = S.panel_w, h = S.panel_h,
    hbp = S.hbp, hspw = S.hspw, hfp = S.hfp,
    vbp = S.vbp, vspw = S.vspw, vfp = S.vfp,
    bus_speed = S.bus_speed,
  })
  if not ok then
    log.error("main", "显示初始化失败", backend)
    return
  end

  -- 3、AirUI
  airui.init(S.w, S.h)
  airui.set_rotation(0)

  -- 4、字号一次载齐（hzfont 按已加载字号出字，缺档渲染成方框）
  -- cache_size 是每档字形位图上限（LRU 上限，不是预分配）；本工程文案约 130 个汉字
  for _, sz in ipairs(cfg.SIZES) do
    airui.font_load({ type = "hzfont", size = sz, cache_size = 256, antialias = 1 })
  end

  -- 5、触摸（container on_click 依赖它）
  if not is_pc then
    if not tp.init() then log.warn("main", "触摸不可用，界面仅展示") end
  end

  -- 6、业务状态
  if fskv and fskv.init then pcall(fskv.init) end
  ST.init()

  -- 7、搭界面（内部先应用落盘主题，再切到首个可见页）
  ui.build()

  -- 8、背光：留一帧余量再点亮
  if not is_pc then
    sys.wait(150)
    power.backlight_on(100)
  end

  -- 9、主循环
  sys.taskInit(function()
    init_timebase()
    local waitMs = POLL_MS
    local t_start = now_ms()
    local prev = now_ms()
    local elapsed, dead = 0, 0
    local err_n = 0
    local PERF = false                 -- 排查卡顿时改 true
    local pn, pcycle, pcost = 0, 0, 0
    -- 传给 ui.tick 的是「毫秒」，判据见 ui.lua：时钟按 dt_ms/1000 累加到 1s，
    -- 扫码线按累计毫秒走（cfg.ANIM.scan_ms）。传秒会让扫描线 40s 才走一步。
    -- 传的是**实测周期**而不是名义 50ms：sys.wait 会被调度拖长，若恒传 50，
    -- 动画就按「名义帧」走，实际慢 10%~40% 且随负载漂移（节拍不补偿 P8）。
    local dt_ms = POLL_MS

    while true do
      sys.wait(waitMs)
      local t0 = now_ms()
      local cycle = diff_ms(t0, prev)
      prev = t0
      -- 实测周期转动画步长：0（ticks 不可用）退回名义值；超长周期压到 200ms 防一帧跳太远
      dt_ms = cycle
      if dt_ms <= 0 then dt_ms = POLL_MS end
      if dt_ms > 200 then dt_ms = 200 end
      if dt_ms < 4 then dt_ms = 4 end

      -- 时间轴用「距启动的真实毫秒」；mcu.ticks 缺失时退化为按名义周期累加
      local e = diff_ms(t0, t_start)
      if e > 0 then
        elapsed = e
        dead = 0
      else
        dead = dead + 1
        if dead > 30 then elapsed = elapsed + POLL_MS end
      end

      local ok2, err = pcall(ui.tick, dt_ms)
      local cost = diff_ms(now_ms(), t0)

      if not ok2 then
        err_n = err_n + 1
        if err_n <= 3 or err_n % 100 == 0 then
          log.error("main", "tick 异常", err_n, err)
        end
        sys.wait(500)
        prev = now_ms()
        waitMs = POLL_MS
      else
        if err_n > 0 then
          log.warn("main", "tick 恢复正常，此前异常", err_n, "次")
          err_n = 0
        end
        -- 补偿式节拍：实际周期 = 睡眠 + 本帧耗时；下限 4ms（sys.wait(0) 会静默失败）
        -- 切页过渡 / 位移动画期间临时用 busy_ms：50ms 节拍一帧走 3~4px，看着就是一跳，
        -- 提到 16ms 才够顺；过渡一结束立刻回 50ms，不长期空转（P10）。
        local budget = POLL_MS
        if ui.busy and ui.busy() then budget = BUSY_MS end
        local w = budget - cost
        if w < 4 then w = 4 end
        waitMs = math.floor(w)

        if PERF then
          pn = pn + 1
          pcycle = pcycle + cycle
          pcost = pcost + cost
          if pn >= 300 then
            log.info("main", string.format("PERF 周期 %.1fms 巡检耗时 %.2fms",
              pcycle / pn, pcost / pn))
            pn, pcycle, pcost = 0, 0, 0
          end
        end
      end
    end
  end)

  log.info("main", "自助售币机 ready", VERSION)
end)

-- 必须显式启动事件循环：main chunk 返回后 luat_main_call 就结束，
-- 表现为「界面搭完、日志无报错、1ms 后 Lua VM exit!! reboot」
sys.run()
