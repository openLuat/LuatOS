--[[
@module  ui_kit
@summary 界面公共组件：页面骨架 / 卡片 / 按钮 / 标签 / 列表行 / 宫格 / 分页 / 提示条
@version 2.0
@date    2026.10.16
@usage
    local ui = require "ui_kit"
    local T  = require "ui_theme"

    local page = ui.page({ title = "网络状态", on_back = function() exwin.close(win_id) end })
    ui.card({ parent = page.body, x = 20, y = 20, w = 360, h = 160 })
    ui.button({ parent = page.body, x = 20, y = 300, w = 200, h = 48,
                text = "刷新", on_click = do_refresh })
    page.toast("已刷新")
    page.destroy()      -- on_destroy 里必须调，否则容器泄漏

坐标约定（多屏自适应的关键）
1. 所有 x / y / w / h 都填**设计坐标**（基准 800×480），组件内部用 T.px() 换算成实际像素；
   页面里算布局用 ui_theme.SCREEN.DW / DH，不要用 S.W / S.H（那是真实分辨率）；
2. 字号直接用 T.FONT.*（已按屏幕缩放）；
3. 颜色直接用 T.COLOR.*。
这样 5 寸 800×480 和 7/9/10 寸 1024×600 是同一份页面代码，只是整体放大 ~1.25 倍。
]]

local M = {}
local T = require "ui_theme"

local C, F, S, G, R = T.COLOR, T.FONT, T.SCREEN, T.GAP, T.RADIUS
local px = T.px

-- ===== 滚动条兜底 =====

local function no_scroll(obj)
    if obj and obj.set_scrollbar_mode then
        pcall(function() obj:set_scrollbar_mode(0) end)
    end
    return obj
end

M.no_scroll = no_scroll

local function tap_once(fn)
    if not fn then return nil end
    local busy = false
    return function(...)
        if busy then return end
        busy = true
        sys.timerStart(function() busy = false end, 150)
        return fn(...)
    end
end

M.tap_once = tap_once

-- ===== 提示条 =====

local toast_box, toast_timer

local function clear_toast()
    if toast_box then
        pcall(function() toast_box:destroy() end)
        toast_box = nil
    end
    if toast_timer then
        sys.timerStop(toast_timer)
        toast_timer = nil
    end
end

--- 底部临时提示，2.5 秒后自动消失（同一时刻只留一条）
function M.toast(parent, text)
    clear_toast()
    if not parent then return end

    local w, h = S.DW - G.L * 2, 46
    toast_box = no_scroll(airui.container({
        parent = parent, x = px(G.L), y = px(S.DH - 100), w = px(w), h = px(h),
        color = C.TOAST, radius = px(R.M), color_opacity = 235,
    }))
    airui.label({
        parent = toast_box, x = px(2), y = math.floor((px(h) - F.SMALL) / 2), w = px(w) - px(4), h = F.SMALL + px(4),
        text = text, font_size = F.SMALL, color = C.TEXT_ON_DARK,
        align = airui.TEXT_ALIGN_CENTER,
    })
    toast_timer = sys.timerStart(clear_toast, 2500)
end

-- ===== 基础控件 =====

function M.button(opt)
    local color = opt.disabled and C.DISABLED or (opt.color or C.PRIMARY)
    local size  = opt.size or F.NORMAL
    local w, h  = opt.w or 160, opt.h or 48
    local hw, hh = px(w), px(h)
    local tap = tap_once(opt.disabled and function() end or opt.on_click)

    local btn = no_scroll(airui.container({
        parent = opt.parent, x = px(opt.x or 0), y = px(opt.y or 0), w = hw, h = hh,
        color = color, radius = px(opt.radius or R.S),
        on_click = tap,
    }))
    airui.label({
        parent = btn, x = px(2), y = math.floor((hh - size) / 2), w = hw - px(4), h = size + px(4),
        text = opt.text or "", font_size = size, color = opt.text_color or C.TEXT_ON_DARK,
        align = airui.TEXT_ALIGN_CENTER,
        on_click = tap,
    })
    return btn
end

