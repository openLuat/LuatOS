--[[
@module  ui
@summary LCD 预览绘制、裁剪和触摸按钮
@version 001.999.000
@date    2026.11.21
@usage
使用 LCD 帧缓冲逐帧提交 RGB565 图像。大图居中裁剪后保持标题和按钮栏可见。
]]

local board = require "board"

local ui = {}
local W, H
-- 标题栏和按钮栏之间是预览区，1024×600 屏上可见区域为 1024×480。
local header_h, footer_h = 72, 48
local button_count = 2
local selected, running, status = 1, false, "Ready"
local pressed_button, pressed_command
local black, navy, white = 0x0000, 0x1128, 0xFFFF
local blue, slate = 0x04BF, 0x294D

local function fill(x, y, w, h, color)
    lcd.fill(x, y, x + w - 1, y + h - 1, color)
end

local function draw_header()
    fill(0, 0, W, header_h, navy)
    lcd.drawStr(14, 24, "AirCAMERA_1030  USB Preview", white)
    lcd.drawStr(14, 49, status, white)
end

local function draw_footer()
    fill(0, H - footer_h, W, footer_h, navy)
    local middle = W // 2
    local mode = board.CAM.modes[selected]
    fill(5, H - footer_h + 6, middle - 10, footer_h - 12, blue)
    fill(middle + 5, H - footer_h + 6, W - middle - 10, footer_h - 12, slate)
    lcd.drawStr(17, H - 20, string.format("RES  %dx%d", mode.w, mode.h), white)
    lcd.drawStr(middle + 17, H - 20, running and "STOP" or "START", white)
end

function ui.init()
    W, H = board.size()
    lcd.setFont(lcd.font_opposansm12)
end

function ui.show(mode, active, message)
    selected, running, status = mode, active, message
    lcd.clear(black)
    draw_header()
    draw_footer()
    lcd.flush()
end

local function hit_button(x, y)
    if x < 0 or x >= W or y < H - footer_h or y >= H then return end
    return math.floor(x * button_count / W) + 1
end

-- 按下时记住按钮和命令，抬手时仅提交一次。
function ui.touch(event, x, y)
    if event == tp.EVENT_DOWN then
        pressed_button = hit_button(x, y)
        if pressed_button == 1 then
            pressed_command = "next"
        elseif pressed_button == 2 then
            pressed_command = running and "stop" or "start"
        else
            pressed_command = nil
        end
    elseif event == tp.EVENT_UP then
        local button, command = pressed_button, pressed_command
        pressed_button, pressed_command = nil, nil
        if command and hit_button(x, y) == button then
            sys.publish("AIR1030_CONTROL", command)
        end
    end
end

function ui.draw_frame(path)
    local raw = lcd.image2raw(path)
    if not raw then return false end
    local pw, ph = raw.width or 0, raw.height or 0
    if pw == 0 or ph == 0 then
        raw:free()
        return false
    end

    -- 以预览区为中心定位原图，RGB LCD 驱动按源行宽裁剪超出屏幕的像素。
    local body_h = H - header_h - footer_h
    local x = (W - pw) // 2
    local y = header_h + (body_h - ph) // 2
    local drawn = lcd.draw(x, y, 0, 0, raw)
    raw:free()
    if not drawn then return false end

    -- 大图可能覆盖界面栏，在同一次刷屏前恢复这些区域。
    if y < header_h then draw_header() end
    if y + ph > H - footer_h then draw_footer() end
    lcd.flush()
    return true, pw, ph, math.min(W, pw), math.min(body_h, ph)
end

return ui
