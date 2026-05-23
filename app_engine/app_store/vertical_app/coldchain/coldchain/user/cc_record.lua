--[[
@module  cc_record
@summary 智慧冷链监控运行记录页面
@version 1.0.0
@date    2026.05.14
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

    -- 主容器
    main_container = airui.container({
        x = 0, y = 0,
        w = screen_w, h = screen_h,
        color = 0x0a1931,
        parent = airui.screen
    })

    -- 顶部导航栏
    local header_h = math.floor(50 * density)
    airui.container({
        parent = main_container,
        x = 0, y = 0,
        w = screen_w, h = header_h,
        color = 0x141e30,
        radius = math.floor(8 * density),
    })

    -- 返回按钮
    airui.button({
        parent = main_container,
        x = math.floor(10 * density),
        y = math.floor((header_h - 32 * density) / 2),
        w = math.floor(70 * density),
        h = math.floor(32 * density),
        text = "返回",
        style = {
            bg_color = 0x1e2630,
            pressed_bg_color = 0x0d47a1,
            text_color = 0x4fc3f7,
            radius = math.floor(6 * density),
            font_size = math.floor(13 * density),
            font_weight = 500,
            border_width = 0,
        },
        on_click = function()
            exwin.close(win_id)
        end
    })

    -- 标题
    airui.label({
        parent = main_container,
        text = "运行记录",
        x = 0,
        y = math.floor((header_h - 18 * density) / 2),
        w = screen_w,
        h = math.floor(18 * density),
        font_size = math.floor(18 * density),
        color = 0xffffff,
        font_weight = 600,
        align = airui.TEXT_ALIGN_CENTER,
    })

    -- 时间显示
    airui.label({
        parent = main_container,
        text = os.date("%H:%M:%S"),
        x = screen_w - math.floor(80 * density),
        y = math.floor((header_h - 16 * density) / 2),
        w = math.floor(70 * density),
        h = math.floor(16 * density),
        font_size = math.floor(14 * density),
        color = 0xffffff,
        font_weight = 500,
        align = airui.TEXT_ALIGN_RIGHT,
    })

    -- 主内容区域
    local content_y = header_h + math.floor(10 * density)
    local content_h = screen_h - header_h - math.floor(50 * density)

    -- 左侧：运行统计
    local left_w = math.floor(screen_w / 2 - 5 * density)
    local left_x = math.floor(5 * density)

    airui.container({
        parent = main_container,
        x = left_x, y = content_y,
        w = left_w, h = content_h,
        color = 0x141e30,
        radius = math.floor(8 * density),
    })

    airui.label({
        parent = main_container,
        text = "运行统计",
        x = left_x,
        y = content_y + math.floor(10 * density),
        w = left_w,
        h = math.floor(20 * density),
        font_size = math.floor(14 * density),
        color = 0xffffff,
        font_weight = 600,
    })

    -- 统计卡片
    local stat_y = content_y + math.floor(40 * density)
    local stat_w = math.floor((left_w - math.floor(15 * density)) / 2)
    local stat_h = math.floor(80 * density)

    -- 运行时长
    airui.container({
        parent = main_container,
        x = left_x + math.floor(5 * density),
        y = stat_y,
        w = stat_w, h = stat_h,
        color = 0x1e2630,
        radius = math.floor(6 * density),
    })

    airui.label({
        parent = main_container,
        text = "运行时长",
        x = left_x + math.floor(5 * density),
        y = stat_y + math.floor(10 * density),
        w = stat_w,
        h = math.floor(16 * density),
        font_size = math.floor(12 * density),
        color = 0x888888,
        align = airui.TEXT_ALIGN_CENTER,
    })

    airui.label({
        parent = main_container,
        text = "156",
        x = left_x + math.floor(5 * density),
        y = stat_y + math.floor(30 * density),
        w = stat_w * 0.6,
        h = math.floor(30 * density),
        font_size = math.floor(28 * density),
        color = 0x4fc3f7,
        font_weight = 600,
        align = airui.TEXT_ALIGN_RIGHT,
    })

    airui.label({
        parent = main_container,
        text = "小时",
        x = left_x + math.floor(5 * density) + stat_w * 0.6,
        y = stat_y + math.floor(38 * density),
        w = stat_w * 0.4,
        h = math.floor(18 * density),
        font_size = math.floor(12 * density),
        color = 0x888888,
        align = airui.TEXT_ALIGN_LEFT,
    })

    -- 告警次数
    airui.container({
        parent = main_container,
        x = left_x + stat_w + math.floor(10 * density),
        y = stat_y,
        w = stat_w, h = stat_h,
        color = 0x1e2630,
        radius = math.floor(6 * density),
    })

    airui.label({
        parent = main_container,
        text = "告警次数",
        x = left_x + stat_w + math.floor(10 * density),
        y = stat_y + math.floor(10 * density),
        w = stat_w,
        h = math.floor(16 * density),
        font_size = math.floor(12 * density),
        color = 0x888888,
        align = airui.TEXT_ALIGN_CENTER,
    })

    airui.label({
        parent = main_container,
        text = "23",
        x = left_x + stat_w + math.floor(10 * density),
        y = stat_y + math.floor(30 * density),
        w = stat_w * 0.6,
        h = math.floor(30 * density),
        font_size = math.floor(28 * density),
        color = 0xf44336,
        font_weight = 600,
        align = airui.TEXT_ALIGN_RIGHT,
    })

    airui.label({
        parent = main_container,
        text = "次",
        x = left_x + stat_w + math.floor(10 * density) + stat_w * 0.6,
        y = stat_y + math.floor(38 * density),
        w = stat_w * 0.4,
        h = math.floor(18 * density),
        font_size = math.floor(12 * density),
        color = 0x888888,
        align = airui.TEXT_ALIGN_LEFT,
    })

    -- 平均温度
    airui.container({
        parent = main_container,
        x = left_x + math.floor(5 * density),
        y = stat_y + stat_h + math.floor(10 * density),
        w = stat_w, h = stat_h,
        color = 0x1e2630,
        radius = math.floor(6 * density),
    })

    airui.label({
        parent = main_container,
        text = "平均温度",
        x = left_x + math.floor(5 * density),
        y = stat_y + stat_h + math.floor(20 * density),
        w = stat_w,
        h = math.floor(16 * density),
        font_size = math.floor(12 * density),
        color = 0x888888,
        align = airui.TEXT_ALIGN_CENTER,
    })

    airui.label({
        parent = main_container,
        text = "3.8",
        x = left_x + math.floor(5 * density),
        y = stat_y + stat_h + math.floor(40 * density),
        w = stat_w * 0.6,
        h = math.floor(30 * density),
        font_size = math.floor(28 * density),
        color = 0x4fc3f7,
        font_weight = 600,
        align = airui.TEXT_ALIGN_RIGHT,
    })

    airui.label({
        parent = main_container,
        text = "°C",
        x = left_x + math.floor(5 * density) + stat_w * 0.6,
        y = stat_y + stat_h + math.floor(48 * density),
        w = stat_w * 0.4,
        h = math.floor(18 * density),
        font_size = math.floor(12 * density),
        color = 0x888888,
        align = airui.TEXT_ALIGN_LEFT,
    })

    -- 平均湿度
    airui.container({
        parent = main_container,
        x = left_x + stat_w + math.floor(10 * density),
        y = stat_y + stat_h + math.floor(10 * density),
        w = stat_w, h = stat_h,
        color = 0x1e2630,
        radius = math.floor(6 * density),
    })

    airui.label({
        parent = main_container,
        text = "平均湿度",
        x = left_x + stat_w + math.floor(10 * density),
        y = stat_y + stat_h + math.floor(20 * density),
        w = stat_w,
        h = math.floor(16 * density),
        font_size = math.floor(12 * density),
        color = 0x888888,
        align = airui.TEXT_ALIGN_CENTER,
    })

    airui.label({
        parent = main_container,
        text = "62",
        x = left_x + stat_w + math.floor(10 * density),
        y = stat_y + stat_h + math.floor(40 * density),
        w = stat_w * 0.6,
        h = math.floor(30 * density),
        font_size = math.floor(28 * density),
        color = 0x66bb6a,
        font_weight = 600,
        align = airui.TEXT_ALIGN_RIGHT,
    })

    airui.label({
        parent = main_container,
        text = "%",
        x = left_x + stat_w + math.floor(10 * density) + stat_w * 0.6,
        y = stat_y + stat_h + math.floor(48 * density),
        w = stat_w * 0.4,
        h = math.floor(18 * density),
        font_size = math.floor(12 * density),
        color = 0x888888,
        align = airui.TEXT_ALIGN_LEFT,
    })

    -- 运行状态图表区域
    local chart_y = stat_y + stat_h * 2 + math.floor(20 * density)
    airui.container({
        parent = main_container,
        x = left_x + math.floor(5 * density),
        y = chart_y,
        w = left_w - math.floor(10 * density),
        h = content_h - (chart_y - content_y) - math.floor(10 * density),
        color = 0x1e2630,
        radius = math.floor(6 * density),
    })

    airui.label({
        parent = main_container,
        text = "运行状态分布",
        x = left_x + math.floor(10 * density),
        y = chart_y + math.floor(12 * density),
        w = math.floor(120 * density),
        h = math.floor(16 * density),
        font_size = math.floor(12 * density),
        color = 0xffffff,
        font_weight = 500,
    })

    -- 饼图占位
    airui.image({
        parent = main_container,
        x = left_x + math.floor(left_w / 2 - 35 * density),
        y = chart_y + math.floor(35 * density),
        w = math.floor(70 * density),
        h = math.floor(70 * density),
        src = "/luadb/pie.png",
        radius = math.floor(35 * density),
    })

    -- 图例
    local legend_y = chart_y + math.floor(115 * density)
    local legend_items = {
        {color = 0x66bb6a, label = "正常运行"},
        {color = 0xff9800, label = "告警状态"},
        {color = 0xf44336, label = "故障停机"},
    }

    for i, item in ipairs(legend_items) do
        airui.container({
            parent = main_container,
            x = left_x + math.floor(20 * density) + (i - 1) * math.floor(100 * density),
            y = legend_y,
            w = math.floor(10 * density),
            h = math.floor(10 * density),
            color = item.color,
            radius = math.floor(2 * density),
        })

        airui.label({
            parent = main_container,
            text = item.label,
            x = left_x + math.floor(35 * density) + (i - 1) * math.floor(100 * density),
            y = legend_y - math.floor(2 * density),
            w = math.floor(60 * density),
            h = math.floor(14 * density),
            font_size = math.floor(11 * density),
            color = 0x888888,
        })
    end

    -- 右侧：事件记录
    local right_x = left_w + math.floor(10 * density)
    local right_w = screen_w - right_x - math.floor(5 * density)

    airui.container({
        parent = main_container,
        x = right_x, y = content_y,
        w = right_w, h = content_h,
        color = 0x141e30,
        radius = math.floor(8 * density),
    })

    airui.label({
        parent = main_container,
        text = "事件记录",
        x = right_x,
        y = content_y + math.floor(10 * density),
        w = right_w,
        h = math.floor(20 * density),
        font_size = math.floor(14 * density),
        color = 0xffffff,
        font_weight = 600,
    })

    -- 事件列表
    local event_y = content_y + math.floor(40 * density)
    local event_h = math.floor(55 * density)

    -- 事件1
    airui.container({
        parent = main_container,
        x = right_x + math.floor(5 * density),
        y = event_y,
        w = right_w - math.floor(10 * density),
        h = event_h,
        color = 0x1e2630,
        radius = math.floor(4 * density),
    })

    airui.image({
        parent = main_container,
        x = right_x + math.floor(12 * density),
        y = event_y + math.floor(12 * density),
        w = math.floor(20 * density),
        h = math.floor(20 * density),
        src = "/luadb/alarm.png",
    })

    airui.label({
        parent = main_container,
        text = "温度过高告警",
        x = right_x + math.floor(38 * density),
        y = event_y + math.floor(10 * density),
        w = math.floor(150 * density),
        h = math.floor(16 * density),
        font_size = math.floor(12 * density),
        color = 0xf44336,
        font_weight = 500,
    })

    airui.label({
        parent = main_container,
        text = "温度达到7.2°C，超过上限",
        x = right_x + math.floor(38 * density),
        y = event_y + math.floor(28 * density),
        w = math.floor(180 * density),
        h = math.floor(14 * density),
        font_size = math.floor(10 * density),
        color = 0x888888,
    })

    airui.label({
        parent = main_container,
        text = "10:25:34",
        x = right_x + right_w - math.floor(80 * density),
        y = event_y + math.floor(19 * density),
        w = math.floor(70 * density),
        h = math.floor(14 * density),
        font_size = math.floor(10 * density),
        color = 0x888888,
        align = airui.TEXT_ALIGN_RIGHT,
    })

    -- 事件2
    airui.container({
        parent = main_container,
        x = right_x + math.floor(5 * density),
        y = event_y + event_h + math.floor(5 * density),
        w = right_w - math.floor(10 * density),
        h = event_h,
        color = 0x1e2630,
        radius = math.floor(4 * density),
    })

    airui.image({
        parent = main_container,
        x = right_x + math.floor(12 * density),
        y = event_y + event_h + math.floor(17 * density),
        w = math.floor(20 * density),
        h = math.floor(20 * density),
        src = "/luadb/alarm.png",
    })

    airui.label({
        parent = main_container,
        text = "设备启动",
        x = right_x + math.floor(38 * density),
        y = event_y + event_h + math.floor(15 * density),
        w = math.floor(100 * density),
        h = math.floor(16 * density),
        font_size = math.floor(12 * density),
        color = 0x66bb6a,
        font_weight = 500,
    })

    airui.label({
        parent = main_container,
        text = "压缩机、风扇正常启动",
        x = right_x + math.floor(38 * density),
        y = event_y + event_h + math.floor(33 * density),
        w = math.floor(150 * density),
        h = math.floor(14 * density),
        font_size = math.floor(10 * density),
        color = 0x888888,
    })

    airui.label({
        parent = main_container,
        text = "08:00:01",
        x = right_x + right_w - math.floor(80 * density),
        y = event_y + event_h + math.floor(24 * density),
        w = math.floor(70 * density),
        h = math.floor(14 * density),
        font_size = math.floor(10 * density),
        color = 0x888888,
        align = airui.TEXT_ALIGN_RIGHT,
    })

    -- 事件3
    airui.container({
        parent = main_container,
        x = right_x + math.floor(5 * density),
        y = event_y + event_h * 2 + math.floor(10 * density),
        w = right_w - math.floor(10 * density),
        h = event_h,
        color = 0x1e2630,
        radius = math.floor(4 * density),
    })

    airui.image({
        parent = main_container,
        x = right_x + math.floor(12 * density),
        y = event_y + event_h * 2 + math.floor(22 * density),
        w = math.floor(20 * density),
        h = math.floor(20 * density),
        src = "/luadb/alarm.png",
    })

    airui.label({
        parent = main_container,
        text = "数据上报",
        x = right_x + math.floor(38 * density),
        y = event_y + event_h * 2 + math.floor(20 * density),
        w = math.floor(100 * density),
        h = math.floor(16 * density),
        font_size = math.floor(12 * density),
        color = 0x4fc3f7,
        font_weight = 500,
    })

    airui.label({
        parent = main_container,
        text = "成功上传温度数据至服务器",
        x = right_x + math.floor(38 * density),
        y = event_y + event_h * 2 + math.floor(38 * density),
        w = math.floor(180 * density),
        h = math.floor(14 * density),
        font_size = math.floor(10 * density),
        color = 0x888888,
    })

    airui.label({
        parent = main_container,
        text = "10:25:00",
        x = right_x + right_w - math.floor(80 * density),
        y = event_y + event_h * 2 + math.floor(29 * density),
        w = math.floor(70 * density),
        h = math.floor(14 * density),
        font_size = math.floor(10 * density),
        color = 0x888888,
        align = airui.TEXT_ALIGN_RIGHT,
    })

    -- 事件4
    airui.container({
        parent = main_container,
        x = right_x + math.floor(5 * density),
        y = event_y + event_h * 3 + math.floor(15 * density),
        w = right_w - math.floor(10 * density),
        h = event_h,
        color = 0x1e2630,
        radius = math.floor(4 * density),
    })

    airui.image({
        parent = main_container,
        x = right_x + math.floor(12 * density),
        y = event_y + event_h * 3 + math.floor(27 * density),
        w = math.floor(20 * density),
        h = math.floor(20 * density),
        src = "/luadb/alarm.png",
    })

    airui.label({
        parent = main_container,
        text = "除霜完成",
        x = right_x + math.floor(38 * density),
        y = event_y + event_h * 3 + math.floor(25 * density),
        w = math.floor(100 * density),
        h = math.floor(16 * density),
        font_size = math.floor(12 * density),
        color = 0xff9800,
        font_weight = 500,
    })

    airui.label({
        parent = main_container,
        text = "除霜周期结束，恢复制冷",
        x = right_x + math.floor(38 * density),
        y = event_y + event_h * 3 + math.floor(43 * density),
        w = math.floor(150 * density),
        h = math.floor(14 * density),
        font_size = math.floor(10 * density),
        color = 0x888888,
    })

    airui.label({
        parent = main_container,
        text = "09:30:45",
        x = right_x + right_w - math.floor(80 * density),
        y = event_y + event_h * 3 + math.floor(34 * density),
        w = math.floor(70 * density),
        h = math.floor(14 * density),
        font_size = math.floor(10 * density),
        color = 0x888888,
        align = airui.TEXT_ALIGN_RIGHT,
    })

    -- 底部状态栏
    local footer_y = screen_h - math.floor(35 * density)
    airui.container({
        parent = main_container,
        x = math.floor(5 * density), y = footer_y,
        w = screen_w - math.floor(10 * density), h = math.floor(30 * density),
        color = 0x141e30,
        radius = math.floor(6 * density),
    })

    airui.label({
        parent = main_container,
        text = "记录总数: 128 条 | 存储占用: 2.4 MB",
        x = 0,
        y = footer_y + math.floor((30 * density - 12 * density) / 2),
        w = screen_w,
        h = math.floor(12 * density),
        font_size = math.floor(11 * density),
        color = 0x888888,
        align = airui.TEXT_ALIGN_CENTER,
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
        log.info("cc_record", "记录窗口打开成功", win_id)
    end
end

sys.subscribe("OPEN_CC_RECORD_WIN", open)
