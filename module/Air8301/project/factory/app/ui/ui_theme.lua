--[[
@module  ui_theme
@summary Air8301 出厂固件 UI 设计系统（480×272 小屏·深色玻璃态）
@version 1.0
@date    2026.10.08
@author  江访

=== 设计来源 ===
视觉语言参考 factory_new（TabOS 深色玻璃态：深色底 + 面板卡片 + 琥珀强调色）。
但 8301 是 4.3 寸 480×272 的 SPI(ST6201) 屏，与参考目标的 >=800×480 RGB 大屏
差异巨大，故按小屏重新定标：
  1) 玻璃态降级为「深色实底面板 + 1px 描边」：视觉基调一致，SPI 刷新开销低，
     同时规避 AirUI(LVGL) 无模糊、无阴影的能力限制；
  2) 字号在 hzfont 16px 硬下限之上重新分档（16/18/20）；
  3) 全部几何按 480×272 定标：统一页边距 8、标题栏 40、内容区 210。

=== 用法 ===
local theme = require "ui_theme"
local ctx = theme.page({ title = "网络状态", on_back = on_back_click })
theme.kv_row(ctx.base, { x = ctx.x, y = ctx.y, w = ctx.w, label = "4G信号", value = "获取中" })
theme.label(ctx.base, { x = ctx.x, y = ..., text = "标题", px_size = theme.fs("h3") })

=== 关键约束（新增界面文案前必读） ===
固件内置字库 hzfont 的符号区极窄，下列字形不包含，渲染为空白或方框：
    ·  U+00B7 中缀点     ●  U+25CF 实心圆     •  U+2022 项目符号
    °  U+00B0 度符号     ←  →  ↑  ↓ 等箭头
已确认可用：℃(U+2103)、× (U+00D7)、ASCII 全量、全部汉字。
因此：行内分隔统一用 "|"，温度统一用 "℃"，状态圆点用 theme.dot() 画实心圆。
字号硬下限 16px：低于该值 hzfont 渲染发糊，theme 内部一律夹到 16。
]]

local M = {}

-- ==================== 一、设计令牌 ====================

-- 颜色（0xRRGGBB）
M.C = {
    bg          = 0x0D131C,   -- 页面底色
    bg_top      = 0x121A26,   -- 顶部微亮层
    panel       = 0x18202C,   -- 面板卡片底
    panel_hi    = 0x202A38,   -- 面板高亮（标题栏）
    surface     = 0xFFFFFF,   -- 白（配合低透明度做玻璃近似的描边/高光）
    t1          = 0xEDF1F7,   -- 主文字
    t2          = 0x95A0AE,   -- 次级文字
    t3          = 0x5E6978,   -- 弱文字
    amber       = 0xFFB454,   -- 主强调色（琥珀）
    amber_light = 0xFFCB7E,
    amber_deep  = 0xF08838,
    cyan        = 0x5CC9E8,   -- 信息 / 链接
    green       = 0x4FD69C,   -- 成功 / 在线
    violet      = 0xA78BFA,   -- 次级强调
    rose        = 0xFF7B8B,   -- 危险 / 断开
    stroke      = 0x333C4A,   -- 卡片 / 控件常规描边
    stroke_soft = 0x2A3240,   -- 弱描边（分隔线、内嵌色块）
    stroke_hi   = 0x4A5666,   -- 高亮描边（聚焦 / 按键）
    selected    = 0x25344A,   -- 列表行选中底
    pressed     = 0x2A3240,   -- 按压态底
    track       = 0x2C3542,   -- 进度条 / 开关轨道底
    input_bg    = 0x1B2431,   -- 输入框底
    knob        = 0xFFFFFF,   -- 开关滑块（开）
    knob_off    = 0xC9D2DC,   -- 开关滑块（关）
    on_amber    = 0x1A1206,   -- 琥珀底上的文字色
    divider     = 0xFFFFFF,   -- 分隔线（靠透明度压淡）
    scrim       = 0x0E141C,   -- 遮罩底
    white       = 0xFFFFFF,
    black       = 0x000000,
    -- 品牌蓝系列（业务模式主色；产测模式不引用，此处给出缺省值以保证令牌恒定存在）
    brand       = 0x2B6DE5,
    brand_light = 0x5B90F0,
    brand_deep  = 0x1F55C0,
    brand_soft  = 0xEAF1FE,
    on_brand    = 0xFFFFFF,
}

--[[语义色别名
业务页面应表达「语义」而非「色值」：用 theme.SEM.danger，不要硬编码 0xFF7B8B。
由 sync_sem() 在主题切换时统一刷新。]]
M.SEM = {
    danger  = M.C.rose,
    success = M.C.green,
    warning = M.C.amber,
    info    = M.C.cyan,
    link    = M.C.cyan,
    accent  = M.C.violet,
}

-- 透明度（0-255）
M.OPA = {
    glass    = 26,    -- 玻璃卡片（深底上轻微提亮）
    glass_hi = 36,    -- 玻璃高亮 / 选中
    fill     = 22,    -- 内嵌小色块
    fill_hi  = 32,
    stroke   = 22,    -- 描边
    divider  = 18,    -- 分隔线
    scrim    = 140,   -- 遮罩
    off      = 26,    -- 关闭态元素
}

-- 圆角（像素）
M.R = { lg = 8, md = 6, sm = 4, xs = 3 }

-- 字号档位（像素，均 >= FONT_MIN）
M.FS = { h1 = 20, h2 = 18, h3 = 16, body = 16, small = 16 }

-- hzfont 渲染清晰度硬下限
M.FONT_MIN = 16

--[[跨平台统一符号
hzfont 符号区极窄，只有下面两个符号确认可用，其余符号一律不要写进界面文案。]]
M.CHAR = { deg = "℃", sep = "|" }

--[[产品品牌名（左上角标题统一文案）
需要展示产品身份处（分区页状态条、开机画面等）一律引用本常量，不散落字面量。]]
M.BRAND = "合宙工业网关Air8301"

-- ==================== 二、屏幕与布局（480×272 横屏） ====================

M.SCREEN_W = 480
M.SCREEN_H = 272
M.HDR_H    = 40    -- 标题栏高度
M.PAD      = 8     -- 统一页边距
M.GAP      = 6     -- 标题栏与内容区之间的间距

local density = _G.density_scale or 1.0

-- 逻辑量（字号/圆角）→ 像素
local function dp(v)
    local d = _G.density_scale or density
    return math.floor((v or 0) * d + 0.5)
end
M.dp = dp

--[[字号：传档位名（"h2"/"body"…）或直接传像素数，结果一律夹到 FONT_MIN]]
function M.fs(name)
    if type(name) == "number" then
        local v = dp(name)
        if v < M.FONT_MIN then v = M.FONT_MIN end
        return v
    end
    local v = dp(M.FS[name] or M.FS.body)
    if v < M.FONT_MIN then v = M.FONT_MIN end
    return v
end

-- 圆角：传档位名，返回像素值
function M.r(name)
    return dp(M.R[name] or M.R.md)
end

--[[图标路径解析
以 "/" 开头的视为真实路径直接使用；否则按 /luadb/<name>.png 拼接。
8301 出厂固件的图标源文件在工程 web/ 目录：打包器把子目录内容平铺时设备内是
/luadb/hw_*.png，若打包器保留子目录则是 /luadb/web/hw_*.png —— 这里做一次存在性兜底，
两种打包方式都能显示图标。]]
function M.resolve_icon(v)
    if v == nil or v == "" then return nil end
    local has_io = io and io.exists
    if string.sub(v, 1, 1) == "/" then
        if has_io and not io.exists(v) and io.exists("/luadb/web" .. v) then
            return "/luadb/web" .. v
        end
        return v
    end
    local p = "/luadb/" .. v .. ".png"
    if has_io and not io.exists(p) and io.exists("/luadb/web/" .. v .. ".png") then
        return "/luadb/web/" .. v .. ".png"
    end
    return p
