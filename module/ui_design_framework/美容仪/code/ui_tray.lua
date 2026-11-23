--[[
  ui_tray.lua  底部状态托片 470..574，928x104
    ● 已连接 ｜ 电量 78% ｜ 模式说明 ｜ [开始护理 168x52]

  内容区 926x102（bw=1）。左侧三项都用 text_mid 按 102 高垂直居中，
  分隔线是 1x18 的 line2（真机上一根 1px 线在白底上仍然看得见，
  line 太淡会像脏点，这里按 F6 用 line2）。

  === 强调色分工 ===
  状态点（8px 圆）     glow  夜间 #4C8DFF —— 小面积亮点在深底才抓眼
  主按钮底（168x52）   fill  夜间 #1D4ED8 —— 白字压上去 7.5:1，当底必须够深
  按钮上的字与图标     on_fill 夜间 #FFFFFF

  图标不能写成模块级常量：C.card 在模块加载时就被求值固化成日间的白色，
  切到夜间后按钮变成亮蓝底，白图标还在上面，对比度掉到 1.4:1。
  所以 PLAY/PAUSE 做成按当前色板现算的函数，每次切换重算再下发。
]]

local cfg = require "app_config"
local W = require "ui_widget"

local L = cfg.LAYOUT
local M = {}

local CW = L.content_w - 2      -- 926
local CH = L.tray_h - 2         -- 102
local BTN_W, BTN_H = 168, 52

local ICON_X, ICON_Y, ICON_W, ICON_H = 34, 17, 16, 18

--- 播放三角（3 段 line 收成三角形）与暂停（两个实心 rect）
--  图标不用 symbol 字体：hzfont 没有 LVGL 私有字形，会渲染成空心方框
local function icon_items(run)
  if run then
    return {
      { type = "rect", x = 1,  y = 2, w = 5, h = 14, color = "on_fill", width = 1,
        fill = true, fill_color = "on_fill" },
      { type = "rect", x = 10, y = 2, w = 5, h = 14, color = "on_fill", width = 1,
        fill = true, fill_color = "on_fill" },
    }
  end
  return {
    { type = "line", x1 = 1,  y1 = 1, x2 = 1,  y2 = 17, color = "on_fill", width = 2 },
    { type = "line", x1 = 1,  y1 = 1, x2 = 14, y2 = 9,  color = "on_fill", width = 2 },
    { type = "line", x1 = 14, y1 = 9, x2 = 1,  y2 = 17, color = "on_fill", width = 2 },
  }
end

function M.build(page, on_start)
  local box = W.box(page, L.pad, L.tray_y, L.content_w, L.tray_h,
    { color = "card", bw = 1, border = "line2", tag = "tray" })

  -- 状态点（fill=true 才是实心圆；只给 width 会变成一圈描边）
  W.shape(box, 26, 47, 8, 8, {
    { type = "circle", cx = 4, cy = 4, r = 4, color = "glow", width = 1,
      fill = true, fill_color = "glow" },
  })
  W.text_mid(box, 42, 0, 64, CH, { text = "已连接", size = 16, color = "ink2" })
  W.bar(box, 124, 42, 1, 18, "line2")

  -- 电量（等宽，避免 78→77 时整串右移）
  W.text_mid(box, 144, 0, 40, CH, { text = "电量", size = 16, color = "ink2" })
  local batt = W.num(box, 186, 41, "99%", 16, "ink2")
  batt.set("78")
  W.bar(box, 232, 42, 1, 18, "line2")

  -- 模式说明 / 护理中提示
  local hint = W.text_mid(box, 256, 0, 460, CH,
    { text = "", size = 16, color = "ink3", tag = "hint" })

  -- 主按钮
  local btnX = CW - 26 - BTN_W
  local btnY = math.floor((CH - BTN_H) / 2)
  local bgc = W.box(box, btnX, btnY, BTN_W, BTN_H,
    { color = "fill", bw = 0, tag = "btnbg" })

  local ico = W.shape(bgc, ICON_X, ICON_Y, ICON_W, ICON_H, icon_items(false))

  local label = W.text_mid(bgc, 62, 0, 70, BTN_H,
    { text = "开始护理", size = 16, color = "on_fill", tag = "btntxt" })

  -- 热区必须最后盖在 box 上：LVGL9 的 container / shape 默认就带 LV_OBJ_FLAG_CLICKABLE，
  -- 先建透明热区再往里塞可见容器，可见容器在上层把 press 截走，热区永远收不到 → 点不动。
  -- 同一个区域里，热区在建完所有可见件之后再创建，才会位于最顶层。
  W.press(box, btnX, btnY, BTN_W, BTN_H, on_start, 0, "starthit")

  return {
    hint = hint,
    set_hint = function(t) hint:set_text(t) end,
    set_batt = function(v)
      v = math.max(0, math.min(100, math.floor(v + 0.5)))
      batt.set(tostring(v))
    end,
    set_run = function(run)
      label:set_text(run and "暂停护理" or "开始护理")
      -- 走 W.set_items：同时更新登记，避免下次切主题被 repaint 刷回旧形态
      W.set_items(ico, icon_items(run))
    end,
  }
end

return M
