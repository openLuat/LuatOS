--[[
@module  ui_theme_themes
@summary 内置主题预设（注册进 ui_theme 的主题表）
@version 3.0
@date    2026.09.17
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

=== v3 设计原则：按「明度档 × 色相」两维铺开 ===
v1 的 9 套主题病根是「底的明度过于集中」——浅色 3 套底色全落在 0xE9~0xF5，
深色 6 套全落在 0x00~0x15，中间明度整档空白。于是用户在设置页看到的是
「同一块黑板换了个强调色」，实测最接近的一对（森林 ↔ 曜石）均 ΔE 仅 8.7。

v2 收敛为 8 套、按三段明度铺开；v3 再补「科技蓝 / 活力橙」两套高饱和中间调，
同时淘汰辨识度最弱的「暮色蓝灰」（去饱和的灰蓝，与新科技蓝同族同档），总数回到 9 套：

  浅色档（bg 0xE4~0xF8，深色文字，实底不透明卡）
    1 dawn     晨曦浅色   冷·蓝白   琥珀强调（默认，底色偏冷拉开与 linen 的距离）
    2 linen    暖阳米色   暖·米黄   赭橙强调
    3 jade     青瓷清露   自然·青绿 松绿强调
  中间档（bg 0x1E~0x8A，浅色文字，实底不透明卡）——v1 完全没有这一档
    4 techblue 科技蓝     冷·宝蓝   电光蓝强调
    5 vivid    活力橙     暖·橙     活力橙强调
    6 clay     陶土暖棕   暖·陶棕   陶橙强调
  深色档（bg 0x00~0x0E，浅色文字）
    7 amber    琥珀夜空   深色玻璃  琥珀强调
    8 forest   青竹幽谷   深色玻璃  竹青强调
    9 obsidian 曜石纯黑   深色实底  薄荷强调

新增主题时请守住两条硬约束，否则会退化成「雷同」：
  · 与同档位其他主题的底色应有可辨差异（各档位内底色 ΔE ≥ 8）
  · 正文色对底色对比度 ≥ 4.5、强调色与弱文字 ≥ 3.0（浅色档尤其容易踩线）

=== 三类外观（style 决定）===
  wallpaper = true   深色玻璃：底色 + 顶部渐隐，卡片半透明白（opa≈26）
  wallpaper = false  平铺实底：整屏单色，卡片不透明（opa=255）

v3 起壁纸不再画「四角光斑」（原先 M.wallpaper 里那四个大圆球）——
AirUI 没有径向渐变能力，光斑只是「超大圆角方块」的近似，实机上更像四块贴上去的色斑。
现在深色玻璃只剩「底色 + 顶部渐隐」这条真渐变。

浅色主题与「实底」主题都必须 wallpaper = false：AirUI 的描边不支持透明度，
浅底上 26 透明度的白卡和 8% 白描边都不可见，玻璃语言在这些配色里会整体消失。
这也是为什么浅色 / 实底主题要把 opa 整体提到 200+，并靠实色描边补回层次。
中间档（techblue / vivid / clay）同样走实底 —— 玻璃的半透明白在中明度底上只会糊成一片灰。

=== 关于左栏（rail）底色：rail_bg ===
idle_win 的左栏底色不再借用 theme.C.white，而是读 theme.C.rail_bg。
v1 的 bug 就出在这里：深色实底主题把 OPA.rail 提到 255 却仍用白色，
「曜石纯黑」下整条左栏是一道刺眼的纯白，且它与「石板石墨」的左栏 100% 相同。
现在每套主题都显式给出 rail_bg：
  · 浅色档：近白（左栏在浅底上本来就该是白面板，靠 0xFC~0xF4 的微色偏区分）
  · 中间档 / 深色实底：与 bg 同族、略暗一档的深色（与内容区拉开层次）
  · 深色玻璃：带本主题色相的半透明白 + OPA.rail（半透明，让底色与主题色一起透出来）

=== 关于「主强调色」写在 amber 槽位 ===
历史原因，全工程的主强调色都引用 theme.C.amber。主题切换时把强调色写回该槽位，
所有既有页面（含尚未改造的 wifi / 设置子页）会自动跟着换色；新代码建议用
theme.C.primary / primary_light / primary_deep / on_primary 表达语义。

=== 关于 desc 里的分隔符（踩过的坑）===
固件内置字库（hzfont）不含中点符号(U+00B7)，设置页面上会渲染成方框。
行内分隔一律用 ASCII 的 "|"，或直接画 1px 竖线容器。
]]

