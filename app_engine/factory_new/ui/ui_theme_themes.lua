--[[
@module  ui_theme_themes
@summary 内置主题预设（注册进 ui_theme 的主题表）
@version 1.3
@date    2026.09.16
@author  江访

=== 这是什么 ===
ui_theme 提供令牌（theme.C / theme.SEM / theme.OPA / theme.R / theme.fs）与组件工厂，
本文件只负责「往令牌上写具体颜色」，也就是换肤。

=== 新增一套主题 ===
复制下面任意一个 preset，改 id / name / desc / colors，追加一次
    theme.register(preset)
即完成注册 —— 设置页会自动列出，无需改任何页面代码。
默认主题是 id = "dawn" 的「晨曦浅色」，由 ui_theme.lua 的 M.DEFAULT_THEME 指过来。

  id      唯一标识，同时是持久化到 fskv 的值，改动等于丢弃用户既有选择
  name    设置页显示名
  desc    一句话描述（行内分隔用 ASCII "|"，内置字库不含中点符号 U+00B7）
  order   排序权重（小的靠前）
  colors  覆写 theme.C 的键值（0xRRGGBB）。只写需要变的键，其余回落基线
  opa     覆写 theme.OPA（0-255）
  radius  覆写 theme.R（逻辑值）
  style   { wallpaper = bool, dark = bool }
  swatch  { bg, card, accent, text } —— 设置页色卡预览用

=== 两类外观（style.wallpaper 决定）===
  wallpaper = true   深色玻璃：底色 + 顶部渐隐 + 四角光斑，卡片半透明白（opa≈26）
  wallpaper = false  平铺实底：整屏单色，卡片不透明（opa=255）

浅色主题与「实底」主题都必须 wallpaper = false：AirUI 的描边不支持透明度，
浅底上 26 透明度的白卡和 8% 白描边都不可见，玻璃语言在这些配色里会整体消失。
这也是为什么浅色/实底主题要把 opa 整体提到 200+，并靠实色描边补回层次。

=== 主题一览（order 顺序）===
  1 晨曦浅色 dawn       浅色 | 高对比（默认）
  2 暖阳米色 linen      浅色暖调
  3 晨雾灰   mist       浅色冷调
  4 琥珀夜空 amber      深色玻璃 | 琥珀
  5 深海青   ocean      深色玻璃 | 青蓝
  6 紫霭暮色 violet     深色玻璃 | 紫罗兰
  7 青竹幽谷 forest     深色玻璃 | 竹青
  8 曜石纯黑 obsidian   深色实底 | 薄荷
  9 石板石墨 slate      深色实底 | 天蓝

=== 关于「主强调色」写在 amber 槽位 ===
历史原因，全工程的主强调色都引用 theme.C.amber。主题切换时把强调色写回该槽位，
所有既有页面（含尚未改造的 wifi / 设置子页）会自动跟着换色；新代码建议用
theme.C.primary / primary_light / primary_deep / on_primary 表达语义。

=== 关于 desc 里的分隔符（踩过的坑）===
固件内置字库（hzfont）不含中点符号(U+00B7)，设置页面上会渲染成方框。
行内分隔一律用 ASCII 的 "|"，或直接画 1px 竖线容器。
]]

local theme = require "ui_theme"

--[[浅色 / 实底主题共用的透明度档位：
卡片与控件都要「实」，否则浅底上会糊成一片；分隔线用实色（255）。]]
local OPA_SOLID_LIGHT = {
    glass = 235, glass_hi = 250, glass_soft = 200,
    rail = 220, dock = 240,
    stroke = 255, stroke_hi = 255,
    fill = 235, fill_hi = 245,
    scrim = 150, off = 200, divider = 255,
}

--[[深色实底主题共用的透明度档位：
glass = 255 让卡片完全不透明；fill 也是 255，配合把 surface 改成「卡片色」，
iconbtn / chip / 列表行的填充就是实色卡片色，而不是刺眼的白块。]]
local OPA_SOLID_DARK = {
    glass = 255, glass_hi = 255, glass_soft = 255,
    rail = 255, dock = 255,
    stroke = 255, stroke_hi = 255,
    fill = 255, fill_hi = 255,
    scrim = 170, off = 255, divider = 255,
}