function M.ghost_button(opt)
    local w, h = opt.w or 120, opt.h or 40
    local hw, hh = px(w), px(h)
    local color = opt.color or C.PRIMARY_SOFT
    local size  = opt.size or F.SMALL
    local tap = tap_once(opt.on_click)

    local btn = no_scroll(airui.container({
        parent = opt.parent, x = px(opt.x or 0), y = px(opt.y or 0), w = hw, h = hh,
        color = color, radius = px(hh / 2), on_click = tap,
        on_long_press = opt.on_long_press,
    }))
    airui.label({
        parent = btn, x = px(2), y = math.floor((hh - size) / 2), w = hw - px(4), h = size + px(4),
        text = opt.text or "", font_size = size, color = opt.text_color or C.PRIMARY,
        align = airui.TEXT_ALIGN_CENTER,
        on_click = tap,
    })
    return btn
end

function M.label(opt)
    local o = {
        parent = opt.parent, x = px(opt.x or 0), y = px(opt.y or 0),
        w = px(opt.w or 100), h = px(opt.h or 26),
        text = opt.text or "",
        font_size = opt.size or F.NORMAL,
        color = opt.color or C.TEXT,
        align = opt.align or airui.TEXT_ALIGN_LEFT,
    }
    if opt.symbol then o.symbol = opt.symbol end
    if opt.on_click then o.on_click = tap_once(opt.on_click) end
    return airui.label(o)
end

function M.card(opt)
    local o = {
        parent = opt.parent, x = px(opt.x or 0), y = px(opt.y or 0),
        w = px(opt.w or 100), h = px(opt.h or 100),
        color = opt.color or C.CARD,
        radius = px(opt.radius or R.M),
        on_click = tap_once(opt.on_click),
    }
    if opt.opacity then o.color_opacity = opt.opacity end
    if opt.border then
        o.border_width = px(1)
        o.border_color = opt.border
    end
    return no_scroll(airui.container(o))
end

function M.box(opt)
    return no_scroll(airui.container({
        parent = opt.parent, x = px(opt.x or 0), y = px(opt.y or 0),
        w = px(opt.w or 100), h = px(opt.h or 100),
        color = opt.color or C.BG, radius = px(opt.radius or 0),
        on_click = opt.on_click,
    }))
end

function M.divider(opt)
    return no_scroll(airui.container({
        parent = opt.parent, x = px(opt.x or 0), y = px(opt.y or 0),
        w = px(opt.w or 100), h = math.max(px(1), 1),
        color = opt.color or C.BORDER,
    }))
end

function M.row(opt)
    local w, h = opt.w or S.DW, opt.h or 56
    local hh = px(h)
    -- 左右各内缩 2px：行容器不要和父卡片完全同宽。
    -- 卡片有 1px 描边时，同宽的行会被 LVGL 判成"内容贴边"，卡片底部就画一条滚动条。
    local row = no_scroll(airui.container({
        parent = opt.parent, x = px(opt.x or 0) + px(2), y = px(opt.y or 0), w = px(w) - px(4), h = hh,
        color = opt.color or C.CARD, radius = px(opt.radius or R.M), on_click = opt.on_click,
    }))

    local title_size = F.SMALL
    local value_size = opt.size or F.NORMAL

    local title = airui.label({
        parent = row, x = px(G.M), y = math.floor((hh - title_size) / 2),
        w = px(w - G.M * 2 - 220), h = title_size + px(4),
        text = opt.title or "", font_size = title_size, color = C.TEXT_SUB,
    })
    local value = airui.label({
        parent = row, x = px(w - 220 - G.M), y = math.floor((hh - value_size) / 2),
        w = px(220), h = value_size + px(4),
        text = opt.value ~= nil and tostring(opt.value) or "",
        font_size = value_size, color = opt.value_color or C.TEXT,
        align = airui.TEXT_ALIGN_RIGHT,
    })
    return row, title, value
end

-- ===== 页面骨架 =====

