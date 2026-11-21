--[[
@module  main
@summary 美容仪 · 启动编排（Air8607 + 10.1 寸 1024x600 RGB + GT911）
@version 1.0.0
@date    2026.11.19

=== 分层 ===
  驱动  drv_lcd 屏时序 / drv_power 背光 / drv_tp GT911
  应用  app_config 色板+布局+节奏 / app_state 模式+档位+倒计时+fskv
  界面  ui_widget 安全原语（唯一控件入口）/ ui_topbar / ui_overview
        ui_carousel（含切换微缩动画）/ ui_tray / ui 编排
  入口  main 只排启动顺序

=== 启动顺序（有依赖） ===
1 power_on 背光归零 → 2 drv_lcd.setup → 3 airui.init → 4 字号载齐
→ 5 drv_tp.init → 6 app_state.init → 7 ui.build → 8 backlight_on → 9 主循环
]]

PROJECT = "beauty_device"
VERSION = "1.0.0"

local cfg   = require "app_config"
local ST    = require "app_state"
local lcd   = require "drv_lcd"
local power = require "drv_power"
local tp    = require "drv_tp"
local ui    = require "ui"

local S = cfg.HW.screen
local FRAME_MS = cfg.ANIM.frame_ms

-- ==================== 毫秒时钟 ====================
-- mcu.ticks() 是 tick 数不是毫秒：Air1603（Air8607 主控）约 20ms 一跳，
-- 直接当毫秒用会让所有时间量差 20 倍。按 mcu.hz()（每秒 tick 数）折算；
-- hz 缺失或返回主频（>100000）时退化为 1:1，只丢精度不会算错。
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
  if type(hz) == "number" and hz > 1 and hz <= 100000 then
    TICKS_PER_MS = hz / 1000
  end
  log.info("main", string.format("时间基准 hz=%s tick/ms=%.4f",
    tostring(hz), TICKS_PER_MS))
end

-- ==================== 资源自检 ====================
-- 图片不显示时日志通常很干净：先确认文件在不在、尺寸对不对（F7）
local MODE_KEYS = {}
for _, m in ipairs(ST.MODES) do MODE_KEYS[#MODE_KEYS + 1] = m.k end

local function check_assets()
  local miss = 0
  for _, k in ipairs(MODE_KEYS) do
    local p = "/luadb/mode_" .. k .. ".png"
    if not io.exists(p) then
      miss = miss + 1
      log.error("main", "缺图", p)
    end
  end
  if miss > 0 then
    log.error("main", "共缺 " .. miss .. " 张图，轮播会显示空槽")
  else
    log.info("main", "6 张模式图就位")
  end
end

sys.taskInit(function()
  local is_pc = (rtos.bsp() == "PC")

  -- 1、供电 / 背光先归零
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
  -- cache_size 是每档的字形位图上限：本界面固定文案约 50 个汉字，256 足够
  local seen = {}
  for _, sz in ipairs(cfg.SIZES) do
    if not seen[sz] then
      seen[sz] = true
      airui.font_load({ type = "hzfont", size = sz, cache_size = 256, antialias = 1 })
    end
  end

  -- 5、触摸（container on_click 依赖它）
  if not is_pc then
    if not tp.init() then log.warn("main", "触摸不可用，界面仅展示") end
  end

  -- 6、业务状态 + 资源（fskv 先 init，PC 上没有这个库会直接跳过）
  if fskv and fskv.init then pcall(fskv.init) end
  ST.init()
  check_assets()

  -- 7、搭界面
  ui.build()

  -- 8、背光：首帧余量后点亮
  if not is_pc then
    sys.wait(150)
    power.backlight_on(100)
  end

  -- 9、主循环
  sys.taskInit(function()
    init_timebase()
    local waitMs = FRAME_MS
    local t_start = now_ms()
    local prev = now_ms()
    local elapsed, dead = 0, 0
    local err_n = 0
    local PERF = false
    local perf_n, perf_cycle, perf_cost = 0, 0, 0

    while true do
      sys.wait(waitMs)
      local t0 = now_ms()
      local cycle = diff_ms(t0, prev)
      prev = t0

      -- 时间轴用「距启动的真实毫秒」（不从 0 起累加周期，避免逐帧取整漂移）；
      -- mcu.ticks 缺失时 now_ms() 恒为 0，连续 30 帧没动就退化为按名义帧长累加
      local e = diff_ms(t0, t_start)
      if e > 0 then
        elapsed = e
        dead = 0
      else
        dead = dead + 1
        if dead > 30 then elapsed = elapsed + FRAME_MS end
      end

      -- dt 恒为 frame_ms：动画/阈值按固定步长设计，传实测浮点会让阈值在
      -- N / N+1 帧之间来回跳（P9）；倒计时在 ui.tick 里按 elapsed 差分走。
      local ok2, err = pcall(ui.tick, FRAME_MS / 1000, elapsed)
      local cost = diff_ms(now_ms(), t0)

      if not ok2 then
        err_n = err_n + 1
        if err_n <= 3 or err_n % 100 == 0 then
          log.error("main", "tick 异常", err_n, err)
        end
        sys.wait(500)
        prev = now_ms()
        waitMs = FRAME_MS
      else
        if err_n > 0 then
          log.warn("main", "tick 恢复正常，此前异常", err_n, "次")
          err_n = 0
        end
        -- 补偿式节拍：实际周期 = 睡眠 + 本帧耗时，不补偿帧率会掉。
        -- 下限 4ms：sys.wait(0) 会静默失败。
        local w = FRAME_MS - cost
        if w < 4 then w = 4 end
        waitMs = math.floor(w)

        if PERF then
          perf_n = perf_n + 1
          perf_cycle = perf_cycle + cycle
          perf_cost = perf_cost + cost
          if perf_n >= 300 then
            log.info("main", string.format("PERF 周期 %.1fms 耗时 %.1fms 帧率 %.1f",
              perf_cycle / perf_n, perf_cost / perf_n, 1000 / (perf_cycle / perf_n)))
            perf_n, perf_cycle, perf_cost = 0, 0, 0
          end
        end
      end
    end
  end)

  log.info("main", "美容仪 ready", VERSION)
end)

-- 必须显式启动事件循环：main chunk 返回后 luat_main_call 就结束，
-- 表现为「界面搭完、日志无报错、1ms 后 Lua VM exit!! reboot」。
sys.run()