local theme = require "ui_theme"

--[[浅色档共用的透明度档位：
卡片与控件都要「实」，否则浅底上会糊成一片；分隔线用实色（255）。
rail_active 比深色档高一档 —— 浅色左栏是白底，琥珀块要更实才压得住。]]
local OPA_SOLID_LIGHT = {
    glass = 235, glass_hi = 250, glass_soft = 200,
    rail = 220, rail_active = 96, dock = 240,
    stroke = 255, stroke_hi = 255,
    fill = 235, fill_hi = 245,
    scrim = 150, off = 200, divider = 255,
}

--[[中间档 + 深色实底共用：
glass = 255 让卡片完全不透明；fill 也是 255，配合把 surface 改成「卡片色」，
iconbtn / chip / 列表行的填充就是实色卡片色，而不是刺眼的白块。]]
local OPA_SOLID_DARK = {
    glass = 255, glass_hi = 255, glass_soft = 255,
    rail = 255, rail_active = 64, dock = 255,
    stroke = 255, stroke_hi = 255,
    fill = 255, fill_hi = 255,
    scrim = 170, off = 255, divider = 255,
}

--[[深色玻璃共用：只覆写 rail 与 divider
rail 从基线的 14 提到 40（约 16%）—— 14 / 26 对底色的贡献都太小，
换上任何主题左栏看着都一样（用户报「琥珀夜空和青竹幽谷左栏没改变」）。
40 仍然透明到能让底色透上来，但左栏已经是一块可辨认的导航面板；
「是哪一套主题」则由各主题自己的 rail_bg 色相承担（见下面两套玻璃主题）。]]
local OPA_GLASS = { divider = 16, rail = 40 }

-- ==================== 1. 晨曦浅色（默认主题） ====================
--[[浅色主题走「不透明卡 + 实描边」而不是玻璃：AirUI 的描边不支持透明度，
-- 浅底上 26 透明度的白卡与 8% 白描边都不可见，玻璃语言在浅色下会整体消失。
-- 所以这里把 surface 保持为白、把 OPA 整体提到 200+，并用浅灰描边补回层次。]]
theme.register({
    id = "dawn",
    name = "晨曦浅色",
    desc = "冷调浅白 | 琥珀强调（默认）",
    order = 1,
    style = { wallpaper = false, dark = false },
    colors = {
        bg = 0xEAF0F8, bg_top = 0xF7FBFF,
        panel = 0xFFFFFF, panel_hi = 0xF1F5FA, line_soft = 0xD3DCE8,
        surface = 0xFFFFFF, line = 0x1B2430,
        -- t3 是「弱文字」档，也用在左栏应用名上。v1 的 0x8A97A8 对浅底只有 2.6:1，
        -- 低于 3:1 下限，看上去发灰发虚；压到 0x76869A 后是 3.4:1。
        t1 = 0x1B2430, t2 = 0x55637A, t3 = 0x76869A,
        -- 白底上琥珀必须压深才够对比：实测 0xE08A18 对浅底仅 2.4:1（低于 2.5 下限），
        -- 0xB86E08 可到 3.5:1；primary_light 是「强调文字色」，浅色主题下要更深而非更浅
        amber = 0xB86E08, amber_light = 0x8A5200, amber_deep = 0xA35F06,
        cyan = 0x1E6E96, cyan_light = 0x14536F,
        green = 0x1E7A56, green_light = 0x166043,
        violet = 0x6D4FD1, violet_light = 0x5138A8,
        rose = 0xD6455C, rose_light = 0xB03349,
        stroke = 0xD3DCE8, stroke_soft = 0xE2E8F1, stroke_hi = 0xAEBECD,
        selected = 0xDCE9F8, pressed = 0xE7EDF5,
        rose_deep = 0xC23A50, green_deep = 0x178057,
        dialog = 0xFFFFFF, on_amber = 0xFFFFFF,
        bubble_user = 0x3E6FD6, avatar_text = 0x2E4560,
        dev1 = 0xD9E3F0, dev2 = 0xC6D3E3,
        scrim = 0x2A3542,
        divider = 0xD3DCE8,
        -- 浅色下轨道要「比底更深」才看得见；滑块反过来要够白，关闭态则压深到能在轨道上分辨
        -- input_bg 不能用纯白：浅色主题的卡片本身就是白色（surface 0xFFFFFF + opa 235），
        -- 白底输入框会完全「消失」。用带蓝的浅灰拉开一档。
        track = 0xD3DCE8, track_hi = 0xBFCBD9, input_bg = 0xE9EFF7,
        knob = 0xFFFFFF, knob_off = 0x9AA6B5,
        -- 二维码在浅底上要「深模块 + 纯白底」才够对比
        qr_dark = 0x1B2430, qr_light = 0xFFFFFF,
        rail_bg = 0xFFFFFF,
    },
    opa = OPA_SOLID_LIGHT,
    swatch = { bg = 0xEAF0F8, card = 0xFFFFFF, accent = 0xB86E08, text = 0x1B2430 },
})

