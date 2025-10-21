--[[
@module netLed
@summary netLed 网络状态指示灯
@version 1.2
@date    2025.10.21
@author  马亚丹
@usage
--注意:因使用了sys.wait()所有api需要在协程中使用

]]

netLed = {}
-- 引用sys库
local sys = require("sys")

local simError        --SIM卡状态：true为异常,false或者nil为正常
local flyMode         --是否处于飞行模式：true为是,false或者nil为否
local gprsAttached    --是否附着上GPRS网络,true为是,false或者nil为否
local socketConnected --是否有socket连接上后台,true为是,false或者nil为否
local prevState       -- 保存SIMERR触发前的状态

--[[
网络指示灯表示的工作状态
NULL：功能关闭状态
FLYMODE：飞行模式
SIMERR：未检测到SIM卡或者SIM卡锁pin码等SIM卡异常
IDLE：未注册GPRS网络
GPRS：已附着GPRS数据网络
SCK：socket已连接上后台
]]
local ledState = "NULL"
local ON, OFF = 1, 2
--各种工作状态下配置的点亮、熄灭时长（单位毫秒）
local ledBlinkTime = {
    NULL = {0, 0xFFFF},  --常灭
    FLYMODE = {0, 0xFFFF},  --常灭
    SIMERR = {700, 300},  --亮300毫秒,灭5700毫秒
    IDLE = {300, 3700},  --亮300毫秒,灭3700毫秒
    GPRS = {300, 700},  --亮300毫秒,灭700毫秒
    SCK = {100, 100},  --亮100毫秒,灭100毫秒
}

local ledSwitch = false   --网络指示灯开关,true为打开,false或者nil为关闭
local LEDPIN = 27         --网络指示灯默认PIN脚（GPIO27）

--[[
网络指示灯模块的运行任务
@api netLed.taskLed(ledPinSetFunc)
@return nil 无返回值
@usage 
]]
function netLed.taskLed(ledPinSetFunc)
    while true do
        if ledSwitch then
            local onTime, offTime = ledBlinkTime[ledState][ON], ledBlinkTime[ledState][OFF]
            if onTime > 0 then
                ledPinSetFunc(1)
                if not sys.waitUntil("NET_LED_UPDATE", onTime) then
                    if offTime > 0 then
                        ledPinSetFunc(0)
                        sys.waitUntil("NET_LED_UPDATE", offTime)
                    end
                end
            elseif offTime > 0 then
                ledPinSetFunc(0)
                sys.waitUntil("NET_LED_UPDATE", offTime)
            end            
        else
            ledPinSetFunc(0)
            break
        end
    end
end

--[[
初始化网络指示灯并且立即执行配置后的动作
@api netLed.setup(flag,ledpin)
@bool flag 是否打开网络指示灯功能,true为打开,false为关闭
@number ledPin 控制网络指示灯闪烁的GPIO引脚,例如pio.P0_1表示GPIO1
@return nil 无返回值
@usage 
netLed.setup(true,27)
]]
function netLed.setup(flag, ledPin)
    local oldSwitch = ledSwitch
    if flag ~= ledSwitch then
        ledSwitch = flag
        sys.publish("NET_LED_UPDATE")
    end
    -- 仅在首次打开时初始化并启动网络指示灯任务
    if flag and not oldSwitch then
        sys.taskInit(netLed.taskLed, gpio.setup(ledPin, 0))
    end
end

--[[
配置某种工作状态下指示灯点亮和熄灭的时长（如果用户不配置,使用netLed.lua中ledBlinkTime配置的默认值）
@api netLed.setBlinkTime(state,on,off)
@string state 某种工作状态,仅支持"FLYMODE"、"SIMERR"、"IDLE"、"GPRS"、"SCK"
@number on 指示灯点亮时长,单位毫秒,0xFFFF表示常亮,0表示常灭
@number off 指示灯熄灭时长,单位毫秒,0xFFFF表示常灭,0表示常亮
@return nil 无返回值 
@usage 
netLed.setBlinkTime("FLYMODE",1000,500) --表示飞行模式工作状态下,指示灯闪烁规律为: 亮1秒,灭0.5秒
]]
function netLed.setBlinkTime(state, on, off)
    if not ledBlinkTime[state] then 
        log.error("netLed.setBlinkTime", "invalid state") 
        return 
    end    
    local updated = false
    if on and ledBlinkTime[state][ON] ~= on then
        ledBlinkTime[state][ON] = on
        updated = true
    end
    if off and ledBlinkTime[state][OFF] ~= off then
        ledBlinkTime[state][OFF] = off
        updated = true
    end
    if updated then 
        sys.publish("NET_LED_UPDATE") 
    end
