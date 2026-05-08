--[[
@module  welcome_win
@summary 开机欢迎页面模块
@version 1.1
@date    2026.04.16
@author  江访
]]

local win_id = nil
local main_container
local search_box
local search_icon
local mouse_img
local move_timer

local MOUSE_SPEED = 15
local ZOOM_STEP1 = 450
local ZOOM_NORMAL = 256
local MOUSE_W = 36
local MOUSE_H = 36

local COLOR_PRIMARY        = 0x007AFF
local COLOR_BG             = 0xF5F5F5
local COLOR_CARD           = 0xFFFFFF
local COLOR_TEXT           = 0x333333
local COLOR_TEXT_SECONDARY = 0x757575
local COLOR_WHITE          = 0xFFFFFF

local product_name = "合宙引擎主机"

local function resolution_adapt()
    local ds = _G.density_scale or 1.0
    MOUSE_SPEED = math.floor(15 * ds)
    ZOOM_STEP1 = math.floor(256 + 128 * ds)
    local mouse_size = math.floor(math.max(28, math.min(52, screen_h * 0.055)) * ds)
    MOUSE_W = mouse_size
    MOUSE_H = mouse_size

    local suffix = _G.model_str:gsub("^Air", "")
    if suffix ~= "" then
        product_name = "合宙引擎主机" .. suffix
    end
end


-- 鼠标移动完成后的动作：放大搜索图标，关闭窗口，发布事件
local function on_mouse_arrived()   
    exwin.close(win_id)                     -- 关闭当前窗口
    sys.publish("OPEN_IDLE_WIN")            -- 打开 IDLE 窗口
end

-- 鼠标移动一步
local function move_mouse_step(target_x, target_y)
    if not mouse_img then return end
    local cur_x, cur_y = mouse_img:get_pos()
    cur_x = math.floor(cur_x)
    cur_y = math.floor(cur_y)
    local dx = target_x - cur_x
    local dy = target_y - cur_y
    local dist = math.sqrt(dx*dx + dy*dy)

    if dist <= MOUSE_SPEED then
        -- 到达目标位置
        mouse_img:set_pos(target_x, target_y)
        if move_timer then
            sys.timerStop(move_timer)
            move_timer = nil
        end
        search_icon:set_zoom(ZOOM_STEP1)        -- 放大搜索图标
        mouse_img:destroy()
        sys.timerStart(on_mouse_arrived, 2500)
    else
        -- 继续移动
        local step_x = (dx / dist) * MOUSE_SPEED
        local step_y = (dy / dist) * MOUSE_SPEED
        local new_x = math.floor(cur_x + step_x + 0.5)
        local new_y = math.floor(cur_y + step_y + 0.5)
        mouse_img:set_pos(new_x, new_y)
    end
end

-- 启动鼠标移动动画
local function start_mouse_animation(icon_abs_x, icon_abs_y)
    if not mouse_img then return end
    -- 鼠标起始位置：屏幕右侧，Y随机
    local start_x = screen_w - MOUSE_W
    local start_y = math.random(0, screen_h - MOUSE_H)
    mouse_img:set_pos(start_x, start_y)

    move_timer = sys.timerLoopStart(function()
        move_mouse_step(icon_abs_x, icon_abs_y)
    end, 50)  -- 每50毫秒移动一步
end

local function create_ui()
    resolution_adapt()

    main_container = airui.container({
        parent = airui.screen, x = 0, y = 0, w = screen_w, h = screen_h,
        color = COLOR_PRIMARY
    })

    local box_w = math.floor(math.min(400, screen_w * 0.8))
    local box_h = math.floor(math.min(70, math.max(48, screen_h * 0.08)))
    local box_x = math.floor((screen_w - box_w) / 2)
    local box_y = math.floor((screen_h - box_h) / 2)
    local box_r = math.floor(box_h / 2)

    search_box = airui.container({
        parent = main_container, x = box_x, y = box_y, w = box_w, h = box_h,
        color = COLOR_CARD, radius = box_r
    })

    local icon_size = math.floor(math.max(28, box_h * 0.7) * _G.density_scale)
    local icon_padding = math.floor(box_h * 0.15)
    local icon_x = box_w - icon_size - icon_padding
    local icon_y = math.floor((box_h - icon_size) / 2)
    local label_font = math.floor(math.max(16, box_h * 0.4) * _G.density_scale)

    airui.label({
        parent = search_box, x = math.floor(box_h * 0.3), y = math.floor((box_h - label_font) / 2),
        w = box_w - icon_size - icon_padding - math.floor(box_h * 0.5), h = label_font + 4,
        text = product_name, font_size = label_font, color = COLOR_TEXT,
        align = airui.TEXT_ALIGN_LEFT
    })

    search_icon = airui.image({
        parent = search_box, src = "/luadb/search.png",
        x = icon_x, y = icon_y, w = icon_size, h = icon_size,
        zoom = ZOOM_NORMAL, opacity = 255
    })

    -- 鼠标图片：初始放在屏幕右侧随机Y位置
    local mouse_start_x = screen_w - MOUSE_W
    local mouse_start_y = math.random(0, screen_h - MOUSE_H)
    mouse_img = airui.image({
        parent = main_container, src = "/luadb/mouse.png",
        x = mouse_start_x, y = mouse_start_y, w = MOUSE_W, h = MOUSE_H,
        zoom = ZOOM_NORMAL, opacity = 255
    })

    -- 计算搜索图标的绝对坐标
    local icon_abs_x = box_x + icon_x
    local icon_abs_y = box_y + icon_y
    start_mouse_animation(icon_abs_x, icon_abs_y)
end

local function on_create()
    create_ui()
end

local function on_destroy()
    if move_timer then
        sys.timerStop(move_timer)
        move_timer = nil
    end
    if main_container then
        main_container:destroy()
        main_container = nil
    end
    search_box = nil
    search_icon = nil
    mouse_img = nil
    win_id = nil
end

local function on_get_focus() end
local function on_lose_focus() end

local function open_welcome_handler()
    win_id = exwin.open({
        on_create = on_create,
        on_destroy = on_destroy,
        on_get_focus = on_get_focus,
        on_lose_focus = on_lose_focus,
    })
end

sys.subscribe("OPEN_WELCOME_WIN", open_welcome_handler)