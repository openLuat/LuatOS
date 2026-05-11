--[[
@module  ecboxstatus
@summary 快递柜箱子状态窗口模块
@version 1.9 (正方形格子 + 字体居中)
@date    2026.05.07
]]

local win_id = nil
local main_container
local screen_w, screen_h = 480, 800
local margin = 15
local title_h = 60

local function update_screen_size()
    local rotation = airui.get_rotation()
    local phys_w, phys_h = lcd.getSize()
    if rotation == 0 or rotation == 180 then
        screen_w, screen_h = phys_w, phys_h
    else
        screen_w, screen_h = phys_h, phys_w
    end
    margin = math.floor(screen_w * 0.03)
    title_h = 60
end

local function create_ui()
    update_screen_size()
    main_container = airui.container({
        parent = airui.screen,
        x = 0, y = 0,
        w = screen_w, h = screen_h,
        color = 0xF5F5F5
    })

    -- 标题栏
    local title_bar = airui.container({
        parent = main_container,
        x = 0, y = 0,
        w = screen_w, h = title_h,
        color = 0x2C3E50
    })
    
    -- 返回按钮
    airui.button({
        parent = title_bar,
        x = 10, y = 10,
        w = 70, h = 40,
        text = "返回",
        style = {
            bg_color = 0x6C757D,
            text_color = 0xFFFFFF,
            radius = 5,
            font_size = 14,
            font_weight = 600,
        },
        on_click = function() 
            exwin.close(win_id)
        end
    })
    
    -- 标题
    airui.label({
        parent = title_bar,
        x = 0, y = 14,
        w = screen_w, h = 40,
        text = "箱子状态",
        color = 0xFFFFFF,
        font_size = 24,
        font_weight = 600,
        align = airui.TEXT_ALIGN_CENTER
    })

    -- 内容区域
    local content = airui.container({
        parent = main_container,
        x = 0, y = title_h,
        w = screen_w, h = screen_h - title_h,
        color = 0xF5F5F5,
        scroll = true
    })
    
    -- 计算格子大小（长方形，保持紧凑布局）
    local box_w = math.floor((screen_w - 2 * margin - 60) / 6)  -- 一排6个
    local box_h = box_w * 0.7  -- 保持原来的紧凑高度
    local gap = 8

    -- 小格口标题
    airui.label({
        parent = content,
        x = margin, y = 20,
        w = screen_w - 2 * margin, h = 25,
        text = "小格口（1-10号）",
        color = 0x2C3E50,
        font_size = 14,
        font_weight = 600,
        align = airui.TEXT_ALIGN_LEFT
    })

    -- 小格口（1-10）
    local small_used = {6}
    for i = 1, 10 do
        local row = math.floor((i - 1) / 6)
        local col = (i - 1) % 6
        local is_used = false
        for _, v in ipairs(small_used) do
            if i == v then is_used = true end
        end
        
        local box_x = margin + gap + col * (box_w + gap)
        local box_y = 50 + row * (box_h + gap)
        
        -- 箱子背景
        airui.container({
            parent = content,
            x = box_x,
            y = box_y,
            w = box_w, h = box_h,
            color = is_used and 0xDC3545 or 0x28A745,
            radius = 5,
        })
        
        -- 箱子编号（垂直居中）
        airui.label({
            parent = content,
            x = box_x,
            y = box_y + 5,
            w = box_w, h = 20,
            text = tostring(i),
            color = 0xFFFFFF,
            font_size = 20,
            font_weight = 600,
            align = airui.TEXT_ALIGN_CENTER
        })
        
        -- 箱子类型（垂直居中）
        airui.label({
            parent = content,
            x = box_x,
            y = box_y + 28,
            w = box_w, h = 14,
            text = "小",
            color = 0xFFFFFF,
            font_size = 12,
            align = airui.TEXT_ALIGN_CENTER
        })
    end

    -- 中格口标题（小格口改为2行后，调整起始位置）
    local medium_start_y = 50 + 2 * (box_h + gap) + 15
    airui.label({
        parent = content,
        x = margin, y = medium_start_y,
        w = screen_w - 2 * margin, h = 25,
        text = "中格口（11-25号）",
        color = 0x2C3E50,
        font_size = 14,
        font_weight = 600,
        align = airui.TEXT_ALIGN_LEFT
    })

    -- 中格口（11-25）
    local medium_used = {11, 12, 13, 16, 21, 25}
    for i = 1, 15 do
        local box_num = i + 10
        local row = math.floor((i - 1) / 6)
        local col = (i - 1) % 6
        local is_used = false
        for _, v in ipairs(medium_used) do
            if box_num == v then is_used = true end
        end
        
        local box_x = margin + gap + col * (box_w + gap)
        local box_y = medium_start_y + 30 + row * (box_h + gap)
        
        airui.container({
            parent = content,
            x = box_x,
            y = box_y,
            w = box_w, h = box_h,
            color = is_used and 0xDC3545 or 0x28A745,
            radius = 5,
        })
        
        airui.label({
            parent = content,
            x = box_x,
            y = box_y + 5,
            w = box_w, h = 20,
            text = tostring(box_num),
            color = 0xFFFFFF,
            font_size = 20,
            font_weight = 600,
            align = airui.TEXT_ALIGN_CENTER
        })
        
        airui.label({
            parent = content,
            x = box_x,
            y = box_y + 28,
            w = box_w, h = 14,
            text = "中",
            color = 0xFFFFFF,
            font_size = 12,
            align = airui.TEXT_ALIGN_CENTER
        })
    end

    -- 大格口标题（中格口改为3行后，调整起始位置）
    local large_start_y = medium_start_y + 30 + 3 * (box_h + gap) + 15
    airui.label({
        parent = content,
        x = margin, y = large_start_y,
        w = screen_w - 2 * margin, h = 25,
        text = "大格口（26-30号）",
        color = 0x2C3E50,
        font_size = 14,
        font_weight = 600,
        align = airui.TEXT_ALIGN_LEFT
    })

    -- 大格口（26-30）
    local large_used = {26, 30}
    for i = 1, 5 do
        local box_num = i + 25
        local col = i - 1
        local is_used = false
        for _, v in ipairs(large_used) do
            if box_num == v then is_used = true end
        end
        
        local box_x = margin + gap + col * (box_w + gap)
        local box_y = large_start_y + 30
        
        airui.container({
            parent = content,
            x = box_x,
            y = box_y,
            w = box_w, h = box_h,
            color = is_used and 0xDC3545 or 0x28A745,
            radius = 5,
        })
        
        airui.label({
            parent = content,
            x = box_x,
            y = box_y + 5,
            w = box_w, h = 20,
            text = tostring(box_num),
            color = 0xFFFFFF,
            font_size = 20,
            font_weight = 600,
            align = airui.TEXT_ALIGN_CENTER
        })
        
        airui.label({
            parent = content,
            x = box_x,
            y = box_y + 28,
            w = box_w, h = 14,
            text = "大",
            color = 0xFFFFFF,
            font_size = 12,
            align = airui.TEXT_ALIGN_CENTER
        })
    end
end

local function on_create()
    create_ui()
end

local function on_destroy()
    if main_container then
        main_container:destroy()
        main_container = nil
    end
    win_id = nil
end

local function open_handler()
    win_id = exwin.open({
        on_create = on_create,
        on_destroy = on_destroy,
    })
end

sys.subscribe("OPEN_EXPRESS_BOXSTATUS_WIN", open_handler)