end

--[[ 
呼吸灯
@api netLed.setupBreateLed(ledPin)
@function ledPin 呼吸灯的ledPin用gpio.setup注册返回的方法
@return nil 无返回值
@usage 
]]
function netLed.setupBreateLed(ledPin)
    -- 呼吸灯的状态、PWM周期
    local bLighting, bDarking, LED_PWM = false, true, 18
    if bLighting then
        for i = 1, LED_PWM - 1 do
            ledPin(0)
            sys.wait(i)
            ledPin(1)
            sys.wait(LED_PWM - i)
        end
        bLighting = false
        bDarking = true
        ledPin(0)
        sys.wait(700)
    end
    if bDarking then
        for i = 1, LED_PWM - 1 do
            ledPin(0)
            sys.wait(LED_PWM - i)
            ledPin(1)
            sys.wait(i)
        end
        bLighting = true
        bDarking = false
        ledPin(1)
        sys.wait(700)
    end
end

-- 事件订阅回调直接处理状态更新
sys.subscribe("FLYMODE", function(mode)
    if flyMode == mode then return end
    flyMode = mode
    local newState = "IDLE"
    if flyMode then
        newState = "FLYMODE"
    elseif simError then
        newState = "SIMERR"
    elseif socketConnected then
        newState = "SCK"
    elseif gprsAttached then
        newState = "GPRS"
    end
    if newState ~= ledState then
        ledState = newState
        sys.publish("NET_LED_UPDATE")
    end
end)

sys.subscribe("SIM_IND", function(para)    
    local newSimError = (para ~= "RDY") and (para ~= "GET_NUMBER")
    if simError == newSimError then return end
    
    -- 保存SIM异常前的状态
    if not simError and newSimError then
        prevState = ledState  -- 发生SIM错误时，记录当前状态
    end
    
    simError = newSimError
    local newState = "IDLE"
    
    if flyMode then
        newState = "FLYMODE"
    elseif simError then
        newState = "SIMERR"  -- SIM错误时使用SIMERR状态
    else
        -- SIM恢复正常时，使用错误前的状态或正常计算
        newState = prevState or (socketConnected and "SCK" or (gprsAttached and "GPRS" or "IDLE"))
    end
    
    if newState ~= ledState then
        ledState = newState
        sys.publish("NET_LED_UPDATE")
    end
    log.info("sim status", para)
end)

sys.subscribe("IP_LOSE", function()
    if not gprsAttached then return end
    gprsAttached = false
    local newState = "IDLE"
    if flyMode then
        newState = "FLYMODE"
    elseif simError then
        newState = "SIMERR"
    elseif socketConnected then
        newState = "SCK"
    elseif gprsAttached then
        newState = "GPRS"
    end
    if newState ~= ledState then
        ledState = newState
        sys.publish("NET_LED_UPDATE")
    end
    log.info("mobile", "IP_LOSE", (adapter or -1) == socket.LWIP_GP)
end)

sys.subscribe("IP_READY", function(ip, adapter)
    if gprsAttached == adapter then return end
    gprsAttached = adapter
    local newState = "IDLE"
    if flyMode then
        newState = "FLYMODE"
    elseif simError then
        newState = "SIMERR"
    elseif socketConnected then
        newState = "SCK"
    elseif gprsAttached then
        newState = "GPRS"
    end
    if newState ~= ledState then
        ledState = newState
        sys.publish("NET_LED_UPDATE")
    end
    log.info("mobile", "IP_READY", ip, (adapter or -1) == socket.LWIP_GP)
end)

sys.subscribe("SOCKET_ACTIVE", function(active)
    if socketConnected == active then return end
    socketConnected = active
    local newState = "IDLE"
    if flyMode then
        newState = "FLYMODE"
    elseif simError then
        newState = "SIMERR"
    elseif socketConnected then
        newState = "SCK"
    elseif gprsAttached then
        newState = "GPRS"
    end
    if newState ~= ledState then
        ledState = newState
        sys.publish("NET_LED_UPDATE")
    end
end)

return netLed