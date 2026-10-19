--[[
@module  drv.lcd
@summary LCD 显示驱动（RGB 屏）：初始化 + 产测刷色图案
@version 1.0
@date    2026.10.15
@usage
产测与业务共用；参数全部取自 _G.project_config.hw.lcd，不硬编码引脚。
注意：颜色是 RGB565（16bit），不要传 24bit 色值（会被截断）。
]]

local M = {}

local inited = false
local W, H = 800, 480

local function cfg()
    return (_G.project_config and _G.project_config.hw.lcd) or {}
end

function M.backlight_on()
    local c = cfg()
    local pin = c.backlight_pin or c.pin_pwr
    if pin then
        gpio.setup(pin, 1)
        log.info("drv.lcd", "backlight on, pin", pin)
    else
        log.warn("drv.lcd", "背光引脚未配置，屏幕可能不亮")
    end
end

function M.init()
    if inited then return true end

    local c = cfg()
    local opts = {
        port      = lcd.RGB,
        direction = c.direction or 0,
        w         = c.w,
        h         = c.h,
        xoffset   = c.xoffset or 0,
        yoffset   = c.yoffset or 0,
    }
    if c.pin_rst then opts.pin_rst = c.pin_rst end
    if c.pin_pwr then opts.pin_pwr = c.pin_pwr end

    local ok = lcd.init(c.model, opts)
    if not ok then
        log.error("drv.lcd", "lcd.init 失败:", tostring(c.model))
        return false
    end

    W, H = lcd.getSize()
    lcd.setupBuff(nil, true)
    lcd.autoFlush(false)
    inited = true

    M.backlight_on()
    log.info("drv.lcd", "init ok", W, H)
    return true
end

function M.size()
    return W, H
end

-- 全屏纯色
function M.solid(color)
    lcd.fill(0, 0, W - 1, H - 1, color or 0xFFFF)
    lcd.flush()
end

function M.color_bars()
    local third = math.floor(W / 3)
    lcd.fill(0, 0, third - 1, H - 1, 0xF800)            -- 红
    lcd.fill(third, 0, third * 2 - 1, H - 1, 0x07E0)    -- 绿
    lcd.fill(third * 2, 0, W - 1, H - 1, 0x001F)        -- 蓝
    lcd.flush()
end

-- 在触点处画方块（触摸测试用）
function M.mark(x, y, color)
    if x < 0 or y < 0 or x >= W or y >= H then return end
    lcd.fill(x - 4, y - 4, x + 4, y + 4, color or 0x07E0)
    lcd.flush()
end

M.COLOR = {
    RED = 0xF800, GREEN = 0x07E0, BLUE = 0x001F,
    WHITE = 0xFFFF, BLACK = 0x0000, YELLOW = 0xFFE0,
}

return M