-- ==================== 2. 暖阳米色（浅色暖调） ====================
--[[米白纸感：底色带一点暖黄，卡片仍是白，强调色用赭橙。
-- 浅色主题的强调色一律「压深」——理由同 dawn：浅底上高饱和亮色对比度不够。]]
theme.register({
    id = "linen",
    name = "暖阳米色",
    desc = "暖调米黄 | 赭橙强调",
    order = 2,
    style = { wallpaper = false, dark = false },
    colors = {
        bg = 0xF8F0E2, bg_top = 0xFEFAF2,
        panel = 0xFFFFFF, panel_hi = 0xF6F1E8, line_soft = 0xDCD3C4,
        surface = 0xFFFFFF, line = 0x30271C,
        t1 = 0x2E2418, t2 = 0x6A5D4E, t3 = 0x8A7C68,
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
        scrim = 0x2E2418,
        divider = 0xDCD3C4,
        track = 0xDCD3C4, track_hi = 0xC9BEA9, input_bg = 0xEFE8DB,
        knob = 0xFFFFFF, knob_off = 0xA99B85,
        qr_dark = 0x2E2418, qr_light = 0xFFFFFF,
        -- 比 dawn 的白稍暖一档：浅色档内左栏底色差异只能做到这个量级，
        -- 真正拉开辨识度的是品牌块 / 选中块的强调色（见文件头）。
        rail_bg = 0xFCF7EF,
    },
    opa = OPA_SOLID_LIGHT,
    swatch = { bg = 0xF8F0E2, card = 0xFFFFFF, accent = 0x9C4F17, text = 0x2E2418 },
})

-- ==================== 3. 青瓷清露（浅色自然调） ====================
--[[v2 新增。青瓷釉面的清透青绿，强调色是松绿。
-- 浅色档里唯一一支偏绿的，用于和 dawn（蓝白）/ linen（米黄）拉开色相。]]
theme.register({
    id = "jade",
    name = "青瓷清露",
    desc = "清透青绿 | 松绿强调",
    order = 3,
    style = { wallpaper = false, dark = false },
    colors = {
        bg = 0xE4F2E8, bg_top = 0xF3FBF6,
        panel = 0xFFFFFF, panel_hi = 0xEFF6F1, line_soft = 0xC7D8CD,
        surface = 0xFFFFFF, line = 0x15261C,
        t1 = 0x15261C, t2 = 0x4C6355, t3 = 0x6F8677,
        amber = 0x1F7A55, amber_light = 0x135536, amber_deep = 0x1A6647,
        cyan = 0x146E7A, cyan_light = 0x0E5560,
        green = 0x2F7D4F, green_light = 0x246040,
        violet = 0x5E4AB0, violet_light = 0x48378A,
        rose = 0xC04358, rose_light = 0xA23447,
        stroke = 0xC7D8CD, stroke_soft = 0xDCE9E0, stroke_hi = 0xA3BCAC,
        selected = 0xD4E8DC, pressed = 0xE4F0E8,
        rose_deep = 0xA8394C, green_deep = 0x246040,
        dialog = 0xFFFFFF, on_amber = 0xFFFFFF,
        bubble_user = 0x3A7C74, avatar_text = 0x2C4438,
        dev1 = 0xD6E6DC, dev2 = 0xC2D6C9,
        scrim = 0x15261C,
        divider = 0xC7D8CD,
        track = 0xC7D8CD, track_hi = 0xB2C8B9, input_bg = 0xE2EFE7,
        knob = 0xFFFFFF, knob_off = 0x94A899,
        qr_dark = 0x15261C, qr_light = 0xFFFFFF,
        rail_bg = 0xF4FAF6,
    },
    opa = OPA_SOLID_LIGHT,
    swatch = { bg = 0xE4F2E8, card = 0xFFFFFF, accent = 0x1F7A55, text = 0x15261C },
})

