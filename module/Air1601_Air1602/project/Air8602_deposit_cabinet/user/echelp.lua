--[[
@module  echelp
@summary 寄存柜帮助窗口模块
@version 1.2 (蓝白风格，回调改为命名函数)
@date    2026.05.11
@author  王城钧
@usage
订阅 "OPEN_EXPRESS_HELP_WIN" 消息打开帮助窗口。
]]

local win_id = nil
local main_container = nil
local screen_w, screen_h = 1024, 600

-- 返回按钮回调：关闭帮助窗口
local function on_back_click()
    exwin.close(win_id)
end

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

    main_container = airui.container({
        parent = airui.screen,
        x = 0, y = 0,
        w = screen_w, h = screen_h,
        color = 0xF8F9FA,
    })

    -- 顶部导航栏
    local header_h = math.floor(60 * density)
    local header = airui.container({
        parent = main_container,
        x = 0, y = 0,
        w = screen_w, h = header_h,
        color = 0x4A90E2,
        radius = 0,
    })

    -- 返回按钮
    airui.button({
        parent = header,
        x = math.floor(15 * density),
        y = math.floor((header_h - 35 * density) / 2),
        w = math.floor(70 * density),
        h = math.floor(35 * density),
        text = "返回",
        style = {
            bg_color = 0xFFFFFF, pressed_bg_color = 0xEFEFEF,
            text_color = 0x4A90E2, radius = math.floor(7 * density),
            font_size = math.floor(15 * density), font_weight = 500,
            border_width = 0,
        },
        on_click = on_back_click
    })

    -- 标题居中
    airui.label({
        parent = header,
        text = "使用帮助",
        x = 0,
        y = math.floor((header_h - 28 * density) / 2),
        w = screen_w,
        h = math.floor(28 * density),
        font_size = math.floor(24 * density),
        color = 0xFFFFFF,
        align = airui.TEXT_ALIGN_CENTER,
        font_weight = 600,
    })

    -- 左右两栏布局
    local content_margin = math.floor(15 * density)
    local column_w = math.floor((screen_w - math.floor(40 * density)) / 2)
    local column_h = math.floor((screen_h - header_h - math.floor(42 * density)) * 0.65)

    -- 左侧容器（存件流程）
    local left_container = airui.container({
        parent = main_container,
        x = content_margin,
        y = header_h + content_margin,
        w = column_w,
        h = column_h,
        color = 0xFFFFFF,
        radius = math.floor(8 * density),
        shadow = {
            offset_x = math.floor(2 * density),
            offset_y = math.floor(2 * density),
            blur = math.floor(5 * density),
            color = 0x000000,
            opacity = 0.06,
        }
    })

    -- 右侧容器（取件流程）
    local right_container = airui.container({
        parent = main_container,
        x = screen_w - column_w - content_margin,
        y = header_h + content_margin,
        w = column_w,
        h = column_h,
        color = 0xFFFFFF,
        radius = math.floor(8 * density),
        shadow = {
            offset_x = math.floor(2 * density),
            offset_y = math.floor(2 * density),
            blur = math.floor(5 * density),
            color = 0x000000,
            opacity = 0.06,
        }
    })

    -- 下方容器（注意事项、客服信息和二维码）
    local bottom_h = screen_h - header_h - column_h - math.floor(45 * density)
    local bottom_container = airui.container({
        parent = main_container,
        x = content_margin,
        y = header_h + content_margin + column_h + content_margin,
        w = screen_w - math.floor(30 * density),
        h = bottom_h,
        color = 0xFFFFFF,
        radius = math.floor(8 * density),
        shadow = {
            offset_x = math.floor(2 * density),
            offset_y = math.floor(2 * density),
            blur = math.floor(5 * density),
            color = 0x000000,
            opacity = 0.06,
        }
    })

    -- 左侧：存件流程
    airui.label({
        parent = left_container,
        text = "存件流程",
        x = math.floor(15 * density),
        y = math.floor(12 * density),
        w = column_w - math.floor(30 * density),
        h = math.floor(24 * density),
        font_size = math.floor(16 * density),
        color = 0x4A90E2,
        align = airui.TEXT_ALIGN_LEFT,
        font_weight = 600,
    })

    local deposit_steps = {
        { title = "选择存件", desc = "在主页面点击存件按钮" },
        { title = "输入存件码", desc = "扫描二维码获取存件码" },
        { title = "选择格口", desc = "根据物品大小选择合适的格口" },
        { title = "放置物品", desc = "打开柜门，放入物品" },
        { title = "关闭柜门", desc = "确保物品放置稳妥后关闭柜门" },
        { title = "支付费用", desc = "根据选择的格口类型支付相应费用" },
        { title = "完成存件", desc = "存件完成，系统会发送取件码" },
    }

    local deposit_step_y = math.floor(38 * density)
    for i, step in ipairs(deposit_steps) do
        airui.label({
            parent = left_container,
            text = string.format("%d. %s", i, step.title),
            x = math.floor(15 * density),
            y = deposit_step_y + (i - 1) * math.floor(36 * density),
            w = column_w - math.floor(30 * density),
            h = math.floor(16 * density),
            font_size = math.floor(12 * density),
            color = 0x4A90E2,
            align = airui.TEXT_ALIGN_LEFT,
            font_weight = 600,
        })

        airui.label({
            parent = left_container,
            text = step.desc,
            x = math.floor(15 * density),
            y = deposit_step_y + (i - 1) * math.floor(36 * density) + math.floor(18 * density),
            w = column_w - math.floor(30 * density),
            h = math.floor(18 * density),
            font_size = math.floor(10 * density),
            color = 0x999999,
            align = airui.TEXT_ALIGN_LEFT,
        })
    end

    -- 右侧：取件流程
    airui.label({
        parent = right_container,
        text = "取件流程",
        x = math.floor(15 * density),
        y = math.floor(12 * density),
        w = column_w - math.floor(30 * density),
        h = math.floor(24 * density),
        font_size = math.floor(16 * density),
        color = 0x4A90E2,
        align = airui.TEXT_ALIGN_LEFT,
        font_weight = 600,
    })

    local retrieve_steps = {
        { title = "选择取件", desc = "在主页面点击取件按钮" },
        { title = "输入取件码", desc = "输入收到的取件码" },
        { title = "柜门打开", desc = "系统验证取件码后打开柜门" },
        { title = "取出物品", desc = "取出物品，检查是否有遗漏" },
        { title = "关闭柜门", desc = "确保物品全部取出后关闭柜门" },
    }

    local retrieve_step_y = math.floor(38 * density)
    for i, step in ipairs(retrieve_steps) do
        airui.label({
            parent = right_container,
            text = string.format("%d. %s", i, step.title),
            x = math.floor(15 * density),
            y = retrieve_step_y + (i - 1) * math.floor(42 * density),
            w = column_w - math.floor(30 * density),
            h = math.floor(16 * density),
            font_size = math.floor(12 * density),
            color = 0x4A90E2,
            align = airui.TEXT_ALIGN_LEFT,
            font_weight = 600,
        })

        airui.label({
            parent = right_container,
            text = step.desc,
            x = math.floor(15 * density),
            y = retrieve_step_y + (i - 1) * math.floor(42 * density) + math.floor(18 * density),
            w = column_w - math.floor(30 * density),
            h = math.floor(18 * density),
            font_size = math.floor(10 * density),
            color = 0x999999,
            align = airui.TEXT_ALIGN_LEFT,
        })
    end

    -- 下方：注意事项（左侧）
    local note_top = math.floor(18 * density)
    airui.label({
        parent = bottom_container,
        text = "注意事项",
        x = math.floor(20 * density),
        y = note_top,
        w = math.floor(100 * density),
        h = math.floor(22 * density),
        font_size = math.floor(14 * density),
        color = 0x4A90E2,
        align = airui.TEXT_ALIGN_LEFT,
        font_weight = 600,
    })

    local notes = {
        "妥善保管取件码，避免泄露",
        "存件前检查格口内是否有遗留物品",
        "贵重物品请选择合适格口",
        "存件超过24小时可能产生额外费用",
        "柜门无法关闭请联系客服",
        "禁止存放违禁物品",
    }

    local note_y = note_top + math.floor(24 * density)
    for i, note in ipairs(notes) do
        airui.label({
            parent = bottom_container,
            text = string.format("• %s", note),
            x = math.floor(20 * density),
            y = note_y + (i - 1) * math.floor(17 * density),
            w = math.floor((screen_w - math.floor(30 * density)) / 2) - math.floor(100 * density),
            h = math.floor(16 * density),
            font_size = math.floor(10 * density),
            color = 0x999999,
            align = airui.TEXT_ALIGN_LEFT,
        })
    end

    -- 下方：客服信息（右侧，与取件流程对齐）
    local cs_x = math.floor((screen_w - math.floor(40 * density)) / 2)
    airui.label({
        parent = bottom_container,
        text = "客服信息",
        x = cs_x + math.floor(25 * density),
        y = note_top,
        w = math.floor(100 * density),
        h = math.floor(24 * density),
        font_size = math.floor(16 * density),
        color = 0x4A90E2,
        align = airui.TEXT_ALIGN_LEFT,
        font_weight = 600,
    })

    airui.label({
        parent = bottom_container,
        text = "客服电话：400-123-4567",
        x = cs_x + math.floor(25 * density),
        y = note_top + math.floor(30 * density),
        w = math.floor(160 * density),
        h = math.floor(22 * density),
        font_size = math.floor(12 * density),
        color = 0x999999,
        align = airui.TEXT_ALIGN_LEFT,
    })

    airui.label({
        parent = bottom_container,
        text = "工作时间：08:00-20:00",
        x = cs_x + math.floor(25 * density),
        y = note_top + math.floor(56 * density),
        w = math.floor(160 * density),
        h = math.floor(22 * density),
        font_size = math.floor(12 * density),
        color = 0x999999,
        align = airui.TEXT_ALIGN_LEFT,
    })

    airui.label({
        parent = bottom_container,
        text = "微信公众号：智能寄存柜",
        x = cs_x + math.floor(25 * density),
        y = note_top + math.floor(82 * density),
        w = math.floor(160 * density),
        h = math.floor(22 * density),
        font_size = math.floor(12 * density),
        color = 0x999999,
        align = airui.TEXT_ALIGN_LEFT,
    })

    -- 右下角：二维码
    local qr_size = math.floor(80 * density)
    airui.qrcode({
        parent = bottom_container,
        x = screen_w - content_margin - qr_size - math.floor(20 * density),
        y = bottom_h - qr_size - math.floor(15 * density),
        size = qr_size,
        data = "https://docs.openluat.com/",
        dark_color = 0x000000,
        light_color = 0xFFFFFF,
        quiet_zone = true,
    })
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
        log.info("echelp", "帮助窗口打开成功", win_id)
    else
        log.warn("echelp", "帮助窗口已打开", win_id)
    end
end

sys.subscribe("OPEN_EXPRESS_HELP_WIN", open)