-- ==================== 1. 晨曦浅色（默认主题） ====================
--[[浅色主题走「不透明卡 + 实描边」而不是玻璃：AirUI 的描边不支持透明度，
-- 浅底上 26 透明度的白卡与 8% 白描边都不可见，玻璃语言在浅色下会整体消失。
-- 所以这里把 surface 保持为白、把 OPA 整体提到 200+，并用浅灰描边补回层次。]]
theme.register({
    id = "dawn",
    name = "晨曦浅色",
    desc = "明亮浅色 | 高对比（默认）",
    order = 1,
    style = { wallpaper = false, dark = false },
    colors = {
        bg = 0xEEF2F7, bg_top = 0xFAFCFF,
        panel = 0xFFFFFF, panel_hi = 0xF1F5FA, line_soft = 0xD3DCE8,
        surface = 0xFFFFFF, line = 0x1B2430,
        t1 = 0x1B2430, t2 = 0x5A6879, t3 = 0x8A97A8,
        -- 白底上琥珀必须压深才够对比：实测 0xE08A18 对浅底仅 2.4:1（低于 2.5 下限），
        -- 0xB86E08 可到 3.5:1；primary_light 是「强调文字色」，浅色主题下要更深而非更浅
        amber = 0xB86E08, amber_light = 0x8A5200, amber_deep = 0xA35F06,
        cyan = 0x1E93B8, cyan_light = 0x14718F,
        green = 0x1E9E6A, green_light = 0x16794F,
        violet = 0x6D4FD1, violet_light = 0x5138A8,
        rose = 0xD6455C, rose_light = 0xB03349,
        stroke = 0xD3DCE8, stroke_soft = 0xE2E8F1, stroke_hi = 0xAEBECD,
        selected = 0xDCE9F8, pressed = 0xE7EDF5,
        rose_deep = 0xC23A50, green_deep = 0x178057,
        dialog = 0xFFFFFF, on_amber = 0xFFFFFF,
        bubble_user = 0x3E6FD6, avatar_text = 0x2E4560,
        dev1 = 0xD9E3F0, dev2 = 0xC6D3E3,
        blob_pink = 0xEEF2F7, scrim = 0x2A3542,
        divider = 0xD3DCE8,
        -- 浅色下轨道要「比底更深」才看得见；滑块反过来要够白，关闭态则压深到能在轨道上分辨
        -- input_bg 不能用纯白：浅色主题的卡片本身就是白色（surface 0xFFFFFF + opa 235），
        -- 白底输入框会完全「消失」。用带蓝的浅灰拉开一档。
        track = 0xD3DCE8, track_hi = 0xBFCBD9, input_bg = 0xE9EFF7,
        knob = 0xFFFFFF, knob_off = 0x9AA6B5,
        -- 二维码在浅底上要「深模块 + 纯白底」才够对比；基线那套浅底 0xEDF1F7
        -- 在浅色主题里偏灰，会和白卡片咬在一起。
        qr_dark = 0x1B2430, qr_light = 0xFFFFFF,
    },
    opa = OPA_SOLID_LIGHT,
    swatch = { bg = 0xEEF2F7, card = 0xFFFFFF, accent = 0xB86E08, text = 0x1B2430 },
})

