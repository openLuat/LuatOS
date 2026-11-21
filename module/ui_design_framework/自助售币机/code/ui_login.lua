--[[
  ui_login.lua  登录页（左视觉 + 右 392×456 登录卡）

  坐标见 docs/handoff.md §3.3。
  左半是品牌视觉（金币位图 + 三行卖点），右半只有一个纵向流程：输入 → 登录 → 或扫码。
  视觉信息与操作信息分开摆，用户不会在左边找按钮。
]]

local cfg = require "app_config"
local ST  = require "app_state"
local W   = require "ui_widget"

local M = {}
local L = cfg.L

-- 金币主视觉位图。
-- 铁律：位图必须放在 code/ 下（与 main.lua 同级），下载脚本只打包 code/ 里的文件，
-- 落点 /luadb/<文件名>。放在 docs/ 里永远进不了真机 —— 表现为「日志干净、图片空白」。
-- 上传方式不同会把子目录拍平（res/ → /luadb/），所以给一串候选依次试，
-- 全拿不到才退化成图元金币（失败只告警，不拖垮整页）。
local HERO_SRC = {
  "/luadb/coin_hero.png",          -- code/coin_hero.png（正常落点：只下载 code/ 目录）
  "/luadb/code/coin_hero.png",     -- 把整个项目目录下载进去时的落点
  "/luadb/img/coin_hero.png",      -- 保留了 code/img/ 子目录的打包方式
  "/luadb/docs/img/coin_hero.png",
  "coin_hero.png",                 -- PC 模拟器：相对 code/ 当前目录
  "/coin_hero.png",                -- 兜底：luadb 挂在 vfs 根而不是 /luadb
}

-- 位图存在性探测：airui.image 在文件不存在时**也返回非 nil 对象**
-- （C 层只是 lv_image_set_src，失败不抛错也不返回 nil），所以「拿到对象」≠「有图」。
-- 不先探文件，路径一错就是「既没位图、也没图元金币」的一片空白 —— 日志还干净。
local function hero_pick()
  if not (io and io.exists) then return HERO_SRC[1] end     -- 老固件没有 io.exists，交给 W.image 试
  for i = 1, #HERO_SRC do
    local ok, yes = pcall(io.exists, HERO_SRC[i])
    if ok and yes then return HERO_SRC[i] end
  end
  return nil
end

local root, code_lb, clear_ic, hint_lb

local HINT_IDLE = "支持 4~11 位会员号或手机号"