end

-- ==================== 三、基础绘制 ====================

--[[关闭容器滚动条（全工程统一兜底，v2.3 修复）

airui.container 底层是 LVGL 对象，默认带 SCROLLABLE 标志且 scrollbar_mode = AUTO：
子控件只要比容器高出 / 宽出 1px（取整误差、行高差、居中偏移都会造成），
容器就会在自身下边缘 / 右边缘画出一条滚动条 —— 这就是「按钮、小控件下方多出一条」的根因。

注意：airui.container 的参数表里 **没有 scrollable 字段**，传了会被直接忽略，
所以此前「传 scrollable = false 参数」的修法无效。必须用对象方法
set_scrollbar_mode(0)（0 = LV_SCROLLBAR_MODE_OFF）关闭。
部分固件版本无此方法，故做存在性判断 + pcall 保护。

@param object obj airui 容器对象
@return object 原对象（便于直接 return）
]]
local function no_scroll(obj)
    if obj and obj.set_scrollbar_mode then
        pcall(function() obj:set_scrollbar_mode(0) end)
    end
    return obj
end

--[[矩形容器（最常用的布局盒子）
  opa = 0 时完全透明（只当布局容器用）
  on_click / on_long_press 直接透传]]
function M.box(parent, o)
    o = o or {}
    return no_scroll(airui.container({
        parent      = o.parent or parent,
        x           = o.x or 0,
        y           = o.y or 0,
        w           = o.w,
        h           = o.h,
        color       = o.color,
        color_opacity = o.opa,
        radius      = dp(o.radius or 0),
        border_color = o.border,
        border_width = o.border and (o.border_w or 1) or 0,
        scrollable  = (o.scrollable == true),
        clip_corner = (o.clip_corner == true),
        on_click    = o.on_click,
        on_long_press = o.on_long_press,
    }))
end

--[[面板卡片（深色实底 + 1px 描边，替代玻璃态）
  默认：panel 实底 + stroke 描边 + 圆角 lg；传 opa < 255 可做半透明玻璃近似。]]
function M.card(parent, o)
    o = o or {}
    local color = o.color or M.C.panel
    local opa = (o.opa ~= nil) and o.opa or 255
    local border = o.border
    if border == nil and o.border_w ~= 0 then border = M.C.stroke end
    local bw
    if o.border_w ~= nil then bw = o.border_w
    elseif border then bw = 1
    else bw = 0 end
    return no_scroll(airui.container({
        parent      = o.parent or parent,
        x           = o.x or 0,
        y           = o.y or 0,
        w           = o.w or 0,
        h           = o.h or 0,
        color       = color,
        color_opacity = opa,
        radius      = dp(o.radius or M.R.lg),
        border_color = border,
        border_width = bw,
        scrollable  = (o.scrollable == true),
        clip_corner = (o.clip_corner == true),
        on_click    = o.on_click,
        on_long_press = o.on_long_press,
    }))
end

--[[文本标签
  盒高 h 缺省取「字号 + 3」——hzfont 行高 = 字号 + 3，盒高不足会把文字画到盒子外。
  需要严格按像素字号时传 px_size；否则用 size 传档位名。]]
function M.label(parent, o)
    o = o or {}
    local fs = o.px_size or M.fs(o.size or "body")
    return airui.label({
        parent      = o.parent or parent,
        x           = o.x or 0,
        y           = o.y or 0,
        w           = o.w or 100,
        h           = o.h or (fs + 3),
        text        = o.text or "",
        font_size   = fs,
        color       = o.color or M.C.t1,
        align       = o.align or airui.TEXT_ALIGN_LEFT,
        on_click    = o.on_click,
        on_long_press = o.on_long_press,
    })
end

--[[图片
  src 支持真实路径或语义名（自动补 /luadb/ 前缀）；资源缺失时跳过绘制并返回 nil]]
function M.image(parent, o)
    o = o or {}
    local src = M.resolve_icon(o.src)
    if src == nil then return nil end
    return airui.image({
        parent  = o.parent or parent,
        x       = o.x or 0,
        y       = o.y or 0,
        w       = o.w or 24,
        h       = o.h or 24,
        src     = src,
        fit     = o.fit or "contain",
        -- opacity 仅在调用方显式传入时下发：airui 的 opacity/zoom 仅对 PNG 生效，
        -- 官方文档注明「jpg 必须为默认值」，对 JPEG 传入会干扰其解码渲染；
        -- 不传时 airui 内部默认即 255（不透明），对 PNG 的行为完全等价。
        opacity = o.opacity,
        on_click = o.on_click,
    })
end

--[[实心圆点（状态指示）
  hzfont 没有 ● 字形，状态圆点一律用本函数画。radius = 直径 即得正圆。]]
function M.dot(parent, o)
    o = o or {}
    local d = o.d or 8
    return M.box(parent, {
        x = o.x or 0, y = o.y or 0, w = d, h = d,
        color = o.color or M.C.green,
        opa = 255,
        radius = math.floor(d / 2),
        on_click = o.on_click,
    })
end

-- 分隔线
function M.divider(parent, o)
    o = o or {}
    return M.box(parent, {
        x = o.x or 0, y = o.y or 0, w = o.w or 100, h = o.h or 1,
        color = o.color or M.C.divider,
        opa = (o.opa ~= nil) and o.opa or M.OPA.divider,
    })
end

-- 分组小标题
-- 兼容保护：若第一个参数是字符串（分区 key），说明调用方想取「分区配色」，
-- 转交 M.pal 处理，避免误建 label 或与 M.pal 语义混淆。
function M.section(parent, o)
    if type(parent) == "string" then return M.pal(parent) end
    o = o or {}
    local fs = o.px_size or M.fs(o.size or "small")
    return M.label(parent, {
        x = o.x, y = o.y, w = o.w, h = o.h or (fs + 3),
        text = o.text or "",
        px_size = fs,
        color = o.color or M.C.t3,
        align = o.align or airui.TEXT_ALIGN_LEFT,
    })
end

-- ==================== 四、交互组件 ====================

--[[点击回调去重（全局工具）
airui 的触摸事件在「父容器 + 子元素」之间可能存在重复投递（父子各触发一次）。
为固定「一次物理点击 = 一次业务翻转」的语义，用本函数包装回调：window 毫秒内只放行首次。
每次调用各自持锁，互不干扰。

@param function fn     原始回调（非函数时原样返回）
@param number   window 去重窗口(ms)，默认 60
@return function 包装后的回调
]]
function M.click_once(fn, window)
    if type(fn) ~= "function" then return fn end
    local win = window or 60
    local locked = false
    local function unlock() locked = false end
    return function(...)
        if locked then return end
        locked = true
        sys.timerStart(unlock, win)
        return fn(...)
    end
end