function M.page(opt)
    opt = opt or {}
    local bg = opt.bg or C.BG

    -- 根容器：铺满整屏（真实分辨率），把整块屏先刷成背景色
    local root = no_scroll(airui.container({
        parent = airui.screen, x = 0, y = 0, w = S.W, h = S.H, color = bg,
    }))

    -- 内容区：设计基准 800×480 等比放大后在整屏**居中**（偏移 S.OX/S.OY）。
    -- 页面内部坐标仍是设计坐标、由 px() 换算，所以屏幕宽高比和 800:480 不一致时，
    -- 多出来的那条边是根容器的背景色（不是黑边），界面本身也不会被裁。
    local content = no_scroll(airui.container({
        parent = root, x = S.OX, y = S.OY, w = S.CW, h = S.CH - px(2), color = bg,
    }))

    local body_y, title_label, sub_label = 0, nil, nil
    local bar_h = px(S.TITLE_H)

    if opt.title then
        -- 顶栏：白底 + 底部 1px 分隔线（清爽风），标题左对齐
        local bar = no_scroll(airui.container({
            parent = content, x = 0, y = 0, w = S.CW, h = bar_h, color = C.CARD,
        }))
        no_scroll(airui.container({
            parent = bar, x = px(1), y = bar_h - px(3), w = S.CW - px(2), h = px(1), color = C.BORDER,
        }))

        local title_x = G.M
        if opt.on_back then
            -- 返回按钮：宽一点、高一点，并且**长按也触发**（个别固件上短按事件偶发丢失）
            -- 文字用 F.NORMAL：和标题栏里的副标题保持同一字号，避免同一行 16/22 混排显得乱
            local bw = 96
            M.ghost_button({
                parent = bar, x = G.M, y = (S.TITLE_H - 44) / 2, w = bw, h = 44,
                text = "返回", size = F.NORMAL,
                on_click = opt.on_back, on_long_press = opt.on_back,
            })
            title_x = G.M + bw + G.S
        end

        title_label = airui.label({
            parent = bar, x = px(title_x), y = math.floor((bar_h - F.NORMAL) / 2),
            w = px(S.DW - title_x - G.M), h = F.NORMAL + px(4),
            text = opt.title, font_size = F.NORMAL, color = C.TEXT,
            align = airui.TEXT_ALIGN_LEFT,
        })
        if opt.subtitle then
            sub_label = airui.label({
                parent = bar, x = px(S.DW - G.M - 300), y = math.floor((bar_h - F.NORMAL) / 2),
                w = px(300), h = F.NORMAL + px(4),
                text = opt.subtitle, font_size = F.NORMAL, color = C.TEXT_WEAK,
                align = airui.TEXT_ALIGN_RIGHT,
            })
        end
        body_y = bar_h
    end

    local body = no_scroll(airui.container({
        parent = content, x = 0, y = body_y, w = S.CW, h = S.CH - body_y - px(2), color = bg,
        on_click = opt.on_body_click,
    }))

    return {
        root = root,
        content = content,
        body = body,
        set_title = function(s) if title_label then title_label:set_text(s) end end,
        set_subtitle = function(s) if sub_label then sub_label:set_text(s) end end,
        toast = function(s) M.toast(content, s) end,
        destroy = function()
            clear_toast()
            if root then
                pcall(function() root:destroy() end)
                root = nil
            end
            content = nil
        end,
    }
end

-- ===== 复合控件 =====