-- ==================== 构建 ====================
function M.build()
  W.group("login")
  root = W.box(nil, -1080, 0, cfg.HW.screen.w, cfg.HW.screen.h, { color = W.c("bg"), opa = 0, tag = "login" })

  -- ---------- 左：品牌视觉 ----------
  -- 位图优先；探不到真实文件时退化成同尺寸图元金币 —— 左半区不能空着
  local src = hero_pick()
  local img = src and W.image(root, L.hero_x, L.hero_y, L.hero_s, L.hero_s, src, "contain") or nil
  if not img then
    -- 走到这里就是「位图没进 luadb」：日志会打出实际试过的路径，对着文件树一查就知道差在哪
    log.warn("login", "主视觉位图缺失，退化为图元金币", tostring(src or HERO_SRC[1]))
    W.icon(root, "coin", L.hero_x, L.hero_y, L.hero_s, "pri", "lgcoin")
  elseif src then
    log.info("login", "主视觉位图", src)
  end
  W.bar(root, 64, 372, 44, 1, "pri_deep", 255)
  W.label(root, 64, 388, 320, { text = "扫码即玩", size = 34, ck = "text", h = 41, tag = "lghero" })
  W.label(root, 64, 442, 320, { text = "COIN · LOAD · PLAY", size = 16, ck = "text_dim", h = 19, tag = "lgsub" })
  -- 三个卖点：16 号 × 4~6 字，横向留 20px 间隔，右缘 456 ≤ 592-64 ✅
  W.label(root, 64, 486, 120, { text = "24H 自助", size = 16, ck = "text_sub", h = 19, tag = "lgf1" })
  W.label(root, 196, 486, 120, { text = "秒到账", size = 16, ck = "text_sub", h = 19, tag = "lgf2" })
  W.label(root, 316, 486, 140, { text = "会员专属加赠", size = 16, ck = "text_sub", h = 19, tag = "lgf3" })
  W.bar(root, 64, 534, 456, 1, "divider", 255)
  W.label(root, 64, 550, 400, { text = "支持微信 / 支付宝 · 客服 400-000-0000", size = 16, ck = "text_dim", h = 19, tag = "lgfoot" })

  -- ---------- 右：登录卡 392×456 → 内容区 390×454 ----------
  local c = W.box(root, L.lg_x, L.lg_y, L.lg_w, L.lg_h, {
    bw = 1, radius = 18, skin = "card", bskin = "edge", tag = "lgcard" })

  W.label(c, 28, 30, 200, { text = "会员登录", size = 26, ck = "text", h = 31, tag = "lgtitle" })
  W.label(c, 28, 72, 334, { text = "登录后可查看余额与专属加赠", size = 16, ck = "text_dim", h = 19, tag = "lgdesc" })

  -- 输入框 334×68 → 内容区 332×66
  local f = W.box(c, 28, 110, 334, 68, { bw = 1, radius = 14, skin = "tile", bskin = "edge", tag = "lgfield" })
  W.icon(f, "member", 16, 22, 22, "text_dim", "lgfi")
  code_lb = W.label(f, 52, 22, 236, { text = "请输入会员号", size = 18, ck = "text_dim", h = 22, tag = "lgcode" })
  clear_ic = W.icon(f, "cross", 296, 23, 20, "text_dim", "lgfclear")
  -- 热区按内容区坐标：起点 (1,1)，右/下缘停在 331/65（内容区 332×66，各留 1px）
  W.press(f, 1, 1, 330, 64, function() M.on_field() end, { tag = "lgfhit" })

  hint_lb = W.label(c, 28, 188, 334, { text = HINT_IDLE, size = 16, ck = "text_dim", h = 19, tag = "lghint" })

  -- 主按钮 334×64（无描边，内容区即 334×64）
  local b = W.box(c, 28, 220, 334, 64, {
    color = W.c("btn"), radius = 14, bw = 0, skin = "btn", tag = "lgbtn" })
  W.text_mid(b, 0, 20, 332, 24, { text = "登录并选币", size = 20, ck = "on_pri", tag = "lgbtnt" })
  W.press(b, 1, 1, 332, 62, function() M.on_ok() end, { tag = "lgbtnhit" })

  -- 「或」分隔：155 + 4 + 24 + 4 + 155 = 342 ≤ 362 ✅
  W.bar(c, 28, 308, 155, 1, "divider", 255)
  W.text_mid(c, 179, 299, 32, 19, { text = "或", size = 16, ck = "text_dim", tag = "lgor" })
  W.bar(c, 211, 308, 155, 1, "divider", 255)

  -- 扫码登录：334×56 → 内容区 332×54
  local s = W.box(c, 28, 330, 334, 56, { bw = 1, radius = 14, skin = "tile", bskin = "edge", tag = "lgscan" })
  W.icon(s, "scan", 22, 17, 22, "pri", "lgscani")
  W.label(s, 58, 18, 250, { text = "扫码登录（会员二维码）", size = 18, ck = "text_sub", h = 21, tag = "lgscant" })
  W.press(s, 1, 1, 330, 52, function() M.on_scan() end, { tag = "lgscanhit" })

  W.label(c, 28, 404, 120, { text = "没有会员号？", size = 16, ck = "text_dim", h = 19, tag = "lgreg" })
  W.label(c, 152, 404, 140, { text = "先购币再注册", size = 16, ck = "pri", h = 19, tag = "lgreg2" })
  W.press(c, 152, 400, 140, 27, function() M.on_ok() end, { tag = "lgreghit" })

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
  if not code_lb then return end
  local code = ST.S.code or ""
  local has = (code ~= "")
  code_lb:set_text(has and code or "请输入会员号")
  pcall(code_lb.set_color, code_lb, W.c(has and "text" or "text_dim"))
  if clear_ic then W.opa(clear_ic, has and 255 or 0) end
end

-- 提示行：超时 / 位数不足时由 ui.lua 调用
function M.hint(text, kind)
  if not hint_lb then return end
  hint_lb:set_text(text or HINT_IDLE)
  pcall(hint_lb.set_color, hint_lb, W.c(
    (kind == "warn" and "warn") or (kind == "err" and "danger") or "text_dim"))
end

return M