-- ==================== 2. 暖阳米色（浅色暖调） ====================
--[[米白纸感：底色带一点暖黄，卡片仍是白，强调色用赭橙。
浅色主题的强调色一律「压深」——理由同 dawn：浅底上高饱和亮色对比度不够。]]
theme.register({
    id = "linen",
    name = "暖阳米色",
    desc = "暖调米白 | 赭橙强调",
    order = 2,
    style = { wallpaper = false, dark = false },
    colors = {
        bg = 0xF5F0E8, bg_top = 0xFDFAF4,
        panel = 0xFFFFFF, panel_hi = 0xF6F1E8, line_soft = 0xDCD3C4,
        surface = 0xFFFFFF, line = 0x30271C,
        t1 = 0x2E2418, t2 = 0x6E6152, t3 = 0x9C8F7C,
        amber = 0x9C4F17, amber_light = 0x7A3C0C, amber_deep = 0x863F0D,
        cyan = 0x1B7F86, cyan_light = 0x14666C,
        green = 0x2F7D4F, green_light = 0x246040,
        violet = 0x6A4BB5, violet_light = 0x53398F,
        rose = 0xC4455A, rose_light = 0xA6374A,
        stroke = 0xDCD3C4, stroke_soft = 0xE8E0D3, stroke_hi = 0xB9AC97,
        selected = 0xF0E4D2, pressed = 0xF3ECE0,
        rose_deep = 0xAC3B4E, green_deep = 0x246040,
        dialog = 0xFFFFFF, on_amber = 0xFFFFFF,
        bubble_user = 0x4A6FC4, avatar_text = 0x4A3E2E,
        dev1 = 0xE6DCCB, dev2 = 0xD6C9B3,
        blob_pink = 0xF5F0E8, scrim = 0x2E2418,
        divider = 0xDCD3C4,
        track = 0xDCD3C4, track_hi = 0xC9BEA9, input_bg = 0xEFE8DB,
        knob = 0xFFFFFF, knob_off = 0xA99B85,
        qr_dark = 0x2E2418, qr_light = 0xFFFFFF,
    },
    opa = OPA_SOLID_LIGHT,
    swatch = { bg = 0xF5F0E8, card = 0xFFFFFF, accent = 0x9C4F17, text = 0x2E2418 },
})

-- ==================== 3. 晨雾灰（浅色冷调） ====================
--[[中性冷灰 + 靛青强调：比晨曦浅色更「工具感」，适合长时间看数据页。]]
theme.register({
    id = "mist",
    name = "晨雾灰",
    desc = "冷调浅灰 | 靛青强调",
    order = 3,
    style = { wallpaper = false, dark = false },
    colors = {
        bg = 0xE9EBEF, bg_top = 0xF7F8FA,
        panel = 0xFFFFFF, panel_hi = 0xF2F4F7, line_soft = 0xD5D9E0,
        surface = 0xFFFFFF, line = 0x232830,
        t1 = 0x232830, t2 = 0x5C6473, t3 = 0x8B93A2,
        amber = 0x2F6F8F, amber_light = 0x24596F, amber_deep = 0x2A627F,
        cyan = 0x1D7C92, cyan_light = 0x146275,
        green = 0x2C7A55, green_light = 0x22613F,
        violet = 0x5B4BB8, violet_light = 0x463A93,
        rose = 0xC24555, rose_light = 0xA33544,
        stroke = 0xD5D9E0, stroke_soft = 0xE3E6EB, stroke_hi = 0xB3B9C4,
        selected = 0xDCE4F0, pressed = 0xE8EBF0,
        rose_deep = 0xA83B4A, green_deep = 0x22613F,
        dialog = 0xFFFFFF, on_amber = 0xFFFFFF,
        bubble_user = 0x4468C8, avatar_text = 0x3A4453,
        dev1 = 0xDFE4EC, dev2 = 0xCDD4DE,
        blob_pink = 0xE9EBEF, scrim = 0x232830,
        divider = 0xD5D9E0,
        track = 0xD5D9E0, track_hi = 0xC1C7D1, input_bg = 0xEDF0F5,
        knob = 0xFFFFFF, knob_off = 0x9BA3B0,
        qr_dark = 0x232830, qr_light = 0xFFFFFF,
    },
    opa = OPA_SOLID_LIGHT,
    swatch = { bg = 0xE9EBEF, card = 0xFFFFFF, accent = 0x2F6F8F, text = 0x232830 },
})

