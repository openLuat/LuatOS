--[[
@module  cc_main
@summary 智慧冷链监控主页面
@version 1.0.0
@date    2026.05.14
]]

local win_id = nil
local main_container = nil
local timer_id = nil
local screen_w, screen_h = 1024, 600

-- 设备状态管理
local device_status = {
    power = false,          -- 电源开关：false=关, true=开
    cooling = false,        -- 制冷模式：false=关, true=开
    defrost = false,        -- 除霜：false=关, true=开
    lighting = false,       -- 箱内照明：false=关, true=开
    alarm_mute = false,     -- 告警静音：false=关, true=开
    emergency_stop = false  -- 紧急停机：false=正常, true=停机
}

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

    -- 顶部状态栏（高度调整为45）
    local header_h = math.floor(45 * density)
    airui.container({
        parent = main_container,
        x = 0, y = 0,
        w = screen_w, h = header_h,
        color = 0x141e30,
        radius = math.floor(6 * density),
    })

    -- 返回按钮（带实际返回功能）
    airui.button({
        parent = main_container,
        x = math.floor(10 * density),
        y = math.floor((header_h - math.floor(30 * density)) / 2),
        w = math.floor(65 * density),
        h = math.floor(30 * density),
        text = "返回",
        style = {
            bg_color = 0x1e2630,
            pressed_bg_color = 0x0d47a1,
            text_color = 0x4fc3f7,
            radius = math.floor(4 * density),
            font_size = math.floor(13 * density),
            font_weight = 500,
            border_width = 0,
        },
        on_click = function()
            log.info("cc_main", "返回按钮点击")
            exwin.close(win_id)
        end
    })

    -- 智慧冷链监控标题（居中）
    airui.label({
        parent = main_container,
        text = "智慧冷链监控",
        x = math.floor(screen_w / 2 - 100 * density),
        y = math.floor((header_h - 20 * density) / 2),
        w = math.floor(200 * density),
        h = math.floor(20 * density),
        font_size = math.floor(18 * density),
        color = 0xffffff,
        font_weight = 600,
        align = airui.TEXT_ALIGN_CENTER,
    })

    -- 右侧状态信息（优化布局，避免超出屏幕）
    local status_right_margin = math.floor(10 * density)
    local time_w = math.floor(50 * density)
    local status_x = screen_w - status_right_margin - time_w - math.floor(200 * density)
    local status_y = math.floor((header_h - 16 * density) / 2)

    -- 温度
    airui.image({
        parent = main_container,
        x = status_x, y = status_y,
        w = math.floor(14 * density), h = math.floor(14 * density),
        src = "/luadb/temp.png",
    })
    airui.label({
        parent = main_container,
        text = "3.5°C",
        x = status_x + math.floor(18 * density),
        y = status_y,
        w = math.floor(50 * density),
        h = math.floor(16 * density),
        font_size = math.floor(13 * density),
        color = 0x4fc3f7,
        font_weight = 500,
    })

    -- 湿度
    airui.image({
        parent = main_container,
        x = status_x + math.floor(72 * density), y = status_y,
        w = math.floor(14 * density), h = math.floor(14 * density),
        src = "/luadb/humi.png",
    })
    airui.label({
        parent = main_container,
        text = "65%",
        x = status_x + math.floor(92 * density),
        y = status_y,
        w = math.floor(40 * density),
        h = math.floor(16 * density),
        font_size = math.floor(13 * density),
        color = 0x66bb6a,
        font_weight = 500,
    })

    -- 网络状态
    airui.image({
        parent = main_container,
        x = status_x + math.floor(135 * density), y = status_y,
        w = math.floor(14 * density), h = math.floor(14 * density),
        src = "/luadb/wifi.png",
    })
    airui.label({
        parent = main_container,
        text = "在线",
        x = status_x + math.floor(155 * density),
        y = status_y,
        w = math.floor(40 * density),
        h = math.floor(16 * density),
        font_size = math.floor(13 * density),
        color = 0x66bb6a,
        font_weight = 500,
    })

    -- 时间（精确到分钟）
    local time_label = airui.label({
        parent = main_container,
        text = os.date("%H:%M"),
        x = screen_w - status_right_margin - time_w,
        y = status_y,
        w = time_w,
        h = math.floor(16 * density),
        font_size = math.floor(15 * density),
        color = 0xffffff,
        font_weight = 600,
    })

    -- 主内容区域
    local section_w = math.floor((screen_w - math.floor(20 * density)) / 3)
    local section_h = screen_h - header_h - math.floor(45 * density)
    local section_y = header_h + math.floor(8 * density)

    -- 左侧：温度监控面板
    local left_x = math.floor(5 * density)
    airui.container({
        parent = main_container,
        x = left_x, y = section_y,
        w = section_w, h = section_h,
        color = 0x141e30,
        radius = math.floor(6 * density),
    })

    -- 温度监控标题
    airui.label({
        parent = main_container,
        text = "温度监控",
        x = left_x,
        y = section_y + math.floor(10 * density),
        w = section_w,
        h = math.floor(22 * density),
        font_size = math.floor(15 * density),
        color = 0xffffff,
        font_weight = 600,
    })

    airui.label({
        parent = main_container,
        text = "正常",
        x = left_x + section_w - math.floor(65 * density),
        y = section_y + math.floor(10 * density),
        w = math.floor(55 * density),
        h = math.floor(18 * density),
        font_size = math.floor(12 * density),
        color = 0x69f0ae,
        align = airui.TEXT_ALIGN_CENTER,
        bg_color = 0x1b5e20,
        radius = math.floor(8 * density),
    })

    -- 温度显示
    airui.label({
        parent = main_container,
        text = "3.5",
        x = left_x,
        y = section_y + math.floor(45 * density),
        w = section_w * 0.5,
        h = math.floor(50 * density),
        font_size = math.floor(36 * density),
        color = 0x4fc3f7,
        align = airui.TEXT_ALIGN_CENTER,
        font_weight = 600,
    })
    airui.label({
        parent = main_container,
        text = "°C",
        x = left_x,
        y = section_y + math.floor(80 * density),
        w = section_w * 0.5,
        h = math.floor(18 * density),
        font_size = math.floor(14 * density),
        color = 0x888888,
        align = airui.TEXT_ALIGN_CENTER,
    })

    -- 湿度显示
    airui.label({
        parent = main_container,
        text = "65",
        x = left_x + section_w * 0.5,
        y = section_y + math.floor(45 * density),
        w = section_w * 0.5,
        h = math.floor(50 * density),
        font_size = math.floor(36 * density),
        color = 0x66bb6a,
        align = airui.TEXT_ALIGN_CENTER,
        font_weight = 600,
    })
    airui.label({
        parent = main_container,
        text = "%",
        x = left_x + section_w * 0.5,
        y = section_y + math.floor(80 * density),
        w = section_w * 0.5,
        h = math.floor(18 * density),
        font_size = math.floor(14 * density),
        color = 0x888888,
        align = airui.TEXT_ALIGN_CENTER,
    })

    -- 设备状态网格
    local dev_y = section_y + math.floor(110 * density)
    local dev_w = math.floor((section_w - math.floor(12 * density)) / 2)
    local dev_h = math.floor((section_h - math.floor(130 * density)) / 3)

    -- 压缩机
    airui.container({
        parent = main_container,
        x = left_x + math.floor(5 * density),
        y = dev_y,
        w = dev_w, h = dev_h,
        color = 0x1e2630,
        radius = math.floor(6 * density),
    })
    airui.image({
        parent = main_container,
        x = left_x + math.floor(5 * density) + math.floor((dev_w - 32 * density) / 2),
        y = dev_y + math.floor(12 * density),
        w = math.floor(32 * density),
        h = math.floor(32 * density),
        src = "/luadb/comp.png",
    })
    airui.label({
        parent = main_container,
        text = "压缩机",
        x = left_x + math.floor(5 * density),
        y = dev_y + math.floor(50 * density),
        w = dev_w,
        h = math.floor(18 * density),
        font_size = math.floor(13 * density),
        color = 0xffffff,
        align = airui.TEXT_ALIGN_CENTER,
    })
    airui.label({
        parent = main_container,
        text = "运行中",
        x = left_x + math.floor(5 * density),
        y = dev_y + math.floor(70 * density),
        w = dev_w,
        h = math.floor(14 * density),
        font_size = math.floor(12 * density),
        color = 0x69f0ae,
        align = airui.TEXT_ALIGN_CENTER,
    })

    -- 冷凝风机
    airui.container({
        parent = main_container,
        x = left_x + dev_w + math.floor(7 * density),
        y = dev_y,
        w = dev_w, h = dev_h,
        color = 0x1e2630,
        radius = math.floor(6 * density),
    })
    airui.image({
        parent = main_container,
        x = left_x + dev_w + math.floor(7 * density) + math.floor((dev_w - 32 * density) / 2),
        y = dev_y + math.floor(12 * density),
        w = math.floor(32 * density),
        h = math.floor(32 * density),
        src = "/luadb/fan.png",
    })
    airui.label({
        parent = main_container,
        text = "冷凝风机",
        x = left_x + dev_w + math.floor(7 * density),
        y = dev_y + math.floor(50 * density),
        w = dev_w,
        h = math.floor(18 * density),
        font_size = math.floor(13 * density),
        color = 0xffffff,
        align = airui.TEXT_ALIGN_CENTER,
    })
    airui.label({
        parent = main_container,
        text = "运行中",
        x = left_x + dev_w + math.floor(7 * density),
        y = dev_y + math.floor(70 * density),
        w = dev_w,
        h = math.floor(14 * density),
        font_size = math.floor(12 * density),
        color = 0x69f0ae,
        align = airui.TEXT_ALIGN_CENTER,
    })

    -- 蒸发风机
    airui.container({
        parent = main_container,
        x = left_x + math.floor(5 * density),
        y = dev_y + dev_h + math.floor(5 * density),
        w = dev_w, h = dev_h,
        color = 0x1e2630,
        radius = math.floor(6 * density),
    })
    airui.image({
        parent = main_container,
        x = left_x + math.floor(5 * density) + math.floor((dev_w - 32 * density) / 2),
        y = dev_y + dev_h + math.floor(15 * density),
        w = math.floor(32 * density),
        h = math.floor(32 * density),
        src = "/luadb/evap.png",
    })
    airui.label({
        parent = main_container,
        text = "蒸发风机",
        x = left_x + math.floor(5 * density),
        y = dev_y + dev_h + math.floor(55 * density),
        w = dev_w,
        h = math.floor(18 * density),
        font_size = math.floor(13 * density),
        color = 0xffffff,
        align = airui.TEXT_ALIGN_CENTER,
    })
    airui.label({
        parent = main_container,
        text = "运行中",
        x = left_x + math.floor(5 * density),
        y = dev_y + dev_h + math.floor(75 * density),
        w = dev_w,
        h = math.floor(14 * density),
        font_size = math.floor(12 * density),
        color = 0x69f0ae,
        align = airui.TEXT_ALIGN_CENTER,
    })

    -- 箱门检测
    airui.container({
        parent = main_container,
        x = left_x + dev_w + math.floor(7 * density),
        y = dev_y + dev_h + math.floor(5 * density),
        w = dev_w, h = dev_h,
        color = 0x1e2630,
        radius = math.floor(6 * density),
    })
    airui.image({
        parent = main_container,
        x = left_x + dev_w + math.floor(7 * density) + math.floor((dev_w - 32 * density) / 2),
        y = dev_y + dev_h + math.floor(15 * density),
        w = math.floor(32 * density),
        h = math.floor(32 * density),
        src = "/luadb/cond.png",
    })
    airui.label({
        parent = main_container,
        text = "箱门",
        x = left_x + dev_w + math.floor(7 * density),
        y = dev_y + dev_h + math.floor(55 * density),
        w = dev_w,
        h = math.floor(18 * density),
        font_size = math.floor(13 * density),
        color = 0xffffff,
        align = airui.TEXT_ALIGN_CENTER,
    })
    airui.label({
        parent = main_container,
        text = "关闭",
        x = left_x + dev_w + math.floor(7 * density),
        y = dev_y + dev_h + math.floor(75 * density),
        w = dev_w,
        h = math.floor(14 * density),
        font_size = math.floor(12 * density),
        color = 0x69f0ae,
        align = airui.TEXT_ALIGN_CENTER,
    })

    -- 传感器状态
    airui.container({
        parent = main_container,
        x = left_x + math.floor(5 * density),
        y = dev_y + dev_h * 2 + math.floor(10 * density),
        w = dev_w, h = dev_h,
        color = 0x1e2630,
        radius = math.floor(6 * density),
    })
    airui.image({
        parent = main_container,
        x = left_x + math.floor(5 * density) + math.floor((dev_w - 32 * density) / 2),
        y = dev_y + dev_h * 2 + math.floor(20 * density),
        w = math.floor(32 * density),
        h = math.floor(32 * density),
        src = "/luadb/sensor.png",
    })
    airui.label({
        parent = main_container,
        text = "传感器",
        x = left_x + math.floor(5 * density),
        y = dev_y + dev_h * 2 + math.floor(60 * density),
        w = dev_w,
        h = math.floor(18 * density),
        font_size = math.floor(13 * density),
        color = 0xffffff,
        align = airui.TEXT_ALIGN_CENTER,
    })
    airui.label({
        parent = main_container,
        text = "正常",
        x = left_x + math.floor(5 * density),
        y = dev_y + dev_h * 2 + math.floor(80 * density),
        w = dev_w,
        h = math.floor(14 * density),
        font_size = math.floor(12 * density),
        color = 0x69f0ae,
        align = airui.TEXT_ALIGN_CENTER,
    })

    -- 告警状态
    airui.container({
        parent = main_container,
        x = left_x + dev_w + math.floor(7 * density),
        y = dev_y + dev_h * 2 + math.floor(10 * density),
        w = dev_w, h = dev_h,
        color = 0x1e2630,
        radius = math.floor(6 * density),
    })
    airui.image({
        parent = main_container,
        x = left_x + dev_w + math.floor(7 * density) + math.floor((dev_w - 32 * density) / 2),
        y = dev_y + dev_h * 2 + math.floor(20 * density),
        w = math.floor(32 * density),
        h = math.floor(32 * density),
        src = "/luadb/alarm.png",
    })
    airui.label({
        parent = main_container,
        text = "告警",
        x = left_x + dev_w + math.floor(7 * density),
        y = dev_y + dev_h * 2 + math.floor(60 * density),
        w = dev_w,
        h = math.floor(18 * density),
        font_size = math.floor(13 * density),
        color = 0xffffff,
        align = airui.TEXT_ALIGN_CENTER,
    })
    airui.label({
        parent = main_container,
        text = "2条",
        x = left_x + dev_w + math.floor(7 * density),
        y = dev_y + dev_h * 2 + math.floor(80 * density),
        w = dev_w,
        h = math.floor(14 * density),
        font_size = math.floor(12 * density),
        color = 0xff9800,
        align = airui.TEXT_ALIGN_CENTER,
    })

    -- 中间：温度曲线图
    local center_x = left_x + section_w + math.floor(5 * density)
    airui.container({
        parent = main_container,
        x = center_x, y = section_y,
        w = section_w, h = section_h,
        color = 0x141e30,
        radius = math.floor(6 * density),
    })

    airui.label({
        parent = main_container,
        text = "温度曲线 (24h)",
        x = center_x,
        y = section_y + math.floor(10 * density),
        w = section_w,
        h = math.floor(22 * density),
        font_size = math.floor(15 * density),
        color = 0xffffff,
        font_weight = 600,
    })

    -- 使用airui.chart绘制温度曲线图（调整高度避免拖拽条）
    local chart_margin = math.floor(20 * density)
    local chart_w = section_w - math.floor(40 * density)
    local chart_h = math.floor(section_h * 0.45)
    local chart_x = center_x + chart_margin
    local chart_y = section_y + math.floor(45 * density)
    
    -- 生成模拟温度数据
    local temp_data = {}
    for i = 1, 24 do
        table.insert(temp_data, {time = i..":00", value = 3.5 + math.sin(i * 0.5) * 2 + math.random() * 1})
    end
    
    -- 创建曲线图（参考演示代码优化，调整温度范围）
    local chart = airui.chart({
        parent = main_container,
        x = chart_x,
        y = chart_y,
        w = chart_w,
        h = chart_h,
        type = "line",
        y_min = -10,
        y_max = 10,
        point_count = 24,
        update_mode = "shift",
        line_color = 0x4fc3f7,
        line_width = 2,
        point_radius = 2,
        hdiv = 6,
        vdiv = 5,
        legend = true,
        x_axis = { enable = true, min = 0, max = 24, ticks = 6, unit = "h" },
        y_axis = { enable = true, min = -10, max = 10, ticks = 5, unit = "°C" }
    })

    -- 设置初始温度数据（包含负数温度）
    chart:set_series_name(1, "温度")
    chart:set_values(1, {-2.5, -3.2, -4.1, -3.8, -2.9, -1.5, -0.8, 1.2, 2.5, 3.8, 4.2, 3.5, 2.8, 1.5, 0.5, -1.2, -2.8, -3.5, -4.2, -3.8, -3.0, -2.5, -2.2, -1.8})

    -- 温度统计（调整位置避免遮挡）
    airui.label({
        parent = main_container,
        text = "当前: -1.5°C | 最高: 0°C | 最低: -3.8°C",
        x = center_x,
        y = chart_y + chart_h + math.floor(25 * density),
        w = section_w,
        h = math.floor(16 * density),
        font_size = math.floor(12 * density),
        color = 0x888888,
        align = airui.TEXT_ALIGN_CENTER,
    })

    -- 实时告警列表
    local alarm_y = chart_y + chart_h + math.floor(45 * density)
    airui.label({
        parent = main_container,
        text = "实时告警",
        x = center_x,
        y = alarm_y,
        w = section_w,
        h = math.floor(20 * density),
        font_size = math.floor(14 * density),
        color = 0xffffff,
        font_weight = 600,
    })

    -- 告警数量徽章
    airui.label({
        parent = main_container,
        text = "2个告警",
        x = center_x + section_w - math.floor(70 * density),
        y = alarm_y,
        w = math.floor(60 * density),
        h = math.floor(18 * density),
        font_size = math.floor(12 * density),
        color = 0xf44336,
        align = airui.TEXT_ALIGN_CENTER,
        bg_color = 0xb71c1c,
        radius = math.floor(8 * density),
    })

    -- 告警项1
    airui.container({
        parent = main_container,
        x = center_x + math.floor(8 * density),
        y = alarm_y + math.floor(25 * density),
        w = section_w - math.floor(16 * density),
        h = math.floor(42 * density),
        color = 0x1e2630,
        radius = math.floor(4 * density),
    })

    airui.image({
        parent = main_container,
        x = center_x + math.floor(12 * density),
        y = alarm_y + math.floor(32 * density),
        w = math.floor(22 * density),
        h = math.floor(22 * density),
        src = "/luadb/alarm.png",
    })

    airui.label({
        parent = main_container,
        text = "温度过高告警",
        x = center_x + math.floor(40 * density),
        y = alarm_y + math.floor(30 * density),
        w = math.floor(120 * density),
        h = math.floor(18 * density),
        font_size = math.floor(13 * density),
        color = 0xf44336,
        font_weight = 500,
    })

    airui.label({
        parent = main_container,
        text = "当前温度7.2°C，超过上限6°C",
        x = center_x + math.floor(40 * density),
        y = alarm_y + math.floor(50 * density),
        w = math.floor(180 * density),
        h = math.floor(14 * density),
        font_size = math.floor(11 * density),
        color = 0x888888,
    })

    airui.label({
        parent = main_container,
        text = "10:25",
        x = center_x + section_w - math.floor(75 * density),
        y = alarm_y + math.floor(38 * density),
        w = math.floor(65 * density),
        h = math.floor(14 * density),
        font_size = math.floor(11 * density),
        color = 0x888888,
        align = airui.TEXT_ALIGN_RIGHT,
    })

    -- 告警项2
    airui.container({
        parent = main_container,
        x = center_x + math.floor(8 * density),
        y = alarm_y + math.floor(72 * density),
        w = section_w - math.floor(16 * density),
        h = math.floor(42 * density),
        color = 0x1e2630,
        radius = math.floor(4 * density),
    })

    airui.image({
        parent = main_container,
        x = center_x + math.floor(12 * density),
        y = alarm_y + math.floor(79 * density),
        w = math.floor(22 * density),
        h = math.floor(22 * density),
        src = "/luadb/alarm.png",
    })

    airui.label({
        parent = main_container,
        text = "压缩机异常",
        x = center_x + math.floor(40 * density),
        y = alarm_y + math.floor(77 * density),
        w = math.floor(100 * density),
        h = math.floor(18 * density),
        font_size = math.floor(13 * density),
        color = 0xff9800,
        font_weight = 500,
    })

    airui.label({
        parent = main_container,
        text = "运行电流超出正常范围",
        x = center_x + math.floor(40 * density),
        y = alarm_y + math.floor(97 * density),
        w = math.floor(150 * density),
        h = math.floor(14 * density),
        font_size = math.floor(11 * density),
        color = 0x888888,
    })

    airui.label({
        parent = main_container,
        text = "09:15",
        x = center_x + section_w - math.floor(75 * density),
        y = alarm_y + math.floor(86 * density),
        w = math.floor(65 * density),
        h = math.floor(14 * density),
        font_size = math.floor(11 * density),
        color = 0x888888,
        align = airui.TEXT_ALIGN_RIGHT,
    })

    -- 右侧：设备控制和功能菜单
    local right_x = center_x + section_w + math.floor(5 * density)
    airui.container({
        parent = main_container,
        x = right_x, y = section_y,
        w = section_w, h = section_h,
        color = 0x141e30,
        radius = math.floor(6 * density),
    })

    -- 设备控制标题
    airui.label({
        parent = main_container,
        text = "设备控制",
        x = right_x,
        y = section_y + math.floor(10 * density),
        w = section_w,
        h = math.floor(22 * density),
        font_size = math.floor(15 * density),
        color = 0xffffff,
        font_weight = 600,
    })

    -- 设备控制按钮（带图标，增大字体）
    local ctrl_w = math.floor((section_w - math.floor(15 * density)) / 3)
    local ctrl_h = math.floor(75 * density)
    local ctrl_y = section_y + math.floor(42 * density)

    -- 所有状态标签先定义（确保闭包可以捕获）
    local power_status = airui.label({
        parent = main_container,
        text = device_status.power and "开" or "关",
        x = right_x + math.floor(5 * density),
        y = ctrl_y + math.floor(62 * density),
        w = ctrl_w,
        h = math.floor(12 * density),
        font_size = math.floor(11 * density),
        color = device_status.power and 0x4ade80 or 0x6b7280,
        align = airui.TEXT_ALIGN_CENTER,
    })
    
    local cooling_status = airui.label({
        parent = main_container,
        text = device_status.cooling and "开" or "关",
        x = right_x + ctrl_w + math.floor(7 * density),
        y = ctrl_y + math.floor(62 * density),
        w = ctrl_w,
        h = math.floor(12 * density),
        font_size = math.floor(11 * density),
        color = device_status.cooling and 0x22d3ee or 0x6b7280,
        align = airui.TEXT_ALIGN_CENTER,
    })
    
    local defrost_status = airui.label({
        parent = main_container,
        text = device_status.defrost and "运行中" or "空闲",
        x = right_x + ctrl_w * 2 + math.floor(12 * density),
        y = ctrl_y + math.floor(62 * density),
        w = ctrl_w,
        h = math.floor(12 * density),
        font_size = math.floor(11 * density),
        color = device_status.defrost and 0xfbbf24 or 0x6b7280,
        align = airui.TEXT_ALIGN_CENTER,
    })
    
    local lighting_status = airui.label({
        parent = main_container,
        text = device_status.lighting and "开" or "关",
        x = right_x + math.floor(5 * density),
        y = ctrl_y + ctrl_h + math.floor(68 * density),
        w = ctrl_w,
        h = math.floor(12 * density),
        font_size = math.floor(11 * density),
        color = device_status.lighting and 0xfef3c7 or 0x6b7280,
        align = airui.TEXT_ALIGN_CENTER,
    })
    
    local alarm_mute_status = airui.label({
        parent = main_container,
        text = device_status.alarm_mute and "已静音" or "正常",
        x = right_x + ctrl_w + math.floor(7 * density),
        y = ctrl_y + ctrl_h + math.floor(68 * density),
        w = ctrl_w,
        h = math.floor(12 * density),
        font_size = math.floor(11 * density),
        color = device_status.alarm_mute and 0xa78bfa or 0x6b7280,
        align = airui.TEXT_ALIGN_CENTER,
    })
    
    local emergency_stop_status = airui.label({
        parent = main_container,
        text = device_status.emergency_stop and "已停机" or "运行中",
        x = right_x + ctrl_w * 2 + math.floor(12 * density),
        y = ctrl_y + ctrl_h + math.floor(68 * density),
        w = ctrl_w,
        h = math.floor(12 * density),
        font_size = math.floor(11 * density),
        color = device_status.emergency_stop and 0xf87171 or 0x6b7280,
        align = airui.TEXT_ALIGN_CENTER,
    })

    -- 电源开关
    local power_btn = airui.container({
        parent = main_container,
        x = right_x + math.floor(5 * density),
        y = ctrl_y,
        w = ctrl_w, h = ctrl_h,
        color = device_status.power and 0x22c55e or 0x1e2630,
        radius = math.floor(6 * density),
        on_click = function()
            airui.msgbox({
                parent = main_container,
                text = "确定要" .. (device_status.power and "关闭" or "开启") .. "电源开关吗？",
                buttons = {"确定", "取消"},
                on_action = function(self, label)
                    if label == "确定" then
                        device_status.power = not device_status.power
                        power_btn.color = device_status.power and 0x22c55e or 0x1e2630
                        power_status.text = device_status.power and "开" or "关"
                        power_status.color = device_status.power and 0x4ade80 or 0x6b7280
                    end
                    self:hide()
                end
            })
        end
    })
    airui.image({
        parent = main_container,
        x = right_x + math.floor(5 * density) + math.floor((ctrl_w - 30 * density) / 2),
        y = ctrl_y + math.floor(10 * density),
        w = math.floor(30 * density),
        h = math.floor(30 * density),
        src = "/luadb/dianyuan.png",
    })
    airui.label({
        parent = main_container,
        text = "电源开关",
        x = right_x + math.floor(5 * density),
        y = ctrl_y + math.floor(45 * density),
        w = ctrl_w,
        h = math.floor(18 * density),
        font_size = math.floor(12 * density),
        color = 0x9ca3af,
        align = airui.TEXT_ALIGN_CENTER,
    })

    -- 制冷模式
    local cooling_btn = airui.container({
        parent = main_container,
        x = right_x + ctrl_w + math.floor(7 * density),
        y = ctrl_y,
        w = ctrl_w, h = ctrl_h,
        color = device_status.cooling and 0x06b6d4 or 0x1e2630,
        radius = math.floor(6 * density),
        on_click = function()
            airui.msgbox({
                parent = main_container,
                text = "确定要" .. (device_status.cooling and "关闭" or "开启") .. "制冷模式吗？",
                buttons = {"确定", "取消"},
                on_action = function(self, label)
                    if label == "确定" then
                        device_status.cooling = not device_status.cooling
                        cooling_btn.color = device_status.cooling and 0x06b6d4 or 0x1e2630
                        cooling_status.text = device_status.cooling and "开" or "关"
                        cooling_status.color = device_status.cooling and 0x22d3ee or 0x6b7280
                    end
                    self:hide()
                end
            })
        end
    })
    airui.image({
        parent = main_container,
        x = right_x + ctrl_w + math.floor(7 * density) + math.floor((ctrl_w - 30 * density) / 2),
        y = ctrl_y + math.floor(10 * density),
        w = math.floor(30 * density),
        h = math.floor(30 * density),
        src = "/luadb/chart.png",
    })
    airui.label({
        parent = main_container,
        text = "制冷模式",
        x = right_x + ctrl_w + math.floor(7 * density),
        y = ctrl_y + math.floor(45 * density),
        w = ctrl_w,
        h = math.floor(18 * density),
        font_size = math.floor(12 * density),
        color = 0x9ca3af,
        align = airui.TEXT_ALIGN_CENTER,
    })

    -- 除霜
    local defrost_btn = airui.container({
        parent = main_container,
        x = right_x + ctrl_w * 2 + math.floor(12 * density),
        y = ctrl_y,
        w = ctrl_w, h = ctrl_h,
        color = device_status.defrost and 0xf59e0b or 0x1e2630,
        radius = math.floor(6 * density),
        on_click = function()
            airui.msgbox({
                parent = main_container,
                text = "确定要" .. (device_status.defrost and "停止" or "开始") .. "除霜吗？",
                buttons = {"确定", "取消"},
                on_action = function(self, label)
                    if label == "确定" then
                        device_status.defrost = not device_status.defrost
                        defrost_btn.color = device_status.defrost and 0xf59e0b or 0x1e2630
                        defrost_status.text = device_status.defrost and "运行中" or "空闲"
                        defrost_status.color = device_status.defrost and 0xfbbf24 or 0x6b7280
                    end
                    self:hide()
                end
            })
        end
    })
    airui.image({
        parent = main_container,
        x = right_x + ctrl_w * 2 + math.floor(12 * density) + math.floor((ctrl_w - 30 * density) / 2),
        y = ctrl_y + math.floor(10 * density),
        w = math.floor(30 * density),
        h = math.floor(30 * density),
        src = "/luadb/chushuang.png",
    })
    airui.label({
        parent = main_container,
        text = "除霜",
        x = right_x + ctrl_w * 2 + math.floor(12 * density),
        y = ctrl_y + math.floor(45 * density),
        w = ctrl_w,
        h = math.floor(18 * density),
        font_size = math.floor(12 * density),
        color = 0x9ca3af,
        align = airui.TEXT_ALIGN_CENTER,
    })

    -- 箱内照明
    local lighting_btn = airui.container({
        parent = main_container,
        x = right_x + math.floor(5 * density),
        y = ctrl_y + ctrl_h + math.floor(6 * density),
        w = ctrl_w, h = ctrl_h,
        color = device_status.lighting and 0xfbbf24 or 0x1e2630,
        radius = math.floor(6 * density),
        on_click = function()
            airui.msgbox({
                parent = main_container,
                text = "确定要" .. (device_status.lighting and "关闭" or "开启") .. "箱内照明吗？",
                buttons = {"确定", "取消"},
                on_action = function(self, label)
                    if label == "确定" then
                        device_status.lighting = not device_status.lighting
                        lighting_btn.color = device_status.lighting and 0xfbbf24 or 0x1e2630
                        lighting_status.text = device_status.lighting and "开" or "关"
                        lighting_status.color = device_status.lighting and 0xfef3c7 or 0x6b7280
                    end
                    self:hide()
                end
            })
        end
    })
    airui.image({
        parent = main_container,
        x = right_x + math.floor(5 * density) + math.floor((ctrl_w - 30 * density) / 2),
        y = ctrl_y + ctrl_h + math.floor(18 * density),
        w = math.floor(30 * density),
        h = math.floor(30 * density),
        src = "/luadb/zhaoming.png",
    })
    airui.label({
        parent = main_container,
        text = "箱内照明",
        x = right_x + math.floor(5 * density),
        y = ctrl_y + ctrl_h + math.floor(53 * density),
        w = ctrl_w,
        h = math.floor(18 * density),
        font_size = math.floor(12 * density),
        color = 0x9ca3af,
        align = airui.TEXT_ALIGN_CENTER,
    })

    -- 告警静音
    local alarm_mute_btn = airui.container({
        parent = main_container,
        x = right_x + ctrl_w + math.floor(7 * density),
        y = ctrl_y + ctrl_h + math.floor(6 * density),
        w = ctrl_w, h = ctrl_h,
        color = device_status.alarm_mute and 0x8b5cf6 or 0x1e2630,
        radius = math.floor(6 * density),
        on_click = function()
            airui.msgbox({
                parent = main_container,
                text = "确定要" .. (device_status.alarm_mute and "取消" or "启用") .. "告警静音吗？",
                buttons = {"确定", "取消"},
                on_action = function(self, label)
                    if label == "确定" then
                        device_status.alarm_mute = not device_status.alarm_mute
                        alarm_mute_btn.color = device_status.alarm_mute and 0x8b5cf6 or 0x1e2630
                        alarm_mute_status.text = device_status.alarm_mute and "已静音" or "正常"
                        alarm_mute_status.color = device_status.alarm_mute and 0xa78bfa or 0x6b7280
                    end
                    self:hide()
                end
            })
        end
    })
    airui.image({
        parent = main_container,
        x = right_x + ctrl_w + math.floor(7 * density) + math.floor((ctrl_w - 30 * density) / 2),
        y = ctrl_y + ctrl_h + math.floor(18 * density),
        w = math.floor(30 * density),
        h = math.floor(30 * density),
        src = "/luadb/alarm.png",
    })
    airui.label({
        parent = main_container,
        text = "告警静音",
        x = right_x + ctrl_w + math.floor(7 * density),
        y = ctrl_y + ctrl_h + math.floor(53 * density),
        w = ctrl_w,
        h = math.floor(18 * density),
        font_size = math.floor(12 * density),
        color = 0x9ca3af,
        align = airui.TEXT_ALIGN_CENTER,
    })

    -- 紧急停机
    local emergency_stop_btn = airui.container({
        parent = main_container,
        x = right_x + ctrl_w * 2 + math.floor(12 * density),
        y = ctrl_y + ctrl_h + math.floor(6 * density),
        w = ctrl_w, h = ctrl_h,
        color = device_status.emergency_stop and 0xef4444 or 0x1e2630,
        radius = math.floor(6 * density),
        on_click = function()
            local msg_text = device_status.emergency_stop 
                and "确定要恢复设备运行吗？" 
                or "确定要执行紧急停机吗？\n此操作将立即停止所有设备运行！"
            airui.msgbox({
                parent = main_container,
                text = msg_text,
                buttons = {"确定", "取消"},
                on_action = function(self, label)
                    if label == "确定" then
                        device_status.emergency_stop = not device_status.emergency_stop
                        emergency_stop_btn.color = device_status.emergency_stop and 0xef4444 or 0x1e2630
                        emergency_stop_status.text = device_status.emergency_stop and "已停机" or "运行中"
                        emergency_stop_status.color = device_status.emergency_stop and 0xf87171 or 0x6b7280
                    end
                    self:hide()
                end
            })
        end
    })
    airui.image({
        parent = main_container,
        x = right_x + ctrl_w * 2 + math.floor(12 * density) + math.floor((ctrl_w - 30 * density) / 2),
        y = ctrl_y + ctrl_h + math.floor(18 * density),
        w = math.floor(30 * density),
        h = math.floor(30 * density),
        src = "/luadb/tingji.png",
    })
    airui.label({
        parent = main_container,
        text = "紧急停机",
        x = right_x + ctrl_w * 2 + math.floor(12 * density),
        y = ctrl_y + ctrl_h + math.floor(53 * density),
        w = ctrl_w,
        h = math.floor(18 * density),
        font_size = math.floor(12 * density),
        color = device_status.emergency_stop and 0xef4444 or 0x9ca3af,
        align = airui.TEXT_ALIGN_CENTER,
    })
    -- 状态标签
    local emergency_stop_status = airui.label({
        parent = main_container,
        text = device_status.emergency_stop and "已停机" or "运行中",
        x = right_x + ctrl_w * 2 + math.floor(12 * density),
        y = ctrl_y + ctrl_h + math.floor(68 * density),
        w = ctrl_w,
        h = math.floor(12 * density),
        font_size = math.floor(11 * density),
        color = device_status.emergency_stop and 0xf87171 or 0x6b7280,
        align = airui.TEXT_ALIGN_CENTER,
    })

    -- 功能菜单
    local menu_y = ctrl_y + ctrl_h * 2 + math.floor(18 * density)
    airui.label({
        parent = main_container,
        text = "功能菜单",
        x = right_x,
        y = menu_y,
        w = section_w,
        h = math.floor(22 * density),
        font_size = math.floor(15 * density),
        color = 0xffffff,
        font_weight = 600,
    })

    -- 参数设置按钮
    airui.button({
        parent = main_container,
        x = right_x + math.floor(5 * density),
        y = menu_y + math.floor(25 * density),
        w = section_w - math.floor(10 * density),
        h = math.floor(42 * density),
        text = "参数设置",
        style = {
            bg_color = 0x1e2630,
            pressed_bg_color = 0x0d47a1,
            text_color = 0xffffff,
            radius = math.floor(4 * density),
            font_size = math.floor(14 * density),
            font_weight = 500,
            border_width = 0,
        },
        on_click = function()
            sys.publish("OPEN_CC_SETTINGS_WIN")
        end
    })

    -- 运行记录按钮
    airui.button({
        parent = main_container,
        x = right_x + math.floor(5 * density),
        y = menu_y + math.floor(75 * density),
        w = section_w - math.floor(10 * density),
        h = math.floor(42 * density),
        text = "运行记录",
        style = {
            bg_color = 0x1e2630,
            pressed_bg_color = 0x0d47a1,
            text_color = 0xffffff,
            radius = math.floor(4 * density),
            font_size = math.floor(14 * density),
            font_weight = 500,
            border_width = 0,
        },
        on_click = function()
            sys.publish("OPEN_CC_RECORD_WIN")
        end
    })

    -- 二维码区域（使用airui.qrcode）
    local qr_y = menu_y + math.floor(130 * density)
    airui.label({
        parent = main_container,
        text = "扫码关注",
        x = right_x,
        y = qr_y,
        w = section_w,
        h = math.floor(18 * density),
        font_size = math.floor(12 * density),
        color = 0x888888,
        align = airui.TEXT_ALIGN_CENTER,
    })

    -- 使用airui.qrcode生成二维码
    airui.qrcode({
        parent = main_container,
        x = right_x + math.floor((section_w - math.floor(80 * density)) / 2),
        y = qr_y + math.floor(25 * density),
        size = math.floor(80 * density),
        data = "https://docs.openluat.com/",
    })

    -- 底部状态栏
    local footer_h = math.floor(28 * density)
    local footer_y = screen_h - footer_h - math.floor(5 * density)
    airui.container({
        parent = main_container,
        x = math.floor(5 * density), y = footer_y,
        w = screen_w - math.floor(10 * density), h = footer_h,
        color = 0x141e30,
        radius = math.floor(6 * density),
    })

    airui.label({
        parent = main_container,
        text = "系统运行正常 | 数据更新: 刚刚 | 设备状态: 在线",
        x = math.floor(15 * density),
        y = footer_y + math.floor((footer_h - 14 * density) / 2),
        w = math.floor(300 * density),
        h = math.floor(14 * density),
        font_size = math.floor(12 * density),
        color = 0x888888,
    })

    airui.label({
        parent = main_container,
        text = "智慧冷链监控系统 v1.0.0",
        x = screen_w - math.floor(180 * density),
        y = footer_y + math.floor((footer_h - 14 * density) / 2),
        w = math.floor(170 * density),
        h = math.floor(14 * density),
        font_size = math.floor(12 * density),
        color = 0x888888,
        align = airui.TEXT_ALIGN_RIGHT,
    })

    -- 更新时间（每分钟更新）
    local function update_time()
        local now = os.date("%H:%M")
        time_label:set_text(now)
    end
    timer_id = sys.timerLoopStart(update_time, 60000)
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
    if timer_id then
        sys.timerStop(timer_id)
        timer_id = nil
    end
    win_id = nil
end

local function open()
    if not exwin.is_active(win_id) then
        win_id = exwin.open({
            on_create = on_create,
            on_destroy = on_destroy,
        })
        log.info("cc_main", "主窗口打开成功", win_id)
    end
end

sys.subscribe("OPEN_CC_MAIN_WIN", open)
