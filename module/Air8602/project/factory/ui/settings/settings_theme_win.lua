--[[
@module  settings_theme_win
@summary 主题风格选择页 —— 列出 ui_theme 中已注册的全部主题，点击即换肤
@version 1.0
@date    2026.09.16
@author  江访

=== 消息协议 ===
订阅: OPEN_THEME_WIN       → 打开本页
发布: UI_THEME_CHANGED(id) → 主题已切换；其他页面据此在下次获得焦点时重建

=== 换肤如何生效（重要） ===
theme.apply() 只就地改写令牌值，不会重建任何控件。本页用「延迟重建自己」立即
呈现新皮肤；其余页面订阅 UI_THEME_CHANGED 打脏标记，在 on_get_focus 时重建 ——
这样既不用操作窗口栈顺序，也不会在控件点击回调里销毁父容器。
]]

local theme = require "ui_theme"
local titlebar = require "settings_titlebar"

local window_id = nil
local main_container = nil

local sw, sh = 480, 800
local REBUILD_DELAY = 30   -- ms，等本轮点击事件派发结束再销毁容器

local function update_screen_size()
    sw, sh = screen_w or 480, screen_h or 800
    -- 宽屏有左栏时收窄到右侧内容区（窄屏原样返回）
    sw, sh = theme.content_fit(sw, sh)
end

--[[画一张主题缩略预览：外层=主题底色，内层=卡片色，两条短线=文字色，胶囊=强调色
小到 48px 也仍然可辨识「深/浅 + 强调色」三件事。]]
local function build_preview(parent, x, y, w, h, sp)
    local pv = theme.box(parent, {
        x = x, y = y, w = w, h = h,
        radius = theme.R.xs, color = sp.bg, opa = 255,
        border = theme.C.stroke_soft, border_w = 1,
    })
    local inx = math.max(3, math.floor(w * 0.07))
    local iny = math.max(3, math.floor(h * 0.08))
    theme.box(pv, {
        x = inx, y = iny, w = w - 2 * inx, h = h - 2 * iny,
        radius = theme.R.xs, color = sp.card, opa = 255,
    })
    -- 两行「假文字」
    local lx = inx * 2
    local lw = math.max(6, math.floor((w - 4 * inx) * 0.62))
    local lh = math.max(2, math.floor(h * 0.09))
    theme.box(pv, { x = lx, y = iny * 2, w = lw, h = lh,
        radius = lh, color = sp.text, opa = 255 })
    theme.box(pv, { x = lx, y = iny * 2 + lh + math.max(2, math.floor(h * 0.06)),
        w = math.floor(lw * 0.66), h = lh, radius = lh, color = sp.text, opa = 130 })
    -- 强调色胶囊
    local pw = math.max(10, math.floor((w - 4 * inx) * 0.46))
    local ph = math.max(4, math.floor(h * 0.15))
    theme.box(pv, {
        x = lx, y = h - iny * 2 - ph, w = pw, h = ph,
        radius = math.floor(ph / 2), color = sp.accent, opa = 255,
    })
    return pv
end

