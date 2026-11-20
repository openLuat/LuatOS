--[[
@module  tp_app
@summary Air8607 GT911 触摸初始化应用功能模块（tp 库 + PLCUI 触摸绑定）
@version 1.0
@date    2026.11.10
@author  江访
@usage
本文件为 plcui_water_station 演示项目的触摸初始化应用功能模块，核心业务逻辑为：
1、tp_app.init 用 i2c.setup 初始化 I2C1 总线（第三参 true 表示轮询模式），
   再调 tp.init 初始化 GT911 触摸芯片，保存 tp.init 返回的触摸设备对象；
2、tp_app.bind 调 plcui.device_bind_touch 把触摸设备绑定到 PLCUI，
   绑定之后按钮的 on-click 才会被触发；
   注意：plcui.device_bind_touch 必须在 plcui.init 之后调用，
   所以 init 和 bind 拆成两步，由 boot_app.lua 按顺序调用。

内核 tp 库一次上电只接受一次 tp.init，重复调用返回 nil 并打印 tp has been initialized，
所以本模块只认首次成功，之后只补总线配置，不再碰 tp.init。

本文件的对外接口有3个：
1、tp_app.init：初始化 I2C1 与 GT911，成功返回 true，失败返回 false
2、tp_app.bind：把触摸设备绑定到 PLCUI，成功返回 true，失败返回 false
3、tp_app.i2c_restore：立即补回触摸 I2C 总线配置
]]

local tp_app = {}

-- GT911 触摸控制器，Air8607 整机板载
local TP_MODEL = "gt911"

-- 触摸挂在 I2C1 上，速率用 i2c.FAST（与出厂固件触摸驱动配置一致）
local TP_I2C_PORT = 1

-- TP_RST = GPIO14，TP_INT = WAKEUP = GPIO51
local PIN_TP_RST = 14
local PIN_TP_INT = 51

-- 触摸面板分辨率，与 1024x600 的屏幕一一对应
local TP_W = 1024
local TP_H = 600

-- tp.init 返回的触摸设备对象，非 nil 表示已经初始化成功
local tp_device = nil

--[[
补回触摸 I2C 总线配置；

@summary 按本模块的端口号、速率、轮询模式重新调用 i2c.setup

@return boolean 补回成功返回 true，触摸还没初始化过返回 false
]]
local function i2c_restore_bus()
    if not tp_device then
        return false
    end
    i2c.setup(TP_I2C_PORT, i2c.FAST)
    log.info("tp_app", "触摸 I2C 总线配置已补回", "端口" .. TP_I2C_PORT)
    return true
end

--[[
初始化触摸屏；

@api tp_app.init()

@summary 初始化 I2C1 总线与 GT911 触摸芯片，触摸已初始化过时只补总线配置；
本函数不绑定 PLCUI，绑定要等 plcui.init 之后由 tp_app.bind 完成

@return boolean 初始化成功返回 true，失败返回 false

@usage
if not tp_app.init() then
    log.error("boot_app", "触摸初始化失败，界面按钮点不动")
end
]]
function tp_app.init()
    -- 内核 tp 库一次上电只接受一次 tp.init，重复调用直接补总线配置返回
    if tp_device then
        log.info("tp_app", "触摸已经初始化过，跳过 tp.init")
        i2c_restore_bus()
        return true
    end

    -- _G 在部分固件上是 rotable，rawget 会报 bad argument，直接用下标安全取值
    local tp_lib = _G["tp"]
    if not tp_lib or not tp_lib.init then
        log.error("tp_app", "固件不支持 tp 库，请烧录带 LUAT_USE_TP 的固件")
        return false
    end

    -- I2C1 总线初始化，触摸坐标走这里读
    i2c.setup(TP_I2C_PORT, i2c.FAST)
    log.info("tp_app", "触摸 I2C 总线初始化", "端口" .. TP_I2C_PORT)

    local param = {
        port     = TP_I2C_PORT,
        pin_rst  = PIN_TP_RST,
        pin_int  = PIN_TP_INT,
        int_type = tp.FALLING,
        w        = TP_W,
        h        = TP_H,
    }

    -- 第三个参数传触摸回调，使用 PLCUI 时不需要，这里不传，由 LVGL 处理触摸事件
    local device = tp.init(TP_MODEL, param)
    if not device then
        log.error("tp_app", "触摸初始化失败", "请检查 I2C1、TP_RST、TP_INT 与屏幕是否匹配")
        return false
    end
    tp_device = device
    log.info("tp_app", "触摸初始化成功", TP_MODEL, "尺寸", TP_W .. "x" .. TP_H)
    return true
end

--[[
把触摸设备绑定到 PLCUI；

@api tp_app.bind()

@summary 调 plcui.device_bind_touch 绑定 tp.init 返回的触摸设备对象，
绑定之后按钮的 on-click 才会被触发；必须在 plcui.init 之后调用；
PC 模拟器上调用同样兼容（输入由 SDL 鼠标提供）

@return boolean 绑定成功返回 true，失败返回 false

@usage
plcui.init({width = 1024, height = 600})
tp_app.bind()
]]
function tp_app.bind()
    if not tp_device then
        log.error("tp_app", "触摸还没初始化，不能绑定 PLCUI")
        return false
    end

    if not plcui or not plcui.device_bind_touch then
        log.error("tp_app", "固件不支持 plcui.device_bind_touch，按钮点击不会响应")
        return false
    end

    -- 把触摸设备绑定到 PLCUI 输入，绑定之后按钮的 on_click 才会被触发
    local ok, err = plcui.device_bind_touch(tp_device)
    if not ok then
        log.error("tp_app", "触摸绑定 PLCUI 失败", err)
        return false
    end
    log.info("tp_app", "触摸已绑定 PLCUI")
    return true
end

--[[
立即补回触摸 I2C 总线配置；

@api tp_app.i2c_restore()

@summary 触摸不响应时调用，重新配置 I2C1 的速率与轮询模式

@return boolean 补回成功返回 true，触摸还没初始化过返回 false

@usage
tp_app.i2c_restore()
]]
function tp_app.i2c_restore()
    return i2c_restore_bus()
end

return tp_app
