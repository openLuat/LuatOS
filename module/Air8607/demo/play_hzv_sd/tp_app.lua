--[[
@module  tp_app
@summary Air8607 GT911 触摸初始化应用功能模块（tp 库 + AirUI 触摸绑定）
@version 1.0
@date    2026.10.30
@author  江访
@usage
本文件为 Air8607 播放 SD 卡 HZV 素材 demo 的触摸初始化应用功能模块，核心业务逻辑为：
1、用 i2c.setup 初始化 I2C1 总线，第三参 true 表示轮询模式；
2、调用 tp.init 初始化 GT911 触摸芯片，传入 I2C 端口号、TP_RST、TP_INT 和触摸面板分辨率；
3、调用 airui.device_bind_touch 把触摸设备绑定到 AirUI，绑定之后按钮的 on_click 才会被触发；
4、播放音视频之后补回触摸 I2C 总线配置，恢复触摸响应。

内核 tp 库一次上电只接受一次 tp.init，重复调用返回 nil 并打印 tp has been initialized，
所以本模块只认首次成功，之后只补总线配置，不再碰 tp.init。

本文件的对外接口有3个：
1、tp_app.init：初始化触摸屏并绑定到 AirUI，成功返回 true，失败返回 false
2、tp_app.i2c_restore：立即补回触摸 I2C 总线配置
3、tp_app.recover：延迟一发补回触摸 I2C 总线配置，避开音频收尾那一瞬间
]]

local M = {}

-- GT911 触摸控制器，Air8607 整机板载
local TP_MODEL = "gt911"

-- 触摸挂在 I2C1 上，速率填 0 表示用内核默认速率
local TP_I2C_PORT    = 1
local TP_I2C_SPEED   = 0
local TP_I2C_POLLING = true

-- TP_RST = GPIO14，TP_INT = WAKEUP = GPIO51
local PIN_TP_RST = 14
local PIN_TP_INT = 51

-- 触摸面板分辨率，与 1024x600 的屏幕一一对应
local TP_W = 1024
local TP_H = 600

-- 触摸总线恢复的延迟时间，单位 ms
local T_TP_RECOVER = 300

-- tp.init 返回的触摸设备对象，非 nil 表示已经初始化成功
local tp_device = nil

-- 触摸总线恢复定时器句柄，用于取消上一次没执行的恢复
local recover_timer = nil

--[[
补回触摸 I2C 总线配置；

@summary 按本模块的端口号、速率、轮询模式重新调用 i2c.setup

@return boolean 补回成功返回 true，触摸还没初始化过返回 false
]]
local function i2c_restore_bus()
    if not tp_device then
        return false
    end
    i2c.setup(TP_I2C_PORT, TP_I2C_SPEED, TP_I2C_POLLING)
    log.info("tp_app", "触摸 I2C 总线配置已补回",
        "端口" .. TP_I2C_PORT, "轮询模式", TP_I2C_POLLING)
    return true
end

--[[
触摸总线恢复定时器的回调函数；

@summary 到点后清掉句柄并补回触摸 I2C 总线配置

@return nil
]]
local function tp_recover_timer_cbfunc()
    recover_timer = nil
    i2c_restore_bus()
end

--[[
初始化触摸屏并绑定到 AirUI；

@api tp_app.init()

@summary 初始化 I2C1 与 GT911，再把触摸设备绑定到 AirUI，触摸已初始化过时只补总线配置

@return boolean 初始化成功返回 true，失败返回 false

@usage
if not tp_app.init() then
    log.error("main", "触摸初始化失败，界面按钮点不动")
end
]]
function M.init()
    -- 内核 tp 库一次上电只接受一次 tp.init，重复调用直接补总线配置返回
    if tp_device then
        log.info("tp_app", "触摸已经初始化过，跳过 tp.init")
        i2c_restore_bus()
        return true
    end

    if not rawget(_G, "tp") or not tp.init then
        log.error("tp_app", "固件不支持 tp 库，请烧录带 LUAT_USE_TP 的固件")
        return false
    end

    -- I2C1 总线初始化，触摸坐标走这里读
    i2c.setup(TP_I2C_PORT, TP_I2C_SPEED, TP_I2C_POLLING)
    log.info("tp_app", "触摸 I2C 总线初始化", "端口" .. TP_I2C_PORT)

    local param = {
        port     = TP_I2C_PORT,
        pin_rst  = PIN_TP_RST,
        pin_int  = PIN_TP_INT,
        int_type = tp.FALLING,
        w        = TP_W,
        h        = TP_H,
    }

    -- 第三个参数传触摸回调，使用 AirUI 时不需要，这里不传，由 LVGL 处理触摸事件
    local device = tp.init(TP_MODEL, param)
    if not device then
        log.error("tp_app", "触摸初始化失败", "请检查 I2C1、TP_RST、TP_INT 与屏幕是否匹配")
        return false
    end
    tp_device = device
    log.info("tp_app", "触摸初始化成功", TP_MODEL,
        "尺寸", TP_W .. "x" .. TP_H)

    if not airui or not airui.device_bind_touch then
        log.error("tp_app", "固件不支持 airui.device_bind_touch，按钮点击不会响应")
        return false
    end

    -- 把触摸设备绑定到 AirUI 输入，绑定之后按钮的 on_click 才会被触发
    if not airui.device_bind_touch(device) then
        log.error("tp_app", "触摸绑定 AirUI 失败")
        return false
    end
    log.info("tp_app", "触摸已绑定 AirUI")
    return true
end

--[[
立即补回触摸 I2C 总线配置；

@api tp_app.i2c_restore()

@summary 播放音视频之后触摸不响应时调用，重新配置 I2C1 的速率与轮询模式

@return boolean 补回成功返回 true，触摸还没初始化过返回 false

@usage
tp_app.i2c_restore()
]]
function M.i2c_restore()
    return i2c_restore_bus()
end

--[[
延迟补回触摸 I2C 总线配置；

@api tp_app.recover(delay_ms)

@summary 先取消没执行的恢复定时器，再排一个延时恢复，避开音频收尾抢总线的那一刻

@param number delay_ms 延迟毫秒数，不传用 T_TP_RECOVER

@return boolean 排上定时器返回 true，触摸还没初始化过返回 false

@usage
tp_app.recover()
]]
function M.recover(delay_ms)
    if not tp_device then
        return false
    end

    if recover_timer then
        sys.timerStop(recover_timer)
        recover_timer = nil
    end
    recover_timer = sys.timerStart(tp_recover_timer_cbfunc, delay_ms or T_TP_RECOVER)
    return true
end

return M