--[[可点击卡片：点击贯通到卡片内**所有**子元素（务必配合使用）

用法：
  local card, tap = theme.tap_card(parent, { x=.., y=.., w=.., h=.., on_click=fn })
  theme.label(card, { ..., on_click = tap })
  theme.box  (card, { ..., on_click = tap })

即把返回的 tap 交给卡片内每一个可见子元素。
原因：airui 的触摸命中不会从子元素回传给父容器，只给外层容器绑回调时，
      命中图标 / 文字 / 状态点等子元素区域的触摸会被直接吞掉，
      表现为「按钮非常不灵敏、只有容器空白/边缘能点」。全绑 + 去重后整卡任意处可点，且只触发一次。

@return card 卡片容器
@return tap  已去重的回调（未传 on_click 时为 nil）
]]
function M.tap_card(parent, o)
    o = o or {}
    local tap = o.on_click and M.click_once(o.on_click) or nil
    local card = M.card(parent, {
        x = o.x, y = o.y, w = o.w, h = o.h,
        color = o.color, radius = o.radius, border = o.border,
        on_click = tap,
    })
    return card, tap
end

--[[主按钮（主强调色实底 + 反色文字）
  返回按钮容器；文字为子 label
  v2.1：容器与文字 label 绑定同一去重回调（避免点到文字区域无响应）
  v2.4：主色改引用语义令牌 M.C.primary —— 产测模式=琥珀、业务模式=品牌蓝，随主题自动切换]]
function M.btn(parent, o)
    o = o or {}
    local w, h = o.w or 96, o.h or 34
    local bg = o.bg or M.C.primary
    local fg = o.fg or M.C.on_primary
    local fs = M.fs(o.size or "body")
    -- 点击贯通：容器与文字 label 绑同一去重回调，点文字区域同样生效
    local tap = o.on_click and M.click_once(o.on_click) or nil
    local btn = no_scroll(airui.container({
        parent = o.parent or parent,
        x = o.x or 0, y = o.y or 0, w = w, h = h,
        color = bg, color_opacity = 255,
        radius = dp(o.radius or M.R.md),
        border_color = o.border, border_width = o.border and 1 or 0,
        -- 按钮是固定尺寸控件，子 label 触边会让容器在下边缘画出滚动条；
        -- 创建后由 no_scroll() 调 set_scrollbar_mode(0) 关闭（v2.3 修复）
        on_click = tap,
    }))
    M.label(btn, {
        --[[标签宽度左右各内缩 2px（不触边）
        airui.container 底层是 LVGL 对象：只要子元素与容器边缘「贴合」（哪怕 0px 差），
        容器就会在自身下边缘画出滚动条 —— 这就是「按钮 / 返回键下方多出一条横线」的根因。
        此前改用 set_scrollbar_mode(0) 的做法在部分固件版本上并无该方法（被静默跳过）；
        内缩标签宽度属于「消除触边条件」，不依赖任何固件 API，可靠消除该横条。]]
        x = 2, y = math.floor((h - (fs + 3)) / 2), w = w - 4, h = fs + 3,
        text = o.text or "", px_size = fs, color = fg,
        align = airui.TEXT_ALIGN_CENTER,
        on_click = tap,
    })
    return btn
end

--[[幽灵按钮（描边底）
  on 为真时用主强调色描边 + 主强调色文字，用于「一组里选中当前项」
  v2.4：主色改引用 M.C.primary，随主题自动切换（业务模式为品牌蓝、产测模式为琥珀）；
        透明度仍沿用 M.OPA.glass_hi / M.OPA.fill，保证产测观感与改动前完全一致]]
function M.ghost(parent, o)
    o = o or {}
    local w, h = o.w or 96, o.h or 34
    local on = (o.on == true)
    local fs = M.fs(o.size or "body")
    -- 点击贯通：容器与文字 label 绑同一去重回调
    local tap = o.on_click and M.click_once(o.on_click) or nil
    local btn = no_scroll(airui.container({
        parent = o.parent or parent,
        x = o.x or 0, y = o.y or 0, w = w, h = h,
        color = on and M.C.primary or M.C.surface,
        color_opacity = on and M.OPA.glass_hi or M.OPA.fill,
        radius = dp(o.radius or M.R.md),
        border_color = on and M.C.primary or M.C.stroke,
        border_width = 1,
        -- 同 M.btn：创建后由 no_scroll() 调 set_scrollbar_mode(0) 关闭（v2.3 修复）
        on_click = tap,
    }))
    M.label(btn, {
        -- 标签宽度左右各内缩 2px，消除「子元素触边 → 容器画滚动条」（同 M.btn，v2.5 修复）
        x = 2, y = math.floor((h - (fs + 3)) / 2), w = w - 4, h = fs + 3,
        text = o.text or "", px_size = fs,
        color = on and M.C.primary_light or (o.fg or M.C.t1),
        align = airui.TEXT_ALIGN_CENTER,
        on_click = tap,
    })
    return btn
end

--[[状态胶囊（圆点 + 文字）
  返回胶囊容器，可用 :set_dot? 不便，动态更新请自行重建或改用 label:set_text]]
function M.chip(parent, o)
    o = o or {}
    local h = o.h or 26
    local w = o.w or 96
    local chip = M.card(parent, {
        x = o.x, y = o.y, w = w, h = h,
        color = o.color or M.C.panel,
        radius = M.R.sm,
        border = o.border or M.C.stroke_soft,
    })
    local tx = 10
    if o.dot then
        M.dot(chip, { x = 10, y = math.floor((h - 8) / 2), d = 8, color = o.dot })
        tx = 24
    end
    local fs = o.px_size or M.fs("small")
    M.label(chip, {
        x = tx, y = math.floor((h - (fs + 3)) / 2), w = w - tx - 8, h = fs + 3,
        text = o.text or "", px_size = fs,
        color = o.text_color or M.C.t2,
        align = airui.TEXT_ALIGN_LEFT,
    })
    return chip
end

--[[键值行（左侧标签 + 右侧数值）
  返回 row, value_label —— value_label 可直接 :set_text() / :set_color() 做动态刷新]]
function M.kv_row(parent, o)
    o = o or {}
    local fs = o.px_size or M.fs(o.size or "body")
    local lh = fs + 3
    local h = o.h or (lh + 16)
    local pad = o.pad or 10
    -- 行内文字与容器绑同一去重回调（点击贯通）
    local tap = o.on_click and M.click_once(o.on_click) or nil
    local row = M.card(parent, {
        x = o.x, y = o.y, w = o.w, h = h,
        color = o.color or M.C.panel,
        radius = (o.radius ~= nil) and o.radius or M.R.sm,
        border = (o.border ~= nil) and o.border or M.C.stroke_soft,
        on_click = tap,
    })
    local ty = math.floor((h - lh) / 2)
    if ty < 0 then ty = 0 end
    local lw = o.label_w or math.floor((o.w or 200) * 0.42)
    M.label(row, {
        x = pad, y = ty, w = lw, h = lh,
        text = o.label or "", px_size = fs,
        color = o.label_color or M.C.t2,
        align = airui.TEXT_ALIGN_LEFT,
        on_click = tap,
    })
    local value_label = M.label(row, {
        x = pad + lw, y = ty, w = (o.w or 200) - pad * 2 - lw, h = lh,
        text = o.value or "", px_size = fs,
        color = o.value_color or M.C.t1,
        align = o.align or airui.TEXT_ALIGN_RIGHT,
        on_click = tap,
    })
    return row, value_label
end

--[[列表行（图标 + 标题 + 右侧文字，可点击）
  返回 row, title_label, right_label]]
