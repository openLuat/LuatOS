--[[
@module  ecabinet
@summary 智能寄存柜主窗口模块
@version 4.0 (深蓝风格：玻璃柜团背景 + 蓝色标题条 + 四色方形按钮)
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

    -- ================= 背景：深蓝色 =================
    main_container = airui.container({
        x = 0, y = 0,
        w = screen_w, h = screen_h,
        color = 0x0A1E3A,
        parent = airui.screen
    })

    -- ================= 智能柜背景：已移除（按 HTML 设计稿，柜墙不需要） =================
    -- 原 5 列错落大方格代码删除，左侧背景直接使用 main_container 的 0x0A1E3A 深蓝

    -- ================= 左侧寄存柜背景：airui.shape 透视柜墙（梯形墙，5 行 5 列，格子宽≈高（高度再高一点），延伸至按钮背面） ================
    -- 1) 用竖条填出整面梯形柜墙（x=0 处保留上下边距，越往右越矮）
    -- 2) 横向透视线全部交汇于右侧消失点
    -- 3) 竖向分列线从墙顶画到墙底，列宽循环生成（列宽 = 1.05 × 行高，宽度≈高度）
    -- 格线用底色 0x0A1E3A（与 main_container 同色），柜格用明亮饱和蓝 0x2478E8
    local cell_color  = 0x2478E8   -- 明亮饱和蓝柜格
    local wall_w, wall_h = 960, 600
    local wall_right  = 636          -- 墙面右边界（延伸至取件按钮 580~750 背面；最后一列已删除）
    local vp_x, vp_y  = 1200, 290    -- 透视消失点（屏幕外右侧、垂直居中偏上）
    local edge_top, edge_bot = -40, 720 -- x=0 处墙面上下边界（出血，row_h0 增大→格子更高）
    local row_count   = 5            -- 行数（左端行高 152）
    local line_w      = 6            -- 格线粗细
    local row_h0      = (edge_bot - edge_top) / row_count  -- x=0 处行高

    -- 列边线循环生成：列宽 = 1.125 × 行高（宽度 161/139/121/104/91，高度不变 142/125/109/96/84）；最后一列删除——wall_right 收缩到最后一列右边界，无多余蓝色窄带
    local col_edge = { 0 }
    local cx = 0
    while true do
        local w = row_h0 * 1.125 * (vp_x - cx) / (vp_x + row_h0 / 2)
        if w < 20 or cx + w >= wall_right then break end
        cx = cx + math.floor(w + 0.5)
        col_edge[#col_edge + 1] = cx
    end
    wall_right = cx   -- 缩到最后一列右边界（删除末尾蓝色窄带）

    -- 透视投影：把 x=0 处的 y0 投影到 x 处的 y（所有横线相交于消失点）
    local function proj_y(y0, x)
        return vp_y + (y0 - vp_y) * (vp_x - x) / vp_x
    end

    local items = {}

    -- 1) 梯形墙面：8px 宽竖条拼接
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

    -- 2) 横向透视线
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

    -- 3) 竖向分列线
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

    -- ================= 左侧标题面板 =================
    local tp_x = math.floor(110 * density)   -- 整体右移：40 → 110，靠近按钮但不挨着
    local tp_y = math.floor(222 * density)
    local tp_w = math.floor(440 * density)   -- 宽度略增：424 → 440
    local tp_h = math.floor(144 * density)

    -- 标题主体（深蓝，圆角）
    airui.container({
        parent = main_container,
        x = tp_x, y = tp_y,
        w = tp_w, h = tp_h,
        color = 0x093868,
        radius = math.floor(10 * density),
        shadow = {
            offset_x = math.floor(3 * density),
            offset_y = math.floor(4 * density),
            blur     = math.floor(12 * density),
            color    = 0x000814,
            opacity  = 0.55,
        },
    })

    -- 标题条左侧亮边（细高亮条）
    airui.container({
        parent = main_container,
        x = tp_x, y = tp_y,
        w = math.floor(6 * density), h = tp_h,
        color = 0x6BB6FF,
        radius = math.floor(10 * density),
    })

    -- 标题文字：三段拼接，「合宙」用亮黄色
    local title_y = tp_y + math.floor(18 * density)
    local title_h = math.floor(40 * density)
    local font_title = math.floor(32 * density)

    -- 段1：欢迎使用（4 字 × 32 = 128，从 30 起）
    airui.label({
        parent = main_container,
        text = "欢迎使用",
        x = tp_x + math.floor(30 * density),
        y = title_y,
        w = math.floor(128 * density),
        h = title_h,
        font_size  = font_title,
        color      = 0xFFFFFF,
        align      = airui.TEXT_ALIGN_LEFT,
        font_weight = 800,
    })
    -- 段2：合宙（亮黄色，紧接段1：30+128=158）
    airui.label({
        parent = main_container,
        text = "合宙",
        x = tp_x + math.floor(158 * density),
        y = title_y,
        w = math.floor(64 * density),
        h = title_h,
        font_size  = font_title,
        color      = 0xFFEB00,
        align      = airui.TEXT_ALIGN_LEFT,
        font_weight = 800,
    })
    -- 段3：智能寄存柜（紧接段2：158+64=222，5 字 × 32 = 160）
    airui.label({
        parent = main_container,
        text = "智能寄存柜",
        x = tp_x + math.floor(222 * density),
        y = title_y,
        w = math.floor(160 * density),
        h = title_h,
        font_size  = font_title,
        color      = 0xFFFFFF,
        align      = airui.TEXT_ALIGN_LEFT,
        font_weight = 800,
    })

    -- 副标题（在标题面板内水平居中）
    airui.label({
        parent = main_container,
        text = "随存随取，安全便捷。",
        x = tp_x,
        y = tp_y + math.floor(86 * density),
        w = tp_w,
        h = math.floor(28 * density),
        font_size = math.floor(18 * density),
        color     = 0xEAF2FF,
        align     = airui.TEXT_ALIGN_CENTER,
    })

    -- ================= 右侧六个功能方块（2 列 × 3 行，方框放大） =================
    -- 2 列 × 3 行，每块 170×158，gap_x=20，gap_y=14
    -- 总宽 2×170 + 20 = 360；btn_x0=580，结束 x=940，右边距 84
    -- 总高 3×158 + 2×14 = 502；btn_y0=50，最后一行结束 y=552，底部留 48
    -- 与原 140×140 相比：宽 +21%、高 +13%，明显更大气
    local btn_size  = math.floor(170 * density)
    local btn_h     = math.floor(158 * density)
    local btn_gap_x = math.floor(20  * density)
    local btn_gap_y = math.floor(14  * density)
    local btn_x0    = math.floor(580 * density)
    local btn_y0    = math.floor(50  * density)

    local icon_size = math.floor(74 * density)    -- 图标随按钮放大
    local icon_y    = math.floor(22 * density)    -- 图标顶部偏移
    local label_y   = math.floor(108 * density)   -- 文字顶部偏移
    local label_h   = math.floor(32 * density)
    local label_fs  = math.floor(24 * density)

    -- 配色体系：每行同色系深浅成对
    --   行 1（深色衬底）：深蓝 / 深紫
    --   行 2（中性色）：   天蓝 / 琥珀橙
    --   行 3（工具色）：   薄荷绿 / 淡紫
    local buttons = {
        -- 左列（列 1）：刷脸取件 / 取件 / 管理
        { row = 1, col = 1, color = 0x1E5FA8, icon = "/luadb/bzqu.png",
          label = "刷脸取件", tts = "刷脸取件", action = "OPEN_FACE_RECEIVE_WIN" },
        { row = 2, col = 1, color = 0x2244CC, icon = "/luadb/qujian.png",
          label = "取件", tts = "取件", action = "OPEN_EXPRESS_RECEIVE_WIN" },
        { row = 3, col = 1, color = 0x1FBE9E, icon = "/luadb/guanli.png",
          label = "管理", tts = "管理", action = "OPEN_COURIER_MANAGEMENT_WIN" },
        -- 右列（列 2）：刷脸存件 / 存件 / 帮助
        { row = 1, col = 2, color = 0x6A4FD0, icon = "/luadb/bzcun.png",
          label = "刷脸存件", tts = "刷脸存件", action = "OPEN_FACE_DEPOSIT_WIN" },
        { row = 2, col = 2, color = 0xF59426, icon = "/luadb/cunjian.png",
          label = "存件", tts = "存件", action = "OPEN_EXPRESS_SEND_WIN" },
        { row = 3, col = 2, color = 0xA78BEE, icon = "/luadb/bangzhu.png",
          label = "帮助", tts = "帮助", action = "OPEN_EXPRESS_HELP_WIN" },
    }

    for _, b in ipairs(buttons) do
        local x = btn_x0 + (b.col - 1) * (btn_size + btn_gap_x)
        local y = btn_y0 + (b.row - 1) * (btn_h + btn_gap_y)

        -- 按钮主体
        airui.container({
            parent = main_container,
            x = x, y = y,
            w = btn_size, h = btn_h,
            color = b.color,
            radius = math.floor(14 * density),
            shadow = {
                offset_x = math.floor(3 * density),
                offset_y = math.floor(4 * density),
                blur     = math.floor(10 * density),
                color    = 0x000814,
                opacity  = 0.30,
            },
            on_click = function()
                log.info("ecabinet", b.label .. "按键触发")
                pcall(function()
                    local audio_tts = require "audio_tts"
                    audio_tts.play(b.tts)
                end)
                sys.publish(b.action)
            end,
        })

        -- 图标（垂直居中偏上）
        airui.image({
            parent = main_container,
            x = x + math.floor((btn_size - icon_size) / 2),
            y = y + icon_y,
            w = icon_size, h = icon_size,
            src = b.icon,
        })

        -- 文字（紧贴图标下方，水平居中）
        airui.label({
            parent = main_container,
            text = b.label,
            x = x,
            y = y + label_y,
            w = btn_size,
            h = label_h,
            font_size  = label_fs,
            color      = 0xFFFFFF,
            align      = airui.TEXT_ALIGN_CENTER,
            font_weight = 700,
        })
    end
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
            on_create   = on_create,
            on_destroy  = on_destroy,
        })
        log.info("ecabinet", "主窗口打开成功", win_id)
    else
        log.warn("ecabinet", "主窗口已打开", win_id)
    end
end

sys.subscribe("OPEN_EXPRESS_CABINET_WIN", open)