-- ==================== 4. 琥珀夜空（深色玻璃） ====================
-- 深色玻璃 + 琥珀强调，与 1024×600 设计稿一致。不覆写任何键即基线本身，
-- 但仍显式列出关键色，便于作为新增主题的抄写模板。
theme.register({
    id = "amber",
    name = "琥珀夜空",
    desc = "深色玻璃 | 琥珀强调",
    order = 4,
    style = { wallpaper = true, dark = true },
    colors = {
        bg = 0x0D131C, bg_top = 0x121A26,
        panel = 0x18202C, panel_hi = 0x202A38, line_soft = 0x39434F,
        surface = 0xFFFFFF, line = 0xFFFFFF,
        t1 = 0xEDF1F7, t2 = 0x95A0AE, t3 = 0x5E6978,
        amber = 0xFFB454, amber_light = 0xFFCB7E, amber_deep = 0xF08838,
        cyan = 0x5CC9E8, cyan_light = 0x9BE4F7,
        green = 0x4FD69C, green_light = 0xA8E8CB,
        violet = 0xA78BFA, violet_light = 0xE9E3FF,
        rose = 0xFF7B8B, rose_light = 0xFFA4B0,
        stroke = 0x333C4A, stroke_soft = 0x2A3240, stroke_hi = 0x4A5666,
        selected = 0x25344A, pressed = 0x2A3240,
        rose_deep = 0xE05A6B, green_deep = 0x35B080,
        dialog = 0x121821, on_amber = 0x1A1206,
        bubble_user = 0x3D4E9E, avatar_text = 0xC3D6E8,
        dev1 = 0x2B3A4E, dev2 = 0x16202C,
        blob_pink = 0xFF76A8, scrim = 0x0E141C,
        divider = 0xFFFFFF,
        -- 轨道 / 输入框 / 滑块（见 ui_theme 的 M.bar / M.input / M.slider / M.toggle）
        track = 0x2C3542, track_hi = 0x3A4655, input_bg = 0x1B2431,
        knob = 0xF2F6FA, knob_off = 0xB9C4D0,
    },
    opa = { divider = 16 },
    swatch = { bg = 0x0D131C, card = 0x18202C, accent = 0xFFB454, text = 0xEDF1F7 },
})

-- ==================== 5. 深海青（深色玻璃） ====================
theme.register({
    id = "ocean",
    name = "深海青",
    desc = "冷调深蓝 | 青蓝强调",
    order = 5,
    style = { wallpaper = true, dark = true },
    colors = {
        bg = 0x0A1620, bg_top = 0x0E1F2C,
        panel = 0x14242F, panel_hi = 0x1B303E, line_soft = 0x2E4350,
        t1 = 0xE6F2F8, t2 = 0x8CA3B2, t3 = 0x597081,
        amber = 0x45C6E8, amber_light = 0x8FE2F7, amber_deep = 0x2E9DBE,
        cyan = 0x5CC9E8, cyan_light = 0x9BE4F7,
        green = 0x4FD6B0, green_light = 0xA8E8DE,
        violet = 0x8FA8FA, violet_light = 0xDDE4FF,
        rose = 0xFF7F92, rose_light = 0xFFA8B4,
        stroke = 0x2B3E4B, stroke_soft = 0x22333E, stroke_hi = 0x3E5866,
        selected = 0x1E3846, pressed = 0x22333E,
        rose_deep = 0xE05E72, green_deep = 0x35AE8C,
        dialog = 0x0F1E28, on_amber = 0x06222C,
        bubble_user = 0x2F5AA0, avatar_text = 0xB9DCEA,
        dev1 = 0x24404F, dev2 = 0x0A1620,
        blob_pink = 0x4FB6D6, scrim = 0x061018,
        divider = 0xFFFFFF,
        track = 0x25333E, track_hi = 0x33454F, input_bg = 0x17262F,
        knob = 0xEAF4F9, knob_off = 0xAEC0CC,
    },
    opa = { divider = 16 },
    swatch = { bg = 0x0A1620, card = 0x14242F, accent = 0x45C6E8, text = 0xE6F2F8 },
})