function M.row(parent, o)
    o = o or {}
    local w, h = o.w or 300, o.h or 40
    -- 点击贯通：容器、图标、左右文字全部绑同一去重回调
    local tap = o.on_click and M.click_once(o.on_click) or nil
    local row = M.card(parent, {
        x = o.x, y = o.y, w = w, h = h,
        color = o.color or M.C.panel,
        radius = (o.radius ~= nil) and o.radius or M.R.sm,
        border = (o.border ~= nil) and o.border or M.C.stroke_soft,
        on_click = tap,
    })
    local tx = 10
    if o.icon then
        local s = o.icon_size or 22
        M.image(row, { x = 10, y = math.floor((h - s) / 2), w = s, h = s, src = o.icon, on_click = tap })
        tx = 10 + s + 8
    end
    local fs = o.px_size or M.fs(o.size or "body")
    local lh = fs + 3
    local fr = o.right_px or M.fs("small")
    local right_w = o.right_w or (o.right and 150 or 0)
    local txw = w - tx - 10 - right_w
    if txw < 24 then txw = 24 end
    local ty = math.floor((h - lh) / 2)
    if ty < 0 then ty = 0 end
    local title_label = M.label(row, {
        x = tx, y = ty, w = txw, h = lh,
        text = o.text or "", px_size = fs,
        color = o.text_color or M.C.t1,
        align = airui.TEXT_ALIGN_LEFT,
        on_click = tap,
    })
    local right_label = nil
    if o.right then
        right_label = M.label(row, {
            x = w - right_w - 10, y = math.floor((h - (fr + 3)) / 2), w = right_w, h = fr + 3,
            text = o.right, px_size = fr,
            color = o.right_color or M.C.t2,
            align = airui.TEXT_ALIGN_RIGHT,
            on_click = tap,
        })
    end
    return row, title_label, right_label
end

--[[功能磁贴（分区页入口：图标 + 名称 + 状态摘要）
  返回 tile, name_label, sub_label, dot
    - sub 为可选：不传则退化为「图标 + 名称」的纯入口磁贴
    - name_label / sub_label 可动态 set_text / set_color 做状态刷新
    - dot 恒为 nil（依需求已移除右上角状态点，仅保留返回位以兼容调用方）
]]
function M.tile(parent, o)
    o = o or {}
    local w, h = o.w or 88, o.h or 62
    --[[点击贯通：把同一去重回调绑到磁贴及其全部可见子元素。
    airui 的触摸命中不会从子元素回传给父容器，若只绑外层容器，
    点到图标 / 名称 / 摘要 / 状态点区域时事件会被吞掉 → 表现为「磁贴不灵敏」。
    全绑 + 去重后，磁贴任意位置均可点，且一次点击只触发一次业务。]]
    local tap = o.on_click and M.click_once(o.on_click) or nil
    local tile = M.card(parent, {
        x = o.x, y = o.y, w = w, h = h,
        -- v2.4：支持分区配色 —— 传入 accent_soft / accent_line 时使用分区浅底 + 分区描边，
        -- 使「通信 / IO / 系统」各分区一眼可辨；不传则维持通用面板底（产测模式即如此）。
        color = o.color or o.accent_soft or M.C.panel,
        radius = o.radius or M.R.md,
        border = o.border or o.accent_line or M.C.stroke_soft,
        on_click = tap,
    })
    -- 依需求移除磁贴右上角状态点；保留 dot 变量（恒为 nil）以兼容既有返回签名
    local dot = nil

    local isz = o.icon_size or 26
    local iy = o.icon_y or 9
    if o.icon then
        M.image(tile, { x = math.floor((w - isz) / 2), y = iy, w = isz, h = isz, src = o.icon, on_click = tap })
    end

    local fs = M.fs("small")
    local name_label = M.label(tile, {
        x = 2, y = iy + isz + 5, w = w - 4, h = fs + 3,
        text = o.text or "", px_size = fs,
        color = o.text_color or M.C.t1,
        align = airui.TEXT_ALIGN_CENTER,
        on_click = tap,
    })

    local sub_label = nil
    if o.sub then
        sub_label = M.label(tile, {
            x = 2, y = iy + isz + 5 + fs + 4, w = w - 4, h = fs + 3,
            text = o.sub, px_size = fs,
            color = o.sub_color or M.C.t3,
            align = airui.TEXT_ALIGN_CENTER,
            on_click = tap,
        })
    end
    return tile, name_label, sub_label, dot
end

--[[开关（轨道 + 滑块，自绘以完全跟随主题令牌）
  返回 handle，方法：get_state() / set_state(bool) / set_enabled(bool)
  on_change(handle) 在状态切换后回调

  两种工作模式：
    1) 常规（o.readonly 非真）：开关自行响应点击，内部 50ms 去重后翻转并回调；
    2) 只读指示（o.readonly = true）：开关不自行翻转，仅作状态显示；
       此时可传 o.tap（父卡片已去重的回调）绑到轨道与滑块上，
       使「点开关图形区域」也能命中父卡片的业务逻辑（点击贯通）。]]
local function build_switch(parent, o)
    o = o or {}
    local w, h = o.w or 44, o.h or 24
    local pad = 3
    local kd = h - pad * 2
    local state = (o.checked == true)
    local enabled = (o.disabled ~= true)
    local on_color = o.color or M.C.primary
    local track, knob
    local handle = { _state = state, _enabled = enabled }

    local function track_color(s)
        if not enabled then return M.C.stroke_soft end
        return s and on_color or M.C.track
    end

    local function apply()
        track:set_color(track_color(state), 255)
        track:set_border_color(track_color(state), 1)
        knob:set_color(enabled and (state and M.C.knob or M.C.knob_off) or M.C.t3, 255)
        knob:set_pos(state and (w - pad - kd) or pad, pad)
    end

    --[[点击去重：滑块是轨道的子容器，二者都会收到同一次点击。
       若各自回调就会「翻转两次 = 视觉上没反应」，故 50ms 内只取第一次触发。]]
    local toggle_locked = false
    local function unlock_toggle()
        toggle_locked = false
    end

    local function do_toggle()
        if not enabled or toggle_locked then return end
        toggle_locked = true
        sys.timerStart(unlock_toggle, 50)
        state = not state
        handle._state = state
        apply()
        if o.on_change then o.on_change(handle) end
    end

    --[[readonly = true：只作「状态指示器」绘制，不自行翻转，点击由父卡片承接。
    v2.2：允许外部传入已去重的 o.tap 并绑到轨道与滑块 ——
    airui 的触摸命中不会从子元素回传给父容器，若此二者不绑回调，
    点到开关图形区域的事件会被吞掉，表现为「点开关没反应 / 不灵敏」。]]
    local click_cb
    if o.readonly then
        click_cb = o.tap           -- 外部已去重回调（可为 nil：纯指示、不可点）
    else
        click_cb = do_toggle
    end

    track = no_scroll(airui.container({
        parent = o.parent or parent,
        x = o.x or 0, y = o.y or 0, w = w, h = h,
        color = track_color(state), color_opacity = 255,
        radius = math.floor(h / 2),
        border_color = track_color(state), border_width = 1,
        -- 开关为固定尺寸控件，创建后由 no_scroll() 关闭滚动条（v2.3 修复）
        on_click = click_cb,
    }))
    knob = no_scroll(airui.container({
        parent = track,
        x = state and (w - pad - kd) or pad, y = pad, w = kd, h = kd,
        color = state and M.C.knob or M.C.knob_off, color_opacity = 255,
        radius = math.floor(kd / 2),
        on_click = click_cb,
    }))
    handle.track = track
    handle.knob = knob

    function handle:get_state() return self._state end
    function handle:set_state(v)
        v = (v == true)
        if self._state == v then return end
        self._state = v
        state = v
        apply()
    end
    function handle:set_enabled(v)
        enabled = (v == true)
        apply()
    end
    return handle
end

--[[开关组件
  o.readonly = true 时仅作状态指示器（不自行翻转）；
  o.tap 传入父卡片已去重的回调后，轨道与滑块也会命中该回调（整卡点击贯通）。]]
function M.switch(parent, o)
    return build_switch(parent, o)
