--[[
  app_sim.lua  仪表数据仿真（车速 / 电量 / 功率 / 温度 / 骑行统计 / 指示灯）
  与 UI 完全解耦：UI 重建后状态不丢，重建完继续读这里。
  没有整车总线时，这里是唯一的"数据源"，接真车时替换本文件即可。
]]

local cfg  = require "app_config"
local util = require "app_util"

local M = {}

local MAX    = cfg.MAX_SPEED
local BOOT_S = cfg.ANIM.sweep_s

-- ==================== 驾驶模式 ====================
-- lo/hi = 目标车速区间；acc = 车速收敛速率；kw = 功率系数
-- name 保留英文缩写（顶栏胶囊 / 日志用），cn 是卡片上的中文档位名
-- acc 由 1.9/2.6/3.6 降到 1.2/1.7/2.3：时间常数 τ=1/acc 从 0.53/0.38/0.28s
-- 拉长到 0.83/0.59/0.43s。指针只有 15Hz，τ 太小时一帧要扫 20°，看起来
-- 是"跳"而不是"转"，实机反馈动态跟不上。
M.MODES = {
  { id = "eco",    name = "ECO",    cn = "经济", lo = 16, hi = 58,  acc = 1.2, kw = 0.028 },
  { id = "normal", name = "NORMAL", cn = "标准", lo = 28, hi = 108, acc = 1.7, kw = 0.035 },
  { id = "sport",  name = "SPORT",  cn = "运动", lo = 52, hi = 152, acc = 2.3, kw = 0.046 },
}

-- ==================== 运行时状态 ====================
M.mode    = 2         -- 1 ECO / 2 NORMAL / 3 SPORT
M.speed   = 0         -- 当前车速（指针/数字）
M.target  = 0         -- 目标车速
M.power   = 0         -- 输出功率 kW
M.eff     = 0         -- 瞬时电耗 Wh/km
M.battery = 78        -- 电量 %
M.range   = 186       -- 续航 KM
M.temp    = 32        -- 电机温度 ℃
M.ctrl    = 28        -- 控制器温度 ℃
M.trip    = 42.6      -- 单程 KM
M.odo     = 12860     -- 总里程 KM
M.ride_s  = 204       -- 本次骑行时长（秒）
M.avg     = 24        -- 平均车速
M.charging = false    -- 充电中
M.booting = true
M.blink   = false     -- 转向灯闪烁相位

M.ind = {
  left  = false,      -- 左转向（绿，闪烁）
  right = false,      -- 右转向（绿，闪烁）
  high  = false,      -- 远光（青）
  abs   = false,      -- 制动辅助（琥珀）
  batt  = false,      -- 电池告警（琥珀，电量 < 22）
  tcs   = false,      -- 牵引力控制（品红）
}

M.demo_ind = true   -- 指示灯演示固定态；置 false 回到 2.6s 随机

-- ==================== 内部计时 ====================
local boot_t, target_t, data_t, ind_t, blink_t = 0, 0, 0, 0, 0

local function mode_tbl() return M.MODES[M.mode] or M.MODES[2] end

local MAX_JUMP = 28       -- 单次目标变化上限（km/h）
local TGT_S    = 5.5      -- 目标车速刷新周期（原 3.8s）

-- 巡航换目标：在「当前目标 ±MAX_JUMP」内取，而不是每次全区间重掷。
-- 原先是 lo..hi 均匀取，3.8s 一次经常 28 → 108 跨 80km/h，指针一帧扫 20°。
-- 起点先向档位中心回拉 30%，否则随机游走会长期贴在区间边缘不动。
local function pick_target()
  local md     = mode_tbl()
  local lo, hi = md.lo, md.hi
  local mid    = (lo + hi) * 0.5
  local base   = (M.target > 0) and (M.target + (mid - M.target) * 0.3) or lo
  local a = math.max(lo, base - MAX_JUMP)
  local b = math.min(hi, base + MAX_JUMP)
  M.target = a + util.rnd() * (b - a)
end

function M.set_mode(i)
  if i < 1 or i > 3 then return end
  M.mode = i
  if not M.booting then
    -- 切档是用户主动动作，不受 MAX_JUMP 限制：点 SPORT 就该立刻冲出去
    local md = mode_tbl()
    M.target = md.lo + util.rnd() * (md.hi - md.lo)
  end
end

function M.toggle_charge()
  M.charging = not M.charging
end