local function build_ui()
    update_screen_size()
    local ctx = theme.page({
        title = "主题风格",
        sub = "外观、配色与强调色",
        on_back = function() exwin.close(window_id) end,
    })
    main_container = ctx.base

    local list = theme.theme_list()
    local cur = theme.current()

    if #list == 0 then
        theme.label(ctx.base, {
            x = ctx.x, y = ctx.y, w = ctx.w, h = theme.dp(60),
            text = "未注册任何主题（请检查 ui_theme_themes.lua）",
            px_size = theme.fs("label"), color = theme.C.t3,
            align = airui.TEXT_ALIGN_CENTER,
        })
        return
    end

    -- 列数按可用宽度定：窄屏 1 列、480 宽 2 列、横屏大屏 3 列
    local min_col = theme.dp(200)
    local cols = math.floor(ctx.w / min_col)
    if cols < 1 then cols = 1 end
    if cols > 3 then cols = 3 end
    local rows = math.ceil(#list / cols)

    local gap = math.max(theme.dp(8), math.floor(ctx.w * 0.02))
    local cw = math.floor((ctx.w - (cols - 1) * gap) / cols)
    -- 卡片高度自适应：优先塞满一屏，但夹在 64~118 之间，超出部分交给滚动容器
    local ch = math.floor((ctx.h - (rows - 1) * gap) / rows)
    local cap_hi, cap_lo = theme.dp(118), theme.dp(64)
    if ch > cap_hi then ch = cap_hi end
    if ch < cap_lo then ch = cap_lo end

    -- 内容区可滚动：小屏上主题较多时不至于被裁掉
    local body = theme.box(ctx.base, {
        x = ctx.x, y = ctx.y, w = ctx.w, h = ctx.h,
        color = theme.C.black, opa = 0, scrollable = true,
    })

    for i, t in ipairs(list) do
        local col = (i - 1) % cols
        local row = math.floor((i - 1) / cols)
        local cx = col * (cw + gap)
        local cy = row * (ch + gap)
        local on = (t.id == cur)
        local sp = t.swatch or {}

        local card = theme.card(body, {
            x = cx, y = cy, w = cw, h = ch,
            radius = theme.R.md,
            opa = on and theme.OPA.glass_hi or theme.OPA.glass,
            border = on and theme.C.primary or theme.C.stroke,
            border_w = on and 2 or 1,
            on_click = function()
                if theme.current() == t.id then return end
                theme.apply(t.id)
                sys.publish("UI_THEME_CHANGED", t.id)
                -- 延迟重建自己：此时点击事件已派发完毕，销毁父容器是安全的
                sys.timerStart(function()
                    if not window_id then return end
                    if main_container then
                        main_container:destroy()
                        main_container = nil
                    end
                    build_ui()
                end, REBUILD_DELAY)
            end,
        })

        local pd = math.max(theme.dp(6), math.floor(ch * 0.08))
        local fs_name = theme.fs("label")
        local fs_desc = theme.fs("micro")

        if cols == 1 then
            -- 窄屏：预览在左，文字在右（横向排，省高度）
            local pvw = math.max(theme.dp(44), math.floor(ch * 0.66))
            local pvh = ch - 2 * pd
            build_preview(card, pd, pd, pvw, pvh, sp)
            local tx = pd + pvw + pd
            local tw = cw - tx - pd
            theme.label(card, {
                x = tx, y = pd, w = tw, h = fs_name + theme.dp(4),
                text = t.name or t.id, px_size = fs_name,
                color = on and theme.C.primary_light or theme.C.t1,
                align = airui.TEXT_ALIGN_LEFT,
            })
            theme.label(card, {
                x = tx, y = pd + fs_name + theme.dp(4), w = tw, h = fs_desc + theme.dp(4),
                text = t.desc or "", px_size = fs_desc, color = theme.C.t3,
                align = airui.TEXT_ALIGN_LEFT,
            })
            if on then
                theme.label(card, {
                    x = tx, y = ch - pd - fs_desc - theme.dp(4), w = tw, h = fs_desc + theme.dp(4),
                    text = "当前使用", px_size = fs_desc, color = theme.C.primary,
                    align = airui.TEXT_ALIGN_LEFT,
                })
            end
        else
            -- 宽屏：预览在上、文字在下（竖向排，预览更舒展）
            local pvh = math.floor(ch * 0.44)
            build_preview(card, pd, pd, cw - 2 * pd, pvh, sp)
            local ty = pd + pvh + math.max(theme.dp(4), math.floor(ch * 0.06))
            theme.label(card, {
                x = pd, y = ty, w = cw - 2 * pd, h = fs_name + theme.dp(4),
                text = t.name or t.id, px_size = fs_name,
                color = on and theme.C.primary_light or theme.C.t1,
                align = airui.TEXT_ALIGN_LEFT,
            })
            theme.label(card, {
                x = pd, y = ty + fs_name + theme.dp(4), w = cw - 2 * pd, h = fs_desc + theme.dp(4),
                text = t.desc or "", px_size = fs_desc, color = theme.C.t3,
                align = airui.TEXT_ALIGN_LEFT,
            })
            if on then
                theme.label(card, {
                    x = pd, y = ch - pd - fs_desc - theme.dp(4), w = cw - 2 * pd,
                    h = fs_desc + theme.dp(4),
                    text = "当前使用", px_size = fs_desc, color = theme.C.primary,
                    align = airui.TEXT_ALIGN_RIGHT,
                })
            end
        end
    end

    -- 底部说明（body 的坐标原点即 ctx.x/ctx.y，所以这里用相对坐标 0）
    local ny = rows * (ch + gap) + theme.dp(4)
    if ny + theme.dp(30) <= ctx.h then
        theme.label(body, {
            x = 0, y = ny, w = ctx.w, h = theme.dp(30),
            text = "选择即生效并保存，重启后保持",
            px_size = theme.fs("micro"), color = theme.C.t3,
            align = airui.TEXT_ALIGN_CENTER,
        })
    end
end

local function on_create()
    build_ui()
    -- 本页在点击后自行重建，不订阅 UI_THEME_CHANGED
    -- （若在此处订阅，必须用具名函数，否则 unsubscribe 拿到的是另一个闭包、注销不掉）
end

local function on_destroy()
    if main_container then main_container:destroy(); main_container = nil end
    window_id = nil
end

local function on_get_focus() end
local function on_lose_focus() end

local function open_handler()
    window_id = exwin.open({
        on_create = on_create,
        on_destroy = on_destroy,
        on_lose_focus = on_lose_focus,
        on_get_focus = on_get_focus,
    })
end

sys.subscribe("OPEN_THEME_WIN", open_handler)
