--[[
@module  ecabinet
@summary 智能寄存柜主窗口模块（深蓝透视柜墙风格，对应 index.html 首页）
@version 4.0
@date    2026.09.15
]]

local win_id = nil
local main_container = nil
local screen_w, screen_h = 1024, 600

local function update_screen_size()
    local rotation = airui.get_rotation()
    local phys_w, phys_h = lcd.getSize()
    if rotation == 0 or rotation == 180 then
        screen_w, screen_h = phys_w, phys_h
    else
        screen_w, screen_h = phys_h, phys_w
    end
end

local function create_ui()
    local density = _G.density_scale or 1

    -- ============== 背景（深蓝，对应 HTML 的 stage 底色） ==============
    main_container = airui.container({
        x = 0, y = 0,
        w = screen_w, h = screen_h,
        color = 0x0A1E3A,
        parent = airui.screen,
    })

    -- ============== 柜墙（梯形透视墙，延伸至取件按钮背面，格子宽>高） ==============
    -- 消失点在屏幕外右侧；x=0 处上下出血，首列顶到屏幕边缘
    -- 格线用底色 0x0A1E3A，柜格用明亮饱和蓝 0x2478E8
    local cell_color  = 0x2478E8        -- 明亮饱和蓝柜格
    local wall_w, wall_h = 960, 600
    local wall_right  = 636             -- 墙面右边界（删除最后一列；仍延伸至取件按钮 478~698 背面）
    local vp_x, vp_y  = 1200, 290       -- 透视消失点（屏幕外右侧、垂直居中偏上）
    local edge_top, edge_bot = -40, 640 -- x=0 处墙面上下边界（出血，首列上下顶到屏幕边缘）
    local row_count   = 5               -- 行数（左端行高 136）
    local line_w      = 6               -- 格线粗细
    local row_h0      = (edge_bot - edge_top) / row_count  -- x=0 处行高

    -- 列边线循环生成：列宽 = 1.10 × 行高（宽稍微大于高、不太长）；最后一列已删除，不越过 wall_right
    local col_edge = { 0 }
    local cx = 0
    while true do
        local w = row_h0 * 1.10 * (vp_x - cx) / (vp_x + row_h0 / 2)
        if w < 20 or cx + w >= wall_right then break end
        cx = cx + math.floor(w + 0.5)
        col_edge[#col_edge + 1] = cx
    end

    -- 透视投影：把 x=0 处的 y0 投影到 x 处的 y（所有横线相交于消失点）
    local function proj_y(y0, x)
        return vp_y + (y0 - vp_y) * (vp_x - x) / vp_x
    end

    local items = {}

    -- 1) 梯形墙面：8px 宽竖条拼接，上下斜边平滑无锯齿
    local step = 8
    local sx = 0
    while sx < wall_right do
        local sw = math.min(step, wall_right - sx)
        local mx = sx + sw / 2
        local top = math.max(0, math.floor(proj_y(edge_top, mx) + 0.5))
        local bot = math.min(wall_h, math.floor(proj_y(edge_bot, mx) + 0.5))
        if bot > top then
            items[#items + 1] = {
                type = "rect",
                x = sx, y = top, w = sw, h = bot - top,
                color = cell_color, width = 1,
                fill = true, fill_color = cell_color, fill_opacity = 255,
            }
        end
        sx = sx + step
    end

    -- 2) 横向透视线（间距逐列收窄，但每行都在一条直线上）
    local row_h = (edge_bot - edge_top) / row_count
    for i = 0, row_count do
        local y0 = edge_top + i * row_h
        items[#items + 1] = {
            type = "line",
            x1 = 0, y1 = math.floor(proj_y(y0, 0) + 0.5),
            x2 = wall_right, y2 = math.floor(proj_y(y0, wall_right) + 0.5),
            color = 0x0A1E3A, width = line_w,
        }
    end

    -- 3) 竖向分列线（从墙顶边画到墙底边）
    for _, cx in ipairs(col_edge) do
        if cx > 0 then
            items[#items + 1] = {
                type = "line",
                x1 = cx, y1 = math.floor(proj_y(edge_top, cx) + 0.5),
                x2 = cx, y2 = math.floor(proj_y(edge_bot, cx) + 0.5),
                color = 0x0A1E3A, width = line_w,
            }
        end
    end

    airui.shape({
        parent = main_container,
        x = 0, y = 0,
        w = wall_w, h = wall_h,
        items = items,
    })

    -- ============== 标题面板（深青蓝 + 左侧绿色装饰条，高度变小，整体右移靠近右侧按钮） ==============
    local panel_x, panel_y, panel_w, panel_h = 60, 230, 380, 140
    airui.container({
        parent = main_container,
        x = panel_x, y = panel_y,
        w = panel_w, h = panel_h,
        color = 0x0E3B5C,
        radius = 10,
        shadow = {
            offset_x = 0, offset_y = 6, blur = 18,
            color = 0x000000, opacity = 0.55,
        },
    })
    -- 左侧绿色装饰条
    airui.container({
        parent = main_container,
        x = panel_x, y = panel_y,
        w = 4, h = panel_h,
        color = 0x2DD4BF,
    })

    -- 标题行（分段上色，让"合宙"显示橘黄）："欢迎使用" + "合宙" + "智能寄存柜"
    -- 字号 28，三段紧贴，无空格
    local title_y = panel_y + 24
    local title_size = 28
    airui.label({
        parent = main_container,
        text = "欢迎使用",
        x = panel_x + 22, y = title_y,
        w = 120, h = 38,
        font_size = title_size,
        color = 0xFFFFFF,
        align = airui.TEXT_ALIGN_LEFT,
        font_weight = 600,
    })
    airui.label({
        parent = main_container,
        text = "合宙",
        x = panel_x + 138, y = title_y,
        w = 60, h = 38,
        font_size = title_size,
        color = 0xF5AE26,
        align = airui.TEXT_ALIGN_LEFT,
        font_weight = 600,
    })
    airui.label({
        parent = main_container,
        text = "智能寄存柜",
        x = panel_x + 198, y = title_y,
        w = 160, h = 38,
        font_size = title_size,
        color = 0xFFFFFF,
        align = airui.TEXT_ALIGN_LEFT,
        font_weight = 600,
    })

    -- 副标题（居中放在面板中间）
    airui.label({
        parent = main_container,
        text = "随存随取，安全便捷。",
        x = panel_x, y = panel_y + 82,
        w = panel_w, h = 26,
        font_size = 18,
        color = 0x9EB3CC,
        align = airui.TEXT_ALIGN_CENTER,
    })

    -- ============== 右侧 2×2 功能按钮（正方形，对应 HTML 四宫格） ==============
    local btn_w, btn_h = 220, 220
    local btn_gap_x, btn_gap_y = 16, 16
    local btns_origin_x = 478
    -- 垂直居中：(600 - (220+16+220))/2 = 72
    local btns_origin_y = 72

    local function make_button(col, row, bg_color, text, icon_src, icon_size, evt)
        local x = btns_origin_x + col * (btn_w + btn_gap_x)
        local y = btns_origin_y + row * (btn_h + btn_gap_y)
        airui.container({
            parent = main_container,
            x = x, y = y,
            w = btn_w, h = btn_h,
            color = bg_color,
            radius = 18,
            shadow = {
                offset_x = 0, offset_y = 8, blur = 18,
                color = 0x000000, opacity = 0.45,
            },
            on_click = function()
                log.info(text .. "按键触发")
                sys.publish(evt)
            end,
        })
        -- 图标（垂直居中偏上：39px 顶部留白）
        airui.image({
            parent = main_container,
            x = x + math.floor((btn_w - icon_size) / 2),
            y = y + 39,
            w = icon_size, h = icon_size,
            src = icon_src,
        })
        -- 文本（垂直居中偏下：紧贴图标下方）
        airui.label({
            parent = main_container,
            text = text,
            x = x, y = y + 145,
            w = btn_w, h = 36,
            font_size = 22,
            color = 0xFFFFFF,
            align = airui.TEXT_ALIGN_CENTER,
            font_weight = 700,
        })
    end

    -- 取件按钮底色加深，避免与浅蓝柜墙 0x6FB5F5 混在一起
    make_button(0, 0, 0x1A5FB4, "取件", "/luadb/qujian.png",  96, "OPEN_EXPRESS_RECEIVE_WIN")
    make_button(1, 0, 0x34C9AF, "管理", "/luadb/guanli.png",  96, "OPEN_COURIER_MANAGEMENT_WIN")
    make_button(0, 1, 0xF5A421, "存件", "/luadb/cunjian.png", 96, "OPEN_EXPRESS_SEND_WIN")
    make_button(1, 1, 0xA78DFF, "帮助", "/luadb/bangzhu.png", 96, "OPEN_EXPRESS_HELP_WIN")
end

local function on_create()
    update_screen_size()
    create_ui()
end

local function on_destroy()
    if main_container then
        main_container:destroy()
        main_container = nil
    end
    win_id = nil
end

local function open()
    if not exwin.is_active(win_id) then
        win_id = exwin.open({
            on_create = on_create,
            on_destroy = on_destroy,
        })
        log.info("ecabinet", "主窗口打开成功", win_id)
    else
        log.warn("ecabinet", "主窗口已打开", win_id)
    end
end

sys.subscribe("OPEN_EXPRESS_CABINET_WIN", open)
