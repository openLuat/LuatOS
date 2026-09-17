--[[
@module  ui_theme
@summary TabOS 深色玻璃态设计系统 —— 设计令牌 + 组件工厂（供全部 UI 页面复用）
@version 1.3
@date    2026.09.16
@author  江访

=== 设计来源 ===
样式取自 tablet-smart-home（1024×600 平板 OS 设计稿）：
深色底 #080B10 + 半透明白玻璃卡片 + 琥珀/青/紫/绿点缀色 + 大圆角。

=== 用法 ===
local theme = require "ui_theme"
local base = theme.wallpaper(airui.screen, screen_w, screen_h)   -- 全屏背景
local bar  = theme.glass(base, { x = 0, y = 0, w = 300, h = 96 }) -- 玻璃卡片
theme.label(base, { x = 8, y = 8, w = 100, h = 20, text = "标题", size = 16, color = theme.C.t2 })

=== 关键设计决策 ===
1. 尺寸契约：几何量（x/y/w/h）一律传「像素值」，由调用方按 screen_w/screen_h 计算；
   「字号 size」与「圆角 radius」传「逻辑值」，由 theme 内部按 _G.density_scale 换算。
   需要直接指定像素字号时用 px_size（如大号时钟）。
2. 无模糊/阴影能力（AirUI 基于 LVGL 基础样式），玻璃感用「低透明度白底 + 细描边」近似；
   背景只有「底色 + 顶部渐隐」，v3 起已去掉原先近似径向渐变的那四个光斑球
3. 每个构造函数都返回创建的 airui 对象，便于调用方继续 set_text / set_src
4. 图标按语义名查找 /luadb/ui/<name>.png，缺失时自动回退旧资源或跳过绘制
]]

local M = {}

-- ==================== 一、设计令牌 ====================

-- 颜色（0xRRGGBB）
M.C = {
    bg          = 0x0D131C,  -- 页面底色
    bg_top      = 0x121A26,  -- 顶部微亮层
    panel       = 0x18202C,  -- 深色面板（不透明卡片，供旧页面调色板复用）
    panel_hi    = 0x202A38,  -- 面板高亮层（弹窗标题栏）
    line_soft   = 0x39434F,  -- 面板分隔线
    surface     = 0xFFFFFF,  -- 玻璃底（配合低透明度）
    line        = 0xFFFFFF,  -- 描边
    t1          = 0xEDF1F7,  -- 主文字
    t2          = 0x95A0AE,  -- 次级文字
    t3          = 0x5E6978,  -- 弱文字
    amber       = 0xFFB454,  -- 主强调色（琥珀）
    amber_light = 0xFFCB7E,
    amber_deep  = 0xF08838,
    cyan        = 0x5CC9E8,
    cyan_light  = 0x9BE4F7,
    green       = 0x4FD69C,
    green_light = 0xA8E8CB,
    violet      = 0xA78BFA,
    violet_light = 0xE9E3FF,
    rose        = 0xFF7B8B,
    rose_light  = 0xFFA4B0,
    dev1        = 0x2B3A4E,  -- 设备基底色（头像）
    dev2        = 0x16202C,
    knob        = 0x101A22,  -- 开关滑块（开启态）
    white       = 0xFFFFFF,
    black       = 0x000000,

    -- ===== 描边 =====
    -- AirUI 的 border 不支持透明度，玻璃描边只能用实色近似。
    -- 全工程统一到下面三档，不要再新增描边色值（原来各页面 0x3A4552 / 0x333C4A /
    -- 0x39424F / 0x3A4351 四种混用，视觉上几乎无法区分却导致改不干净）。
    stroke      = 0x333C4A,  -- 卡片 / 控件常规描边
    stroke_soft = 0x2A3240,  -- 弱描边：分隔线、内嵌小色块
    stroke_hi   = 0x4A5666,  -- 高亮描边：悬停 / 聚焦

    -- ===== 交互态 =====
    selected    = 0x25344A,  -- 列表行选中底色
    pressed     = 0x2A3240,  -- 按压态底色

    -- ===== 遮罩 =====
    scrim       = 0x0E141C,  -- 弹窗遮罩（配合 M.OPA.scrim 使用）

    -- ===== 深色变体（按钮按压态专用）=====
    -- 按下时用「同语义色的加深版」，而不是另找一个近似色
    rose_deep   = 0xE05A6B,  -- danger 按压态
    green_deep  = 0x35B080,  -- success 按压态

    -- ===== 组件专用 =====
    dialog      = 0x121821,  -- 弹窗主体底色（比 C.bg 略亮、比 C.panel 暗）
    on_amber    = 0x1A1206,  -- 琥珀主色按钮上的文字/图标色（深棕，保证对比度）
    bubble_user = 0x3D4E9E,  -- 用户侧气泡底（LLM 对话）
    avatar_text = 0xC3D6E8,  -- 头像首字母文字色
    divider     = 0xFFFFFF,  -- 分隔线（深色主题靠 OPA.divider 压淡；浅色主题换成实色）

    -- ===== 进度/开关/输入框专用 =====
    -- 以前这几处各页面直接写 CLR.line_soft（0x39434F），在深底上是一条突兀的「灰色长条」，
    -- 浅色主题下更是完全看不出来。收口成令牌后由主题统一决定。
    track       = 0x2C3542,  -- 进度条/滑条轨道底（比 stroke_soft 更暗、更沉）
    track_hi    = 0x3A4655,  -- 轨道高亮态（滑条已填充部分之外的强调）
    input_bg    = 0x1B2431,  -- 输入框底色（浅色主题会覆写成白）
    knob        = 0xFFFFFF,  -- 开关/滑条滑块
    knob_off    = 0xC9D2DC,  -- 开关关闭态滑块（浅一点，压在暗轨道上才看得见）

    -- ===== 二维码专用 =====
    -- 二维码靠「深模块 + 浅底」的绝对明暗对比才扫得出来，不能跟着 t1 / scrim 走：
    -- 浅色主题下 t1 是深色正文色，拿它当 light_color 会让整张码糊成一个色块。
    qr_dark     = 0x0E141C,  -- 深色模块
    qr_light    = 0xEDF1F7,  -- 浅色底（静区）

    -- ===== 左栏（rail）=====
    -- 左栏底色**不能借用 white**：全工程 8 套主题里没有一套覆写 white，而 OPA.rail
    -- 只有 14 / 220 / 255 三档，于是左栏只剩三种外观 —— 同一档内的主题左栏完全相同。
    -- 更糟的是深色实底主题把 rail 提到 255 后，左栏被画成一条纯白（在纯黑桌面上极刺眼）。
    -- 现在由每套主题各自给出 rail_bg，左栏才真正跟着主题走。
    rail_bg     = 0xFFFFFF,
}

--[[语义色别名
业务页面应表达「语义」而不是「色值」：用 theme.SEM.danger，不要硬编码 0xE63946。
历史上 wifi/file_manager/settings 各写各的近似色（0xE63946、0xC62828、0xB71C1C
都表示"危险"，0x4CAF50、0x34C759、0x2DA94F 都表示"成功"），这里统一收口。]]
M.SEM = {
    danger  = M.C.rose,    -- 危险 / 删除 / 断开
    success = M.C.green,   -- 成功 / 已连接 / 在线
    warning = M.C.amber,   -- 警告 / 进行中
    info    = M.C.cyan,    -- 信息 / 提示
    link    = M.C.cyan,    -- 可点击链接
    accent  = M.C.violet,  -- 次级强调（分类、标签）
}

-- 透明度（0-255）
M.OPA = {
    glass       = 26,   -- 玻璃卡片（白 ~10%，实机上才看得清）
    glass_hi    = 36,   -- 玻璃悬停/可选
    glass_soft  = 18,   -- 更淡的玻璃
    rail        = 14,   -- 侧栏底
    dock        = 30,   -- 底部 Dock
    stroke      = 22,   -- 描边
    stroke_hi   = 42,   -- 高亮描边
    fill        = 20,   -- 内嵌小色块
    fill_hi     = 30,
    scrim       = 140,  -- 遮罩
    off         = 26,   -- 关闭态元素
    divider     = 16,   -- 分隔线（深色主题：白线 16 透明度）
    -- 左栏选中态底块。浅色主题的左栏是白底，琥珀块要更实一档才压得住
    -- （见 ui_theme_themes.lua 的 OPA_SOLID_LIGHT.rail_active = 96）。
    rail_active = 48,
}

-- 圆角（逻辑值，经 dp 缩放）
M.R = {
    xl = 22, lg = 18, md = 14, sm = 10, xs = 8,
}

--[[字号（逻辑值，旧接口）
经 dp() 缩放并夹到 M.FONT_MIN 下限。新代码建议改用 M.FS 档位 + M.fs()。]]
M.F = {
    hero = 46, h1 = 21, h2 = 17, h3 = 15, body = 13, small = 11.5, tiny = 10.5,
}

--[[逻辑字号的最小像素下限
固件内置点阵字库对字号有物理限制（低分屏 14 / 高分屏 16 起才清晰），低于该值
渲染会糊成一团或直接失败，所以逻辑字号一律夹到这个下限。
确实需要更小字号时，用 theme.label 的 px_size 显式传像素值 —— px_size 不受此下限约束。]]
M.FONT_MIN = 16

--[[像素字号档位：乘密度前的基准值（@density=1.0 时的 px）
刻意收敛到 8 档 —— 写页面时按语义选档，不要临时拍数值，
否则全工程会像改动前那样散成十几个近似档（20/22/24/26 混用，肉眼几乎分不出）。
  display 页面主标题     h1 大标题          h2 区块标题       h3 小标题 / 按钮
  body    正文 / 列表标题  label 标签 / 次要   caption 注释      micro 极弱信息]]
