--[[
@module  ui_theme
@summary 净界洗车 · 视觉令牌（晨曦白 / 夜青 双主题，顶栏切换 + fskv 记忆）
@version 1.1.0
@note 严格对齐 docs/方案A_水光玻璃.html 的 CSS 变量：颜色 0xRRGGBB，透明度 0-255。
      HTML 里 rgba(a,.55) 这类值统一换算成 0.55*255 ≈ 140。
      真机没有 backdrop blur，用「渐变背景 + 两团柔光 + 半透明玻璃卡 + 假投影 + 高光条」近似。
      最小字号 16 号。
]]
local M = {}

-- ---------- 主题偏好：fskv 记忆 ----------
M.mode = "dawn"
if fskv then
    pcall(function()
        if fskv.init then fskv.init() end
        local saved = fskv.get("wash_theme")
        log.info("ui_theme", "读取主题偏好", saved)
        if saved == "dawn" or saved == "night" then M.mode = saved end
    end)
end

-- ---------- 晨曦白 ----------
-- CSS: --txt:#2c2926 --sub:#6a625c --dim:#9c958e --accent:#ae6b52 --on-accent:#fffaf7
--      --glass1:rgba(255,255,255,.90) --hair:rgba(44,41,38,.12) --shadow:…rgba(66,58,50,.46)
M.dawn = {
    c = {
        -- 对比度增强：次级色整体压深一档（原 6A625C / 9C958E 在 565 屏上偏灰、显旧）
        text = 0x241F1C, text_sub = 0x51483F, text_dim = 0x7A7169,
        -- 面板底色 = 「白 90% 叠在背景上」的预混合值，配合 card_opa=255 用纯色画，
        -- 省掉一整块面板面积的 alpha 混合（真机上这是最大的一笔开销）
        card = 0xFFFFFF, edge = 0xCFC6BA, divider = 0xD6CFC6, shadow = 0x423A32,
        pri = 0xB05C3C, pri_deep = 0x8E4A2E, on_pri = 0xFFFAF7,
        accent2 = 0xE0B09B,                       -- --accent2（运行中圆点）
        ok = 0x4E8F6B, warn = 0xB98240, danger = 0xB0574A,
        star_on = 0xC98A54,                       -- --star-on
        star_off = 0xA79E96,                      -- rgba(44,41,38,.18) 近似
        chip_off = 0xFFFFFF, chip_off_t = 0x51483F,
        deep = 0xEFE9E1,
        soft = 0xC9C1B6,
        pkg_off  = 0xFFFFFF,                      -- 未选中卡片面（surface 叠卡片）
        pkg_on   = 0xEDDED9,                      -- 选中：accent 22% 叠白
        vip_bg   = 0xF5EDEA,                      -- accent 13% 叠白
        coupon_bg = 0xFBF9F7,
    },
    glass = {
        bg = 0xF6F5F3,
        -- --bg-base: linear-gradient(168deg,#fdfbf8 0%,#f4efe8 44%,#ded4c7 100%)
        -- 末端按 HTML 实测再压暗一档（无 blur 光晕补不上，用底色找齐）
        -- 底色末端由「土黄」调成偏中性的暖灰，避免整屏发旧发脏
        bg_top = 0xFDFCFA, bg_mid = 0xF3EEE7, bg_bot = 0xDCD5CB,
        glow1 = 0xEEC5AC, glow2 = 0xC2CDD6,       -- --bg-a / --bg-b
        bg_a_opa = 140, bg_b_opa = 107,           -- .55 / .42
        blob1 = 0xF8D9C6, blob2 = 0xCEDCE6,       -- 左上暖光斑 / 右下冷光斑
        blob1_opa = 92, blob2_opa = 66,           -- .36 / .26
        -- RGB565 下「白 .90 叠浅底」会把 R/B 各舍入一档、G 不舍入 → 大面积发绿。
        -- 大面板必须用不透明纯色；玻璃感靠 1px 描边 + 下缘渐隐投影表达。
        card_opa = 255,
        card2_opa = 184,                          -- glass2 ≈ .72（渐变末端，用于底边压暗）
        tile_opa = 143,                           -- 卡内小卡 ≈ .56
        surface_opa = 143,                        -- --surface: 白 .56（芯片/车牌卡/附加服务）
        -- 芯片类容器：为保证与下层玻璃卡的对比度，底色提到 --surface2(.78)、描边提到 --hair3(.18)
        surface2_opa = 199, chip_edge_opa = 46,
        surface3_opa = 82,                        -- --surface3: 白 .32（主题菜单行底）
        -- 胶囊类容器的实色底：半透明会随下层深浅变化，这里给预混合后的不透明色，
        -- 保证「设备就绪 / 洗车房 / 循环水 / 附加服务」四处底色完全一致
        chip_bg = 0xFDFCFA, chip_edge = 0x2C2926,
        topbar_opa = 230,
        -- 没有高斯模糊，实色投影太重会污染背景（缝里发暗发红），降到 ~22%
        shadow_opa = 56, shadow_off = 6,
        -- 底部 2px 预混合“投影线”（零 alpha，替代整卡半透明阴影层）
        shadow_line = 0xC6BCB1,
        hl_opa = 255,                             -- --sheen #fff
        card_edge = 1,
        -- HTML 是 .12，但 565 屏上 12% 的 1px 线几乎看不见（尤其白卡叠米色底），
        -- 这里把「卡片描边 / 内层卡描边」提到 27% / 22%，保证边界可辨
        hair_color = 0x2C2926, hair_opa = 70,
        track_color = 0x2C2926,                    -- 圆环/进度条轨道：晨曦白用墨色
        hair2_opa = 56, hair3_opa = 46,            -- .22 / .18
        a13_opa = 33, a22_opa = 56, a45_opa = 115, a06_opa = 15,
        inset_opa = 36,
        track_opa = 23,                           -- .09（进度条轨道）
        ring_track_opa = 46,                      -- 圆环轨道（白 18%，比 CSS 略高保证可见）
        bar_track_opa = 30,                       -- 进度条轨道
    },
}

-- ---------- 夜青 ----------
-- CSS: --stagebg:#04080b --glass1:rgba(44,64,74,.80) --hair:rgba(255,255,255,.155)
M.night = {
    c = {
        -- 夜青：次级色提亮一档，暗底上更清楚
        text = 0xF2F9FA, text_sub = 0xBACAD3, text_dim = 0x8B9CA7,
        card = 0x2C404A, edge = 0x415A66, divider = 0x2C3E48, shadow = 0x000000,
        pri = 0x57C9B6, pri_deep = 0x3F9F8F, on_pri = 0x062622,
        accent2 = 0x86C4DE,
        ok = 0x6FC7A4, warn = 0xE0C07A, danger = 0xFF7B7B,
        star_on = 0xFFD479,
        star_off = 0x71838F,
        chip_off = 0xFFFFFF, chip_off_t = 0xA4B6C0,
        deep = 0x18262E,
        soft = 0x3A4F5A,
        pkg_off  = 0x35494F,
        pkg_on   = 0x386165,
        vip_bg   = 0x34555C,
        coupon_bg = 0x263740,
    },
    glass = {
        bg = 0x04080B,
        bg_top = 0x0C0F11, bg_mid = 0x080B0D, bg_bot = 0x030405,  -- 中性深色（不带青绿）
        glow1 = 0x2E7C7C, glow2 = 0x265266,
        bg_a_opa = 77, bg_b_opa = 71,             -- .30 / .28
        blob1 = 0x57C9B6, blob2 = 0x86C4DE,
        blob1_opa = 23, blob2_opa = 15,           -- .09 / .06
        card_opa = 255,                           -- 同上：大面板用不透明，避免 565 混色偏色
        card2_opa = 219,                          -- .86
        tile_opa = 60,                            -- 卡内小卡
        surface_opa = 17,                         -- --surface: 白 .065（夜青几乎透明）
        surface2_opa = 40, chip_edge_opa = 60,    -- 底色 白.16 / 描边 白.235（比 HTML 略强，保证可辨）
        surface3_opa = 11,                        -- --surface3: 白 .042
        chip_bg = 0x4C5960, chip_edge = 0xFFFFFF,
        topbar_opa = 204,
        shadow_opa = 170, shadow_off = 7,
        shadow_line = 0x04070A,                   -- 底部投影线（预混合实色）
        hl_opa = 43,                              -- --sheen .17
        card_edge = 1,
        hair_color = 0xFFFFFF, hair_opa = 40,     -- .155
        track_color = 0xFFFFFF,                    -- 圆环/进度条轨道：夜青用白色
        hair2_opa = 27, hair3_opa = 54,           -- .105 / .21
        a13_opa = 36, a22_opa = 61, a45_opa = 122, a06_opa = 15,
        inset_opa = 120,
        track_opa = 28,                           -- .11
        ring_track_opa = 46,
        bar_track_opa = 30,
    },
}

-- 生效主题：M.c / M.glass 常驻表，只原地改字段（页面里用 local C,G = T.c,T.glass 持有引用）
M.c, M.glass = {}, {}
local function copy_tokens(dst, src)
    for k in pairs(dst) do dst[k] = nil end
    for k, v in pairs(src) do dst[k] = v end
end
function M.apply(mode)
    local t = (mode == "night") and M.night or M.dawn
    M.mode = (mode == "night") and "night" or "dawn"
    copy_tokens(M.c, t.c)
    copy_tokens(M.glass, t.glass)
end

function M.set_mode(mode)
    M.apply(mode)
    if fskv then pcall(function()
        fskv.set("wash_theme", M.mode)
        log.info("ui_theme", "保存主题偏好", M.mode)
    end) end
end

M.apply(M.mode)

M.r = { card = 22, panel = 14, chip = 12, thumb = 12 }
M.f = { display = 32, price = 26, big = 24, body = 18, sub = 16, mini = 16 }
M.screen = { w = 1024, h = 600 }
return M
