--[[
@module  ui_theme
@summary 玻璃拟态 · 两套配色（A 石墨黑 / B 石墨紫）× 深浅双主题，运行中可切 + fskv 记忆
@version 3.0.0
@usage  改主题只动这一个文件；关闭全部微动把 M.motion.enabled 设为 false。
        颜色 0xRRGGBB，opacity 0-255（越小越透明）。
        与 docs/方案E_配色升级.html 同一套视觉令牌（A/B × 深/浅 共 4 套）。

        两套配色的差别只在「底 + 玻璃面色相 + 高亮色」，层叠关系完全一致：
          A 石墨黑：近纯黑底 + 石板蓝玻璃 + 电光青高亮（浅色 = 灰蓝纸底 + 纯白卡）
          B 石墨紫：中性黑底  + 石墨紫玻璃 + 紫罗兰高亮（浅色 = 薄紫雾底 + 纯白卡）

        运行中切换：T.set_mode("light"/"dark") 换明暗，T.set_scheme("A"/"B") 换配色，
        两者都是原地更新 M.c / M.glass 的字段并保存 fskv；页面 destroy+create 原地重建。

        浅色「卡片看不清」的根因与修法（v3 起）：
          旧版所有叠层都用 C.card（白色）+ 一个 opa，浅色下白卡(210)、白磁贴(120)、
          白胶囊(140) 叠在同一张白面板上，叠出来全是白——面与面之间没有色差。
          现在把「载体色」拆成独立令牌：card / panel / cardtop / tile / track / hl，
          浅色里它们分别是 纯白 / 纯白 / 纯白 / #E7EDF7 / #DFE7F2，配合深一档的底色
          与 2px 暗边、5px 实投影，卡片与间隙的亮度比从 1.06:1 提到约 1.5:1。
]]
local M = {}

-- ---------- 当前状态：fskv 记忆（固件内置库，直接全局使用，无需 require） ----------
M.scheme = "A"                                  -- 配色方案："A" / "B"
M.mode   = "dark"                               -- 明暗："dark" / "light"
if fskv then
    pcall(function()
        if fskv.init then fskv.init() end
        local s = fskv.get("ui_scheme")
        local m = fskv.get("ui_theme_mode")
        log.info("ui_theme", "读取外观偏好", s, m)
        if s == "A" or s == "B" then M.scheme = s end
        if m == "dark" or m == "light" then M.mode = m end
    end)
end

-- ==================== 色板 ====================
-- 每套都含 c（颜色）与 glass（透明度 / 描边 / 投影参数）两张表，键必须完全一致，
-- 否则切方案后某处取到 nil 会直接报错（apply 是原地覆盖，不会留旧字段）。
local P = {}

-- ---------- A · 深色：近纯黑底 + 石板蓝玻璃（带色相，不是白叠灰）+ 冷蓝暗边 ----------
P.A = {}
P.A.dark = {
    c = {
        text = 0xF5F8FC, text_sub = 0xA7B3C6, text_dim = 0x7B8899,
        -- 玻璃叠层载体：白卡改「石板蓝实色 @88%」，才有色相；灰边改冷蓝暗边
        card = 0x222C3E, panel = 0x1E2738, cardtop = 0x28344A,
        tile = 0x3A4A64, track = 0x2A3547, hl = 0xFFFFFF,
        edge = 0x2E3A50, divider = 0x2E3A50, shadow = 0x000000,
        pri = 0x5FE3FF, pri_deep = 0x22D3EE, btn_bg = 0x2A3A56,
        ok = 0x3DDC97, warn = 0xFFC24B, danger = 0xFF7A8A,
        sw_on = 0x22D3EE, sw_off = 0x39465C, knob = 0xFFFFFF,
        chip_on = 0x5FE3FF, chip_on_t = 0x061018,
        chip_off = 0x3A4A64, chip_off_t = 0xA7B3C6,
        glow = 0x5FE3FF,
        deep = 0x0A0F18,
        soft = 0x2E3A50,
    },
    glass = {
        bg = 0x05060A,
        glow1 = 0x7C3AED, glow2 = 0x2563EB, glow3 = 0xDB2777, glow4 = 0x0891B2,
        bg_glow_opa = 33,
        card_opa = 224, tile_opa = 153, panel_opa = 235, topbar_opa = 240,
        shadow_opa = 158, shadow_off = 4,
        hl_opa = 38, hl_sweep_opa = 150,
        card_edge = 2,
        inset_opa = 222, track_opa = 110,
    },
}

