--[[
  ui_toast.lua  轻提示（底部居中，1.6s 自动消失）

  显隐只改透明度（I2）：set_color(c, 0/255)。不用 hide/open（open 真机恢复不回来）。
  文本用 set_text，不做动画 —— 提示条是低频交互，没必要为它开一个 30fps 的过渡。

  ⚠ 图标不用 W.icon 自动登记：它的颜色/字形要随 kind（ok / warn）变，
    自动登记只记得第一次的令牌，重涂时会把它刷回青色 check。
    所以这里自己管三件事：ico_key / ico_ck / ico_opa，主题切换由 ui.lua 调 M.sync() 重下。
]]

local W = require "ui_widget"
local ICO = require "ui_icons"

local M = {}

local box, lb, right_ico
local timer_id = nil
local ico_key, ico_ck, ico_opa = "check", "pri", 255

local W_BOX, H_BOX = 420, 44
local X = math.floor((1024 - W_BOX) / 2)
local Y = 494

local function draw_ico()
  if not right_ico then return end
  pcall(right_ico.set_items, right_ico, ICO.items(ico_key, 18, W.c(ico_ck), W.pal(), ico_opa))
end

function M.build()
  W.group("toast")
  box = W.box(nil, X, Y, W_BOX, H_BOX, {
    color = W.c("card"), radius = 22, bw = 1, border = W.c("pri"),
    skin = "card", bskin = "pri", opa = 0, tag = "toast",
  })
  right_ico = W.shape(box, 14, 13, 18, 18, ICO.items("check", 18, W.c("pri"), W.pal(), 0), "toast.ico")
  lb = W.text_mid(box, 40, 0, W_BOX - 56, H_BOX - 2, { text = "", size = 18, ck = "text", tag = "toast.lb" })
  M.root = box
  ico_opa = 0
  draw_ico()
  M.opa(0)
end

-- box 走登记表透明度；图标自己重下 items
function M.opa(v)
  W.opa(box, v)
  ico_opa = v
  draw_ico()
  if v == 0 and lb then lb:set_text("") end
  -- 待机必须停到屏外左侧，不能只靠 opa = 0：
  -- airui.container 保留了 LVGL 的 CLICKABLE 标志（C 层没暴露改标志的接口），
  -- color_opacity = 0 只是画不出来，命中测试照常命中。这条 420×44 的隐形长条
  -- 常驻 (302,494) 即 302..722 / 494..538，正好压住扫码页两个按钮（x 294..503、
  -- 519..728，y 488..532）的中上部，支付页「模拟支付成功」和成功页底部按钮同样中招
  -- —— 表现就是「按钮看得见，点不动」。
  -- 只许停左/上侧（G6）：停右侧会撑大主屏滚动区。
  if box then pcall(box.set_pos, box, (v > 0) and X or -W_BOX, Y) end
end

function M.show(text, kind)
  if not box then return end
  local warn = (kind == "warn")
  ico_key = warn and "cross" or "check"
  ico_ck  = warn and "danger" or "pri"
  lb:set_text(text or "")
  M.opa(255)
  if timer_id then sys.timerStop(timer_id) end
  timer_id = sys.timerStart(function()
    timer_id = nil
    M.opa(0)
  end, 1600)
end

-- 主题切换后重下图标（颜色令牌变了）
function M.sync()
  draw_ico()
end

return M
