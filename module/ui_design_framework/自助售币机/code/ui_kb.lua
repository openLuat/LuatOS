--[[
  ui_kb.lua  数字键盘（左 420 输入卡 / 右 528 键区）

  键区 3×4：键 161×110，(12 + col*171, 12 + row*120)，右缘 515 ≤ 528、下缘 482 ≤ 496。
  热区必须建在键帽容器内、按内容区 159×108 算 —— 用外框 161×110 会各边越界 1px（§1 判据）。

  坐标见 docs/handoff.md §3.8。
]]

local cfg = require "app_config"
local ST  = require "app_state"
local W   = require "ui_widget"

local M = {}
local L = cfg.L

local root, code_num, hint_lb

local KEYS = {
  { "1", "2", "3" },
  { "4", "5", "6" },
  { "7", "8", "9" },
  { "clear", "0", "del" },
}

-- ==================== 构建 ====================
function M.build()
  W.group("kb")
  root = W.box(nil, -1080, 0, cfg.HW.screen.w, cfg.HW.screen.h, { color = W.c("bg"), opa = 0, tag = "kb" })

  -- ---------- 左卡 420×496 → 内容区 418×494 ----------
  local lc = W.box(root, L.lx_x, L.lx_y, L.lx_w, L.lx_h, {
    bw = 1, radius = 18, skin = "card", bskin = "edge", tag = "kbl" })

  W.label(lc, 28, 30, 362, { text = "输入会员号", size = 26, ck = "text", h = 31, tag = "kbt" })
  W.label(lc, 28, 74, 362, { text = "会员号 / 手机号，4 位以上", size = 16, ck = "text_dim", h = 19, tag = "kbd" })

  -- 回显框 362×88 → 内容区 360×86
  local ef = W.box(lc, 28, 112, 362, 88, { bw = 1, radius = 14, skin = "tile", bskin = "edge", tag = "kbe" })
  code_num = W.num(ef, 20, 22, "99999999999", 34, "text")

  hint_lb = W.label(lc, 28, 218, 362, { text = "支持 4~11 位，输入后点确认", size = 16, ck = "text_dim", h = 19, tag = "kbh" })

  -- 确认 362×64（无描边）
  local ok = W.box(lc, 28, 300, 362, 64, { color = W.c("btn"), radius = 14, bw = 0, skin = "btn", tag = "kbok" })
  W.text_mid(ok, 0, 20, 360, 24, { text = "确认", size = 20, ck = "on_pri", tag = "kbokt" })
  W.press(ok, 1, 1, 360, 62, function() M.on_ok() end, { tag = "kbokhit" })

  -- 返回 362×56 → 内容区 360×54
  local bk = W.box(lc, 28, 382, 362, 56, { bw = 1, radius = 14, skin = "tile", bskin = "edge", tag = "kbbk" })
  W.text_mid(bk, 0, 16, 358, 21, { text = "返回", size = 18, ck = "text_sub", tag = "kbbkt" })
  W.press(bk, 1, 1, 358, 52, function() M.on_back() end, { tag = "kbbkhit" })

  W.label(lc, 28, 456, 362, { text = "会员号可在门店前台查询", size = 16, ck = "text_dim", h = 19, tag = "kbf" })

  -- ---------- 键区 528×496 ----------
  local area = W.box(root, L.rx_x, L.rx_y, L.rx_w, L.rx_h, {
    color = W.c("bg"), opa = 0, tag = "kbkeys" })

  for r = 1, 4 do
    for c = 1, 3 do
      local k = KEYS[r][c]
      local x = L.key_x + (c - 1) * L.key_dx
      local y = L.key_y + (r - 1) * L.key_dy
      local kv = W.box(area, x, y, L.key_w, L.key_h, {
        bw = 1, radius = 14, skin = "tile", bskin = "edge", tag = "k" .. r .. c })

      -- 键帽 161×110 → 内容区 159×108：文字宽 157、热区 1,1,157,106，右下各留 1px
      if k == "clear" then
        W.text_mid(kv, 0, 44, 157, 22, { text = "清空", size = 18, ck = "text_sub", tag = "kct" .. r .. c })
        W.press(kv, 1, 1, 157, 106, function() M.on_clear() end, { tag = "kch" .. r .. c })
      elseif k == "del" then
        W.text_mid(kv, 0, 44, 157, 22, { text = "退格", size = 18, ck = "text_sub", tag = "kdt" .. r .. c })
        W.press(kv, 1, 1, 157, 106, function() M.on_del() end, { tag = "kdh" .. r .. c })
      else
        W.text_mid(kv, 0, 37, 157, 36, { text = k, size = 30, ck = "text", tag = "knt" .. r .. c })
        W.press(kv, 1, 1, 157, 106, function() M.on_digit(k) end, { tag = "knh" .. r .. c })
      end
    end
  end

  M.sync()
end

-- ==================== 显隐 ====================
function M.show(on)
  -- 传数字 = 过渡帧：直接摆 x（只接受 ≤ 0，右侧永不越界，AGENTS G6）
  if type(on) == "number" then
    if root and on <= 0 then pcall(root.set_pos, root, on, 0) end
    return
  end
  if root then pcall(root.set_pos, root, on and 0 or -1080, 0) end
  if on then M.sync() end
end

-- ==================== 状态同步 ====================
function M.sync()
  if not code_num then return end
  local code = ST.S.code or ""
  code_num.set(code ~= "" and code or "")
  if hint_lb then
    hint_lb:set_text(code == "" and "支持 4~11 位，输入后点确认" or ("已输入 " .. #code .. " 位"))
    pcall(hint_lb.set_color, hint_lb, W.c(#code >= 4 and "text_sub" or "text_dim"))
  end
end

function M.hint(text, kind)
  if not hint_lb then return end
  hint_lb:set_text(text or "")
  pcall(hint_lb.set_color, hint_lb, W.c(
    (kind == "err" and "danger") or (kind == "warn" and "warn") or "text_dim"))
end

return M
