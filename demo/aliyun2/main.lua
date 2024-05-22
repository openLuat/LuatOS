--[[
本demo是演示aliyun2模块的使用，使用该模块可以连接阿里云物联网平台
注意与aliyun库的差异

TODO 本demo当前还不是很完整, 后续继续改造
]]
PROJECT = "aliyundemo"
VERSION = "1.0.0"

local sys = require "sys"
local aliyun2 = require "aliyun2"

if fskv then
    fskv.init()
end

local rtos_bsp = rtos.bsp()
function pinx() -- 根据不同开发板，给LED赋值不同的gpio引脚编号
    if rtos_bsp == "AIR101" then -- Air101开发板LED引脚编号
        return pin.PB08, pin.PB09, pin.PB10
    elseif rtos_bsp == "AIR103" then -- Air103开发板LED引脚编号
        return pin.PB26, pin.PB25, pin.PB24
    elseif rtos_bsp == "AIR601" then -- Air103开发板LED引脚编号
        return pin.PA7, 255, 255
    elseif rtos_bsp == "AIR105" then -- Air105开发板LED引脚编号
        return pin.PD14, pin.PD15, pin.PC3
    elseif rtos_bsp == "ESP32C3" then -- ESP32C3开发板的引脚
        return 12, 13, 255 -- 开发板上就2个灯
    elseif rtos_bsp == "ESP32S3" then -- ESP32C3开发板的引脚
        return 10, 11, 255 -- 开发板上就2个灯
    elseif rtos_bsp == "EC618" then -- Air780E开发板引脚
        return 27, 255, 255 -- AIR780E开发板上就一个灯
    elseif rtos_bsp == "EC718P" then -- Air780E开发板引脚
        return 27, 255, 255 -- AIR780EP开发板上就一个灯
    elseif rtos_bsp == "UIS8850BM" then -- Air780UM开发板引脚
        return 36, 255, 255 -- Air780UM开发板上就一个灯
    else
        log.info("main", "define led pin in main.lua")
        return 0, 0, 0
    end
end


--LED引脚判断赋值结束

local P1,P2,P3=pinx()--赋值开发板LED引脚编号
local LEDA= gpio.setup(P1, 0, gpio.PULLUP)
-- local LEDB= gpio.setup(P2, 0, gpio.PULLUP)
-- local LEDC= gpio.setup(P3, 0, gpio.PULLUP)

sys.taskInit(function()
    sys.waitUntil("IP_READY")
    local ali = aliyun2.create({
        productKey = "a1QPg8JEj02",
        deviceName = "869300038718048",
        -- deviceSecret = "8837e03c52650fde37614fd078cac6e9",
        productSecret = "tHqlKgc2Evq5V2m1",
        regnwl = true
    })
    if ali and aliyun2.start(ali) then
        while 1 do
            local result, event, data, payload = sys.waitUntil(ali.topic, 30000)
            if result then
                log.info("aliyun", "event", event, data)
                if event == "ota" then
                    log.info("aliyun", "ota", data.url)
                elseif event == "recv" then
                    if data == ali.sub_topics.down_raw then
                        log.info("aliyun", "下行的透传信息", data)
                    elseif data == ali.sub_topics.property_set then
                        log.info("aliyun2", "属性设置")
                        local jdata = json.decode(payload)
                        if jdata and jdata.params then
                            if jdata.params.LEDSwitch then
                                if jdata.params.LEDSwitch == 0 then
                                    log.info("aliyun2", "关闭LEDA")
                                    if LEDA then
                                        LEDA(0)
                                    end
                                else
                                    log.info("aliyun2", "打开LEDA")
                                    if LEDA then
                                        LEDA(1)
                                    end
                                end
                            end
                        end
                    end
                end
            end
        end
    end
end)

-- 用户代码已结束---------------------------------------------
-- 结尾总是这一句
sys.run()
-- sys.run()之后后面不要加任何语句!!!!!