function M.app_grid(opt)
    local w      = opt.w or S.DW
    local cols   = opt.cols or 4
    local per    = opt.per_page or (cols * 2)
    local cell_h = opt.cell_h or 100
    local gap    = G.M
    local cell_w = math.floor((w - gap * (cols + 1)) / cols)
    local rows   = math.ceil(per / cols)

    local grid = no_scroll(airui.container({
        parent = opt.parent, x = px(opt.x or 0), y = px(opt.y or 0),
        w = px(w), h = px(rows * (cell_h + gap)), color = opt.bg or C.BG,
    }))

    local start = ((opt.page or 1) - 1) * per
    for i = 1, per do
        local item = opt.items and opt.items[start + i]
        if item then
            local col   = (i - 1) % cols
            local row_i = math.floor((i - 1) / cols)
            local color = item.todo and C.DISABLED or (item.color or C.PRIMARY)

            -- 点击统一走这里：卡片、图标块、文字都挂同一个回调
            -- （只挂在卡片上时，点在图标/文字上会被子控件吞掉 → 表现为"点好几次才有反应"）
            -- 按下瞬间把卡片底色点亮：页面创建要几百毫秒，有即时反馈才不像"点了没反应"
            local cell
            local cell_color = opt.cell_bg or C.CARD
            local function tap()
                if cell then
                    pcall(function() cell:set_color(C.PRIMARY_SOFT) end)
                    sys.timerStart(function()
                        if cell then pcall(function() cell:set_color(cell_color) end) end
                    end, 220)
                end
                if opt.on_open then opt.on_open(item) end
            end

            -- 卡片底色/描边可配：整页白底时用 cell_border 勾边，否则白卡在白底上看不见边界
            local cell_opt = {
                parent = grid,
                x = px(gap + col * (cell_w + gap)),
                y = px(row_i * (cell_h + gap)),
                w = px(cell_w), h = px(cell_h),
                color = opt.cell_bg or C.CARD, radius = px(R.M),
                on_click = tap,
            }
            if opt.cell_border then
                cell_opt.border_width = px(1)
                cell_opt.border_color = opt.cell_border
            end
            cell = no_scroll(airui.container(cell_opt))

            local ib      = opt.icon_size or 52            -- 图标块边长（设计值）
            local pad     = 10                             -- 图标与名称的间距（设计值）
            local text_h  = F.SMALL + px(4)
            local content_h = px(ib) + px(pad) + text_h
            local top     = math.max(px(6), math.floor((px(cell_h) - content_h) / 2))

            -- 图标两种来源：
            --   item.icon_path = "/luadb/app_xxx.png"（48×48 PNG，随脚本烧入）→ 直接贴图
            --   item.icon      = airui.SYMBOL_XX（内置符号）或无 → 彩色圆角块 + 符号/首字
            local icon_path = item.icon_path
            local icon_box = no_scroll(airui.container({
                parent = cell, x = px((cell_w - ib) / 2), y = top,
                w = px(ib), h = px(ib),
                color = icon_path and (opt.cell_bg or C.CARD) or color,
                radius = px(ib * 0.28),
                on_click = tap,
            }))
            if icon_path then
                pcall(airui.image, {
                    parent = icon_box, x = px(6), y = px(6),
                    w = px(ib) - px(12), h = px(ib) - px(12),
                    src = icon_path, on_click = tap,
                })
            else
                local icon_size = F.BIG
                airui.label({
                    parent = icon_box, x = px(2), y = math.floor((px(ib) - icon_size) / 2), w = px(ib) - px(4), h = icon_size + px(4),
                    text = item.icon and "" or string.sub(item.name, 1, 1),
                    symbol = item.icon,
                    font_size = icon_size,
                    color = C.TEXT_ON_DARK, align = airui.TEXT_ALIGN_CENTER,
                    on_click = tap,
                })
            end

            -- 名称
            airui.label({
                parent = cell, x = px(2), y = top + px(ib) + px(pad), w = px(cell_w) - px(4), h = text_h,
                text = item.name, font_size = F.SMALL,
                color = item.todo and C.TEXT_WEAK or C.TEXT,
                align = airui.TEXT_ALIGN_CENTER,
                on_click = tap,
            })
        end
    end

    return grid
end

function M.pager(opt)
    local cur, total = opt.page or 1, opt.page_count or 1
    local y = opt.y or (S.DH - 56)
    local bar = no_scroll(airui.container({
        parent = opt.parent, x = 0, y = px(y), w = px(S.DW), h = px(44),
        color = opt.bg or C.BG,
    }))

    local bw, bh = 120, 38
    local function mkbtn(x, text, target, disabled)
        local hh = px(bh)
        local tap = tap_once(disabled and function() end or function() opt.on_change(target) end)
        local btn = no_scroll(airui.container({
            parent = bar, x = px(x), y = math.floor((px(44) - hh) / 2), w = px(bw), h = hh,
            color = disabled and C.BG or C.PRIMARY_SOFT, radius = px(hh / 2),
            on_click = tap,
        }))
        airui.label({
            parent = btn, x = px(2), y = math.floor((hh - F.SMALL) / 2), w = px(bw) - px(4), h = F.SMALL + px(4),
            text = text, font_size = F.SMALL,
            color = disabled and C.TEXT_WEAK or C.PRIMARY,
            align = airui.TEXT_ALIGN_CENTER,
            on_click = tap,
        })
    end

    mkbtn(G.M, "上一页", cur - 1, cur <= 1)
    airui.label({
        parent = bar, x = px(2), y = math.floor((px(44) - F.SMALL) / 2), w = px(S.DW) - px(4), h = F.SMALL + px(4),
        text = string.format("%d / %d", cur, total),
        font_size = F.SMALL, color = C.TEXT_WEAK, align = airui.TEXT_ALIGN_CENTER,
    })
    mkbtn(S.DW - G.M - bw, "下一页", cur + 1, cur >= total)

    return bar
end

return M
