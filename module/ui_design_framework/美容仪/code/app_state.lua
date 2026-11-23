--[[
  app_state.lua  护理状态：6 个模式 / 能量档位 / 本次倒计时
  只存数据与纯函数，不碰任何控件（UI 层单向依赖本模块）。
  fskv 只落「上次模式 + 档位」，重启后回到上次选择。
]]

local M = {}

-- k: 图片键（/luadb/mode_<k>.png）；m: 建议分钟；lv: 默认档位
M.MODES = {
  { k = "clean",  n = "深层清洁",   m = 10, lv = 3, d = "导出毛孔油脂与角质" },
  { k = "import", n = "精华导入",   m = 15, lv = 4, d = "超声促渗，直达肌底" },
  { k = "ems",    n = "微电流提拉", m = 12, lv = 4, d = "低频微电流，即时提拉" },
  { k = "rf",     n = "射频紧致",   m = 15, lv = 5, d = "温热深层加热，激发胶原" },
  { k = "led",    n = "光子嫩肤",   m = 20, lv = 2, d = "红光照射，改善暗沉" },
  { k = "cool",   n = "冰感舒缓",   m = 8,  lv = 2, d = "低温镇定，收敛毛孔" },
}
M.N = 6
M.LV_MAX = 5

local KEY_MODE = "bm_mode"
local KEY_LV   = "bm_lv"

-- fskv 在 PC 模拟器/未分区的固件上可能不存在或未 init：
-- 一律 pcall，失败就当没存过，绝不让落盘拖死开机
local function kv_get(k)
  if not fskv then return nil end
  local ok, v = pcall(fskv.get, k)
  if ok then return v end
  return nil
end

local function kv_set(k, v)
  if not fskv then return end
  pcall(fskv.set, k, v)
end

local S = { i = 4, lv = 5, total = 900, left = 900, run = false, acc = 0 }
M.S = S

-- 索引统一 1 基（1..N），与 MODES 数组、数码页码共用一套，
-- 避免 0 基越界时 MODES[0] 取到 nil（真机直接崩在 set_src）。
function M.wrap(i)
  return (i - 1) % M.N + 1
end

function M.cur()
  return M.MODES[S.i]
end

function M.fmt(sec)
  if sec < 0 then sec = 0 end
  return string.format("%02d:%02d", math.floor(sec / 60), math.floor(sec % 60))
end

function M.init()
  local i = kv_get(KEY_MODE)
  local lv = kv_get(KEY_LV)
  if type(i) == "number" and i >= 1 and i <= M.N and i % 1 == 0 then S.i = i end
  local m = M.MODES[S.i]
  S.lv = (type(lv) == "number" and lv >= 1 and lv <= M.LV_MAX) and lv or m.lv
  S.total = m.m * 60
  S.left = S.total
  S.run = false
  S.acc = 0
  log.info("state", "恢复模式", S.i, m.n, "档位", S.lv)
end

-- 切模式：清零计时、套用该模式的默认档位（与设计稿 pick() 一致）
function M.pick(i)
  i = M.wrap(i)
  if i == S.i then return false end
  S.i = i
  local m = M.MODES[i]
  S.lv = m.lv
  S.total = m.m * 60
  S.left = S.total
  S.run = false
  S.acc = 0
  kv_set(KEY_MODE, i)
  kv_set(KEY_LV, S.lv)
  return true
end

function M.set_lv(v)
  if v < 1 or v > M.LV_MAX or v == S.lv then return false end
  S.lv = v
  kv_set(KEY_LV, v)
  return true
end

-- 开始 / 暂停 / 继续。返回 true 表示状态变了
function M.toggle()
  if S.left <= 0 then
    S.left = S.total
    S.acc = 0
  end
  S.run = not S.run
  return true
end

-- 主循环每帧调用；dt 秒。返回 true 表示秒数变了（需要重绘数字）
function M.tick(dt)
  if not S.run then return false end
  S.acc = S.acc + dt
  if S.acc < 1 then return false end
  local step = math.floor(S.acc)
  S.acc = S.acc - step
  S.left = S.left - step
  if S.left <= 0 then
    S.left = 0
    S.run = false
    log.info("state", "护理完成", M.cur().n)
  end
  return true
end

return M
