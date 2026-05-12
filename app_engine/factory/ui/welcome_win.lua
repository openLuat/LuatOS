--[[
@module  welcome_win
@summary 开机欢迎页面模块
@version 1.1
@date    2026.04.16
@author  江访
]]

local window_id = nil
local main_container
local search_bar
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

local function recalc_adapt()
    local density_scale = _G.density_scale or 1.0
    MOUSE_SPEED = math.floor(15 * density_scale)
    ZOOM_STEP1 = math.floor(256 + 128 * density_scale)
    local mouse_size = math.floor(math.max(28, math.min(52, screen_h * 0.055)) * density_scale)
    MOUSE_W = mouse_size
    MOUSE_H = mouse_size

    local suffix = _G.model_str:gsub("^Air", "")
    if suffix ~= "" then
        product_name = "合宙引擎主机" .. suffix
    end
end

-- 鼠标移动完成后的动作：放大搜索图标，关闭窗口，发布事件
local function on_mouse_arrive()
    exwin.close(window_id)
    sys.publish("OPEN_IDLE_WIN")
end

-- 鼠标移动一步
local function move_mouse_step(tx, ty)
    if not mouse_img then return end
    local cx, cy = mouse_img:get_pos()
    cx = math.floor(cx)
    cy = math.floor(cy)
    local dx = tx - cx
    local dy = ty - cy
    local dt = math.sqrt(dx*dx + dy*dy)

    if dt <= MOUSE_SPEED then
        -- 到达目标位置
        mouse_img:set_pos(tx, ty)
        if move_timer then
            sys.timerStop(move_timer)
            move_timer = nil
        end
        search_icon:set_zoom(ZOOM_STEP1)
        mouse_img:destroy()
        sys.timerStart(on_mouse_arrive, 2500)
    else
        -- 继续移动
        local sx = (dx / dt) * MOUSE_SPEED
        local sy = (dy / dt) * MOUSE_SPEED
        local nx = math.floor(cx + sx + 0.5)
        local ny = math.floor(cy + sy + 0.5)
        mouse_img:set_pos(nx, ny)
    end
end

-- 启动鼠标移动动画
local function start_mouse_anim(ax, ay)
    if not mouse_img then return end
    local sx = screen_w - MOUSE_W
    local sy = math.random(0, screen_h - MOUSE_H)
    mouse_img:set_pos(sx, sy)

    move_timer = sys.timerLoopStart(function()
        move_mouse_step(ax, ay)
    end, 50)
end

local function build_ui()
    recalc_adapt()

    main_container = airui.container({
        parent = airui.screen, x = 0, y = 0, w = screen_w, h = screen_h,
        color = COLOR_PRIMARY
    })

    local bw = math.floor(math.min(400, screen_w * 0.8))
    local bh = math.floor(math.min(70, math.max(48, screen_h * 0.08)))
    local bx = math.floor((screen_w - bw) / 2)
    local by = math.floor((screen_h - bh) / 2)
    local br = math.floor(bh / 2)

    search_bar = airui.container({
        parent = main_container, x = bx, y = by, w = bw, h = bh,
        color = COLOR_CARD, radius = br
    })

    local ic = math.floor(math.max(28, bh * 0.7) * _G.density_scale)
    local ipd = math.floor(bh * 0.15)
    local ix = bw - ic - ipd
    local iy = math.floor((bh - ic) / 2)
    local lf = math.floor(math.max(16, bh * 0.4) * _G.density_scale)

    airui.label({
        parent = search_bar, x = math.floor(bh * 0.3), y = math.floor((bh - lf) / 2),
        w = bw - ic - ipd - math.floor(bh * 0.5), h = lf + 4,
        text = product_name, font_size = lf, color = COLOR_TEXT,
        align = airui.TEXT_ALIGN_LEFT
    })

    search_icon = airui.image({
        parent = search_bar, src = "/luadb/search.png",
        x = ix, y = iy, w = ic, h = ic,
        zoom = ZOOM_NORMAL, opacity = 255
    })

    -- 鼠标图片：初始放在屏幕右侧随机Y位置
    local mx = screen_w - MOUSE_W
    local my = math.random(0, screen_h - MOUSE_H)
    mouse_img = airui.image({
        parent = main_container, src = "/luadb/mouse.png",
        x = mx, y = my, w = MOUSE_W, h = MOUSE_H,
        zoom = ZOOM_NORMAL, opacity = 255
    })

    start_mouse_anim(bx + ix, by + iy)
end

local function on_create()
    build_ui()
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
    search_bar = nil
    search_icon = nil
    mouse_img = nil
    window_id = nil
end

local function on_get_focus() end
local function on_lose_focus() end

local function open_handler()
    window_id = exwin.open({
        on_create = on_create,
        on_destroy = on_destroy,
        on_get_focus = on_get_focus,
        on_lose_focus = on_lose_focus,
    })
end

sys.subscribe("OPEN_WELCOME_WIN", open_handler)
