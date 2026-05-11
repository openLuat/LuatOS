-- nconv: var2-4 fn2-5 tag-short
--[[
@module  settings_display_app
@summary 显示与亮度业务逻辑层
@version 1.0
@date    2026.04.01
@author  江访
@usage
本模块为显示与亮度业务逻辑层，管理PWM背光亮度调节。提供亮度增减、设置、查询接口。
]]
-- ==================== 局部变量 ====================
local pi = false  -- PWM 初始化标志
local cb = 100    -- 当前亮度值 (10-100)

-- 根据平台选择 PWM 通道和频率（对应各平台 lcd_drv 中 backlight_on 的配置）
local pch, pf
if _G.model_str:find("Air8000") then
    pch, pf = 0, 1000
elseif _G.model_str:find("Air8101") then
    pch, pf = 1, 10000
elseif _G.model_str:find("Air1601") or _G.model_str:find("Air1602") then
    pch, pf = 3, 1000
end
if not pch then
    pch, pf = 0, 1000  -- 默认值
end

-- ==================== 内部函数 ====================
--[[
@function init_pwm
@summary 初始化背光 PWM
]]
local function ipw()
    if not pi then
        pwm.setup(pch, pf, cb)
        pwm.start(pch)
        pi = true
        log.info("sda", "PWM 初始化完成，初始亮度: " .. cb)
    end
end

--[[
@function set_brightness
@summary 设置背光亮度并上报变更事件
@param level 亮度值 (10-100)
]]
local function sb(lv)
    if not pi then
        ipw()
    end
    if lv < 10 then
        lv = 10
    elseif lv > 100 then
        lv = 100
    end
    cb = lv
    pwm.setDuty(pch, lv)
    log.info("sda", "亮度设置为: " .. lv .. "%")
    -- 上报亮度变化事件
    sys.publish("DISPLAY_BRIGHTNESS_CHANGED", cb)
end

-- ==================== 事件订阅 ====================
-- 订阅亮度增加事件
sys.subscribe("DISPLAY_BRIGHTNESS_INCREASE", function()
    local nl = cb + 10
    if nl > 100 then
        nl = 100
    end
    sb(nl)
end)

-- 订阅亮度减少事件
sys.subscribe("DISPLAY_BRIGHTNESS_DECREASE", function()
    local nl = cb - 10
    if nl < 10 then
        nl = 10
    end
    sb(nl)
end)

-- 订阅亮度设置事件（直接设置指定值）
sys.subscribe("DISPLAY_BRIGHTNESS_SET", function(lv)
    if type(lv) == "number" then
        sb(lv)
    end
end)

-- 订阅亮度查询事件（业务层上报当前值）
sys.subscribe("DISPLAY_BRIGHTNESS_GET", function()
    sys.publish("DISPLAY_BRIGHTNESS_VALUE", cb)
end)
