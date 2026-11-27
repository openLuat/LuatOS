-- 背光亮度：fskv 持久化，输出走 PWM3。
local board = require "air8801_board"
local bl = require("air8801_config").hw.lcd.backlight
local M = {}
local key = "display_brightness"

local function clamp(level)
    return math.max(10, math.min(100, math.floor(level)))
end

function M.restore_brightness()
    if not fskv or not fskv.init() then return end
    local level = fskv.get(key)
    if type(level) == "number" then bl.level = clamp(level) end
end

local function set_brightness(level)
    local ok, applied = pcall(board.set_backlight, level)
    if not ok or not applied then
        log.error("settings_display", "PWM3 亮度设置失败", applied)
        sys.publish("DISPLAY_BRIGHTNESS_VALUE", bl.level)
        return
    end
    bl.level = level
    if fskv and fskv.init() and not fskv.set(key, level) then
        log.warn("settings_display", "亮度未能保存")
    end
    sys.publish("DISPLAY_BRIGHTNESS_CHANGED", level)
end

sys.subscribe("DISPLAY_BRIGHTNESS_SET", function(level)
    if type(level) == "number" then set_brightness(clamp(level)) end
end)
sys.subscribe("DISPLAY_BRIGHTNESS_INCREASE", function() set_brightness(clamp(bl.level + 10)) end)
sys.subscribe("DISPLAY_BRIGHTNESS_DECREASE", function() set_brightness(clamp(bl.level - 10)) end)
sys.subscribe("DISPLAY_BRIGHTNESS_GET", function() sys.publish("DISPLAY_BRIGHTNESS_VALUE", bl.level) end)

return M

