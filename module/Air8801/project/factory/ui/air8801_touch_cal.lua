local touch = require "air8801_touch"
local theme = require "ui_theme"
local M = {status = "IDLE"}
local panel, marker, hint

local function close()
    if panel then panel:destroy(); panel = nil end
    marker, hint = nil, nil
end

local function on_event(event, x, y)
    if marker then marker:destroy(); marker = nil end
    if event == "point" then
        marker = airui.shape({parent = panel, x = x - 12, y = y - 12, w = 25, h = 25,
            items = {
                {type = "rect", x = 0, y = 11, w = 25, h = 3, fill = true, fill_color = 0xFFFFFF},
                {type = "rect", x = 11, y = 0, w = 3, h = 25, fill = true, fill_color = 0xFFFFFF},
            }})
    elseif event == "done" then
        if x == true then
            M.status = touch.save_calibration() and "SAVED" or "SAVE_FAILED"
            log.info("air8801_touch", "CAL_DONE", M.status)
            close()
        else
            M.status = "FAILED"
            log.warn("air8801_touch", "CAL_FAILED")
            -- 无有效标定时，继续显示标定页以便再次用触笔点击四角。
            if not touch.calibrated() then
                hint:set_text("标定未完成。请松手，稍后重试")
                sys.timerStart(function()
                    if M.status == "FAILED" and panel then
                        close()
                        M.open()
                    end
                end, 1000)
            else
                close()
            end
        end
    end
end

function M.open()
    if M.status == "RUNNING" then return false, "BUSY" end
    -- 电容屏不需要标定，直接拒绝，避免先建全屏黑底再失败关闭造成闪屏
    if not touch.resistive() then return false, "NOT_RESISTIVE" end
    close()
    panel = theme.box(airui.screen, {x = 0, y = 0, w = screen_w, h = screen_h, color = 0, opa = 255})
    hint = theme.label(panel, {x = 0, y = screen_h // 2 - 18, w = screen_w, h = 36,
        align = airui.TEXT_ALIGN_CENTER, text = "依次按住十字片刻，再松手", color = 0xFFFFFF})
    M.status = "RUNNING"
    local ok, reason = touch.calibrate(on_event)
    if not ok then
        M.status = "FAILED"
        close()
    end
    return ok, reason
end

return M
