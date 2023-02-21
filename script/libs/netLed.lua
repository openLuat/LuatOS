--- 模块功能：网络指示灯模块
-- @module netLed
-- @author openLuat
-- @license MIT
-- @copyright HH
-- @release 2023年2月2日
netLed = {}


--SIM卡状态：true为异常，false或者nil为正常
local simError
--是否处于飞行模式：true为是，false或者nil为否
local flyMode
--是否注册上GSM网络，true为是，false或者nil为否
local gsmRegistered
--是否附着上GPRS网络，true为是，false或者nil为否
local gprsAttached
--是否有socket连接上后台，true为是，false或者nil为否
local socketConnected

--[[网络指示灯表示的工作状态
NULL：功能关闭状态
FLYMODE：飞行模式
SIMERR：未检测到SIM卡或者SIM卡锁pin码等SIM卡异常
IDLE：未注册GSM网络
GSM：已注册GSM网络
GPRS：已附着GPRS数据网络
SCK：socket已连接上后台]]
local ledState = "NULL"
local ON,OFF = 1,2
--[[各种工作状态下配置的点亮、熄灭时长（单位毫秒）]]
local ledBlinkTime =
{
    NULL = {0,0xFFFF},  --[[常灭]]
    FLYMODE = {0,0xFFFF},  --[[常灭]]
    SIMERR = {300,5700},  --[[亮300毫秒，灭5700毫秒]]
    IDLE = {300,3700},  --[[亮300毫秒，灭3700毫秒]]
    GSM = {300,1700},  --[[亮300毫秒，灭1700毫秒]]
    GPRS = {300,700},  --[[亮300毫秒，灭700毫秒]]
    SCK = {100,100},  --[[亮100毫秒，灭100毫秒]]
}

--[[网络指示灯开关，true为打开，false或者nil为关闭]]
local ledSwitch = false
--[[网络指示灯默认PIN脚（GPIO27）]]
local LEDPIN = 27
--[[LTE指示灯开关，true为打开，false或者nil为关闭]]
local lteSwitch = false
--[[LTE指示灯默认PIN脚（GPIO26）]]
local LTEPIN = 26


--[[
模块功能：更新网络指示灯表示的工作状态
参数：无
返回值：无
]]
local function updateState()
    log.info("netLed.updateState",ledSwitch,ledState,flyMode,simError,gsmRegistered,gprsAttached,socketConnected)
    if ledSwitch then
        local newState = "IDLE"
        if flyMode then
            newState = "FLYMODE"
        elseif simError then
            newState = "SIMERR"
        elseif socketConnected then
            newState = "SCK"
        elseif gprsAttached then
            newState = "GPRS"
        elseif gsmRegistered then
            newState = "GSM"	
        end
        --指示灯状态发生变化
        if newState~=ledState then
            ledState = newState
            sys.publish("NET_LED_UPDATE")
        end
    end
end

--[[
模块功能：网络指示灯模块的运行任务
参数：
       ledPinSetFunc：指示灯GPIO的设置函数
返回值：无
]]
local function taskLed(ledPinSetFunc)
    while true do
        --log.info("netLed.taskLed",ledPinSetFunc,ledSwitch,ledState)
        if ledSwitch then
            local onTime,offTime = ledBlinkTime[ledState][ON],ledBlinkTime[ledState][OFF]
            if onTime>0 then
                ledPinSetFunc(1)
                if not sys.waitUntil("NET_LED_UPDATE", onTime) then
                    if offTime>0 then
                        ledPinSetFunc(0)
                        sys.waitUntil("NET_LED_UPDATE", offTime)
                    end
                end
            else if offTime>0 then
                    ledPinSetFunc(0)
                    sys.waitUntil("NET_LED_UPDATE", offTime)
                end
            end            
        else
            ledPinSetFunc(0)
            break
        end
    end
end

--[[
模块功能：LTE指示灯模块的运行任务
参数：
       ledPinSetFunc：指示灯GPIO的设置函数
 返回值：无
]]
local function taskLte(ledPinSetFunc)
    while true do
        local _,arg = sys.waitUntil("LTE_LED_UPDATE")
        if lteSwitch then
            ledPinSetFunc(arg and 1 or 0)
        end
    end