-- ---------- A · 浅色：灰蓝纸底 + 纯白不透明卡 + 深边 + 5px 实影 ----------
P.A.light = {
    c = {
        text = 0x0A1526, text_sub = 0x465469, text_dim = 0x6F7E96,
        card = 0xFFFFFF, panel = 0xFFFFFF, cardtop = 0xFFFFFF,
        tile = 0xE7EDF7, track = 0xDFE7F2, hl = 0xFFFFFF,
        edge = 0xA9BAD2, divider = 0xC7D3E6, shadow = 0x3A5073,
        pri = 0x0A72D6, pri_deep = 0x05538F, btn_bg = 0x14405F,
        ok = 0x0B8F63, warn = 0xB26A05, danger = 0xCE2942,
        sw_on = 0x0A72D6, sw_off = 0xBFCCDE, knob = 0xFFFFFF,
        chip_on = 0x0A72D6, chip_on_t = 0xFFFFFF,
        chip_off = 0xE7EDF7, chip_off_t = 0x465469,
        glow = 0x0A72D6,
        deep = 0xE7EDF7,
        soft = 0xA9BAD2,
    },
    glass = {
        bg = 0xC7D3E6,
        glow1 = 0xAFC4EE, glow2 = 0x96D4F3, glow3 = 0xF3C4DD, glow4 = 0x9EEADF,
        bg_glow_opa = 51,
        card_opa = 255, tile_opa = 255, panel_opa = 255, topbar_opa = 255,
        shadow_opa = 107, shadow_off = 5,
        hl_opa = 0, hl_sweep_opa = 0,          -- 白卡上不要顶部反光条（白叠白 = 塑料亮边）
        card_edge = 2,
        inset_opa = 235, track_opa = 255,
    },
}

-- ---------- B · 深色：中性黑底 + 石墨紫玻璃 + 紫罗兰高亮（无绿） ----------
P.B = {}
P.B.dark = {
    c = {
        text = 0xF4F2FB, text_sub = 0xADA6C2, text_dim = 0x807A93,
        card = 0x262138, panel = 0x221E32, cardtop = 0x2C2644,
        tile = 0x443C62, track = 0x2E2846, hl = 0xFFFFFF,
        edge = 0x3B3352, divider = 0x3B3352, shadow = 0x000000,
        pri = 0xB49BFF, pri_deep = 0x8B5CF6, btn_bg = 0x332A52,
        ok = 0x4ADE80, warn = 0xF5C05A, danger = 0xFB7185,
        sw_on = 0x8B5CF6, sw_off = 0x3E3558, knob = 0xFFFFFF,
        chip_on = 0xB49BFF, chip_on_t = 0x120C22,
        chip_off = 0x443C62, chip_off_t = 0xADA6C2,
        glow = 0xB49BFF,
        deep = 0x0D0A16,
        soft = 0x3B3352,
    },
    glass = {
        bg = 0x07060C,
        glow1 = 0x7C3AED, glow2 = 0x4F46E5, glow3 = 0xE11D48, glow4 = 0x6366F1,
        bg_glow_opa = 32,
        card_opa = 224, tile_opa = 153, panel_opa = 235, topbar_opa = 240,
        shadow_opa = 153, shadow_off = 4,
        hl_opa = 33, hl_sweep_opa = 140,
        card_edge = 2,
        inset_opa = 222, track_opa = 110,
    },
}

