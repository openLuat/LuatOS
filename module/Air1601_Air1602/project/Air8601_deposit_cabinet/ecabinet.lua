--[[
@module  ecabinet
@summary 智能寄存柜主窗口模块
@version 3.5 (蓝白风格，使用之前的布局比例)
@date    2026.05.11
@author  王城钧
@usage
智能寄存柜主窗口：顶部导航栏 + 存件/取件/刷脸/帮助/管理入口按钮。订阅 OPEN_EXPRESS_CABINET_WIN 打开主窗口
]]

local win_id = nil
local main_container = nil
local timer_id = nil
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
        color = 0xF8F9FA,
        parent = airui.screen
    })

    -- 顶部导航栏
    local header_h = math.floor(60 * density)
    airui.container({
        parent = main_container,
        x = 0, y = 0,
        w = screen_w, h = header_h,
        color = 0x4A90E2,
        radius = 0,
    })
    
    -- 标题居中
    airui.label({
        parent = main_container,
        text = "智能寄存柜系统",
        x = 0,
        y = math.floor((header_h - 28 * density) / 2),
        w = screen_w,
        h = math.floor(28 * density),
        font_size = math.floor(24 * density),
        color = 0xFFFFFF,
        align = airui.TEXT_ALIGN_CENTER,
        font_weight = 600,
    })
    
    -- 时间显示
    local time_display = airui.label({
        parent = main_container,
        text = "2023年1月1日 12:00:00",
        x = screen_w - math.floor(180 * density),
        y = math.floor((header_h - 18 * density) / 2),
        w = math.floor(170 * density),
        h = math.floor(18 * density),
        font_size = math.floor(13 * density),
        color = 0xFFFFFF,
        opacity = 0.8,
        align = airui.TEXT_ALIGN_RIGHT,
    })

    -- 更新时间显示
    local function update_time()
        local now = os.date("%Y年%m月%d日 %H:%M")
        time_display:set_text(now)
    end
    update_time()
    timer_id = sys.timerLoopStart(update_time, 1000)

    -- 主内容区域尺寸计算
    local left_w = math.floor(screen_w * 0.4)
    local right_w = screen_w - left_w - math.floor(40 * density)
    
    -- 左侧区域 - 系统信息和柜子状态
    local left_h = screen_h - header_h - math.floor(40 * density)
    airui.container({
        parent = main_container,
        x = math.floor(20 * density),
        y = header_h + math.floor(20 * density),
        w = left_w,
        h = left_h,
        color = 0xFFFFFF,
        radius = math.floor(10 * density),
        shadow = {
            offset_x = math.floor(2 * density),
            offset_y = math.floor(2 * density),
            blur = math.floor(5 * density),
            color = 0x000000,
            opacity = 0.06,
        }
    })

    -- 系统信息区域
    airui.image({
        parent = main_container,
        x = math.floor(20 * density) + math.floor((left_w - 60 * density) / 2),
        y = header_h + math.floor(20 * density) + math.floor(30 * density),
        w = math.floor(60 * density),
        h = math.floor(60 * density),
        src = "/luadb/jicungui.png",
        radius = math.floor(30 * density),
    })
    
    airui.label({
        parent = main_container,
        text = "智能寄存柜",
        x = math.floor(20 * density),
        y = header_h + math.floor(20 * density) + math.floor(100 * density),
        w = left_w,
        h = math.floor(30 * density),
        font_size = math.floor(22 * density),
        color = 0x4A90E2,
        align = airui.TEXT_ALIGN_CENTER,
        font_weight = 600,
    })
    
    -- 安全便捷提示
    airui.container({
        parent = main_container,
        x = math.floor(20 * density) + math.floor(10 * density),
        y = header_h + math.floor(20 * density) + math.floor(140 * density),
        w = left_w - math.floor(20 * density),
        h = math.floor(120 * density),
        color = 0xF8F9FA,
        radius = math.floor(8 * density),
        border_left = {
            width = math.floor(3 * density),
            color = 0x667EEA
        }
    })
    
    airui.label({
        parent = main_container,
        text = "安全便捷",
        x = math.floor(20 * density),
        y = header_h + math.floor(20 * density) + math.floor(160 * density),
        w = left_w,
        h = math.floor(25 * density),
        font_size = math.floor(18 * density),
        color = 0x4A90E2,
        align = airui.TEXT_ALIGN_CENTER,
        font_weight = 600,
    })
    
    airui.label({
        parent = main_container,
        text = "随存随取，安心寄存",
        x = math.floor(20 * density),
        y = header_h + math.floor(20 * density) + math.floor(190 * density),
        w = left_w,
        h = math.floor(20 * density),
        font_size = math.floor(12 * density),
        color = 0x999999,
        align = airui.TEXT_ALIGN_CENTER,
    })
    
    airui.image({
        parent = main_container,
        x = math.floor(20 * density) + math.floor((left_w - 50 * density) / 2),
        y = header_h + math.floor(20 * density) + math.floor(215 * density),
        w = math.floor(50 * density),
        h = math.floor(50 * density),
        src = "/luadb/cunjian.png",
    })

    -- 柜子状态
    local status_y = header_h + math.floor(20 * density) + math.floor(280 * density)
    airui.container({
        parent = main_container,
        x = math.floor(20 * density) + math.floor(10 * density),
        y = status_y,
        w = left_w - math.floor(20 * density),
        h = math.floor(80 * density),
        color = 0xF8F9FA,
        radius = math.floor(8 * density),
        border_left = {
            width = math.floor(3 * density),
            color = 0x667EEA
        }
    })
    
    airui.label({
        parent = main_container,
        text = "18",
        x = math.floor(20 * density),
        y = status_y + math.floor(10 * density),
        w = left_w,
        h = math.floor(30 * density),
        font_size = math.floor(24 * density),
        color = 0x4A90E2,
        align = airui.TEXT_ALIGN_CENTER,
        font_weight = 600,
    })
    
    airui.label({
        parent = main_container,
        text = "可用格数",
        x = math.floor(20 * density),
        y = status_y + math.floor(45 * density),
        w = left_w,
        h = math.floor(20 * density),
        font_size = math.floor(12 * density),
        color = 0x999999,
        align = airui.TEXT_ALIGN_CENTER,
    })

    -- 右侧区域 - 功能按钮
    local right_x = left_w + math.floor(30 * density)
    local right_y = header_h + math.floor(20 * density)
    local button_w = math.floor((right_w - math.floor(20 * density)) / 2) -- 半宽按钮宽度
    
    -- 取件按钮（取件码方式）
    airui.container({
        parent = main_container,
        x = right_x,
        y = right_y,
        w = button_w,
        h = math.floor(170 * density),
        color = 0xFFFFFF,
        radius = math.floor(15 * density),
        shadow = {
            offset_x = math.floor(2 * density),
            offset_y = math.floor(2 * density),
            blur = math.floor(5 * density),
            color = 0x000000,
            opacity = 0.06,
        },
        on_click = function()
            log.info("取件按键触发")
            sys.publish("OPEN_EXPRESS_RECEIVE_WIN")
        end
    })
    
    airui.image({
        parent = main_container,
        x = right_x + math.floor((button_w - math.floor(80 * density)) / 2),
        y = right_y + math.floor(40 * density),
        w = math.floor(80 * density),
        h = math.floor(80 * density),
        src = "/luadb/qujian.png",
    })
    
    airui.label({
        parent = main_container,
        text = "取件",
        x = right_x,
        y = right_y + math.floor(130 * density),
        w = button_w,
        h = math.floor(30 * density),
        font_size = math.floor(20 * density),
        color = 0x4A90E2,
        align = airui.TEXT_ALIGN_CENTER,
        font_weight = 600,
    })
    
    -- 刷脸取件按钮（人脸验证方式）
    airui.container({
        parent = main_container,
        x = right_x + button_w + math.floor(20 * density),
        y = right_y,
        w = button_w,
        h = math.floor(170 * density),
        color = 0xFFFFFF,
        radius = math.floor(15 * density),
        shadow = {
            offset_x = math.floor(2 * density),
            offset_y = math.floor(2 * density),
            blur = math.floor(5 * density),
            color = 0x000000,
            opacity = 0.06,
        },
        on_click = function()
            log.info("刷脸取件按键触发")
            sys.publish("OPEN_FACE_RECEIVE_WIN")
        end
    })
    
    airui.image({
        parent = main_container,
        x = right_x + button_w + math.floor(20 * density) + math.floor((button_w - math.floor(80 * density)) / 2),
        y = right_y + math.floor(40 * density),
        w = math.floor(80 * density),
        h = math.floor(80 * density),
        src = "/luadb/qujian.png",
    })
    
    airui.label({
        parent = main_container,
        text = "刷脸取件",
        x = right_x + button_w + math.floor(20 * density),
        y = right_y + math.floor(130 * density),
        w = button_w,
        h = math.floor(30 * density),
        font_size = math.floor(20 * density),
        color = 0x667EEA,
        align = airui.TEXT_ALIGN_CENTER,
        font_weight = 600,
    })
    
    -- 存件按钮（取件码方式）
    local deposit_y = right_y + math.floor(180 * density)
    airui.container({
        parent = main_container,
        x = right_x,
        y = deposit_y,
        w = button_w,
        h = math.floor(170 * density),
        color = 0xFFFFFF,
        radius = math.floor(15 * density),
        shadow = {
            offset_x = math.floor(2 * density),
            offset_y = math.floor(2 * density),
            blur = math.floor(5 * density),
            color = 0x000000,
            opacity = 0.06,
        },
        on_click = function()
            log.info("存件按键触发")
            sys.publish("OPEN_EXPRESS_SEND_WIN")
        end
    })
    
    airui.image({
        parent = main_container,
        x = right_x + math.floor((button_w - math.floor(80 * density)) / 2),
        y = deposit_y + math.floor(40 * density),
        w = math.floor(80 * density),
        h = math.floor(80 * density),
        src = "/luadb/cunjian.png",
    })
    
    airui.label({
        parent = main_container,
        text = "存件",
        x = right_x,
        y = deposit_y + math.floor(130 * density),
        w = button_w,
        h = math.floor(30 * density),
        font_size = math.floor(20 * density),
        color = 0x4A90E2,
        align = airui.TEXT_ALIGN_CENTER,
        font_weight = 600,
    })
    
    -- 刷脸存件按钮（人脸注册方式）
    airui.container({
        parent = main_container,
        x = right_x + button_w + math.floor(20 * density),
        y = deposit_y,
        w = button_w,
        h = math.floor(170 * density),
        color = 0xFFFFFF,
        radius = math.floor(15 * density),
        shadow = {
            offset_x = math.floor(2 * density),
            offset_y = math.floor(2 * density),
            blur = math.floor(5 * density),
            color = 0x000000,
            opacity = 0.06,
        },
        on_click = function()
            log.info("刷脸存件按键触发")
            sys.publish("OPEN_FACE_DEPOSIT_WIN")
        end
    })
    
    airui.image({
        parent = main_container,
        x = right_x + button_w + math.floor(20 * density) + math.floor((button_w - math.floor(80 * density)) / 2),
        y = deposit_y + math.floor(40 * density),
        w = math.floor(80 * density),
        h = math.floor(80 * density),
        src = "/luadb/cunjian.png",
    })
    
    airui.label({
        parent = main_container,
        text = "刷脸存件",
        x = right_x + button_w + math.floor(20 * density),
        y = deposit_y + math.floor(130 * density),
        w = button_w,
        h = math.floor(30 * density),
        font_size = math.floor(20 * density),
        color = 0x667EEA,
        align = airui.TEXT_ALIGN_CENTER,
        font_weight = 600,
    })
    
    -- 底部区域 - 其他功能按钮
    local bottom_y = deposit_y + math.floor(180 * density)
    
    -- 帮助按钮
    airui.container({
        parent = main_container,
        x = right_x,
        y = bottom_y,
        w = button_w,
        h = math.floor(100 * density),
        color = 0xFFFFFF,
        radius = math.floor(10 * density),
        shadow = {
            offset_x = math.floor(2 * density),
            offset_y = math.floor(2 * density),
            blur = math.floor(5 * density),
            color = 0x000000,
            opacity = 0.06,
        },
        on_click = function()
            log.info("帮助按键触发")
            sys.publish("OPEN_EXPRESS_HELP_WIN")
        end
    })
    
    airui.image({
        parent = main_container,
        x = right_x + math.floor((button_w - math.floor(50 * density)) / 2),
        y = bottom_y + math.floor(20 * density),
        w = math.floor(50 * density),
        h = math.floor(50 * density),
        src = "/luadb/bangzhu.png",
    })
    
    airui.label({
        parent = main_container,
        text = "帮助",
        x = right_x,
        y = bottom_y + math.floor(75 * density),
        w = button_w,
        h = math.floor(20 * density),
        font_size = math.floor(14 * density),
        color = 0x4A90E2,
        align = airui.TEXT_ALIGN_CENTER,
        font_weight = 500,
    })
    
    -- 管理按钮
    airui.container({
        parent = main_container,
        x = right_x + button_w + math.floor(20 * density),
        y = bottom_y,
        w = button_w,
        h = math.floor(100 * density),
        color = 0xFFFFFF,
        radius = math.floor(10 * density),
        shadow = {
            offset_x = math.floor(2 * density),
            offset_y = math.floor(2 * density),
            blur = math.floor(5 * density),
            color = 0x000000,
            opacity = 0.06,
        },
        on_click = function()
            log.info("管理按键触发")
            sys.publish("OPEN_COURIER_MANAGEMENT_WIN")
        end
    })
    
    airui.image({
        parent = main_container,
        x = right_x + button_w + math.floor(20 * density) + math.floor((button_w - math.floor(50 * density)) / 2),
        y = bottom_y + math.floor(20 * density),
        w = math.floor(50 * density),
        h = math.floor(50 * density),
        src = "/luadb/guanli.png",
    })
    
    airui.label({
        parent = main_container,
        text = "管理",
        x = right_x + button_w + math.floor(20 * density),
        y = bottom_y + math.floor(75 * density),
        w = button_w,
        h = math.floor(20 * density),
        font_size = math.floor(14 * density),
        color = 0x4A90E2,
        align = airui.TEXT_ALIGN_CENTER,
        font_weight = 500,
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
        log.info("ecabinet", "主窗口打开成功", win_id)
    else
        log.warn("ecabinet", "主窗口已打开", win_id)
    end
end

sys.subscribe("OPEN_EXPRESS_CABINET_WIN", open)