end

--[[配置网络指示灯和LTE指示灯并且立即执行配置后的动作
@bool flag 是否打开网络指示灯和LTE指示灯功能，true为打开，false为关闭
@number ledPin 控制网络指示灯闪烁的GPIO引脚，例如pio.P0_1表示GPIO1
@number ltePin 控制LTE指示灯闪烁的GPIO引脚，例如pio.P0_4表示GPIO4
@return nil
@usage setup(true,26,27)表示打开网络指示灯和LTE指示灯功能，GPIO27控制网络指示灯，GPIO26控制LTE指示灯
@usage setup(false)表示关闭网络指示灯和LTE指示灯功能]]
function netLed.setup(flag,ledPin,ltePin)
    --log.info("netLed.setup",flag,pin,ledSwitch)    
    local oldSwitch = ledSwitch
    if flag~=ledSwitch then
        ledSwitch = flag
        sys.publish("NET_LED_UPDATE")
    end
    if flag and not oldSwitch then
        sys.taskInit(taskLed, gpio.setup(ledPin or LEDPIN, 0))
    end
    if flag~=lteSwitch then
        lteSwitch = flag	
    end  
    if flag and ltePin and not oldSwitch then
        sys.taskInit(taskLte, gpio.setup(ltePin, 0))  
    end	
end

--[[配置某种工作状态下指示灯点亮和熄灭的时长（如果用户不配置，使用netLed.lua中ledBlinkTime配置的默认值）
@string state 某种工作状态，仅支持"FLYMODE"、"SIMERR"、"IDLE"、"GSM"、"GPRS"、"SCK"
@number on 指示灯点亮时长，单位毫秒，0xFFFF表示常亮，0表示常灭
@number off 指示灯熄灭时长，单位毫秒，0xFFFF表示常灭，0表示常亮
@return nil
@usage updateBlinkTime("FLYMODE",1000,500)表示飞行模式工作状态下，指示灯闪烁规律为：亮1秒，灭0.5秒
@usage updateBlinkTime("SCK",0xFFFF,0)表示有socket连接上后台的工作状态下，指示灯闪烁规律为：常亮
@usage updateBlinkTime("SIMERR",0,0xFFFF)表示SIM卡异常状态下，指示灯闪烁规律为：常灭]]
function netLed.updateBlinkTime(state,on,off)
    if not ledBlinkTime[state] then log.error("netLed.updateBlinkTime") return end    
    local updated
    if on and ledBlinkTime[state][ON]~=on then
        ledBlinkTime[state][ON] = on
        updated = true
    end
    if off and ledBlinkTime[state][OFF]~=off then
        ledBlinkTime[state][OFF] = off
        updated = true
    end
    --log.info("netLed.updateBlinkTime",state,on,off,updated)
    if updated then sys.publish("NET_LED_UPDATE") end
end

--[[ 呼吸灯
@function ledPin 呼吸灯的ledPin(1)用pins.setup注册返回的方法
@return nil
@usage led.breateLed(ledPin)
@usage 调用函数需要使用任务支持]]
function netLed.breateLed(ledPin)
    -- [[呼吸灯的状态、PWM周期]]
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

sys.subscribe("FLYMODE", function(mode) if flyMode~=mode then flyMode=mode updateState() end end)
sys.subscribe("SIM_IND", function(para) if simError~=(para~="RDY") then simError=(para~="RDY") updateState() end end)
sys.subscribe("IP_CLOSE", function() if gsmRegistered then gsmRegistered=false updateState() end end)
sys.subscribe("IP_READY", function() if not gsmRegistered then gsmRegistered=true updateState() end end)
sys.subscribe("IP_READY", function(attach) if gprsAttached~=attach then gprsAttached=attach updateState() end end)
sys.subscribe("SOCKET_ACTIVE", function(active) if socketConnected~=active then socketConnected=active updateState() end end)
--[[sys.subscribe("NET_UPD_NET_MODE", function() if lteSwitch then sys.publish("LTE_LED_UPDATE",net.getNetMode()==net.NetMode_LTE) end end)]]


return netLed