-- ---------- B · 浅色：薄紫雾底 + 纯白卡 ----------
P.B.light = {
    c = {
        text = 0x16122A, text_sub = 0x514B69, text_dim = 0x7A7391,
        card = 0xFFFFFF, panel = 0xFFFFFF, cardtop = 0xFFFFFF,
        tile = 0xEEEAF6, track = 0xE4DFF0, hl = 0xFFFFFF,
        edge = 0xB4AACB, divider = 0xD2CBE0, shadow = 0x55467B,
        pri = 0x6644E0, pri_deep = 0x4A2CB8, btn_bg = 0x332570,
        ok = 0x0B8F63, warn = 0xA96A08, danger = 0xCE2942,
        sw_on = 0x6644E0, sw_off = 0xC6BFD9, knob = 0xFFFFFF,
        chip_on = 0x6644E0, chip_on_t = 0xFFFFFF,
        chip_off = 0xEEEAF6, chip_off_t = 0x514B69,
        glow = 0x6644E0,
        deep = 0xEEEAF6,
        soft = 0xB4AACB,
    },
    glass = {
        bg = 0xD2CBE0,
        glow1 = 0xC4B7F2, glow2 = 0xB2D1F6, glow3 = 0xF0C4DA, glow4 = 0xC2E4FF,
        bg_glow_opa = 46,
        card_opa = 255, tile_opa = 255, panel_opa = 255, topbar_opa = 255,
        shadow_opa = 102, shadow_off = 5,
        hl_opa = 0, hl_sweep_opa = 0,
        card_edge = 2,
        inset_opa = 235, track_opa = 255,
    },
}

-- 生效当前外观：M.c / M.glass 是常驻表，只原地改字段，不换引用。
-- page_glass / ui_widget 在 require 时就把这两张表存进了 local C, G，
-- 若这里改成 M.c = t.c，那些引用会永远停在旧主题；原地改字段才能全局同步。
M.c, M.glass = {}, {}
local function copy_tokens(dst, src)
    for k in pairs(dst) do dst[k] = nil end
    for k, v in pairs(src) do dst[k] = v end
end

-- 应用外观：scheme = "A"/"B"，mode = "dark"/"light"
-- 只给一个参数也可以：T.apply("light") / T.apply("B")，另一个维度保持当前值
function M.apply(scheme, mode)
    if scheme == "light" or scheme == "dark" then scheme, mode = nil, scheme end
    if mode == nil and scheme == nil then mode = M.mode end
    if scheme ~= nil then M.scheme = (scheme == "B") and "B" or "A" end
    if mode ~= nil then M.mode = (mode == "light") and "light" or "dark" end
    local t = P[M.scheme][M.mode]
    copy_tokens(M.c, t.c)
    copy_tokens(M.glass, t.glass)
end

local function save()
    if not fskv then return end
    pcall(function()
        fskv.set("ui_scheme", M.scheme)
        fskv.set("ui_theme_mode", M.mode)
        log.info("ui_theme", "保存外观偏好", M.scheme, M.mode)
    end)
end

-- 换明暗（保留当前配色方案）
function M.set_mode(mode)
    M.apply(M.scheme, mode)
    save()
end

-- 换配色方案（保留当前明暗）
function M.set_scheme(scheme)
    M.apply(scheme, M.mode)
    save()
end

M.apply(M.scheme, M.mode)

-- ==================== 固定参数 ====================
M.o = { chip = 140, sw_off = 200 }
M.r = { card = 22, panel = 14, chip = 17 }
-- 字号：验收标准「最小字号 16 号」，sub/mini 已并到 16；body 及以上不受影响
M.f = { h1 = 32, title = 28, temp = 46, ac = 32, body = 18, sub = 16, mini = 16 }

-- 微动：全部是「短、局部、状态驱动」的隐性反馈，不做全屏/整卡持续动画
M.motion = {
    enabled     = true,
    instant     = true,  -- 交互反馈全即时（默认）：不建逐帧定时器，状态一帧到位、松手即结束。
                         -- 真机上 Lua 逐帧定时器受其他任务抢占会抖动，动画排队还有拖尾，
                         -- 观感反而廉价；设为 false 可退回补间版本对比。
    frame_ms    = 20,    -- 软补间每帧间隔（sys.timerStart），30→20 更跟手
    press_dy    = 2,     -- 按压下沉像素
    press_fr    = 3,     -- 按压/回弹帧数（约 60ms）
    knob_fr     = 5,     -- 开关滑块缓动（约 100ms）
    glow_fr     = 4,     -- 数值刷新高亮（约 80ms）
    sweep_fr    = 4,     -- 磁贴/按钮高光条扫光（约 80ms）
    enter_dy    = 10,    -- 入场位移
    enter_fr    = 6,     -- 入场约 120ms
    enter_gap   = 60,    -- 各模块依次入场的间隔 ms
    swap_fr     = 4,     -- 房间切换磁贴逐个上浮（约 80ms）
    swap_gap    = 30,    -- 磁贴错开间隔 ms
}

M.screen = { w = 1024, h = 600 }
return M
