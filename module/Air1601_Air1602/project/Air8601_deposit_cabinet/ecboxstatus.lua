--[[
@module  ecboxstatus
@summary 寄存柜箱子状态页面
@version 10.0 (大统计区域 + 迷你箱子布局)
@date    2026.05.13
@author  王城钧
@usage
寄存柜箱子状态页面：显示所有箱子的占用/空闲状态。订阅 OPEN_EXPRESS_BOX_STATUS_WIN 打开
]]

local win_id = nil
local main_container
local screen_w, screen_h = 1024, 600
local margin = 15
local title_h = 55

local function update_screen_size()
    local rotation = airui.get_rotation()
    local phys_w, phys_h = lcd.getSize()
    if rotation == 0 or rotation == 180 then
        screen_w, screen_h = phys_w, phys_h
    else
        screen_w, screen_h = phys_h, phys_w
    end
    margin = 15
    title_h = 55
end

local function create_ui()
    update_screen_size()
    
    main_container = airui.container({
        parent = airui.screen,
        x = 0, y = 0,
        w = screen_w, h = screen_h,
        color = 0xF5F5F5
    })

    -- 标题栏（蓝色背景）
    local title_bar = airui.container({
        parent = main_container,
        x = 0, y = 0,
        w = screen_w, h = title_h,
        color = 0x4A90E2
    })
    
    -- 返回按钮
    airui.button({
        parent = title_bar,
        x = 15, y = math.floor((title_h - 35) / 2),
        w = 70, h = 35,
        text = "返回",
        style = {
            bg_color = 0xFFFFFF,
            pressed_bg_color = 0xEFEFEF,
            text_color = 0x4A90E2,
            radius = 7,
            font_size = 15,
            font_weight = 500,
            border_width = 0,
        },
        on_click = function() 
            exwin.close(win_id)
        end
    })

    -- 标题
    airui.label({
        parent = title_bar,
        x = 0, y = 12,
        w = screen_w, h = 38,
        text = "箱子状态",
        color = 0xFFFFFF,
        font_size = 24,
        font_weight = 600,
        align = airui.TEXT_ALIGN_CENTER
    })

    -- 大统计区域
    local stats_y = title_h + 15
    local stats_h = 75
    local stats_w = math.floor((screen_w - 2 * margin - 30) / 3)
    
    -- 总箱子数
    airui.container({
        parent = main_container,
        x = margin, y = stats_y,
        w = stats_w, h = stats_h,
        color = 0xFFFFFF,
        radius = 8,
    })
    airui.label({
        parent = main_container,
        text = "总箱子",
        x = margin + 15, y = stats_y + 12,
        w = stats_w - 30, h = 18,
        font_size = 14,
        color = 0x666666,
        align = airui.TEXT_ALIGN_CENTER,
    })
    airui.label({
        parent = main_container,
        text = "30",
        x = margin + 15, y = stats_y + 32,
        w = stats_w - 30, h = 30,
        font_size = 32,
        color = 0x2C3E50,
        align = airui.TEXT_ALIGN_CENTER,
        font_weight = 700,
    })
    
    -- 已使用
    local used_x = margin + stats_w + 15
    airui.container({
        parent = main_container,
        x = used_x, y = stats_y,
        w = stats_w, h = stats_h,
        color = 0xFFFFFF,
        radius = 8,
    })
    airui.label({
        parent = main_container,
        text = "已使用",
        x = used_x + 15, y = stats_y + 12,
        w = stats_w - 30, h = 18,
        font_size = 14,
        color = 0x666666,
        align = airui.TEXT_ALIGN_CENTER,
    })
    airui.label({
        parent = main_container,
        text = "12",
        x = used_x + 15, y = stats_y + 32,
        w = stats_w - 30, h = 30,
        font_size = 32,
        color = 0xDC3545,
        align = airui.TEXT_ALIGN_CENTER,
        font_weight = 700,
    })
    
    -- 可用
    local avail_x = used_x + stats_w + 15
    airui.container({
        parent = main_container,
        x = avail_x, y = stats_y,
        w = stats_w, h = stats_h,
        color = 0xFFFFFF,
        radius = 8,
    })
    airui.label({
        parent = main_container,
        text = "可用",
        x = avail_x + 15, y = stats_y + 12,
        w = stats_w - 30, h = 18,
        font_size = 14,
        color = 0x666666,
        align = airui.TEXT_ALIGN_CENTER,
    })
    airui.label({
        parent = main_container,
        text = "18",
        x = avail_x + 15, y = stats_y + 32,
        w = stats_w - 30, h = 30,
        font_size = 32,
        color = 0x28A745,
        align = airui.TEXT_ALIGN_CENTER,
        font_weight = 700,
    })

    -- 迷你正方形箱子（增大20%）
    local gap = 8
    local base_w = math.floor((screen_w - 2 * margin - 14 * gap) / 15)
    local box_w = math.floor(base_w * 1.2)  -- 增大20%
    local box_h = box_w + 10  -- 稍微增高一点，确保数字能完整显示

    -- 大箱子区域（1-5）
    local large_y = stats_y + stats_h + 18
    airui.label({
        parent = main_container,
        x = margin, y = large_y,
        w = screen_w - 2 * margin, h = 22,
        text = "大箱子（1-5号）",
        color = 0x2C3E50,
        font_size = 15,
        font_weight = 600,
        align = airui.TEXT_ALIGN_LEFT
    })
    
    local large_used = {1, 3}
    local large_box_y = large_y + 22
    for i = 1, 5 do
        local col = i - 1
        local is_used = false
        for _, v in ipairs(large_used) do
            if i == v then is_used = true end
        end
        
        local box_x = margin + col * (box_w + gap)
        
        airui.container({
            parent = main_container,
            x = box_x,
            y = large_box_y,
            w = box_w, h = box_h,
            color = is_used and 0xDC3545 or 0x28A745,
            radius = 2,
        })
        
        local font_size = math.max(10, math.floor(box_w * 0.4))
        local label_h = math.max(14, math.floor(box_h * 0.5))
        airui.label({
            parent = main_container,
            x = box_x,
            y = large_box_y + math.floor((box_h - label_h) / 2),
            w = box_w, h = label_h,
            text = tostring(i),
            color = 0xFFFFFF,
            font_size = font_size,
            font_weight = 600,
            align = airui.TEXT_ALIGN_CENTER
        })
    end

    -- 中箱子区域（6-20）
    local medium_y = large_box_y + box_h + 15
    airui.label({
        parent = main_container,
        x = margin, y = medium_y,
        w = screen_w - 2 * margin, h = 22,
        text = "中箱子（6-20号）",
        color = 0x2C3E50,
        font_size = 15,
        font_weight = 600,
        align = airui.TEXT_ALIGN_LEFT
    })
    
    local medium_used = {6, 7, 10, 15, 18}
    local medium_box_y = medium_y + 22
    for i = 1, 15 do
        local box_num = i + 5
        local row = math.floor((i - 1) / 10)
        local col = (i - 1) % 10
        local is_used = false
        for _, v in ipairs(medium_used) do
            if box_num == v then is_used = true end
        end
        
        local box_x = margin + col * (box_w + gap)
        local box_y = medium_box_y + row * (box_h + gap)
        
        airui.container({
            parent = main_container,
            x = box_x,
            y = box_y,
            w = box_w, h = box_h,
            color = is_used and 0xDC3545 or 0x28A745,
            radius = 2,
        })
        
        local font_size = math.max(10, math.floor(box_w * 0.4))
        local label_h = math.max(14, math.floor(box_h * 0.5))
        airui.label({
            parent = main_container,
            x = box_x,
            y = box_y + math.floor((box_h - label_h) / 2),
            w = box_w, h = label_h,
            text = tostring(box_num),
            color = 0xFFFFFF,
            font_size = font_size,
            font_weight = 600,
            align = airui.TEXT_ALIGN_CENTER
        })
    end

    -- 小箱子区域（21-30）
    local small_y = medium_box_y + 2 * (box_h + gap) + 15
    airui.label({
        parent = main_container,
        x = margin, y = small_y,
        w = screen_w - 2 * margin, h = 22,
        text = "小箱子（21-30号）",
        color = 0x2C3E50,
        font_size = 15,
        font_weight = 600,
        align = airui.TEXT_ALIGN_LEFT
    })
    
    local small_used = {22, 25, 28, 30}
    local small_box_y = small_y + 22
    for i = 1, 10 do
        local box_num = i + 20
        local col = i - 1
        local is_used = false
        for _, v in ipairs(small_used) do
            if box_num == v then is_used = true end
        end
        
        local box_x = margin + col * (box_w + gap)
        
        airui.container({
            parent = main_container,
            x = box_x,
            y = small_box_y,
            w = box_w, h = box_h,
            color = is_used and 0xDC3545 or 0x28A745,
            radius = 2,
        })
        
        local font_size = math.max(10, math.floor(box_w * 0.4))
        local label_h = math.max(14, math.floor(box_h * 0.5))
        airui.label({
            parent = main_container,
            x = box_x,
            y = small_box_y + math.floor((box_h - label_h) / 2),
            w = box_w, h = label_h,
            text = tostring(box_num),
            color = 0xFFFFFF,
            font_size = font_size,
            font_weight = 600,
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