end

--[[进度条
  返回 airui.bar 对象（自带 set_value(v, anim)）]]
function M.bar(parent, o)
    o = o or {}
    return no_scroll(airui.bar({
        parent = o.parent or parent,
        x = o.x or 0, y = o.y or 0, w = o.w or 200, h = o.h or 8,
        min = o.min or 0, max = o.max or 100, value = o.value or 0,
        bg_color = o.track or M.C.track,
        indicator_color = o.color or M.C.primary,
        radius = (o.radius ~= nil) and o.radius or dp(99),
    }))
end

--[[输入框
  style 字段可整体覆盖；其余透传 airui.textarea]]
function M.input(parent, o)
    o = o or {}
    local st = {
        radius = dp(o.radius or M.R.sm),
        bg_color = o.bg or M.C.input_bg,
        text_color = o.fg or o.text_color or M.C.t1,
        font_size = o.px_size or M.fs("body"),
    }
    if o.style then
        for k, v in pairs(o.style) do st[k] = v end
    end
    return airui.textarea({
        parent = o.parent or parent,
        x = o.x or 0, y = o.y or 0, w = o.w or 200, h = o.h or 36,
        text = o.text, placeholder = o.placeholder,
        max_len = o.max_len, align = o.align,
        disabled = o.disabled, keyboard = o.keyboard,
        -- airui.textarea 的密码输入模式参数名是 mode（取值 "password"），并无 password_mode 字段；
        -- 本封装兼容两种写法：显式传 mode 优先，否则由 password_mode 映射，避免密码被明文显示
        mode = o.mode or (o.password_mode and "password" or nil),
        on_text_change = o.on_text_change,
        style = st,
    })
end

-- ==================== 五、页面骨架 ====================

--[[标题栏（返回键 + 标题 + 可选右侧状态文字）
  返回 bar, h, title_label, right_label]]
function M.header(parent, o)
    o = o or {}
    local w = o.w or M.SCREEN_W
    local h = o.h or M.HDR_H
    local bar = M.card(parent, {
        x = o.x or 0, y = o.y or 0, w = w, h = h,
        color = o.color or M.C.panel_hi,
        radius = o.radius or M.R.lg,
        border = o.border or M.C.stroke,
    })

    local tx = 12
    if o.on_back then
        local bs = h - 12
        -- 返回键点击贯通：容器与 "<" 文字 label 同绑一个去重回调
        local back_tap = o.on_back and M.click_once(o.on_back) or nil
        local back = M.card(bar, {
            x = 6, y = math.floor((h - bs) / 2), w = bs + 10, h = bs,
            color = M.C.panel, radius = M.R.sm, border = M.C.stroke_hi,
            on_click = back_tap,
        })
        local fsb = M.fs("h2")
        M.label(back, {
            -- "<" 文字左右各内缩 2px，消除「返回键下方滚动条」（子元素触边，v2.5 修复）
            x = 2, y = math.floor((bs - (fsb + 3)) / 2), w = bs + 6, h = fsb + 3,
            text = "<", px_size = fsb, color = M.C.primary_light,
            align = airui.TEXT_ALIGN_CENTER,
            on_click = back_tap,
        })
        tx = 6 + bs + 10 + 8
    end

    local fs = o.title_px or M.fs("h2")
    local fr = o.right_px or M.fs("small")
    local right_w = o.right_w or (o.right and 160 or 0)
    local tw = w - tx - right_w - 10
    if tw < 40 then tw = 40 end
    local th = fs + 3
    local title_label = M.label(bar, {
        x = tx, y = math.floor((h - th) / 2), w = tw, h = th,
        text = o.title or "", px_size = fs,
        color = o.title_color or M.C.t1,
        align = airui.TEXT_ALIGN_LEFT,
    })
    local right_label = nil
    if o.right then
        right_label = M.label(bar, {
            x = w - right_w - 10, y = math.floor((h - (fr + 3)) / 2), w = right_w, h = fr + 3,
            text = o.right, px_size = fr,
            color = o.right_color or M.C.t2,
            align = airui.TEXT_ALIGN_RIGHT,
        })
    end
    return bar, h, title_label, right_label
end

--[[统一页面骨架：深色底 + 标题栏 + 内容区
@table o
  parent      父容器，默认 airui.screen
  title       给了就画标题栏
  on_back     返回回调（给了才画返回键）
  right       标题栏右侧状态文字
  pad         页边距，默认 M.PAD(8)
  header_pad  标题栏与内容区间距，默认 M.GAP(6)
@return ctx { base, bar, pad, sw, sh, x, y, w, h, title_label, right_label }
         x/y/w/h 即内容区（标题栏之下）的像素几何，均相对 ctx.base
]]
function M.page(o)
    o = o or {}
    local sw, sh = M.SCREEN_W, M.SCREEN_H
    local pad = o.pad or M.PAD
    local p = o.parent or airui.screen
    local base = M.box(p, { x = 0, y = 0, w = sw, h = sh, color = M.C.bg })

    local ctx = {
        base = base, pad = pad, sw = sw, sh = sh,
        x = pad, y = pad, w = sw - 2 * pad, h = sh - 2 * pad,
    }
    if o.title then
        local bar, bh, title_label, right_label = M.header(base, {
            x = pad, y = pad, w = sw - 2 * pad, h = M.HDR_H,
            title = M.BRAND,             -- 左上角统一显示产品品牌名（不随页面变化）
            on_back = o.on_back,
            right = o.right or o.title,  -- 各页页名移到标题栏右侧，保留页面身份
            right_w = o.right_w,
            title_px = o.title_px, title_color = o.title_color,
        })
        local gap = (o.header_pad ~= nil) and o.header_pad or M.GAP
        ctx.bar = bar
        ctx.hdr_h = bh
        ctx.title_label = title_label
        ctx.right_label = right_label
        ctx.y = pad + bh + gap
        ctx.h = sh - ctx.y - pad
        if ctx.h < 1 then ctx.h = 1 end
    else
        ctx.bar = nil
        ctx.hdr_h = 0
    end
    return ctx
end

-- ==================== 五之二、仪表盘范式（v2.0 新增） ====================
--[[
方案A：把「一个 5×3 图标总菜单」改为「4 个功能分区 + 底部 Dock 切换」。
  - 分区页（主页/通信/IO/系统）用 M.shell() 搭建：顶部状态条 + 中部内容区 + 底部 Dock
  - 二级功能页继续用 M.page()（带返回键），业务逻辑不变
这样首页成为实时状态仪表盘，功能入口按分区收纳，信息架构从「扁平 14 项」变为「4 分区」。
]]

--[[底部分区导航定义
字段：key 分区标识（与 shell 的 active 匹配）；label 显示名；icon 图标；msg 点击后发布的消息]]
M.NAV = {
    { key = "overview", label = "主页", icon = "/luadb/hw_sysinfo.png", msg = "OPEN_IDLE_WIN" },
    { key = "comm",     label = "通信", icon = "/luadb/hw_network.png", msg = "OPEN_COMM_WIN" },
    { key = "io",       label = "IO",   icon = "/luadb/hw_di.png",      msg = "OPEN_IO_WIN"   },
    { key = "system",   label = "系统", icon = "/luadb/hw_flash.png",   msg = "OPEN_SYS_WIN"  },
}