function M.tick(dt)
  -- 1) 开机扫针：0 → MAX → 0
  if M.booting then
    boot_t = boot_t + dt
    if boot_t < BOOT_S then
      local p = boot_t / BOOT_S
      if p < 0.6 then
        M.speed = MAX * (1 - (1 - p / 0.6) ^ 3)      -- 前 60% 缓出
      else
        M.speed = MAX * (1 - (p - 0.6) / 0.4)        -- 后 40% 线性回落
      end
    else
      M.booting = false
      M.speed = 0
      pick_target()
    end
  else
    -- 2) 车速向目标指数逼近
    local k = math.min(1, dt * mode_tbl().acc)
    M.speed = M.speed + (M.target - M.speed) * k
    if math.abs(M.target - M.speed) < 0.4 then M.speed = M.target end
  end

  -- 3) 功率 / 电耗：随车速线性上升 + 小抖动（纯展示用）
  if M.charging then
    M.power = 0
    M.eff = 0
  else
    local want = M.speed * mode_tbl().kw + 0.2
    M.power = M.power + (want - M.power) * math.min(1, dt * 3)
    M.eff = (M.speed > 3) and (M.power * 1000 / math.max(M.speed, 1)) or 0
    if M.eff > 45 then M.eff = 45 end
  end

  -- 4) 转向灯 1Hz 闪烁相位
  blink_t = blink_t + dt
  if blink_t >= 0.5 then
    blink_t = blink_t - 0.5
    M.blink = not M.blink
  end

  -- 5) 目标车速每 5.5s 换一次（原 3.8s，换太勤指针一直在追）
  target_t = target_t + dt
  if target_t >= TGT_S then
    target_t = target_t - TGT_S
    if not M.booting then pick_target() end
  end

  -- 6) 电量 / 续航 / 温度每 2.4s 更新
  data_t = data_t + dt
  if data_t >= 2.4 then
    data_t = data_t - 2.4
    if M.charging then
      M.battery = util.clamp(M.battery + 1, 0, 100)
    elseif not M.booting then
      M.battery = util.clamp(M.battery - M.speed * 0.002, 6, 100)
    end
    M.range = math.floor(M.battery * 2.4 + 0.5)
    -- 温度跟随功率，缓慢收敛
    local t_want = 30 + M.power * 4.5
    M.temp = M.temp + (t_want - M.temp) * 0.25 + (util.rnd() - 0.5) * 0.6
    M.ctrl = M.temp - 4 + (util.rnd() - 0.5) * 0.8
    if M.temp < 20 then M.temp = 20 end
    if M.ctrl < 18 then M.ctrl = 18 end
  end

  -- 7) 骑行统计
  if not M.booting and not M.charging then
    local dkm = M.speed * dt / 3600
    M.trip = M.trip + dkm
    M.odo = M.odo + dkm
    M.ride_s = M.ride_s + dt
    -- 均速用滑动平均（用 trip/时长算会因初始里程/时长不成比例而炸到 199）
    M.avg = M.avg + (M.speed - M.avg) * math.min(1, dt * 0.25)
    if M.avg > 199 then M.avg = 199 end
  end

  -- 8) 指示灯
  if M.demo_ind then
    -- 演示固定态：电池常亮、左转常亮（由 blink 做 1Hz 闪烁）、远光开，
    -- 右转 / ABS / TCS 灭。置 M.demo_ind = false 回到下面的随机演示。
    M.ind.left, M.ind.right = true, false
    M.ind.high, M.ind.abs   = true, false
    M.ind.tcs,  M.ind.batt  = false, true
  else
    -- 转向灯左右互斥（真车不会同时打左右，双闪除外）。48% 概率两个都不亮，
    -- 看上去就像"只有左转能用"，这里补一档双闪把两边的灯都演示到。
    ind_t = ind_t + dt
    if ind_t >= 2.6 then
      ind_t = ind_t - 2.6
      local r = util.rnd()
      if r < 0.24 then
        M.ind.left, M.ind.right = true, false
      elseif r < 0.48 then
        M.ind.left, M.ind.right = false, true
      elseif r < 0.60 then
        M.ind.left, M.ind.right = true, true       -- 危险报警双闪
      else
        M.ind.left, M.ind.right = false, false
      end
      M.ind.high  = util.rnd() > 0.55
      M.ind.abs   = util.rnd() > 0.84
      M.ind.tcs   = util.rnd() > 0.78
      M.ind.batt  = M.battery < 22
    end
  end
end

return M