-- ==================== 6. 紫霭暮色（深色玻璃） ====================
theme.register({
    id = "violet",
    name = "紫霭暮色",
    desc = "暖紫暗调 | 紫罗兰强调",
    order = 6,
    style = { wallpaper = true, dark = true },
    colors = {
        bg = 0x110C1C, bg_top = 0x171029,
        panel = 0x1D1630, panel_hi = 0x271E3F, line_soft = 0x3A3050,
        t1 = 0xF1ECFB, t2 = 0xA294BE, t3 = 0x6B5E85,
        amber = 0xB78BFF, amber_light = 0xDCC9FF, amber_deep = 0x8F5CE8,
        cyan = 0x6FD3E8, cyan_light = 0xA9E7F5,
        green = 0x5FD9A6, green_light = 0xB0EBD2,
        violet = 0xC2A0FF, violet_light = 0xEDE4FF,
        rose = 0xFF85A8, rose_light = 0xFFB0C6,
        stroke = 0x352B4A, stroke_soft = 0x2A2340, stroke_hi = 0x4B3E68,
        selected = 0x2A2144, pressed = 0x2A2340,
        rose_deep = 0xE06386, green_deep = 0x3FAF84,
        dialog = 0x150F24, on_amber = 0x1A0F2E,
        bubble_user = 0x5A3FA8, avatar_text = 0xD6C7F0,
        dev1 = 0x33294A, dev2 = 0x110C1C,
        blob_pink = 0xE070B8, scrim = 0x0A0613,
        divider = 0xFFFFFF,
        track = 0x2A2340, track_hi = 0x392F55, input_bg = 0x201833,
        knob = 0xF3EDFF, knob_off = 0xC0B4D2,
    },
    opa = { divider = 16 },
    swatch = { bg = 0x110C1C, card = 0x1D1630, accent = 0xB78BFF, text = 0xF1ECFB },
})

-- ==================== 7. 青竹幽谷（深色玻璃） ====================
theme.register({
    id = "forest",
    name = "青竹幽谷",
    desc = "墨绿暗调 | 竹青强调",
    order = 7,
    style = { wallpaper = true, dark = true },
    colors = {
        bg = 0x0A1512, bg_top = 0x0E1F1A,
        panel = 0x13241F, panel_hi = 0x1A3029, line_soft = 0x2B463D,
        t1 = 0xE9F5F0, t2 = 0x8FAAA0, t3 = 0x5C7A70,
        amber = 0x4FD69C, amber_light = 0xA8E8CB, amber_deep = 0x33A874,
        cyan = 0x5CD6D6, cyan_light = 0x9EEAEA,
        green = 0x4FD69C, green_light = 0xA8E8CB,
        violet = 0x9BB8FA, violet_light = 0xE0E8FF,
        rose = 0xFF8A8A, rose_light = 0xFFB4B4,
        stroke = 0x284038, stroke_soft = 0x1F332C, stroke_hi = 0x3B5F52,
        selected = 0x1D3A32, pressed = 0x1F332C,
        rose_deep = 0xE06A6A, green_deep = 0x33A874,
        dialog = 0x0E1C18, on_amber = 0x06231A,
        bubble_user = 0x2E6B55, avatar_text = 0xBCE4D4,
        dev1 = 0x27423A, dev2 = 0x0A1512,
        blob_pink = 0x5FC9A8, scrim = 0x06100D,
        divider = 0xFFFFFF,
        track = 0x20332C, track_hi = 0x2E4A40, input_bg = 0x16261F,
        knob = 0xEEF7F2, knob_off = 0xB2C7BD,
    },
    opa = { divider = 16 },
    swatch = { bg = 0x0A1512, card = 0x13241F, accent = 0x4FD69C, text = 0xE9F5F0 },
})