--[[业务模式「分区主色」表（v2.4）
仅为业务模式分区页提供辨识色：Dock 选中项与分区磁贴使用。
字段：main 主色（描边 / 文字）、soft 极浅底、line 浅描边。
产测模式不使用本表（产测页面不传 accent）。]]
M.SECTION = {
    overview = { main = 0x2B6DE5, soft = 0xEEF4FE, line = 0xC9DDFB },
    comm     = { main = 0x12B5A8, soft = 0xE7F8F6, line = 0xBDE9E4 },
    io       = { main = 0x22B573, soft = 0xE9F8F0, line = 0xC4ECDA },
    system   = { main = 0x7C5CE6, soft = 0xF2EDFD, line = 0xD9CCF8 },
}

--[[取分区配色（缺省回退到主题主色）

【重要】本函数原命名为 M.section，与上文「分组小标题」组件 M.section(parent, o) 同名。
Lua 后定义者覆盖前者，导致分组小标题组件被本函数覆盖掉 —— 表现为
「联网方式 / 4G信号 / 本机IP / 当前时间 / 天气」等所有分组小标题文字整片消失
（调用 theme.section(parent, opts) 时实际执行的是本函数，只返回一个颜色表、不创建 label）。
故改名为 M.pal，与组件 M.section 彻底区分，二者不再冲突。

@param string key 分区标识（M.NAV[i].key）
@return table { main, soft, line }
]]
function M.pal(key)
    return M.SECTION[key] or { main = M.C.primary, soft = M.C.panel, line = M.C.stroke_soft }
end

-- 顶部状态条 / 底部 Dock / 底部操作条高度
-- 480×272 下：状态条 30 + 间距 6 + 内容区 182 + 间距 6 + Dock 48 = 272，恰好铺满
M.STATUS_H = 30
M.DOCK_H   = 48
-- 底部操作条（产测首页等无 Dock 的分区页使用）：状态条 30 + 间距 6 + 内容区 190 + 操作条 44 + 间距 2
M.BOTTOM_H = 44

--[[顶部状态条（分区页专用）
左侧标题（缺省 M.BRAND「合宙工业网关Air8301」），右侧仅显示时间（依需求已移除告警 / WiFi / 信号三个状态点）。
@return bar, handle   handle = { title, right, time, signal, wifi, alarm }，可动态 set_text / set_color；signal / wifi / alarm 恒为 nil
]]
function M.statusbar(parent, o)
    o = o or {}
    local w = o.w or M.SCREEN_W
    local h = o.h or M.STATUS_H
    local bar = M.card(parent, {
        x = o.x or 0, y = o.y or 0, w = w, h = h,
        color = o.color or M.C.bg_top,
        radius = 0, border = nil, border_w = 0,
    })

    local fs = M.fs("h3")
    local lh = fs + 3
    local ty = math.floor((h - lh) / 2)

    -- 可选右侧状态文字（如产测标识）：为其让出宽度，避免与左侧标题重叠
    local right_w = o.right and (o.right_w or 40) or 0
    local title = M.label(bar, {
        x = 12, y = ty, w = w - 200 - (right_w > 0 and (right_w + 10) or 0), h = lh,
        text = o.title or M.BRAND, px_size = fs,   -- 缺省显示产品品牌名
        color = o.title_color or M.C.t1,
        align = airui.TEXT_ALIGN_LEFT,
    })

    -- 右侧时间（自右向左布局）
    local rx = w - 10

    local time_w = 52
    local time_label = M.label(bar, {
        x = rx - time_w, y = ty, w = time_w, h = lh,
        text = o.time or "", px_size = fs,
        color = M.C.t2, align = airui.TEXT_ALIGN_RIGHT,
    })
    rx = rx - time_w - 14

    -- 可选右侧状态文字（排在时间左侧，如产测模式的「产测」标识）
    local right_label = nil
    if o.right then
        right_label = M.label(bar, {
            x = rx - right_w, y = ty, w = right_w, h = lh,
            text = o.right, px_size = fs,
            color = o.right_color or M.C.amber_light,
            align = airui.TEXT_ALIGN_RIGHT,
        })
        rx = rx - right_w - 10
    end

    -- 依需求移除「时间左侧的三个状态点」（告警 / WiFi / 信号），不再绘制；
    -- 句柄一律以 nil 返回，调用方（idle_win / comm_win）均先 if 判空再 set_color，行为安全。
    return bar, { title = title, right = right_label, time = time_label, signal = nil, wifi = nil, alarm = nil }
end

--[[Dock 导航项点击回调工厂
用工厂函数返回闭包，避免在循环内直接写匿名函数捕获循环变量]]
local function make_nav_handler(o, item)
    return function()
        if o.on_nav then o.on_nav(item.key, item.msg, item.label) end
    end
end

--[[底部 Dock 分区导航（4 项，当前分区以「分区主色」高亮）
@table o
  active  当前分区 key（与 M.NAV[i].key 匹配）
  on_nav  function(key, msg, label) 点击回调
@return dock 容器
@note v2.4：选中项改用该分区的专属色（浅底 + 分区色描边与文字），替代原来的琥珀高亮，
      四个分区一眼可辨；底色仍为浅色，不会遮挡分区图标本身。
]]
function M.dock(parent, o)
    o = o or {}
    local w = o.w or M.SCREEN_W
    local h = o.h or M.DOCK_H
    local y = (o.y ~= nil) and o.y or (M.SCREEN_H - h)
    local dock = M.card(parent, {
        x = o.x or 0, y = y, w = w, h = h,
        color = o.color or M.C.panel,
        radius = 0, border = nil, border_w = 0,
    })

    local n = #M.NAV
    local pad, gap = 6, 4
    local iw = math.floor((w - pad * 2 - gap * (n - 1)) / n)
    local ih = h - 10

    for i = 1, n do
        local item = M.NAV[i]
        local on = (item.key == o.active)
        local sect = M.pal(item.key)
        local x = pad + (i - 1) * (iw + gap)
        -- 点击贯通：Dock 项容器、图标、文字绑同一去重回调
        local tap = M.click_once(make_nav_handler(o, item))
        local btn = M.card(dock, {
            x = x, y = 5, w = iw, h = ih,
            color = on and sect.soft or M.C.surface,
            opa = on and 255 or 0,
            radius = M.R.sm,
            border = on and sect.main or nil,
            border_w = on and 1 or 0,
            on_click = tap,
        })
        local fs = M.fs("small")
        local lh = fs + 3
        -- 图标缺失时自动退回「纯文字居中」，不报错
        local icon = M.image(btn, { x = 12, y = math.floor((ih - 20) / 2), w = 20, h = 20, src = item.icon, on_click = tap })
        local tx = icon and 38 or 0
        M.label(btn, {
            x = tx, y = math.floor((ih - lh) / 2), w = iw - tx - 8, h = lh,
            text = item.label, px_size = fs,
            color = on and sect.main or M.C.t2,
            align = icon and airui.TEXT_ALIGN_LEFT or airui.TEXT_ALIGN_CENTER,
            on_click = tap,
        })
    end
    return dock
end