M.FS = {
    display = 32, h1 = 28, h2 = 22, h3 = 20,
    body = 18, label = 16, caption = 14, micro = 12,
}

-- ==================== 一.5、字体能力约束（新增文案前必读） ====================
--[[固件内置字库（hzfont，覆盖 Air1602 / Air1780H / Air8301 / Air8000W 等多数平台）
的符号区极窄，不含下列字形，渲染出来是空白或方框：
    ·  U+00B7 中缀点     ●  U+25CF 实心圆     •  U+2022 项目符号
    ↓  U+2193 下箭头     °  U+00B0 度符号     ← → ↑ 等箭头
已确认可用：℃(U+2103)、× (U+00D7)、ASCII 全量、汉字。
只有 Air8101 系列走外部 TTF（/MiSans_gb2312.ttf），字符集更宽。

因此写界面文案时：
  - 行内分隔用 "|"（ASCII），或直接画 1px 竖线容器 —— 不要用 "·"
  - 温度单位写 "℃" —— 不要写 "°C"
  - 状态圆点用 M.box 画实心圆（radius = 直径）—— 不要用 "●"
  - 图标缺失兜底用汉字首字或 "-" —— 不要用 "•"
需要跨平台统一的符号，统一引用下面的 M.CHAR。]]
M.CHAR = {
    deg = "℃",   -- 温度单位
    sep = "|",   -- 行内分隔
}

