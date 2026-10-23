--[[
@module  tp_drv
@summary GT911 触摸初始化并绑定 AirUI（i2c / tp / airui 核心库）
@version 1.2.0
@date    2026.10.21
@usage
  local tp_drv = require "tp_drv"
  tp_drv.init()     -- 必须在 lcd_drv.init() 之后调用
]]

local cfg = require "hw_config"

local M = {}

local c = cfg.tp

local function open(port)
    local ok, dev = pcall(tp.init, c.model, {
        port         = port,
        pin_rst      = c.pin_rst,
        pin_int      = c.pin_int,
        int_type     = tp.FALLING or 2,
        w            = UI_W or c.w,
        h            = UI_H or c.h,
        direction    = c.direction or 0,
        refresh_rate = c.refresh_rate,
        tp_num       = c.tp_num,
        swap_xy      = c.swap_xy,
    })
    if ok then return dev end
    log.warn("tp_drv", "tp.init 异常", dev)
    return nil
end

--- 初始化触摸：硬件 I2C1 优先，失败自动退回软件 I2C
-- @return boolean
function M.init()
    if not c.enable then
        log.info("tp_drv", "touch disabled")
        return false
    end

    local dev

    -- 方案一：硬件 I2C1（SIP 整机）
    pcall(i2c.setup, c.port, c.speed or (i2c.SLOW or nil))
    dev = open(c.port)
    if dev then
        log.info("tp_drv", "touch ready (I2C" .. tostring(c.port) .. ")")
    else
        -- 方案二：软件 I2C（AirLCD1090 / 固件缺 pins 库时）
        local fb = c.fallback or {}
        if i2c.createSoft and fb.scl and fb.sda then
            log.warn("tp_drv", "硬件 I2C 触摸失败，改用软件 I2C", fb.scl, fb.sda)
            local bus = i2c.createSoft(fb.scl, fb.sda, fb.delay_us or 5)
            if bus then
                dev = open(bus)
            end
        end
    end

    if not dev then
        log.error("tp_drv", "tp.init fail", c.model)
        return false
    end

    if not airui.device_bind_touch(dev) then
        log.error("tp_drv", "airui.device_bind_touch 失败")
        return false
    end

    if c.debug and airui.touch_subscribe then
        airui.touch_subscribe(function(state, x, y, track)
            log.info("touch", state, x, y, track)
        end)
    end

    log.info("tp_drv", "touch bound", c.model)
    return true
end

return M
