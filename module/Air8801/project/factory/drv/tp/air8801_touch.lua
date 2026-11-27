local cfg = require "air8801_config"
local M = {}
local device, bound

local function calibration_key()
    return "air8801_cal_" .. cfg.panel
end

--- 是否实装触摸芯片。裸屏（K8801_..._LCD_...）没有触摸：
--- 不初始化 GT911/NS2009，标定项与校准入口随 resistive()/ready() 一起自然消失
function M.enabled()
    return cfg.touch_mode ~= "none"
end

function M.init(params)
    if not device then
        if not M.enabled() then return nil, "NO_TOUCH" end
        local resistive = cfg.touch_mode == "resistive"
        -- 电容屏（GT911）：GPIO14 是复位脚，拉低 → 保持 20ms → 释放，芯片进入正常模式。
        -- 电阻屏（NS2009）：同一引脚是 A0 地址脚，拉低即锁 0x48。
        assert(gpio.setup(params.pin_rst, 0), "TP GPIO14")
        if not resistive then sys.wait(20) end
        -- Air1101 的 I2C1 为 SDA GPIO38、SCL GPIO39。
        -- 第三个参数 true = 轮询模式，避免中断/DMA 传输在异常时序下把控制器卡在 busy。
        if i2c.setup(params.port, i2c.SLOW, true) ~= 1 then return nil, "I2C1" end
        local lcd = cfg.hw.lcd.params
        local model = resistive and "ns2009" or "gt911"
        device = tp.init(model, {
            port = params.port, pin_int = params.pin_int, int_type = tp.FALLING,
            pin_rst = not resistive and params.pin_rst or nil, w = lcd.w, h = lcd.h,
        })
        if not device then return nil, "TP_INIT" end
        log.info("air8801_touch", "TP_READY", model, lcd.w, lcd.h)
        if resistive and fskv and fskv.init() then
            local saved = fskv.get(calibration_key())
            if type(saved) == "table" then
                local ok, reason = tp.calibration(device, saved)
                log.info("air8801_touch", ok and "CAL_RESTORED" or "CAL_RESTORE_FAILED", reason)
            end
        end
    end
    if not bound then bound = airui.device_bind_touch(device) end
    return bound and device
end

function M.ready()
    return not not bound
end

--- 是否电阻触摸（NS2009）。只有四线电阻屏需要标定，
--- 电容 GT911 芯片固件自带绝对坐标，插上即准，不存在标定概念。
function M.resistive()
    return cfg.touch_mode == "resistive"
end

--- 触摸是否已可正常使用。电容屏恒为 true；电阻屏看内核是否已有有效系数
function M.calibrated()
    if not M.resistive() then return true end
    return bound and not not tp.calibration(device)
end

function M.calibrate(on_event)
    if not bound or not M.resistive() then return false, "NS2009 未就绪" end
    return tp.calibration(device, on_event)
end

function M.save_calibration()
    local data = tp.calibration(device)
    return data and fskv and fskv.init() and fskv.set(calibration_key(), data)
end

return M