-- ==================== 4. 科技蓝（中间明度 · 冷 · 高饱和） ====================
--[[v3 新增，顶掉 v2 的「暮色蓝灰」。

暮色蓝灰是一块去饱和的灰蓝板 —— 不难看，但也记不住；而且它和本套同族同档，
两套并排就是「同一个蓝色板调了点灰度」。本套把饱和度拉满：底色是明确的宝蓝，
强调色是电光蓝，配浅色文字，是整组里最「数码」的一套。

中间明度必须走实底（wallpaper = false）—— 玻璃的半透明白在中明度底上只会变成脏灰。
本套也不画任何光斑：AirUI 没有径向渐变能力，光斑只是「超大圆角方块」的近似，
叠在实色板上只会更脏（v3 已全局取消壁纸光斑）。]]
theme.register({
    id = "techblue",
    name = "科技蓝",
    desc = "深邃宝蓝 | 电光蓝强调",
    order = 4,
    style = { wallpaper = false, dark = true },
    colors = {
        bg = 0x1E3E74, bg_top = 0x264A85,
        panel = 0x2B4E86, panel_hi = 0x365D9C, line_soft = 0x4A73AC,
        surface = 0x2B4E86, line = 0xFFFFFF,
        t1 = 0xEAF1FB, t2 = 0xAFBFD8, t3 = 0x92A6C4,
        amber = 0x4FA3FF, amber_light = 0x93C7FF, amber_deep = 0x2B7FE0,
        cyan = 0x4FE0E8, cyan_light = 0xA5F0F5,
        green = 0x5FE0A8, green_light = 0xAFF0CE,
        violet = 0xA98BFA, violet_light = 0xE4DAFF,
        rose = 0xFF8A9A, rose_light = 0xFFB8C2,
        stroke = 0x4A73AC, stroke_soft = 0x365D9C, stroke_hi = 0x5F8CC6,
        selected = 0x365D9C, pressed = 0x31548E,
        rose_deep = 0xE0607A, green_deep = 0x3FB888,
        dialog = 0x1B3358, on_amber = 0x06182E,
        bubble_user = 0x2E63A8, avatar_text = 0xCFE0F5,
        dev1 = 0x365D9C, dev2 = 0x14284D,
        scrim = 0x0C1830,
        divider = 0xFFFFFF,
        track = 0x14284D, track_hi = 0x22437D, input_bg = 0x14284D,
        knob = 0xEDF4FF, knob_off = 0x8FA3C0,
        qr_dark = 0x0C1830, qr_light = 0xFFFFFF,
        rail_bg = 0x14284D,
    },
    opa = OPA_SOLID_DARK,
    swatch = { bg = 0x1E3E74, card = 0x2B4E86, accent = 0x4FA3FF, text = 0xEAF1FB },
})

-- ==================== 5. 活力橙（中间明度 · 暖 · 高饱和） ====================
--[[v3 新增。与「陶土暖棕」同档同色温，但饱和度是两个量级 ——
陶土暖棕是一块灰扑扑的陶土，本套是一块实打实的橙：
底色 0x8A4A18 明确偏亮一档，配上亮橙强调，看着就有「电量满格」的意思。

暖色 + 中明度最容易糊，所以卡片 / 输入框 / 轨道都往深橙里走（0x5E2F0C），
靠「亮底 + 深控件」拉开层次，而不是靠白色半透明层。]]
theme.register({
    id = "vivid",
    name = "活力橙",
    desc = "饱和橙调 | 活力橙强调",
    order = 5,
    style = { wallpaper = false, dark = true },
    colors = {
        bg = 0x8A4A18, bg_top = 0x9A5622,
        panel = 0x9A5722, panel_hi = 0xAB6529, line_soft = 0xBC7534,
        surface = 0x9A5722, line = 0xFFFFFF,
        t1 = 0xFFF3E6, t2 = 0xF0CDA8, t3 = 0xDCAE82,
        amber = 0xFFB454, amber_light = 0xFFD08F, amber_deep = 0xE08A2C,
        cyan = 0x6BD8E0, cyan_light = 0xAFEFF2,
        green = 0x7FD88C, green_light = 0xBEEBBE,
        violet = 0xCBA0F5, violet_light = 0xEAD8FF,
        rose = 0xFF9AA0, rose_light = 0xFFC6C6,
        stroke = 0xBC7534, stroke_soft = 0xAB6529, stroke_hi = 0xCC8C4A,
        selected = 0xAB6529, pressed = 0xA25C25,
        rose_deep = 0xE0707A, green_deep = 0x5FB46C,
        dialog = 0x7A3F14, on_amber = 0x2E1404,
        bubble_user = 0xA85E22, avatar_text = 0xF7E3CC,
        dev1 = 0xAB6529, dev2 = 0x5E2F0C,
        scrim = 0x2E1404,
        divider = 0xFFFFFF,
        track = 0x5E2F0C, track_hi = 0x77400F, input_bg = 0x5E2F0C,
        knob = 0xFFF4E8, knob_off = 0xC09A78,
        qr_dark = 0x2E1404, qr_light = 0xFFFFFF,
        rail_bg = 0x5E2F0C,
    },
    opa = OPA_SOLID_DARK,
    swatch = { bg = 0x8A4A18, card = 0x9A5722, accent = 0xFFB454, text = 0xFFF3E6 },
})

