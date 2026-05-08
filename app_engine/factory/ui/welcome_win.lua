--[[
@module  welcome_win
@summary 开机欢迎页面模块
@version 1.1
@date    2026.04.16
@author  江访
]]
-- naming: fn(2-5char), var(2-4char)

local wid = nil
local mc
local sb
local si
local mi
local mt

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

local pn = "合宙引擎主机"

local function ra()
    local ds = _G.density_scale or 1.0
    MOUSE_SPEED = math.floor(15 * ds)
    ZOOM_STEP1 = math.floor(256 + 128 * ds)
    local msz = math.floor(math.max(28, math.min(52, screen_h * 0.055)) * ds)
    MOUSE_W = msz
    MOUSE_H = msz

    local sfx = _G.model_str:gsub("^Air", "")
    if sfx ~= "" then
        pn = "合宙引擎主机" .. sfx
    end
end

-- 鼠标移动完成后的动作：放大搜索图标，关闭窗口，发布事件
local function oma()
    exwin.close(wid)
    sys.publish("OPEN_IDLE_WIN")
end

-- 鼠标移动一步
local function mms(tx, ty)
    if not mi then return end
    local cx, cy = mi:get_pos()
    cx = math.floor(cx)
    cy = math.floor(cy)
    local dx = tx - cx
    local dy = ty - cy
    local dt = math.sqrt(dx*dx + dy*dy)

    if dt <= MOUSE_SPEED then
        -- 到达目标位置
        mi:set_pos(tx, ty)
        if mt then
            sys.timerStop(mt)
            mt = nil
        end
        si:set_zoom(ZOOM_STEP1)
        mi:destroy()
        sys.timerStart(oma, 2500)
    else
        -- 继续移动
        local sx = (dx / dt) * MOUSE_SPEED
        local sy = (dy / dt) * MOUSE_SPEED
        local nx = math.floor(cx + sx + 0.5)
        local ny = math.floor(cy + sy + 0.5)
        mi:set_pos(nx, ny)
    end
end

-- 启动鼠标移动动画
local function sma(ax, ay)
    if not mi then return end
    local sx = screen_w - MOUSE_W
    local sy = math.random(0, screen_h - MOUSE_H)
    mi:set_pos(sx, sy)

    mt = sys.timerLoopStart(function()
        mms(ax, ay)
    end, 50)
end

local function cui()
    ra()

    mc = airui.container({
        parent = airui.screen, x = 0, y = 0, w = screen_w, h = screen_h,
        color = COLOR_PRIMARY
    })

    local bw = math.floor(math.min(400, screen_w * 0.8))
    local bh = math.floor(math.min(70, math.max(48, screen_h * 0.08)))
    local bx = math.floor((screen_w - bw) / 2)
    local by = math.floor((screen_h - bh) / 2)
    local br = math.floor(bh / 2)

    sb = airui.container({
        parent = mc, x = bx, y = by, w = bw, h = bh,
        color = COLOR_CARD, radius = br
    })

    local ic = math.floor(math.max(28, bh * 0.7) * _G.density_scale)
    local ipd = math.floor(bh * 0.15)
    local ix = bw - ic - ipd
    local iy = math.floor((bh - ic) / 2)
    local lf = math.floor(math.max(16, bh * 0.4) * _G.density_scale)

    airui.label({
        parent = sb, x = math.floor(bh * 0.3), y = math.floor((bh - lf) / 2),
        w = bw - ic - ipd - math.floor(bh * 0.5), h = lf + 4,
        text = pn, font_size = lf, color = COLOR_TEXT,
        align = airui.TEXT_ALIGN_LEFT
    })

    si = airui.image({
        parent = sb, src = "/luadb/search.png",
        x = ix, y = iy, w = ic, h = ic,
        zoom = ZOOM_NORMAL, opacity = 255
    })

    -- 鼠标图片：初始放在屏幕右侧随机Y位置
    local mx = screen_w - MOUSE_W
    local my = math.random(0, screen_h - MOUSE_H)
    mi = airui.image({
        parent = mc, src = "/luadb/mouse.png",
        x = mx, y = my, w = MOUSE_W, h = MOUSE_H,
        zoom = ZOOM_NORMAL, opacity = 255
    })

    sma(bx + ix, by + iy)
end

local function oc()
    cui()
end

local function od()
    if mt then
        sys.timerStop(mt)
        mt = nil
    end
    if mc then
        mc:destroy()
        mc = nil
    end
    sb = nil
    si = nil
    mi = nil
    wid = nil
end

local function ogf() end
local function olf() end

local function oh()
    wid = exwin.open({
        on_create = oc,
        on_destroy = od,
        on_get_focus = ogf,
        on_lose_focus = olf,
    })
end

sys.subscribe("OPEN_WELCOME_WIN", oh)