-- ==================== 8. 曜石纯黑（深色实底） ====================
--[[OLED 友好：底色纯黑、卡片实心深灰，没有任何光斑与半透明层。
和玻璃主题的区别一眼可见 —— 屏幕不再是「有层次的暗」，而是「一块块实板」。]]
theme.register({
    id = "obsidian",
    name = "曜石纯黑",
    desc = "纯黑实底 | 薄荷强调",
    order = 8,
    style = { wallpaper = false, dark = true },
    colors = {
        bg = 0x000000, bg_top = 0x07090C,
        panel = 0x121417, panel_hi = 0x1A1D21, line_soft = 0x2C3036,
        -- surface 在这里不是「白色玻璃」而是「卡片实色」：OPA 全 255，
        -- 卡片/按钮/列表行会直接用这个色画实心块
        surface = 0x16191D, line = 0xFFFFFF,
        t1 = 0xF2F4F6, t2 = 0x9BA2AB, t3 = 0x6B7280,
        amber = 0x5EE6A8, amber_light = 0x9BF2C9, amber_deep = 0x33B87E,
        cyan = 0x5CC9E8, cyan_light = 0x9BE4F7,
        green = 0x4FD69C, green_light = 0xA8E8CB,
        violet = 0xA78BFA, violet_light = 0xE9E3FF,
        rose = 0xFF7B8B, rose_light = 0xFFA4B0,
        stroke = 0x2A2E34, stroke_soft = 0x1F2328, stroke_hi = 0x3E444C,
        selected = 0x1B2A23, pressed = 0x22262B,
        rose_deep = 0xE05A6B, green_deep = 0x35B080,
        dialog = 0x0E1114, on_amber = 0x04231A,
        bubble_user = 0x2E6B5A, avatar_text = 0xC7D6D0,
        dev1 = 0x1C2A24, dev2 = 0x000000,
        blob_pink = 0x000000, scrim = 0x000000,
        divider = 0x2A2E34,
        track = 0x22262B, track_hi = 0x2E343A, input_bg = 0x14171A,
        knob = 0xFFFFFF, knob_off = 0x9AA1AA,
        qr_dark = 0x000000, qr_light = 0xFFFFFF,
    },
    opa = OPA_SOLID_DARK,
    swatch = { bg = 0x000000, card = 0x16191D, accent = 0x5EE6A8, text = 0xF2F4F6 },
})

-- ==================== 9. 石板石墨（深色实底） ====================
--[[中性石墨灰 + 天蓝强调：比曜石纯黑「软」一档，适合白天使用；
同样是实底，没有玻璃层。]]
theme.register({
    id = "slate",
    name = "石板石墨",
    desc = "中性石墨 | 天蓝强调",
    order = 9,
    style = { wallpaper = false, dark = true },
    colors = {
        bg = 0x15181D, bg_top = 0x1B1F25,
        panel = 0x1E2229, panel_hi = 0x262B33, line_soft = 0x333A44,
        surface = 0x212630, line = 0xFFFFFF,
        t1 = 0xEDF0F4, t2 = 0x9AA3AF, t3 = 0x6B7480,
        amber = 0x6EA8FE, amber_light = 0xA8CDFF, amber_deep = 0x4C86E0,
        cyan = 0x5CC9E8, cyan_light = 0x9BE4F7,
        green = 0x4FD69C, green_light = 0xA8E8CB,
        violet = 0xB39BFA, violet_light = 0xEDE6FF,
        rose = 0xFF8391, rose_light = 0xFFAFB9,
        stroke = 0x333A44, stroke_soft = 0x262B33, stroke_hi = 0x47505C,
        selected = 0x2C3542, pressed = 0x2A303A,
        rose_deep = 0xE06472, green_deep = 0x35B080,
        dialog = 0x1A1E24, on_amber = 0x0A1830,
        bubble_user = 0x3A5FA8, avatar_text = 0xC6D2E0,
        dev1 = 0x2A313C, dev2 = 0x15181D,
        blob_pink = 0x15181D, scrim = 0x0A0C10,
        divider = 0x333A44,
        track = 0x2A303A, track_hi = 0x39414D, input_bg = 0x1C212A,
        knob = 0xF2F5F9, knob_off = 0xAEB7C3,
        qr_dark = 0x0F1216, qr_light = 0xFFFFFF,
    },
    opa = OPA_SOLID_DARK,
    swatch = { bg = 0x15181D, card = 0x212630, accent = 0x6EA8FE, text = 0xEDF0F4 },
})

-- 注册完成后恢复用户上次选择的主题（首次启动回落默认）
theme.restore()

return theme