-- ==================== 6. 陶土暖棕（中间明度 · 暖） ====================
--[[v2 新增。与 techblue / vivid 同一个明度档，但色温相反 —— 棕灰底 + 陶橙强调。
-- 中明度 + 暖色这个组合在 UI 里少见，是这套主题最容易被记住的地方。]]
theme.register({
    id = "clay",
    name = "陶土暖棕",
    desc = "陶土暖棕 | 陶橙强调",
    order = 6,
    style = { wallpaper = false, dark = true },
    colors = {
        bg = 0x4A3E36, bg_top = 0x53463D,
        panel = 0x574A40, panel_hi = 0x615348, line_soft = 0x6E5F53,
        surface = 0x574A40, line = 0xFFFFFF,
        t1 = 0xFAF4EE, t2 = 0xD6C7B9, t3 = 0xB5A396,
        amber = 0xF0A46A, amber_light = 0xFFC79A, amber_deep = 0xC87E44,
        cyan = 0x7ED0D8, cyan_light = 0xB3E6EA,
        green = 0x9AD68C, green_light = 0xC6E9BC,
        violet = 0xC4A0F0, violet_light = 0xE6D6FA,
        rose = 0xFF9AA0, rose_light = 0xFFC0C4,
        stroke = 0x6E5F53, stroke_soft = 0x615348, stroke_hi = 0x877668,
        selected = 0x5E4E42, pressed = 0x615348,
        rose_deep = 0xE0767C, green_deep = 0x78B46C,
        dialog = 0x4F4238, on_amber = 0x2E1706,
        bubble_user = 0x8A6448, avatar_text = 0xE6D8CA,
        dev1 = 0x5E5046, dev2 = 0x3E342D,
        scrim = 0x241D18,
        divider = 0xFFFFFF,
        track = 0x3E342D, track_hi = 0x4E4238, input_bg = 0x3E342D,
        knob = 0xFBF6F0, knob_off = 0xA7998C,
        qr_dark = 0x241D18, qr_light = 0xFFFFFF,
        rail_bg = 0x3E342D,
    },
    opa = OPA_SOLID_DARK,
    swatch = { bg = 0x4A3E36, card = 0x574A40, accent = 0xF0A46A, text = 0xFAF4EE },
})

-- ==================== 7. 琥珀夜空（深色玻璃 · 暖） ====================
-- 深色玻璃 + 琥珀强调，与 1024×600 设计稿一致。不覆写任何键即基线本身，
-- 但仍显式列出关键色，便于作为新增主题的抄写模板。
theme.register({
    id = "amber",
    name = "琥珀夜空",
    desc = "深色玻璃 | 琥珀强调",
    order = 7,
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
        scrim = 0x0E141C,
        divider = 0xFFFFFF,
        -- 轨道 / 输入框 / 滑块（见 ui_theme 的 M.bar / M.input / M.slider / M.toggle）
        track = 0x2C3542, track_hi = 0x3A4655, input_bg = 0x1B2431,
        knob = 0xF2F6FA, knob_off = 0xB9C4D0,
        --[[玻璃档左栏 = 半透明色 + OPA.rail（40），底下的桌面光斑要透上来。

        这里不能用纯白：琥珀夜空与青竹幽谷（另一套玻璃）都会渲染成一模一样的左栏，
        用户在主题页来回切这两套时看到的就是「左栏没变化」。
        给每套玻璃一个带本主题色相的半透明白：本套是暖琥珀色。]]
        rail_bg = 0xFFD9A0,
    },
    opa = OPA_GLASS,
    swatch = { bg = 0x0D131C, card = 0x18202C, accent = 0xFFB454, text = 0xEDF1F7 },
})

