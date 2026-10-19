--[[
@module  drv_tp
@summary 触摸驱动（GT911）：初始化 + 两种消费方式（产测回调 / AirUI 输入设备）
@version 1.1
@date    2026.10.15
@usage
产测模式（默认）——注册 Lua 回调，把原始触点发成消息：
    require("drv_tp").init()
    sys.subscribe("TP_RAW", function(event, x, y) ... end)

用户模式——把触摸设备直接绑给 AirUI 当输入设备：
    require("drv_tp").init({ airui = true })

注意：这两种方式**必须二选一**。
tp.init 注册了 Lua 回调后，触点事件走回调，AirUI 收不到；
反之 bind 给 AirUI 后，产测那边就取不到 TP_RAW。
总线上游句柄统一走 drv_i2c（默认软件 I2C，GPIO38/39），参数见 config。
]]

local M = {}

local inited = false
M.last = nil   -- { event = tp.EVENT_DOWN/UP, x, y }（仅回调模式下有效）
M.dev  = nil   -- tp.init 返回的触摸设备对象

function M.init(opts)
    if inited then return true end
    opts = opts or {}

    local c = _G.project_config.hw.tp
    local dev = require("drv_i2c").get()

    local callback
    if not opts.airui then
        callback = function(_, data)
            local d = data and data[1]
            if not d then return end
            M.last = { event = d.event, x = d.x, y = d.y }
            sys.publish("TP_RAW", d.event, d.x, d.y)
        end
    end

    local r = tp.init(c.model, {
        port    = dev,
        pin_rst = c.rst,
        pin_int = c.int,
        w = c.w,
        h = c.h,
    }, callback)

    if not r then
        log.error("drv_tp", "tp.init 失败:", tostring(c.model))
        return false
    end
    M.dev = r

    if opts.airui then
        -- 固件不带 airui 时这里会失败，界面只能看不能点，明确告警不静默
        local ok, err = pcall(airui.device_bind_touch, r)
        if ok then
            log.info("drv_tp", "已绑定为 AirUI 触摸输入设备")
        else
            log.error("drv_tp", "绑定 AirUI 触摸输入失败:", tostring(err))
        end
    end

    inited = true
    log.info("drv_tp", "init ok")
    return true
end

return M