--[[仪表盘状态卡（左上标题 + 中间英雄值 + 底部副值）
@return card, handle   handle = { value, sub, dot }，value / sub 可动态 set_text / set_color；dot 恒为 nil
]]
function M.stat_card(parent, o)
    o = o or {}
    local w, h = o.w or 228, o.h or 88
    -- 点击贯通：卡片与卡内全部文字 / 状态点绑同一去重回调
    local tap = o.on_click and M.click_once(o.on_click) or nil
    local card = M.card(parent, {
        x = o.x or 0, y = o.y or 0, w = w, h = h,
        color = o.color or M.C.panel,
        radius = o.radius or M.R.lg,
        border = o.border or M.C.stroke_soft,
        on_click = tap,
    })

    local pad = 10
    local fs_t = M.fs("small")
    local fs_v = o.value_px or M.fs("h1")
    local fs_s = M.fs("small")

    M.label(card, {
        x = pad, y = 8, w = w - pad * 2 - 14, h = fs_t + 3,
        text = o.title or "", px_size = fs_t,
        color = o.title_color or M.C.t3,
        align = airui.TEXT_ALIGN_LEFT,
        on_click = tap,
    })
    -- 依需求移除卡片右上角状态点；保留 dot 变量（恒为 nil）以兼容 handle.dot 判空写法
    local dot = nil

    local value = M.label(card, {
        x = pad, y = 30, w = w - pad * 2, h = fs_v + 3,
        text = o.value or "--", px_size = fs_v,
        color = o.value_color or M.C.t1,
        align = airui.TEXT_ALIGN_LEFT,
        on_click = tap,
    })
    local sub = M.label(card, {
        x = pad, y = h - fs_s - 10, w = w - pad * 2, h = fs_s + 3,
        text = o.sub or "", px_size = fs_s,
        color = o.sub_color or M.C.t2,
        align = airui.TEXT_ALIGN_LEFT,
        on_click = tap,
    })
    return card, { value = value, sub = sub, dot = dot }
end

--[[分区页骨架（方案A：顶部状态条 + 中部内容区 + 底部导航/操作条）
@table o
  title   状态条左标题（可动态改写以承载进度文字）
  active  当前分区 key（nav ~= false 时生效）
  on_nav  导航回调（nav ~= false 时生效）
  time    状态条时间文字
  nav     false 时不画 Dock，改在底部生成空操作条容器 ctx.bottom（调用方自行放置按钮）；
          "none" 时既不画 Dock 也不生成底部区，内容区直接扩展到屏幕底部
  bottom_h 底部操作条高度，默认 M.BOTTOM_H（仅 nav == false 时生效）
@return ctx { base, bar, status, dock|bottom, x, y, w, h, sw, sh }
        x/y/w/h 即内容区像素几何（相对 ctx.base）
]]
function M.shell(o)
    o = o or {}
    local base = M.box(airui.screen, {
        x = 0, y = 0, w = M.SCREEN_W, h = M.SCREEN_H, color = M.C.bg,
    })
    local bar, status = M.statusbar(base, {
        title = o.title, y = 0, time = o.time,
        right = o.right, right_w = o.right_w, right_color = o.right_color,
        signal_color = o.signal_color, wifi_color = o.wifi_color,
        alarm_color = o.alarm_color,
    })

    local ctx = {
        base = base, bar = bar, status = status,
        sw = M.SCREEN_W, sh = M.SCREEN_H,
    }
    ctx.x = M.PAD
    ctx.y = M.STATUS_H + 6
    ctx.w = M.SCREEN_W - 2 * M.PAD

    if o.nav == false then
        -- 无 Dock 变体：底部生成空操作条容器，由调用方摆放按钮/进度条
        local bh = o.bottom_h or M.BOTTOM_H
        ctx.bottom = M.card(base, {
            x = 0, y = M.SCREEN_H - bh, w = M.SCREEN_W, h = bh,
            color = M.C.panel, radius = 0, border = nil, border_w = 0,
        })
        ctx.bottom_h = bh
        ctx.h = (M.SCREEN_H - bh) - ctx.y - 4
    elseif o.nav == "none" then
        -- 无底部区变体：不画 Dock 也不生成操作条，内容区扩展到屏幕底部
        ctx.h = M.SCREEN_H - ctx.y - 6
    else
        ctx.dock = M.dock(base, {
            active = o.active, on_nav = o.on_nav,
            y = M.SCREEN_H - M.DOCK_H,
        })
        ctx.h = (M.SCREEN_H - M.DOCK_H) - ctx.y - 6
    end
    if ctx.h < 1 then ctx.h = 1 end
    return ctx
end

-- ==================== 六、主题引擎（精简：深色为默认） ====================

--[[设计令牌之上再抽象一层：一套主题 = 一组 M.C / M.OPA / M.R 覆写。
页面只认令牌，换主题时由 M.apply() 就地改写，页面代码零改动。]]
M.THEMES = {}
M.THEME_ORDER = {}
M.DEFAULT_THEME = "dark"
M.current = M.DEFAULT_THEME

--[[派生令牌：primary 系列 = 主强调色的语义别名（供通用组件引用）

组件一律引用 M.C.primary，而不直接引用 amber / brand：
  产测模式（light 主题）      → primary = 琥珀
  业务模式（light_brand 主题）→ primary = 品牌蓝
这样一套组件代码即可随主题自动换主色，页面代码零改动。]]
local function sync_sem()
    M.SEM.danger  = M.C.rose
    M.SEM.success = M.C.green
    M.SEM.warning = M.C.amber
    M.SEM.info    = M.C.cyan
    M.SEM.link    = M.C.cyan
    M.SEM.accent  = M.C.violet
    -- 主题未显式指定 primary 时回退到琥珀（深色主题 / 产测浅色主题的主色）
    if M.C.primary == nil then
        M.C.primary       = M.C.amber
        M.C.primary_light = M.C.amber_light
        M.C.primary_deep  = M.C.amber_deep
        M.C.on_primary    = M.C.on_amber
    end
end
sync_sem()

-- 基线快照（深色），apply 时先恢复基线再叠加覆写，避免主题互相污染
-- 注意：必须在 sync_sem() 之后再快照，让 primary 系列一并纳入基线；
--       否则从业务主题切回产测主题时，primary 会残留上一主题的品牌蓝。
local BASE_C, BASE_OPA, BASE_R = {}, {}, {}
for k, v in pairs(M.C) do BASE_C[k] = v end
for k, v in pairs(M.OPA) do BASE_OPA[k] = v end
for k, v in pairs(M.R) do BASE_R[k] = v end

--[[注册主题
@table spec { id, name, desc, colors, opa, radius }
@return boolean]]
function M.register(spec)
    if type(spec) ~= "table" or type(spec.id) ~= "string" or spec.id == "" then
        log.warn("ui_theme", "register: 主题缺少 id，已忽略")
        return false
    end
    if not M.THEMES[spec.id] then
        M.THEME_ORDER[#M.THEME_ORDER + 1] = spec.id
    end
    M.THEMES[spec.id] = spec
    return true
end

--[[应用主题（就地改写令牌）
@param string id 主题标识
@return boolean 是否应用成功]]
function M.apply(id)
    local spec = M.THEMES[id]
    if not spec then
        log.warn("ui_theme", "apply: 未注册的主题", id)
        return false
    end
    for k, v in pairs(BASE_C) do M.C[k] = v end
    for k, v in pairs(BASE_OPA) do M.OPA[k] = v end
    for k, v in pairs(BASE_R) do M.R[k] = v end
    if spec.colors then for k, v in pairs(spec.colors) do M.C[k] = v end end
    if spec.opa then for k, v in pairs(spec.opa) do M.OPA[k] = v end end
    if spec.radius then for k, v in pairs(spec.R) do M.R[k] = v end end
    sync_sem()
    M.current = id
    return true
end

-- 深色主题 = 基线（= 本文件顶部定义的令牌，不覆写任何值）
M.register({
    id = "dark", name = "琥珀夜空", desc = "深色玻璃态（默认）",
})
-- 浅色主题（产测模式使用）：纯白背景，仅覆写色值，几何与字号保持一致
M.register({
    id = "light", name = "晨光浅色", desc = "纯白背景（产测模式使用）",
    colors = {
        bg = 0xFFFFFF, bg_top = 0xFFFFFF,
        panel = 0xFFFFFF, panel_hi = 0xFFFFFF,
        t1 = 0x1B2431, t2 = 0x5B6472, t3 = 0x8B95A3,
        stroke = 0xD8DEE8, stroke_soft = 0xE6EAF1, stroke_hi = 0xC2CAD6,
        selected = 0xE8EEF7, pressed = 0xEDF1F7,
        track = 0xD8DEE8, input_bg = 0xFFFFFF,
        knob = 0xFFFFFF, knob_off = 0xFFFFFF,
        divider = 0x1B2431,
    },
})

--[[业务模式专属主题（v2.4 界面优化）
仅在业务分支启用（main.lua 中 apply "light_brand"）；产测模式仍用 light，互不影响。
设计要点：
  1) 分层：页面底纯白 + 卡片/面板极浅灰白 0xF7F9FC，卡片描边偏冷灰，
     使卡片在白底上「浮」起来，解决原来「全白一片、没有层次」的单调感；
  2) 主色：品牌蓝 0x2B6DE5（primary 系列显式覆写，按钮 / 开关 / 进度条 / 返回键自动跟随），
     琥珀降级为「告警 / 警告」专用色；
  3) 语义色针对白底加深（绿 / 红 / 青 / 紫），保证对比度与可读性。]]
