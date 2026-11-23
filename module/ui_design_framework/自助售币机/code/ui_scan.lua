--[[
  ui_scan.lua  扫码登录（单卡 460×476）

  真机侧：机器下方扫码窗读用户手机上的会员码，硬件回调只给一行码串。
  屏幕职责只有两条：引导用户对准、60 秒超时兜底。

  扫描线是 shape 改 y（不是 CSS 动画）：节拍统一走 ui.lua 的 tick，
  不额外开定时器（P8：多一个定时器就多一处跑偏的节拍）。

  坐标见 docs/handoff.md §3.4。
]]

local cfg = require "app_config"
local ST  = require "app_state"
local W   = require "ui_widget"

local M = {}
local L = cfg.L

local root, dot, tip_lb, left_num, line, sim_lb
local y_top, y_bot = 20, 170       -- 扫描线活动范围（取景框内容区 218 高）
-- 扫描线用「浮点位置 + 整数下发」：浮点负责不丢余量，整数负责只在该变时才 set_pos。
-- 旧写法每 40ms 攒够就步进 3px 并把余量清零，等价于把扫描线锁死在 tick 的整数倍上
-- （50ms 节拍 → 实际每步 50ms，速度慢 25%，且每次都是一次 3px 的硬跳）。
local y_f, y_dir, y_sent = 20, 1, 20
local running = false
local SPEED = cfg.ANIM.scan_step * 1000 / cfg.ANIM.scan_ms   -- px/s，配置改了自动跟随

-- ==================== 构建 ====================
function M.build()
  W.group("scan")
  root = W.box(nil, -1080, 0, cfg.HW.screen.w, cfg.HW.screen.h, { color = W.c("bg"), opa = 0, tag = "scan" })

  local c = W.box(root, L.sc_x, L.sc_y, L.sc_w, L.sc_h, {
    bw = 1, radius = 18, skin = "card", bskin = "edge", tag = "sccard" })

  -- 卡片内容区 458×474：文字块宽取 456/456，右缘 456/456 各留 2px
  W.text_mid(c, 0, 26, 456, 33, { text = "扫码登录", size = 30, ck = "text", tag = "sctitle" })
  W.text_mid(c, 0, 68, 456, 19, { text = "请将手机会员码对准下方扫码口", size = 16, ck = "text_dim", tag = "scdesc" })

  -- 取景框 300×220 → 内容区 298×218
  local vf = W.box(c, 79, 104, 300, 220, { bw = 1, radius = 14, skin = "tile", bskin = "edge", tag = "scvf" })

  -- 四角 L：每个角 2 条 bar（竖 + 横），共 8 条。不用图元旋转，方向天然正确
  local T, Lw = 2, 24                                   -- 线宽 2、臂长 24
  -- 右/下工作边 = 内容区 − 2（298-2 / 218-2）：臂宽 2 起算，右缘正好 296 / 216，不贴边
  local R, B = 296, 216
  W.bar(vf, 0, 0, Lw, T, "pri", 255);            W.bar(vf, 0, 0, T, Lw, "pri", 255)
  W.bar(vf, R - Lw, 0, Lw, T, "pri", 255);       W.bar(vf, R - T, 0, T, Lw, "pri", 255)
  W.bar(vf, 0, B - T, Lw, T, "pri", 255);        W.bar(vf, 0, B - Lw, T, Lw, "pri", 255)
  W.bar(vf, R - Lw, B - T, Lw, T, "pri", 255);   W.bar(vf, R - T, B - Lw, T, Lw, "pri", 255)

  W.icon(vf, "phone", 101, 56, 96, "text_dim", "scphone")
  line = W.bar(vf, 24, y_top, 250, 2, "pri", 219)
  W.text_mid(vf, 0, 190, 296, 19, { text = "对准扫码口，保持不动", size = 16, ck = "text_dim", tag = "scvft" })

  -- 状态条 398×52 → 内容区 396×50
  local sb = W.box(c, 30, 344, 398, 52, { bw = 1, radius = 12, skin = "tile", bskin = "edge", tag = "scstat" })
  dot = W.box(sb, 14, 18, 14, 14, { color = W.c("warn"), radius = 7, tag = "scdot" })
  tip_lb = W.label(sb, 36, 15, 200, { text = "等待扫码", size = 16, ck = "text_sub", h = 19, tag = "sctip" })
  left_num = W.num(sb, 300, 13, "99", 20, "text")
  W.label(sb, 348, 15, 20, { text = "秒", size = 16, ck = "text_dim", h = 19, tag = "scsec" })

  -- 模拟按钮（btn 底，无描边）
  local b = W.box(c, 12, 404, 209, 44, { color = W.c("btn"), radius = 12, bw = 0, skin = "btn", tag = "scsim" })
  sim_lb = W.text_mid(b, 0, 0, 207, 44, { text = "模拟扫码成功", size = 18, ck = "on_pri", tag = "scsimt" })
  W.press(b, 1, 1, 207, 42, function() M.on_ok() end, { tag = "scsimhit" })

  -- 取消 209×44 → 内容区 207×42
  local x = W.box(c, 237, 404, 209, 44, { bw = 1, radius = 12, skin = "tile", bskin = "edge", tag = "sccancel" })
  W.text_mid(x, 0, 0, 205, 42, { text = "取消返回", size = 18, ck = "text_sub", tag = "sccancelt" })
  W.press(x, 1, 1, 205, 40, function() M.on_cancel() end, { tag = "sccancelhit" })

  M.sync()
end

-- ==================== 显隐 / 节拍 ====================
function M.show(on)
  -- 传数字 = 过渡帧：直接摆 x（只接受 ≤ 0，右侧永不越界，AGENTS G6）
  if type(on) == "number" then
    if root and on <= 0 then pcall(root.set_pos, root, on, 0) end
    return
  end
  running = on
  if root then pcall(root.set_pos, root, on and 0 or -1080, 0) end
  if on then
    y_f, y_dir, y_sent = y_top, 1, y_top
    if line then pcall(line.set_pos, line, 24, y_top) end
    M.sync()
  end
end

-- 扫描线：按「真实毫秒 × 速度」算位置，余量留在 y_f 里不丢。
-- 只有取整后的像素变了才 set_pos —— 内容没变不下发（P5），
-- 位置连续、速度恒定，反弹处也不会因为夹值出现一顿（P8）。
function M.tick(dt_ms)
  if not running or not line then return end
  local dt = dt_ms or 0
  if dt <= 0 then return end
  y_f = y_f + y_dir * SPEED * dt / 1000
  if y_f >= y_bot then y_f, y_dir = y_bot, -1
  elseif y_f <= y_top then y_f, y_dir = y_top, 1 end
  local yi = math.floor(y_f + 0.5)
  if yi ~= y_sent then
    y_sent = yi
    pcall(line.set_pos, line, 24, yi)
  end
end

-- ==================== 状态同步 ====================
function M.set_state(kind, text, left)
  if not tip_lb then return end
  local ck = (kind == "ok" and "ok") or (kind == "warn" and "warn") or "text_sub"
  tip_lb:set_text(text or "等待扫码")
  pcall(tip_lb.set_color, tip_lb, W.c(ck))
  if dot then pcall(dot.set_color, dot, W.c(ck), 255) end
  if line then pcall(line.set_color, line, W.c(ck), 255) end
  if left and left_num then left_num.set(string.format("%02d", left)) end
end

function M.sync()
  M.set_state("wait", "等待扫码", math.ceil(ST.S.scanLeft or 0))
end

return M