-- 语义图标名 → 资源路径（新增图标按此命名，放入 res/ui/*.png）
M.ICON_DIR = "/luadb/"

-- 每个图标的兜底路径（旧工程 res/ 下已有资源，缺失新图标时不至于空白）
M.ICON_FALLBACK = {
    settings   = "/luadb/settings.png",
    app_store  = "/luadb/app_store_icon.png",
    file       = "/luadb/file_manager.png",
    speedtest  = "/luadb/internet_speed.png",
    app_factory = "/luadb/app_factory.png",
    ai_chat    = "/luadb/ai_chat.png",
    search     = "/luadb/search.png",
}

local density = _G.density_scale or 1.0

--[[设计令牌 → 像素：仅用于「字号」与「圆角」等逻辑量，几何量(x/y/w/h)直接传像素]]
local function dp(v)
    local d = _G.density_scale or density
    return math.floor((v or 0) * d + 0.5)
end
M.dp = dp

--[[参数归一化：支持两种调用写法
    M.xxx(parent, { ... })   和   M.xxx({ ... })      -- 后者 parent 落在表里
做成双写是因为 airui.textarea / airui.switch 这些原生组件就是单表写法，
页面里既有 theme.xxx(parent, o) 的老代码，也有照抄原生写法的新代码。]]
local function norm(parent, o)
    if o == nil and type(parent) == "table" then
        return nil, parent
    end
    return parent, o or {}
end

--[[按令牌名取圆角像素值]]
function M.r(name)
    return dp(M.R[name] or M.R.md)
end

--[[按令牌名取字号（旧接口，保留兼容）]]
function M.f(name)
    return math.max(M.FONT_MIN, dp(M.F[name] or M.F.body))
end

--[[按语义档位取像素字号（新接口，推荐）
用法: local fs = theme.fs("body")
      theme.label(parent, { x=.., y=.., w=.., h=fs+2, text="..", px_size=fs })
传数字时等价于 dp(n)，便于从旧的手算写法渐进迁移。]]
function M.fs(tier)
    if type(tier) == "number" then return dp(tier) end
    return dp(M.FS[tier] or M.FS.body)
end

--[[图标路径解析：优先新资源（res/ui/<name>.png），不存在时回退旧资源，都没有则返回 nil]]
local icon_cache = {}
function M.icon(name)
    if name == nil then return nil end
    local cached = icon_cache[name]
    if cached ~= nil then return cached, cached ~= false end
    local path = M.ICON_DIR .. name .. ".png"
    local ok = false
    if io and io.exists then
        -- 注意: pcall 返回 (成功标志, 函数返回值)，必须取第二个才是文件是否存在
        local okc, exists = pcall(io.exists, path)
        ok = (okc == true) and (exists == true)
    end
    if not ok then
        local fb = M.ICON_FALLBACK[name]
        if fb and (fb == path or not (io and io.exists)) then
            path = fb
            ok = true
        elseif fb then
            local okc2, exists2 = pcall(io.exists, fb)
            if okc2 == true and exists2 == true then
                path = fb
                ok = true
            end
        end
    end
    icon_cache[name] = ok and path or false
    if not ok then
        log.warn("ui_theme", "图标缺失(将使用占位或跳过):", name)
    end
    return icon_cache[name], ok
end

--[[判断图标资源是否可用（供调用方决定是否画占位块）]]
function M.has_icon(name)
    return (M.icon(name)) ~= nil
end

-- ==================== 二、基础绘制 ====================

-- ==================== 壳层（Shell）内容区 ====================
--[[宽屏设备上 idle_win 会常驻左侧 rail（内置应用栏），其余页面只应占据右侧内容区。
壳层状态由 idle_win 在布局计算完成后写入；窄屏（无 rail）或 idle_win 尚未创建时保持
enabled = false，此时所有页面回到「整屏铺满」的既有行为 —— 窄屏表现与改造前完全一致。

注意：不要把 rail 宽度之类的布局细节塞进 exwin。exwin 是纯窗口栈库，
UI 几何只属于 ui_theme 的职责范围。]]
M.shell = { enabled = false, rail_w = 0, host_id = nil }

--[[返回内容区几何 { x, y, w, h }；无左栏时返回 nil

返回 nil 即「保持整屏行为」，调用方无需写分支判断。]]
function M.content_area()
    if not M.shell.enabled then return nil end
    local rw = M.shell.rail_w or 0
    local W = screen_w or 480
    local H = screen_h or 800
    if rw <= 0 or (W - rw) < 1 then return nil end
    return { x = rw, y = 0, w = W - rw, h = H }
end

--[[页面尺寸修正：把页面里局部的 screen_w/screen_h 收窄到内容区

用法：在页面 update_screen_size() 末尾追加一行
    screen_w, screen_h = theme.content_fit(screen_w, screen_h)

无壳层时原样返回，页面行为与改造前完全一致。
收窄后，页面内所有基于 screen_w 的比例式几何会自动重新自适应 ——
因为 LVGL 子控件坐标是相对父容器的，而父容器宽度已同步收窄。
注意：调用方必须把这个返回值写回自己的 screen_w（通常是在 update_screen_size 末尾），
theme.page_bg 依赖「页面宽度已等于内容区宽度」这个信号来决定是否做偏移。]]
function M.content_fit(w, h)
    local area = M.content_area()
    if not area then return w, h end
    return area.w, h
end

--[[矩形色块（也是最常用的布局容器）
  clip_corner = true 时，子组件按本容器的圆角裁剪（等价 CSS overflow:hidden）。
  贴边的方形子组件（如视频卡片底部的控制栏）会盖住父容器的圆角，
  在圆角卡片边缘冒出两个方角 —— 这类场景要打开 clip_corner。]]
function M.box(parent, o)
    return airui.container({
        parent     = o.parent or parent,
        x = o.x or 0, y = o.y or 0,
        w = (o.w ~= nil) and o.w or nil,
        h = (o.h ~= nil) and o.h or nil,
        color = o.color,
        color_opacity = o.opa,
        radius = (o.radius ~= nil) and dp(o.radius) or 0,
        border_color = o.border,
        border_width = o.border and (o.border_w or 1) or 0,
        scrollable = (o.scrollable == true),
        clip_corner = (o.clip_corner == true),
        on_click = o.on_click,
        on_long_press = o.on_long_press,
    })
end

--[[全屏背景：底色 + 顶部提亮渐变（近似设计稿的壁纸）

以前顶部提亮是一个 h * 0.62 的「实色容器」，于是在屏幕 62% 高度处横着留下
一条贯穿全屏的硬边 —— 深色主题下 bg_top 与 bg 差着几个色阶，边缘一眼可见。
AirUI 没有渐变能力，这里改用 STEPS 条透明度线性递减的窄条去逼近同一条渐变：
相邻两条的不透明度差约 255/9 = 28 级，折算成实际色差不到 1 个 RGB 单位，
看不出台阶，但硬边被彻底抹掉了。]]
function M.wallpaper(parent, w, h, x, y)
    local base = M.box(parent, { x = x or 0, y = y or 0, w = w, h = h, color = M.C.bg })

    local STEPS = 10
    local zone = math.floor(h * 0.62)
    for i = 1, STEPS do
        local opa = math.floor(255 * (STEPS - i) / (STEPS - 1) + 0.5)
        if opa > 0 then
            local y0 = math.floor(zone * (i - 1) / STEPS)
            local y1 = math.floor(zone * i / STEPS)
            M.box(base, { x = 0, y = y0, w = w, h = y1 - y0 + 1, color = M.C.bg_top, opa = opa })
        end
    end

    return base
end

--[[玻璃卡片：半透明白底 + 细描边（设计稿 .glass / .card）]]
function M.glass(parent, o)
    return M.card(parent, o)
end

--[[玻璃卡片（带描边）：AirUI 描边不支持透明度，用深灰描边近似 8% 白描边]]
function M.card(parent, o)
    local opa = (o.opa ~= nil) and o.opa or M.OPA.glass
    --[[描边宽度三条规则（历史坑：这里以前无条件给 border_width = 1，
    于是「全透明列表行」也被画上一圈 1px 边框，看着就是一排空方框）：
      · 显式传 border_w   -> 听调用方的
      · 显式传 border     -> 1px
      · 完全透明(opacity=0) -> 0（不画）；其余 1px]]
    local bw
    if o.border_w ~= nil then bw = o.border_w
    elseif o.border then bw = 1
    elseif opa == 0 then bw = 0
    else bw = 1 end
    local c = airui.container({
        parent = o.parent or parent,
        x = o.x or 0, y = o.y or 0,
        w = o.w or 0, h = o.h or 0,
        color = o.color or M.C.surface,
        color_opacity = opa,
        radius = dp((o.radius ~= nil) and o.radius or M.R.lg),
        border_color = o.border or M.C.stroke,
        border_width = bw,
        scrollable = (o.scrollable == true),
        --[[子组件按圆角裁剪（等价 CSS overflow:hidden）

        圆角卡片里贴边的方形子组件会用直角盖住卡片圆角，看上去就是
        「卡片边缘冒出两个方角」。传 clip_corner = true 即可让子组件被卡片圆角裁掉。]]
        clip_corner = (o.clip_corner == true),
        on_click = o.on_click,
        on_long_press = o.on_long_press,
    })
    return c
end

--[[文本标签
  size    = 逻辑字号，按密度换算后夹到 M.FONT_MIN 下限（防小字在低分屏上发糊）
  px_size = 已换算好的像素字号，完全按给定值渲染、不受 FONT_MIN 约束
            —— 需要 12~14px 这类小字时走这个参数
注意: 行高 h 请自行给足（建议 fs + 2 以上）。小于字号的 h 会把文字裁掉。]]
function M.label(parent, o)
    local fs
    if o.px_size then
        fs = o.px_size
        if fs < 1 then fs = 1 end
    else
        fs = dp(o.size or M.F.body)
        if fs < M.FONT_MIN then fs = M.FONT_MIN end
    end
    return airui.label({
        parent = o.parent or parent,
        x = o.x or 0, y = o.y or 0,
        w = o.w or 100, h = o.h or (fs + 8),
        text = o.text or "",
        font_size = fs,
        color = o.color or M.C.t1,
        align = o.align or airui.TEXT_ALIGN_LEFT,
        on_click = o.on_click,
        on_long_press = o.on_long_press,
    })
end

--[[按像素字号估算文本宽度

AirUI 的 label 默认是 LV_LABEL_LONG_WRAP（自动换行），而且行高 = 字号 + 3，
所以「给多高的盒子」必须按「会换成几行」来算，否则要么文字被裁、要么盒子被撑破。
估算口径：ASCII 约 0.55 x 字号 / 字符，CJK（UTF-8 三字节）约 1.0 x 字号 / 字符。
只用于布局预留，不追求逐像素精确。]]
function M.text_width(text, px)
    if not text or text == "" then return 0 end
    local n_ascii, n_wide = 0, 0
    for i = 1, #text do
        if string.byte(text, i) < 0x80 then n_ascii = n_ascii + 1 else n_wide = n_wide + 1 end
    end
    n_wide = math.floor(n_wide / 3 + 0.5)      -- UTF-8：汉字占 3 字节
    return math.floor(n_ascii * px * 0.55 + n_wide * px)
end

--[[估算文本在给定宽度内会占几行（至少 1 行）]]
function M.text_lines(text, w, px)
    if not text or text == "" then return 1 end
    if not w or w <= 0 then return 1 end
    local n = math.ceil(M.text_width(text, px) / w)
    if n < 1 then n = 1 end
    return n
end

--[[图标地址解析：以 "/" 开头视为真实路径，否则按语义名查表（含旧资源回退）]]
function M.resolve_icon(v)
    if v == nil or v == "" then return nil end
    if string.sub(v, 1, 1) == "/" then return v end
    return M.icon(v)
end

--[[图片；icon/src 为空或资源缺失时跳过绘制；placeholder=true 时改画占位圆角块]]
function M.image(parent, o)
    local src = o.src
    local ok = true
    if (src == nil or src == "") and o.icon ~= nil then
        if string.sub(o.icon, 1, 1) == "/" then
            src = o.icon              -- 真实路径（如外部应用自带图标）
        else
            local p, exists = M.icon(o.icon)
            src = p
            ok = (exists == true) and (p ~= nil)
        end
    end

    if src == nil or src == "" or not ok then
        if o.placeholder then
            local pw, ph = o.w or 32, o.h or 32
            local s = math.min(pw, ph)
            return M.card(parent, {
                x = (o.x or 0) + math.floor((pw - s) / 2),
                y = (o.y or 0) + math.floor((ph - s) / 2),
                w = s, h = s,
                radius = M.R.xs, opa = o.placeholder_opa or M.OPA.fill_hi,
                border_w = 0,
            })
        end
        return nil
    end

    return airui.image({
        parent = o.parent or parent,
        x = o.x or 0, y = o.y or 0,
        w = o.w or 32, h = o.h or 32,
        src = src,
        fit = o.fit or "contain",
        opacity = o.opacity or 255,
        on_click = o.on_click,
    })
end

--[[带底色方块的图标（设计稿 .ic / .app-ic）：图标缺失时只留空色块]]
function M.iconbox(parent, o)
    local s = o.size or 30
    local box = M.card(parent, {
        x = o.x, y = o.y, w = s, h = s,
        radius = o.radius or M.R.sm,
        color = o.tint or M.C.surface, opa = o.tint and 46 or M.OPA.fill, border_w = 0,
        on_click = o.on_click,
    })
    M.image(box, { icon = o.icon, x = s * 0.22, y = s * 0.22, w = s * 0.56, h = s * 0.56 })
    return box
end

--[[圆角图标按钮（设计稿 .iconbtn / .round）
图标资源缺失时依次退化为：text 文字（如 "<" "/" ">"）→ 占位小方块]]
function M.iconbtn(parent, o)
    local w, h = o.w or 38, o.h or 38
    -- 本按钮自己的描边宽度（决定内容区比外框小多少）
    local bw = o.border and 1 or 0
    local btn = M.card(parent, {
        x = o.x, y = o.y, w = w, h = h,
        radius = o.radius or M.R.md, opa = o.opa or M.OPA.fill_hi,
        border = o.border, border_w = bw,
        on_click = o.on_click,
    })

    --[[ 内层子控件必须按**内容区**摆，不能按外框。
    LVGL 的内容区 = 对象尺寸 - pad*2 - border*2（lv_obj_pos.c 的
    lv_obj_get_content_width = width - space_left - space_right，
    lv_obj_style.h 里 space = pad + border_width），子控件的坐标原点也就内移了
    一个 (pad + border)。
    以前这里把内层 label 的 w 直接写成按钮的外宽 w —— 带 1px 描边的按钮，
    label 恒比父内容区宽 2px，这就是「子控件宽度超出父容器」。
    对应用户报的那批控件：idle_win 的 2 个翻页按钮、所有页面的返回键 <
    （它们正是仅有的、在调用处显式传了 border 的 iconbtn）。]]
    local ox, oy = bw, bw
    local iw, ih = w - 2 * bw, h - 2 * bw
    if iw < 1 then iw = 1 end
    if ih < 1 then ih = 1 end

    local img = M.image(btn, { icon = o.icon,
        x = ox + math.floor(iw * 0.26), y = oy + math.floor(ih * 0.26),
        w = math.floor(iw * 0.48), h = math.floor(ih * 0.48) })
    if img then return btn end

    if o.text then
        --[[ 图标缺失时的文字兜底（返回键的 "<" 走这里）。
        关键约束：hzfont 的行高 = 字号 + 3（见 components/airui/src/font/lv_font_hzfont.c
        的 g_airui_hzfont_extra_leading）。label 的 h 只要小于行高，LVGL 就把文字画到
        盒子外面 —— 之前是 `h = 盒高、px_size = 0.60*盒高`，等于让行高(0.6h+3)去撞 h，
        盒高偏小时就溢出父容器。这里改成「先把 label 盒高算成恰好一行」，再垂直居中。]]
        local s = math.min(iw, ih)
        local fs = math.floor(s * 0.52)
        if fs < 14 then fs = 14 end
        if fs > 34 then fs = 34 end
        local lh = fs + 3
        if lh > ih then
            -- 内容区太矮：退到能放下的最小字号，且盒高硬夹到 ih（宁可裁边也不溢出）
            fs = ih - 3
            if fs < 10 then fs = 10 end
            lh = math.min(ih, fs + 3)
        end
        M.label(btn, {
            x = ox, y = oy + math.max(0, math.floor((ih - lh) / 2)), w = iw, h = lh,
            text = o.text, px_size = fs,
            color = o.text_color or M.C.primary_light, align = airui.TEXT_ALIGN_CENTER,
        })
    else
        M.card(btn, {
            x = ox + math.floor(iw * 0.32), y = oy + math.floor(ih * 0.32),
            w = math.floor(iw * 0.36), h = math.floor(ih * 0.36),
            radius = M.R.xs, opa = M.OPA.fill_hi, border_w = 0,
        })
    end
    return btn
end

--[[主色填充按钮（设计稿 .pill.on / .btn-install）]]
function M.button(parent, o)
    return airui.button({
        parent = o.parent or parent,
        x = o.x or 0, y = o.y or 0,
        w = o.w or 120, h = o.h or 36,
        text = o.text or "",
        font_size = math.max(16, dp(o.size or 13)),
        style = {
            bg_color = o.bg or M.C.amber,
            text_color = o.fg or M.C.on_amber,
            radius = dp(o.radius or M.R.md),
            border_width = o.border_w or 0,
            border_color = o.border or M.C.amber,
            pressed_bg_color = o.pressed or M.C.amber_deep,
            pressed_text_color = o.fg or M.C.on_amber,
        },
        on_click = o.on_click,
    })
end

--[[幽灵按钮（描边透明底）]]
function M.ghost_button(parent, o)
    return airui.button({
        parent = o.parent or parent,
        x = o.x or 0, y = o.y or 0,
        w = o.w or 120, h = o.h or 36,
        text = o.text or "",
        font_size = math.max(16, dp(o.size or 13)),
        style = {
            bg_color = M.C.surface, bg_opa = M.OPA.fill,
            text_color = o.fg or M.C.t1,
            radius = dp(o.radius or M.R.md),
            border_width = 1, border_color = M.C.stroke,
            pressed_bg_color = M.C.surface, pressed_bg_opa = M.OPA.fill_hi,
            pressed_text_color = o.fg or M.C.t1,
        },
        on_click = o.on_click,
    })
end

-- ==================== 三、业务组件 ====================

--[[状态栏：左侧产品名 + 提示，右侧按 slots 从右往左排（文字/图标/图片）]]
-- slots 元素: { kind="text"|"icon"|"image", w=, text=, name=, src=, color=, size=, gap= }
-- 返回 bar, h, widgets（widgets[i] 为第 i 个 slot 的控件，便于后续 set_text/set_src）
function M.statusbar(parent, o)
    local h = o.h or 30
    local W = o.w or screen_w
    local bar = M.box(parent, { x = o.x or 0, y = o.y or 0, w = W, h = h, color = M.C.black, opa = 0 })

    local title_w = o.title_w or math.floor(W * 0.3)
    M.label(bar, { x = 0, y = 0, w = title_w, h = h, text = o.title or "", size = o.size or M.F.small,
        color = o.title_color or M.C.t2, align = airui.TEXT_ALIGN_LEFT })
    if o.hint then
        local hx = o.hint_x or math.floor(W * 0.16)
        M.label(bar, { x = hx, y = 0, w = title_w, h = h, text = o.hint, size = o.size or M.F.small,
            color = M.C.t3, align = airui.TEXT_ALIGN_LEFT })
    end

    local slots = o.slots or {}
    local widgets = {}
    local rx = W - dp(6)
    for i = #slots, 1, -1 do
        local s = slots[i]
        local sw = s.w or 40
        local gap = s.gap or 12
        rx = rx - sw - dp(gap)
        if s.kind == "text" then
            widgets[i] = M.label(bar, { x = rx, y = 0, w = sw, h = h, text = s.text or "",
                size = s.size or o.size or M.F.small, color = s.color or M.C.t1, align = s.align or airui.TEXT_ALIGN_RIGHT })
        elseif s.kind == "icon" then
            local is = s.size_h or (h - dp(10))
            widgets[i] = M.image(bar, { x = rx, y = math.floor((h - is) / 2), w = sw, h = is, icon = s.name })
        else
            local is = s.size_h or (h - dp(8))
            widgets[i] = M.image(bar, { x = rx, y = math.floor((h - is) / 2), w = sw, h = is, src = s.src, raw = true })
        end
    end
    return bar, h, widgets
end

--[[页面标题行：左侧大标题 + 副标题，右侧可放内容；on_back 非空时左侧显示返回按钮]]
function M.titlebar(parent, o)
    local h = o.h or 60
    --[[ w 必须兜底：原来直接写 w = o.w，调用方漏传时 M.card 里 o.w or 0 得到 0，
    标题栏变成 0 宽，而返回键 bs = h - dp(16)（默认 44）在 x = dp(8) 处
    → 整块飞出父容器。下面 title_w 早就用了 screen_w 兜底，宽度这里却漏了。]]
    local bw_total = o.w or screen_w
    local bar = M.card(parent, { x = o.x or 0, y = o.y or 0, w = bw_total, h = h, radius = o.radius or M.R.lg, opa = o.opa or M.OPA.glass })

    local tx = dp(14)
    if o.on_back then
        local bs = h - dp(16)
        M.iconbtn(bar, { x = dp(8), y = dp(8), w = bs, h = bs, radius = M.R.sm, icon = "back",
            on_click = o.on_back })
        tx = dp(8) + bs + dp(10)
    end

    local title_h = dp((o.title_size or M.F.h2) + 8)
    local title_w = (o.w or screen_w) - tx - dp(16)
    local title = M.label(bar, {
        x = tx, y = math.floor((h - title_h) / 2), w = title_w, h = title_h,
        text = o.title or "", size = o.title_size or M.F.h2, color = M.C.t1,
        align = airui.TEXT_ALIGN_LEFT,
    })
    if o.sub then
        M.label(bar, {
            x = tx, y = math.floor((h - title_h) / 2) + title_h, w = title_w, h = dp(18),
            text = o.sub, size = o.sub_size or M.F.small, color = M.C.t3,
            align = airui.TEXT_ALIGN_LEFT,
        })
    end
    return bar, h, title
end

--[[左侧导航栏（设计稿 .rail）：品牌块 + 图标导航项 + 底部设置]]
function M.rail(parent, o)
    local w = o.w or 104
    local h = o.h or screen_h
    local rail = M.box(parent, { x = 0, y = 0, w = w, h = h, color = M.C.surface, opa = M.OPA.rail, radius = 0 })

    -- 品牌块（琥珀渐变近似：实心琥珀 + 高光小方块）
    local bs = o.brand_size or 42
    local brand = M.card(rail, {
        x = math.floor((w - bs) / 2), y = dp(16), w = bs, h = bs,
        radius = M.R.md, color = M.C.amber, opa = 255, border_w = 0,
    })
    M.image(brand, { x = bs * 0.24, y = bs * 0.24, w = bs * 0.52, h = bs * 0.52, icon = "brand" })

    -- 导航项
    local items = o.items or {}
    local iw, ih = o.item_w or 80, o.item_h or 58
    local gap = o.gap or 4
    local y = dp(16) + bs + dp(14)
    local widgets = {}
    for i, item in ipairs(items) do
        local on = (i == (o.active or 1))
        local it = M.card(rail, {
            x = math.floor((w - iw) / 2), y = y, w = iw, h = ih,
            radius = M.R.md,
            color = on and M.C.amber or M.C.surface,
            opa = on and 44 or 0,
            border = on and M.C.amber or nil,
            border_w = on and 1 or 0,
            on_click = item.on_click,
        })
        M.image(it, { x = math.floor((iw - 21) / 2), y = dp(11), w = 21, h = 21, icon = item.icon })
        M.label(it, {
            x = 0, y = dp(34), w = iw, h = dp(18),
            text = item.text or "", size = o.item_size or M.F.tiny,
            color = on and M.C.amber_light or M.C.t3, align = airui.TEXT_ALIGN_CENTER,
        })
        widgets[i] = it
        y = y + ih + gap
    end

    -- 底部设置按钮 / 头像
    if o.bottom_icon then
        M.iconbtn(rail, {
            x = math.floor((w - 40) / 2), y = h - dp(40) - dp(66), w = 40, h = 40,
            radius = M.R.md, opa = M.OPA.fill, icon = o.bottom_icon, on_click = o.on_bottom_click,
        })
    end
    -- 头像（首字母方块）
    local av = o.avatar or "AL"
    local as = 40
    local ava = M.card(rail, {
        x = math.floor((w - as) / 2), y = h - dp(16) - as, w = as, h = as,
        radius = M.R.md, color = M.C.dev1, opa = 255, border = M.C.stroke,
    })
    M.label(ava, { x = 0, y = math.floor((as - (M.F.body + 8)) / 2), w = as, h = M.F.body + 8,
        text = av, size = M.F.body, color = M.C.avatar_text, align = airui.TEXT_ALIGN_CENTER })

    return rail, widgets
end

--[[应用磁贴（设计稿 .app + .app-ic）：图标 + 名称 + 可选角标]]
function M.tile(parent, o)
    local w, h = o.w or 96, o.h or 86
    local tile = M.card(parent, {
        x = o.x, y = o.y, w = w, h = h,
        radius = M.R.md, opa = o.opa or 0, border = o.border, border_w = o.border and 1 or 0,
        on_click = o.on_click, on_long_press = o.on_long_press,
    })

    local icon_size = o.icon_size or 46
    local ix = math.floor((w - icon_size) / 2)
    -- icon 支持语义名（查 /luadb/ui/）与真实路径（外部应用自带图标）
    local img = M.image(tile, { icon = o.icon, x = ix, y = dp(6), w = icon_size, h = icon_size })
    if not img then
        -- 资源缺失时用琥珀底块 + 首字占位，保证布局不塌且可辨识
        local ph = M.card(tile, {
            x = ix, y = dp(6), w = icon_size, h = icon_size,
            radius = M.R.md, color = o.tint or M.C.amber, opa = 235, border_w = 0,
        })
        M.label(ph, { x = 0, y = math.floor((icon_size - (dp(M.F.body) + 8)) / 2),
            w = icon_size, h = dp(M.F.body) + 8,
            text = o.mark or (o.text and string.sub(o.text, 1, 1) or "A"), size = M.F.body,
            color = M.C.on_amber, align = airui.TEXT_ALIGN_CENTER })
    end
    M.label(tile, {
        x = dp(2), y = dp(6) + icon_size + dp(4), w = w - dp(4), h = dp(18),
        text = o.text or "", size = o.size or M.F.small, px_size = o.px_size, color = o.text_color or M.C.t1,
        align = airui.TEXT_ALIGN_CENTER,
    })
    if o.badge then
        local bw = dp(48)
        M.label(tile, {
            x = math.floor((w - bw) / 2), y = dp(6) + icon_size + dp(24), w = bw, h = dp(16),
            text = o.badge, size = M.F.tiny, color = o.badge_color or M.C.t3,
            align = airui.TEXT_ALIGN_CENTER,
        })
    end
    return tile
end

--[[列表行（设计稿 .lrow / .set-row）：左图标 + 标题/副标题 + 右侧文字

== 本文件里 M.row 只允许存在一个定义 ==
历史上这里曾用第二个 function M.row(...) 实现了另一种「键值行」（只认 label/value），
结果把本节这个「列表行」整个覆盖掉（Lua 后定义生效）—— 设置页传的是 text/sub/icon，
键值行取不到 o.label / o.value，于是每一行的文字都变成空白。
键值行必须另起名字（kv_row，见下方），绝不能再叫 row。

尺寸契约：所有文本盒高一律取「字号 + 3」（hzfont 行高 = 字号 + 3）并垂直居中，
h 只影响行的外框，不会把文字挤到盒子外面。
字号：px_size 给像素字号（推荐）；size 走旧接口（逻辑字号，夹到 FONT_MIN）。

@table o
  x, y, w, h       位置尺寸（h 默认 44）
  icon             左侧图标语义名；资源缺失时用首字兜底
  icon_size        左侧方块边长（默认 dp(30)，自动夹到行高以内）
  tint             图标底色（给了就用它，否则低透明度白）
  text             主标题        sub  副标题（给了就两行排布）
  right            右侧文字      right_w 右侧预留宽度（不给则按 40% 推）
  px_size/size/sub_px/right_px/right_size  各段字号
  bg, opa, border, radius, scrollable      外观（默认全透明、无描边）
  on_click
@return row, title_label, right_label]]
function M.row(parent, o)
    parent, o = norm(parent, o)
    local w, h = o.w or 300, o.h or 44

    local row = M.card(parent, {
        x = o.x, y = o.y, w = w, h = h,
        radius = o.radius or M.R.sm,
        color = o.bg or M.C.surface,
        opa = (o.opa ~= nil) and o.opa or 0,
        border = o.border, border_w = o.border and 1 or 0,
        scrollable = o.scrollable,
        on_click = o.on_click,
    })

    -- 左侧图标（资源缺失用首字兜底；末位兜底用 ASCII "-"，内置字库没有圆点符号）
    local tx = dp(10)
    if o.icon then
        local s = o.icon_size or dp(30)
        if s > h - dp(4) then s = h - dp(4) end
        if s < dp(16) then s = dp(16) end
        local tint = M.card(row, {
            x = dp(8), y = math.floor((h - s) / 2), w = s, h = s,
            radius = M.R.xs, color = o.tint or M.C.surface,
            opa = o.tint and 46 or M.OPA.fill, border_w = 0,
        })
        local img = M.image(tint, { x = s * 0.22, y = s * 0.22, w = s * 0.56, h = s * 0.56, icon = o.icon })
        if not img then
            local mfs = math.max(12, math.floor(s * 0.5))
            M.label(tint, {
                x = 0, y = math.max(0, math.floor((s - (mfs + 3)) / 2)), w = s, h = mfs + 3,
                text = o.mark or (o.text and string.sub(o.text, 1, 1)) or "-",
                px_size = mfs, color = o.mark_color or M.C.amber_light,
                align = airui.TEXT_ALIGN_CENTER,
            })
        end
        tx = dp(8) + s + dp(10)
    end

    -- 各段字号（size / right_size 兼容旧写法：逻辑字号，夹到 FONT_MIN）
    local fs = o.px_size or dp(math.max(M.FONT_MIN, o.size or M.F.body))
    local fs_sub = o.sub_px or M.fs("micro")
    local fs_right
    if o.right_px then fs_right = o.right_px
    elseif o.right_size then fs_right = dp(math.max(M.FONT_MIN, o.right_size))
    else fs_right = M.fs("caption") end

    local lh, lh_sub, lh_right = fs + 3, fs_sub + 3, fs_right + 3
    local gap = dp(2)
    local total = o.sub and (lh + gap + lh_sub) or lh
    local ty = math.floor((h - total) / 2)
    if ty < 0 then ty = 0 end

    local right_w = o.right_w or (o.right and math.floor(w * 0.4)) or 0
    local txw = w - tx - dp(12) - right_w
    if txw < dp(20) then txw = dp(20) end

    local title_label = M.label(row, {
        x = tx, y = ty, w = txw, h = lh,
        text = o.text or "", px_size = fs,
        color = o.text_color or M.C.t1, align = airui.TEXT_ALIGN_LEFT,
    })
    if o.sub then
        M.label(row, {
            x = tx, y = ty + lh + gap, w = txw, h = lh_sub,
            text = o.sub, px_size = fs_sub,
            color = o.sub_color or M.C.t3, align = airui.TEXT_ALIGN_LEFT,
        })
    end
    local right_label = nil
    if o.right then
        right_label = M.label(row, {
            x = w - right_w - dp(12), y = ty, w = right_w, h = lh_right,
            text = o.right, px_size = fs_right,
            color = o.right_color or M.C.t2, align = airui.TEXT_ALIGN_RIGHT,
        })
    end
    return row, title_label, right_label
end

--[[分组标题（设计稿 .label / .hd）
盒高契约与 theme.row 一致：h 缺省取「字号 + 3」（hzfont 行高），
调用方传了 h 也照样按该值给盒子 —— 但字号一律走 px_size，避免再被 FONT_MIN 顶大。]]
function M.section(parent, o)
    local fs = o.px_size or dp(math.max(M.FONT_MIN, o.size or M.F.small))
    return M.label(parent, {
        x = o.x, y = o.y, w = o.w, h = o.h or (fs + 3),
        text = o.text or "", px_size = fs, color = o.color or M.C.t3,
        align = o.align or airui.TEXT_ALIGN_LEFT,
    })
end

--[[胶囊标签（设计稿 .chip）：图标/圆点 + 文本]]
function M.chip(parent, o)
    local h = o.h or 30
    local cw = o.w or 96
    local chip = M.card(parent, {
        x = o.x, y = o.y, w = cw, h = h, radius = M.R.sm,
        opa = o.opa or M.OPA.fill, border = o.border, border_w = o.border and 1 or 0,
        color = o.color or M.C.surface, on_click = o.on_click,
    })
    local tx = dp(10)
    if o.dot then
        local d = dp(6)
        M.card(chip, { x = dp(11), y = math.floor((h - d) / 2), w = d, h = d, radius = d, color = o.dot, opa = 255, border_w = 0 })
        tx = dp(24)
    elseif o.icon then
        local s = o.icon_size or 15
        M.image(chip, { x = dp(10), y = math.floor((h - s) / 2), w = s, h = s, icon = o.icon })
        tx = dp(10) + s + dp(7)
    end
    if o.text then
        M.label(chip, { x = tx, y = 0, w = cw - tx - dp(10), h = h, text = o.text,
            size = o.size or M.F.small, color = o.text_color or M.C.t2, align = airui.TEXT_ALIGN_LEFT })
    end
    return chip
end

--[[场景胶囊按钮（设计稿 .pill）：横向等分，选中态用强调色]]
function M.pills(parent, o)
    local items = o.items or {}
    local gap = o.gap or 8
    local n = math.max(1, #items)
    local total = o.w or 400
    local pw = math.floor((total - (n - 1) * gap) / n)
    local h = o.h or 38
    local widgets = {}
    for i, it in ipairs(items) do
        local on = (i == (o.active or 0))
        local p = M.card(parent, {
            x = (o.x or 0) + (i - 1) * (pw + gap), y = o.y, w = pw, h = h,
            radius = M.R.md,
            color = on and (it.color or M.C.amber) or M.C.surface,
            opa = on and 48 or M.OPA.fill,
            border = on and (it.color or M.C.amber) or nil, border_w = on and 1 or 0,
            on_click = it.on_click,
        })
        M.label(p, {
            x = 0, y = 0, w = pw, h = h, text = it.text or "",
            size = o.size or M.F.body,
            color = on and (it.text_color or M.C.amber_light) or M.C.t2,
            align = airui.TEXT_ALIGN_CENTER,
        })
        widgets[i] = p
    end
    return widgets
end

--[[搜索框（设计稿 .search）：静态展示，点击可跳转]]
function M.search(parent, o)
    local h = o.h or 38
    local s = M.card(parent, {
        x = o.x, y = o.y, w = o.w or 268, h = h, radius = M.R.md,
        opa = M.OPA.fill_hi, border = M.C.stroke, on_click = o.on_click,
    })
    M.image(s, { x = dp(12), y = math.floor((h - 15) / 2), w = 15, h = 15, icon = "search" })
    M.label(s, { x = dp(36), y = 0, w = (o.w or 268) - dp(48), h = h, text = o.text or "搜索",
        size = o.size or M.F.small, color = M.C.t3, align = airui.TEXT_ALIGN_LEFT })
    return s
end

--[[底部 Dock（设计稿 .dock）：居中排列的应用图标]]
function M.dock(parent, o)
    local h = o.h or 70
    local dock = M.card(parent, {
        x = o.x, y = o.y, w = o.w, h = h, radius = M.R.xl,
        opa = M.OPA.dock, border = M.C.stroke,
    })
    local items = o.items or {}
    local n = #items
    local iw = o.item_w or 68
    local total = n * iw
    local sx = math.floor(((o.w or screen_w) - total) / 2)
    for i, it in ipairs(items) do
        M.tile(dock, {
            x = sx + (i - 1) * iw, y = math.floor((h - 62) / 2), w = iw, h = 62,
            icon = it.icon, icon_size = o.icon_size or 40, text = it.text,
            size = M.F.tiny, text_color = M.C.t2, on_click = it.on_click,
        })
    end
    return dock
end

--[[开关（设计稿 .tgl）
为什么不用 airui.switch：binding 只接受 `style = "danger"/"success"` 字符串，
选中色被硬编码成 0x1A73E8 蓝（见 luat_airui_switch.c 的 airui_switch_apply_style），
在琥珀/青/紫/绿四套深色主题里都是异色；且滑动块颜色也无法从 Lua 改。
所以这里用「轨道 + 滑块」两个容器自己画，配色全部走令牌，换肤自动跟随。

@return handle  —— 与 airui.switch 的关键方法保持同名，调用方无感迁移：
  handle:get_state()          -> boolean
  handle:set_state(bool)      -> 就地更新（不触发 on_change，和官方语义一致）
  handle:set_enabled(bool)    -> 置灰 / 恢复可点
  handle.track / handle.knob  -> 底层容器，需要进一步定制时可用
@table o
  x, y, w, h    位置尺寸（默认 46×26）
  checked       初始状态
  color         开启态轨道色（默认 M.C.primary）
  on_change     回调，签名 on_change(handle)，用 handle:get_state() 取值
  disabled      置灰不可点
]]
local function build_toggle(parent, o)
    parent, o = norm(parent, o)
    local w = o.w or 46
    local h = o.h or 26
    if h < 16 then h = 16 end
    local pad = math.max(2, math.floor(h * 0.14))
    local kd = h - pad * 2

    local state = o.checked and true or false
    local enabled = not o.disabled
    local track_color = state and (o.color or M.C.primary) or M.C.track
    local knob_color = state and M.C.knob or M.C.knob_off
    local knob_x = state and (w - pad - kd) or pad

    -- 先声明再闭包捕获：Lua 里 `local knob` 若写在 on_click 之后，
    -- 闭包捕获到的是全局 knob(nil)，点了就报错
    local track, knob
    local handle = { _state = state }

    local function apply_pos()
        knob:set_pos(state and (w - pad - kd) or pad, pad)
    end

    -- 点击回调要同时挂在轨道和滑块上：LVGL 默认不做事件冒泡，
    -- 只挂在轨道上的话「正好点在滑块上」不会触发
    local function do_toggle()
        if not enabled then return end
        state = not state
        handle._state = state
        local tc = state and (o.color or M.C.primary) or M.C.track
        track:set_color(tc, 255)
        track:set_border_color(tc, 1)
        knob:set_color(state and M.C.knob or M.C.knob_off, 255)
        apply_pos()
        if o.on_change then o.on_change(handle) end
    end

    track = airui.container({
        parent = o.parent or parent,
        x = o.x or 0, y = o.y or 0, w = w, h = h,
        color = track_color, color_opacity = 255,
        radius = math.floor(h / 2),
        border_color = track_color, border_width = 1,
        on_click = do_toggle,
    })
    knob = airui.container({
        parent = track,
        x = knob_x, y = pad, w = kd, h = kd,
        color = knob_color, color_opacity = 255,
        radius = math.floor(kd / 2),
        on_click = do_toggle,
    })

    handle.track = track
    handle.knob = knob
    function handle:get_state() return self._state end
    function handle:set_state(v)
        v = v and true or false
        if self._state == v then return end
        self._state = v
        state = v
        local tc = v and (o.color or M.C.primary) or M.C.track
        track:set_color(tc, 255)
        track:set_border_color(tc, 1)
        knob:set_color(v and M.C.knob or M.C.knob_off, 255)
        apply_pos()
    end
    function handle:set_enabled(v)
        enabled = v and true or false
        if not enabled then
            track:set_color(M.C.stroke_soft, 255)
            track:set_border_color(M.C.stroke_soft, 1)
            knob:set_color(M.C.t3, 255)
        else
            local tc = state and (o.color or M.C.primary) or M.C.track
            track:set_color(tc, 255)
            track:set_border_color(tc, 1)
            knob:set_color(state and M.C.knob or M.C.knob_off, 255)
        end
    end
    return handle
end

--[[开关（设计稿 .tgl）：主题化实现，见 build_toggle 的说明]]
function M.switch(parent, o)
    return build_toggle(parent, o)
end
M.toggle = M.switch

--[[亮度/音量滑条（设计稿 .slider）
轨道走 M.C.track、滑块走 M.C.knob、进度走 M.C.primary —— 三档全部是令牌，
换主题自动跟随；浅色主题下这四色会被覆写成浅底深轨，不会糊成一片。
airui.slider 自带 set_value/get_value/set_range，直接当返回值用。

两个必须知道的约束（来自 lvgl9/src/widgets/slider/lv_slider.c）：
1. 横向滑条的滑块直径 = 对象高度（draw_knob 里 knob_size = lv_obj_get_height）。
   所以 h 决定手感 —— 触屏建议 >= dp(28)，别只当成轨道粗细来填。
2. 滑块只响应「拖到滑块本体上」（LV_EVENT_HIT_TEST 命中判断用 right_knob_area），
   点轨道空白处不会跳值。因此不适合用细高比做精细调节。
on_change 回调签名是 on_change(self)，用 self:get_value() 取值。

3. 圆球会越出盒子：圆球圆心落在「内容区」两端（lv_bar.c 的 indic_area =
   对象坐标 - LV_PART_MAIN 的 padding），所以最左 / 最右时圆球各探出 (h/2 - pad)。
   值为 100% 时右侧圆球就压出父容器 —— 而容器带 LV_OBJ_FLAG_SCROLLABLE，
   超出 1px 就会让父级变成「可滚动」并画出滑动条。因此下面按 box 给的原点 / 宽度
   先内缩 (h/2 - pad)，让圆球的两个极限位置恰好落在 box 的左右边缘上。
   调用方把 x / w 当成「圆球可活动的整段范围」即可，不要再自己减半径。]]
function M.slider(parent, o)
    parent, o = norm(parent, o)
    local h = o.h or 26
    local pad = dp(3)
    local over = math.max(0, math.floor(h / 2) - pad)   -- 圆球每侧探出量
    local sx = (o.x or 0) + over
    local sw = (o.w or 200) - 2 * over
    if sw < dp(24) then sw = dp(24) end
    return airui.slider({
        parent = o.parent or parent,
        x = sx, y = o.y or 0,
        w = sw, h = h,
        min = o.min or 0, max = o.max or 100, value = o.value or 60,
        style = {
            bg_color = o.track or M.C.track, bg_opa = 255,
            border_color = o.track or M.C.track, border_width = 0,
            indicator_color = o.color or M.C.primary, indicator_opa = 255,
            knob_color = o.knob_color or M.C.knob, knob_opa = 255,
            knob_border_color = o.knob_color or M.C.knob, knob_border_width = 0,
            radius = dp(99), pad = pad,
        },
        on_change = o.on_change,
    })
end

--[[进度条（设计稿 .bar）：轨道走令牌，替换各页面直接写 CLR.line_soft 的用法
——那种写法的轨道是 0x39434F 实色，在深底上就是一条突兀的「灰色长条」。
@table o  x,y,w,h  value(0-100)  color  track  radius
@return airui.bar（自带 set_value(v, anim)）]]
function M.bar(parent, o)
    parent, o = norm(parent, o)
    return airui.bar({
        parent = o.parent or parent,
        x = o.x or 0, y = o.y or 0,
        w = o.w or 200, h = o.h or 8,
        min = o.min or 0, max = o.max or 100, value = o.value or 0,
        bg_color = o.track or M.C.track,
        indicator_color = o.color or M.C.primary,
        radius = (o.radius ~= nil) and o.radius or dp(99),
    })
end

--[[输入框（textarea）：与主题配套的唯一下口
默认样式 = 主题输入底色 + 主文字色 + 全局小圆角，调用方传 style 时按字段合并覆盖。
其余字段（x/y/w/h/text/placeholder/max_len/mode/align/keyboard/disabled/
on_text_change/parent）原样透传给 airui.textarea。
注意：airui.textarea 的 bg_color 会强制 LV_OPA_COVER，输入框一定是实底 —— 不能用玻璃。]]
--[[虚拟键盘 = LVGL lv_keyboard + 主题配色

为什么需要这层包装：lv_keyboard 的键位是自绘的 LV_PART_ITEMS，颜色 100% 来自
LVGL 默认主题，键盘除了底色之外没有任何可配项 —— 不包装的话，不管应用切到
哪套主题，键盘永远是「白键 + 灰字」，放到深色主题里就是一块突兀的白板。

配色分工：
  键盘底      panel                       键位底   panel_hi（比底色高一档，键位才有分界）
  键位文字    t1                          键位按下 primary / on_primary
  候选栏文字  t1                          描边     stroke / stroke_soft

@table o 与 airui.keyboard 完全一致；下面这些颜色字段一般不必传，传了则覆盖
         主题默认值：bg_color / key_bg_color / key_text_color /
         key_pressed_bg_color / key_pressed_text_color / key_border_color /
         border_color / text_color / cand_text_color
@return keyboard 对象]]
function M.keyboard(o)
    o = o or {}
    local kw = {}
    for k, v in pairs(o) do kw[k] = v end
    kw.bg_color = kw.bg_color or M.C.panel
    kw.key_bg_color = kw.key_bg_color or M.C.panel_hi
    kw.key_text_color = kw.key_text_color or M.C.t1
    kw.key_pressed_bg_color = kw.key_pressed_bg_color or M.C.primary
    kw.key_pressed_text_color = kw.key_pressed_text_color or M.C.on_primary
    kw.key_border_color = kw.key_border_color or M.C.stroke_soft
    kw.text_color = kw.text_color or M.C.t1
    kw.border_color = kw.border_color or M.C.stroke
    kw.cand_text_color = kw.cand_text_color or M.C.t1
    return airui.keyboard(kw)
end

function M.input(parent, o)
    parent, o = norm(parent, o)
    local st = {
        radius = o.radius or M.R.sm,
        bg_color = o.bg or o.input_bg or M.C.input_bg,
        -- 兼容旧写法：历史上各页面用 color= 表示输入文字色
        text_color = o.fg or o.text_color or o.color or M.C.t1,
        font_size = o.px_size or o.font_size or M.fs("body"),
    }
    if o.style then
        for k, v in pairs(o.style) do st[k] = v end
    end
    return airui.textarea({
        parent = o.parent or parent,
        x = o.x or 0, y = o.y or 0,
        w = o.w or 200, h = o.h or 44,
        text = o.text, placeholder = o.placeholder,
        max_len = o.max_len, mode = o.mode, align = o.align,
        disabled = o.disabled, keyboard = o.keyboard,
        password_mode = o.password_mode,
        on_text_change = o.on_text_change,
        style = st,
    })
end

--[[键值行（KV）：左侧标签 + 右侧数值，一行搞定

== 名字必须叫 kv_row，不能叫 row ==
本文件只允许存在一个 M.row（列表行，认 text/sub/icon/right 这套字段）。
这里曾经把它实现成第二个 function M.row(...)，把上面那个定义整个覆盖掉，
导致设置页取不到 o.label / o.value 的行全部变成空白。
KV 行只认 label/value，字段名和列表行完全不同，所以必须分名。

@table o
  x, y, w, h    位置尺寸（h 默认 = 行高 + dp(12)）
  label         左侧文字          value 右侧文字
  size          字号档位，默认 "label"
  label_w       左侧文字宽度（默认行宽的一半）
  label_color / value_color / align / on_click
@return row, value_label]]
function M.kv_row(parent, o)
    parent, o = norm(parent, o)
    local fs = M.fs(o.size or "label")
    local lh = fs + 3
    local h = o.h or (lh + dp(12))
    local pad = o.pad or dp(12)
    local row = M.box(parent, {
        x = o.x, y = o.y, w = o.w, h = h,
        color = o.bg or M.C.surface,
        opa = (o.opa ~= nil) and o.opa or M.OPA.glass,
        radius = (o.radius ~= nil) and o.radius or M.R.sm,
        border = o.border, border_w = o.border and 1 or 0,
        scrollable = o.scrollable,
        on_click = o.on_click,
    })
    local ty = math.floor((h - lh) / 2)
    if ty < 0 then ty = 0 end
    local lw = o.label_w or math.floor((o.w or 200) * 0.5)
    M.label(row, {
        x = pad, y = ty, w = lw, h = lh,
        text = o.label or "", px_size = fs,
        color = o.label_color or M.C.t2, align = airui.TEXT_ALIGN_LEFT,
    })
    local value_label = M.label(row, {
        x = pad + lw, y = ty, w = (o.w or 200) - pad * 2 - lw, h = lh,
        text = o.value or "", px_size = fs,
        color = o.value_color or M.C.t1,
        align = o.align or airui.TEXT_ALIGN_RIGHT,
    })
    return row, value_label
end

--[[分隔线：颜色与不透明度都走令牌，浅色主题可换成实色细线]]
function M.divider(parent, o)
    return M.box(parent, {
        x = o.x, y = o.y, w = o.w, h = o.h or 1,
        color = o.color or M.C.divider,
        opa = (o.opa ~= nil) and o.opa or M.OPA.divider,
    })
end

-- ==================== 四、页面骨架（全工程唯一入口） ====================
--[[此前每个页面各自实现「画背景 + 算页边距 + 搭标题栏」，导致同一屏内出现
   纯色底 vs 玻璃底、15px vs 12px vs math.floor(6*density) 三种页边距、
   以及四套长得不一样的标题栏。下面三个函数把这三件事收口，新页面只调 M.page()。]]

-- 主题样式开关（M.apply 会重写；此处给出默认真值，供主题未注册时兜底）
M.STYLE = { wallpaper = true, dark = true }

--[[统一页边距（像素）
以屏幕短边为基准 —— 384 宽 → 8px，480 → 10px，1024 × 600 → 13px。
替换此前各页面自定的 15 / 12 / math.floor(6*density) / math.floor(card_w*0.08)。]]
function M.page_margin()
    local s = math.min(screen_w or 480, screen_h or 800)
    return math.max(8, math.min(18, math.floor(s * 0.022)))
end

--[[统一标题栏（全工程唯一实现，settings_titlebar 已改为委托到此）
@table o
  x, y, w, h      位置与尺寸；w 默认铺满屏宽，h 默认 dp(56)
  title           主标题
  sub             副标题（可选，会自动与主标题组成垂直居中块）
  on_back         返回回调；给了才画返回按钮
  icon            左侧图标（无 on_back 时生效）
  right           右侧文本（可选），如 "已连接"
  right_w         右侧文本预留宽度
@return bar, h, title_label, right_label
        后两个是该标题栏里的标题与右侧文本控件（没有右侧文本时为 nil），
        便于调用方后续 set_text / set_color 做动态更新
@usage
local bar, bh = theme.header(base, { x = pad, y = pad, w = sw - 2*pad,
    title = "设置", sub = "设备偏好、网络、显示与系统", on_back = fn })
]]
function M.header(parent, o)
    o = o or {}
    local sw = screen_w or 480
    local w = o.w or sw
    local h = o.h or dp(56)

    local bar = M.card(parent, {
        x = o.x or 0, y = o.y or 0, w = w, h = h,
        radius = o.radius or M.R.lg, opa = o.opa or M.OPA.glass,
    })

    local tx = dp(16)
    if o.on_back then
        --[[返回键边长：先按「高 - 上下各 8」算，再夹到「宽 - 左右各 8」以内。
        容器天生带 LV_OBJ_FLAG_SCROLLABLE，子控件只要超出父容器 1px，父容器就会
        变成「可滚动」并在 AUTO 模式下画出一条滑动条 —— 所以这里宁可按钮小一点，
        也不让它顶出标题栏。垂直方向改为居中（h 偏大时按钮不再贴着上沿）。]]
        -- 标题栏本身也是带描边的卡片，内容区 = w - 2；按钮还要留 dp(8) 左边距，
        -- 所以可用宽度按 w - 2 - dp(8) 算，而不是外框的 w - dp(16)。
        local bs = h - dp(16)
        local bs_max = w - 2 - dp(8)
        if bs_max < bs then bs = bs_max end
        if bs < dp(20) then bs = dp(20) end
        M.iconbtn(bar, {
            x = dp(8), y = math.floor((h - bs) / 2), w = bs, h = bs,
            radius = M.R.sm, opa = M.OPA.fill_hi, border = M.C.stroke_hi,
            icon = "back", text = "<", text_color = M.C.primary_light,
            on_click = o.on_back,
        })
        tx = dp(8) + bs + dp(10)
    elseif o.icon then
        local s = dp(22)
        M.image(bar, { x = dp(14), y = math.floor((h - s) / 2), w = s, h = s, icon = o.icon })
        tx = dp(14) + s + dp(10)
    end

    local fs_title = o.title_px or M.fs("h2")
    local fs_sub   = o.sub_px or M.fs("micro")
    local fs_right = o.right_px or M.fs("caption")
    local th = fs_title + dp(4)
    local shh = fs_sub + dp(4)
    local total = o.sub and (th + shh) or th
    local ty = math.floor((h - total) / 2)
    if ty < dp(2) then ty = dp(2) end

    local right_w = o.right_w or (o.right and dp(88) or 0)
    local tw = w - tx - right_w - dp(16)
    if tw < dp(40) then tw = dp(40) end

    local title_label = M.label(bar, {
        x = tx, y = ty, w = tw, h = th,
        text = o.title or "", px_size = fs_title,
        color = o.title_color or M.C.t1, align = airui.TEXT_ALIGN_LEFT,
    })
    local title_right = nil
    if o.sub then
        M.label(bar, {
            x = tx, y = ty + th, w = tw, h = shh,
            text = o.sub, px_size = fs_sub, color = M.C.t3,
            align = airui.TEXT_ALIGN_LEFT,
        })
    end
    if o.right then
        title_right = M.label(bar, {
            x = w - right_w - dp(14), y = ty, w = right_w, h = th,
            text = o.right, px_size = fs_right,
            color = o.right_color or M.C.t2, align = airui.TEXT_ALIGN_RIGHT,
        })
    end
    return bar, h, title_label, title_right
end

--[[页面背景：尊重主题样式开关
深色玻璃主题 → 底色 + 顶部微亮层；浅色主题 → 一层实底。
所有页面请统一走这个入口，不要直接调 M.wallpaper。]]
function M.page_bg(parent, w, h, x, y)
    --[[壳层（宽屏左栏）存在时，顶层页面自动右移到内容区，左栏因此保持可见。

    触发条件刻意写成「页面宽度 == 内容区宽度」，而不是维护一份全局的偏移状态：
    页面在 update_screen_size() 里调用 theme.content_fit() 收窄 screen_w 后，
    此处传进来的 w 恰好等于内容区宽度，即「该页面已经准备好落在内容区」。
    反之 idle_win 自己传的是整屏宽度，不等于内容区宽度，因此不会被偏移，
    仍然整屏铺满（左栏本来就是它的一部分）。
    显式传入 x/y 时以调用方为准。]]
    if x == nil then
        x, y = 0, 0
        if parent == airui.screen then
            local area = M.content_area()
            if area and w == area.w then
                x, y = area.x, area.y
            end
        end
    end
    if M.STYLE.wallpaper then
        return M.wallpaper(parent, w, h, x, y)
    end
    return M.box(parent, { x = x, y = y, w = w, h = h, color = M.C.bg })
end

--[[统一页面骨架：背景（壁纸/纯色）+ 页边距 + 可选标题栏，一次算清内容区
@table o
  parent     父容器（默认 airui.screen）
  area       渲染区域 { x, y, w, h }；不传时自动取壳层内容区（宽屏左栏右侧），
             窄屏自动回退整屏。需要强制整屏请显式传 area = false
  title      给了就画标题栏；不给则只出背景与内容区
  sub/on_back/icon/right  透传给 M.header
  header_pad 标题栏与内容区之间的间距（默认 = 页边距）
@return ctx  { base, bar, pad, sw, sh, x, y, w, h }
              x/y/w/h 即内容区（标题栏之下、页边距之内）的像素几何，均相对 ctx.base
@usage
local ctx = theme.page({ title = "文件管理", sub = "...", on_back = fn })
-- ctx.base 父容器，ctx.x/y/w/h 内容区
]]
function M.page(o)
    o = o or {}
    --[[区域：显式指定优先；未指定且页面挂在屏幕上时，自动取壳层内容区。
    无左栏（窄屏 / idle_win 未创建）时 content_area() 返回 nil → 整屏铺满，行为与改造前一致。
    需要强制整屏时显式传 area = false。]]
    local area = o.area
    if area == nil and (o.parent == nil or o.parent == airui.screen) then
        area = M.content_area()
    end
    local sw = (area and area.w) or screen_w or 480
    local sh = (area and area.h) or screen_h or 800
    local bx = (area and area.x) or 0
    local by = (area and area.y) or 0
    local pad = o.pad or M.page_margin()
    local p = o.parent or airui.screen

    --[[这里直接调 wallpaper / box 而不复用 page_bg：
    page_bg 在「父为屏幕且宽度等于内容区宽度」时会自动做一次偏移，
    若此处再交给它、同时又自行传 bx/by，就会变成双重偏移。]]
    local base
    if o.flat or not M.STYLE.wallpaper then
        base = M.box(p, { x = bx, y = by, w = sw, h = sh, color = M.C.bg })
    else
        base = M.wallpaper(p, sw, sh, bx, by)
    end

    local ctx = {
        base = base, pad = pad, sw = sw, sh = sh,
        x = pad, y = pad, w = sw - 2 * pad, h = sh - 2 * pad,
    }
    if o.title then
        local bar, bh = M.header(base, {
            x = pad, y = pad, w = sw - 2 * pad,
            title = o.title, sub = o.sub, on_back = o.on_back,
            icon = o.icon, right = o.right, right_w = o.right_w,
        })
        local gap = (o.header_pad ~= nil) and o.header_pad or pad
        ctx.bar = bar
        ctx.hdr_h = bh
        ctx.y = pad + bh + gap
        ctx.h = sh - ctx.y - pad
        if ctx.h < 1 then ctx.h = 1 end
    else
        ctx.bar = nil
        ctx.hdr_h = 0
    end
    return ctx
end

-- ==================== 五、主题引擎 ====================
--[[设计令牌之上再抽象一层：一套主题 = 一组 M.C / M.OPA / M.R 的覆写 + 样式开关。
页面只认令牌（theme.C.xxx / theme.SEM.yyy / theme.fs() / theme.r()），换主题时由
M.apply() 就地改写令牌值，页面代码零改动。

新增主题请调用 M.register()（参考 ui_theme_themes.lua），不要改本文件。]]
M.THEMES = {}
M.THEME_ORDER = {}
--[[默认主题 id = 晨曦浅色（浅色高对比）
改这里等于改「首次开机」以及「fskv 里还没存过选择」时用的皮肤；
用户在设置页手动选过的主题仍以 fskv 里存的值为准，不会被这里覆盖。]]
M.DEFAULT_THEME = "dawn"
local current_theme = M.DEFAULT_THEME
local KV_THEME = "ui_theme"

-- 基线快照：apply 时先恢复基线再叠加覆写，保证主题之间不会互相污染
local BASE_C, BASE_OPA, BASE_R = {}, {}, {}
for k, v in pairs(M.C) do BASE_C[k] = v end
for k, v in pairs(M.OPA) do BASE_OPA[k] = v end
for k, v in pairs(M.R) do BASE_R[k] = v end

--[[派生令牌：primary 系列是 amber 系列的语义别名
历史原因，全工程的「主强调色」都写在 M.C.amber 这个槽位上；主题切换时把强调色写回
该槽位，所有既有页面（含未改造的 wifi / 设置子页）会自动跟着换色。
新代码建议用 M.C.primary / primary_light / primary_deep / on_primary 表达语义。]]
local function sync_derived()
    M.SEM.danger  = M.C.rose
    M.SEM.success = M.C.green
    M.SEM.warning = M.C.amber
    M.SEM.info    = M.C.cyan
    M.SEM.link    = M.C.cyan
    M.SEM.accent  = M.C.violet
    M.C.primary       = M.C.amber
    M.C.primary_light = M.C.amber_light
    M.C.primary_deep  = M.C.amber_deep
    M.C.on_primary    = M.C.on_amber
end
sync_derived()

--[[注册主题
@table spec
  id      唯一标识（同时作为持久化到 fskv 的值）
  name    显示名（设置页展示），如 "琥珀夜空"
  desc    一句话描述
  order   排序权重，小的在前（可省略，默认 99）
  colors  覆写 M.C 的键值表（0xRRGGBB）
  opa     覆写 M.OPA 的键值表
  radius  覆写 M.R 的键值表
  style   { wallpaper = bool, dark = bool }
@return boolean 是否注册成功
]]
function M.register(spec)
    if type(spec) ~= "table" or type(spec.id) ~= "string" or spec.id == "" then
        log.warn("ui_theme", "register: 主题缺少 id，已忽略")
        return false
    end
    if not M.THEMES[spec.id] then
        M.THEME_ORDER[#M.THEME_ORDER + 1] = spec.id
    end
    M.THEMES[spec.id] = spec
    table.sort(M.THEME_ORDER, function(a, b)
        local ta, tb = M.THEMES[a], M.THEMES[b]
        local oa = (ta and ta.order) or 99
        local ob = (tb and tb.order) or 99
        if oa == ob then return a < b end
        return oa < ob
    end)
    return true
end

--[[有序主题列表（供设置页渲染）]]
function M.theme_list()
    local list = {}
    for _, id in ipairs(M.THEME_ORDER) do
        local t = M.THEMES[id]
        if t then list[#list + 1] = t end
    end
    return list
end

function M.theme_of(id) return M.THEMES[id or current_theme] end
function M.current() return current_theme end

local function persist_theme(id)
    if fskv and fskv.set then pcall(fskv.set, KV_THEME, id) end
end

--[[应用主题：就地改写令牌值，不重建任何控件
@param string id       主题 id；不存在时回落到 M.DEFAULT_THEME
@param boolean persist 是否写入 fskv（默认 true）
@return boolean 是否成功
@note 调用方负责让页面重绘：发布 sys.publish("UI_THEME_CHANGED", id)
      标准做法见 settings_theme_win.lua —— 本页立即重建，其他页面在
      on_get_focus 时按脏标记重建，避免操作窗口栈顺序。]]
function M.apply(id, persist)
    local spec = M.THEMES[id]
    if not spec then
        spec = M.THEMES[M.DEFAULT_THEME]
        id = spec and M.DEFAULT_THEME or nil
    end
    if not spec then
        log.warn("ui_theme", "apply: 无可用主题（ui_theme_themes 是否已 require？）")
        return false
    end

    for k, v in pairs(BASE_C) do M.C[k] = v end
    for k, v in pairs(BASE_OPA) do M.OPA[k] = v end
    for k, v in pairs(BASE_R) do M.R[k] = v end
    if spec.colors then for k, v in pairs(spec.colors) do M.C[k] = v end end
    if spec.opa then for k, v in pairs(spec.opa) do M.OPA[k] = v end end
    if spec.radius then for k, v in pairs(spec.radius) do M.R[k] = v end end
    sync_derived()

    M.STYLE.wallpaper = not (spec.style and spec.style.wallpaper == false)
    M.STYLE.dark      = not (spec.style and spec.style.dark == false)

    current_theme = spec.id
    if persist ~= false then persist_theme(spec.id) end
    log.info("ui_theme", "主题已应用:", spec.id, spec.name or "")
    return true
end

--[[从 fskv 恢复上次选择的主题
注意：业务模块（app_main）先于 UI 加载，而 fskv 的挂载是异步的 —— 本模块被
require 时 fskv 很可能还没初始化，此时读不到已保存的主题。所以：
  · 读不到 → 先上默认皮肤并返回 false，允许之后再次调用重试
  · 读到   → 应用并置位，后续调用直接返回
ui_main 的初始化协程会再调一次（那时 fskv 已就绪），确保开机配色不丢。
@return boolean 是否读到了已保存的主题（而非回落到默认）]]
local restored = false
function M.restore()
    if restored then return true end
    local id
    if fskv and fskv.get then
        local ok, v = pcall(fskv.get, KV_THEME)
        if ok and type(v) == "string" and v ~= "" then id = v end
    end
    if not id then
        M.apply(M.DEFAULT_THEME, false)
        return false
    end
    M.apply(id, false)
    restored = true
    return true
end

--[[动态令牌访问器 —— 换主题后自动取到新色值
页面顶部若写成 local COLOR_BG = theme.C.bg，该值在 require 时就被固化，
换主题后不会更新。改用：
    local CLR = theme.live()
    ... color = CLR.bg ...
CLR 的键先查 M.C，再查 M.SEM，等价于「theme.C.<键> 或 theme.SEM.<键>」。]]
local function live_index(_, k)
    local v = M.C[k]
    if v == nil then v = M.SEM[k] end
    return v
end
local live_mt = { __index = live_index }
function M.live() return setmetatable({}, live_mt) end

--[[换肤重建助手：返回 标记函数, 取用函数
页面模块加载时注册一次：
    local mark_theme_dirty, take_theme_dirty = theme.dirty_flag()
    sys.subscribe("UI_THEME_CHANGED", mark_theme_dirty)
然后在 on_get_focus 里：
    if take_theme_dirty() then 重建本页 end

为什么不在换肤当下直接重建：换肤是在设置页发起的，其余页面还在窗口栈下层，
此刻重建会打乱焦点与栈顺序；等方式，等它真正回到前台再重建。
标记/取用拆成两个函数也是为了不再依赖「匿名函数订阅 → 注销不掉」的坑。]]
function M.dirty_flag()
    local dirty = false
    return function() dirty = true end,
           function() local d = dirty; dirty = false; return d end
end

return M