-- ==================== 8. 青竹幽谷（深色玻璃 · 自然） ====================
--[[v1 的底色是 0x0A1512 —— 太暗，暗到和「曜石纯黑」几乎分不出来
--（实测两者的底色 ΔE 只有 7.4，是全部 36 对里最接近的一对）。
-- v2 把绿调提上来：bg 0x0E2619，左栏 / 面板 / 描边同步跟着绿走，
-- 现在它是一眼能认出的「墨绿」，而不是「另一种黑」。]]
theme.register({
    id = "forest",
    name = "青竹幽谷",
    desc = "墨绿暗调 | 竹青强调",
    order = 8,
    style = { wallpaper = true, dark = true },
    colors = {
        bg = 0x0E2619, bg_top = 0x13301F,
        panel = 0x173A26, panel_hi = 0x1E4832, line_soft = 0x2E5540,
        surface = 0xFFFFFF, line = 0xFFFFFF,
        t1 = 0xE9F5F0, t2 = 0x94B3A4, t3 = 0x6B8F7C,
        amber = 0x4FD69C, amber_light = 0xA8E8CB, amber_deep = 0x33A874,
        cyan = 0x5CD6D6, cyan_light = 0x9EEAEA,
        green = 0x4FD69C, green_light = 0xA8E8CB,
        violet = 0x9BB8FA, violet_light = 0xE0E8FF,
        rose = 0xFF8A8A, rose_light = 0xFFB4B4,
        stroke = 0x2A4A38, stroke_soft = 0x1E3A2B, stroke_hi = 0x3E6A52,
        selected = 0x1F4432, pressed = 0x1E3A2B,
        rose_deep = 0xE06A6A, green_deep = 0x33A874,
        dialog = 0x0F2A1C, on_amber = 0x06231A,
        bubble_user = 0x2E6B55, avatar_text = 0xBCE4D4,
        dev1 = 0x28463A, dev2 = 0x0E2619,
        scrim = 0x081710,
        divider = 0xFFFFFF,
        track = 0x20402F, track_hi = 0x2E5540, input_bg = 0x16321F,
        knob = 0xEEF7F2, knob_off = 0xAEC7BB,
        qr_dark = 0x081710, qr_light = 0xFFFFFF,
        -- 同琥珀夜空：换成带竹青绿相的半透明白，否则两套玻璃主题的左栏长得一样
        rail_bg = 0xBFF2DA,
    },
    opa = OPA_GLASS,
    swatch = { bg = 0x0E2619, card = 0x173A26, accent = 0x4FD69C, text = 0xE9F5F0 },
})

-- ==================== 9. 曜石纯黑（深色实底 · 冷） ====================
--[[OLED 友好：底色纯黑、卡片实心深灰，没有任何光斑与半透明层。
-- 和玻璃主题的区别一眼可见 —— 屏幕不再是「有层次的暗」，而是「一块块实板」。

⚠ v1 的 bug 就在这套：OPA_SOLID_DARK.rail = 255 配 theme.C.white，
  左栏被画成纯白（与「石板石墨」完全相同的一条白栏）。
  rail_bg 收口后是 0x0C0F13 —— 比纯黑略亮一档的面板。]]
theme.register({
    id = "obsidian",
    name = "曜石纯黑",
    desc = "纯黑实底 | 薄荷强调",
    order = 9,
    style = { wallpaper = false, dark = true },
    colors = {
        bg = 0x000000, bg_top = 0x07090C,
        panel = 0x121417, panel_hi = 0x1A1D21, line_soft = 0x2C3036,
        surface = 0x16191D, line = 0xFFFFFF,
        t1 = 0xF2F4F6, t2 = 0x9BA2AB, t3 = 0x7A828C,
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
        scrim = 0x000000,
        divider = 0x2A2E34,
        track = 0x22262B, track_hi = 0x2E343A, input_bg = 0x14171A,
        knob = 0xFFFFFF, knob_off = 0x9AA1AA,
        qr_dark = 0x000000, qr_light = 0xFFFFFF,
        rail_bg = 0x0C0F13,
    },
    opa = OPA_SOLID_DARK,
    swatch = { bg = 0x000000, card = 0x16191D, accent = 0x5EE6A8, text = 0xF2F4F6 },
})

-- 注册完成后恢复用户上次选择的主题（首次启动回落默认）
theme.restore()

return theme