M.register({
    id = "light_brand", name = "品牌蓝", desc = "业务模式·现代扁平（纯白 + 品牌蓝）",
    colors = {
        bg = 0xFFFFFF, bg_top = 0xFFFFFF,
        panel = 0xF7F9FC, panel_hi = 0xFFFFFF,
        t1 = 0x1B2431, t2 = 0x5B6472, t3 = 0x8B95A3,
        stroke = 0xE3E9F2, stroke_soft = 0xEDF1F7, stroke_hi = 0xC9D5E6,
        selected = 0xEAF1FE, pressed = 0xF1F5FA,
        track = 0xDCE3EC, input_bg = 0xF4F7FB,
        knob = 0xFFFFFF, knob_off = 0xFFFFFF,
        divider = 0x1B2431,
        -- 主强调色：品牌蓝（primary 系列显式覆写 → 组件自动跟随）
        primary = 0x2B6DE5, primary_light = 0x5B90F0, primary_deep = 0x1F55C0,
        on_primary = 0xFFFFFF,
        brand = 0x2B6DE5, brand_light = 0x5B90F0, brand_deep = 0x1F55C0,
        brand_soft = 0xEAF1FE, on_brand = 0xFFFFFF,
        -- 琥珀降级为「告警 / 警告」专用
        amber = 0xF5A623, amber_light = 0xF7B84C, amber_deep = 0xD98410,
        on_amber = 0xFFFFFF,
        -- 语义色针对白底加深
        green = 0x1FA971, rose = 0xE0454B, cyan = 0x1E9FD0, violet = 0x7C5CE6,
    },
})

-- ==================== 七、分区页 / 详情页公共样板（v2.5 体积优化） ====================
--[[
把 4 个分区页与约 20 个详情页里逐字重复的样板收敛到本区。
对外行为、消息名、参数、防抖时长、几何算法、配色取值与改动前完全一致（纯等价搬移）。
]]

--[[状态条时钟刷新工厂（分区页共用）
等价于各分区页原 refresh_clock：仅在本页可见时刷新状态条时间。
@param function get_wid 返回当前窗口 id
@param function get_st  返回 shell 的 status 句柄
@return function 可直接交给 sys.timerLoopStart
]]
function M.make_clock(get_wid, get_st)
    return function()
        local wid = get_wid and get_wid()
        if not wid or not exwin.is_active(wid) then return end
        local st = get_st and get_st()
        if st and st.time then st.time:set_text(os.date("%H:%M")) end
    end
end

--[[Dock 分区导航回调工厂（分区页共用）
等价于各分区页原 on_nav：同一 nav_busy 防抖（400ms）+ exwin 一级菜单切换事务。
@param string nav_key 本页所属分区标识
@param function get_wid 返回当前窗口 id
@return function on_nav(key, msg)
]]
function M.make_nav(nav_key, get_wid)
    local busy = false
    local function reset_busy() busy = false end
    return function(key, msg)
        if key == nav_key or busy then return end
        busy = true
        local host = _G.UIFW_HOST_WIN or (get_wid and get_wid())
        if host and exwin.begin_menu_switch then
            exwin.begin_menu_switch(host)
        end
        sys.publish(msg)
        sys.timerStart(reset_busy, 400)
    end
end

--[[磁贴状态刷新（分区页共用）：摘要文字 + 指示灯颜色
@param table handle M.tile_grid 返回的 { nil, sub_label, dot }
@param string sub   新摘要文字
@param number color 指示灯颜色
]]
function M.tile_state(handle, sub, color)
    if not handle then return end
    if handle[2] then handle[2]:set_text(sub) end
    if handle[3] then handle[3]:set_color(color, 255) end
end

--[[磁贴网格铺设（分区页共用）
等价于各分区页 create_ui 里的「3 列 × 2 行 逐格摆放」循环。
@param table ctx   M.shell 返回的上下文
@param table cells { { icon, text, sub, dot, on_click }, ... }
@table  opts       { nav_key = 分区标识, cols = 3, rows = 2, gap = 6 }
@return table handles 与 cells 等长的 { { nil, sub_label, dot }, ... }
]]
function M.tile_grid(ctx, cells, opts)
    opts = opts or {}
    local cols, rows, gap = opts.cols or 3, opts.rows or 2, opts.gap or 6
    local cw = math.floor((ctx.w - gap * (cols - 1)) / cols)
    local ch = math.floor((ctx.h - gap * (rows - 1)) / rows)
    local sect = M.pal(opts.nav_key or "")
    local handles = {}
    for i, c in ipairs(cells) do
        local x = ctx.x + ((i - 1) % cols) * (cw + gap)
        local y = ctx.y + math.floor((i - 1) / cols) * (ch + gap)
        local _, _, sub_label, dot = M.tile(ctx.base, {
            x = x, y = y, w = cw, h = ch,
            icon = c.icon, text = c.text, sub = c.sub, dot = c.dot,
            accent_soft = sect.soft, accent_line = sect.line,
            on_click = c.on_click,
        })
        handles[i] = { nil, sub_label, dot }
    end
    return handles
end

--[[二级功能页窗口工厂（详情页共用）
等价于各详情页的「单实例保护 + exwin.open + 销毁收尾」样板。

用法：
    local W = theme.win({
        open = "OPEN_XXX_WIN",
        on_create = on_create, on_destroy = on_destroy,
        on_get_focus = on_get_focus, on_lose_focus = on_lose_focus,
    })
回调签名统一为 function(W)；页内以 W.id 取窗口 id、W:is_active() 判本页是否可见。
@return table W { id, is_active }
]]
function M.win(cfg)
    local W = { id = nil }
    function W:is_active()
        return self.id ~= nil and exwin.is_active(self.id)
    end
    local uc, ud, ug, ul = cfg.on_create, cfg.on_destroy, cfg.on_get_focus, cfg.on_lose_focus
    local function on_create() if uc then uc(W) end end
    local function on_destroy()
        if ud then ud(W) end
        W.id = nil
    end
    local function on_get_focus() if ug then ug(W) end end
    local function on_lose_focus() if ul then ul(W) end end
    local function handler()
        if W.id and exwin.is_active(W.id) then return end
        if W.id and cfg.replace then
            exwin.close(W.id)
            W.id = nil
        end
        W.id = exwin.open({
            on_create = on_create, on_destroy = on_destroy,
            on_get_focus = on_get_focus, on_lose_focus = on_lose_focus,
        })
    end
    sys.subscribe(cfg.open, handler)
    return W
end

return M
