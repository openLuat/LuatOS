-- LuaTools需要PROJECT和VERSION这两个信息
-- Air101，Air103 模块上的ADC0脚-PA1, 0~2.4v,不要超过范围使用!!!
-- Air101，Air103模块上的ADC1脚-PA4, 0~2.4v,不要超过范围使用!!!
-- Air103 模块上的ADC2脚-PA2, 0~2.4v,不要超过范围使用!!! 
-- Air103 模块上的ADC3脚-PA3, 0~2.4v,不要超过范围使用!!! 
-- Air101,Air103 ADC10 为内部温度 ，11为VBAT
-- Air105 adc参考电压是1.88V，所有通道一致，
-- Air105内部分压没有隔离措施，在开启内部分压后，量程有所变化，具体看寄存器手册，1~5分压后能测到3.6，6通道能接近5V，但是不能直接测5V，可以测4.2V 0通道是始终开启无法关闭分压。
-- Air780E内部ADC接口为12bits 外部直流分压为0-3.4V
-- Air780E内部具有2个ADC接口，ADC0 -- AIO3 ADC1 -- AIO4 
-- Temp -- 10 VBAT -- 11
PROJECT = "adcdemo"
VERSION = "1.0.0"

log.info("main", PROJECT, VERSION)

-- 一定要添加sys.lua !!!!
sys = require("sys")

-- 添加硬狗防止程序卡死
if wdt then
    wdt.init(9000) -- 初始化watchdog设置为9s
    sys.timerLoopStart(wdt.feed, 3000) -- 3s喂一次狗
end
local rtos_bsp = rtos.bsp()
function adc_pin() -- 根据不同开发板，设置ADC编号
    if rtos_bsp == "AIR101" then -- Air101开发板ADC编号
        return 0,1,255,255,10,11
    elseif rtos_bsp == "AIR103" then -- Air103开发板ADC编号
        return 0,1,2,3,10,11
    elseif rtos_bsp == "AIR105" then -- Air105开发板ADC编号
        return 0,5,6,255,255,255
    elseif rtos_bsp == "ESP32C3" then -- ESP32C3开发板ADC编号
        return 0,1,2,3,4,10 
    elseif rtos_bsp == "EC618" then --Air780E开发板ADC编号
        return 0,1,255,255,10,11 --
    else
        log.info("main", "define ADC pin in main.lua")
        return 0, 0,0,0,0,0
    end
end
local adc_pin_0,adc_pin_1,adc_pin_2,adc_pin_3,adc_pin_4,adc_pin_5=adc_pin()
sys.taskInit(function()
    if rtos_bsp == "AIR105" then
        adc.setRange(adc.ADC_RANGE_3_6) --开启的内部分压，可以把量程扩大
    end
    if adc_pin_0 and adc_pin_0 ~= 255 then adc.open(adc_pin_0) end
    if adc_pin_1 and adc_pin_1 ~= 255 then adc.open(adc_pin_1) end
    if adc_pin_2 and adc_pin_2 ~= 255 then adc.open(adc_pin_2) end
    if adc_pin_3 and adc_pin_3 ~= 255 then adc.open(adc_pin_3) end
    if adc_pin_4 and adc_pin_4 ~= 255 then adc.open(adc_pin_4) end
    if adc_pin_5 and adc_pin_5 ~= 255 then adc.open(adc_pin_5) end
    while true do
        if adc_pin_0 and adc_pin_0 ~= 255 then
            log.debug("adc", "adc" .. tostring(adc_pin_0), adc.read(adc_pin_0))
        end
        if adc_pin_1 and adc_pin_1 ~= 255 then
            log.debug("adc", "adc" .. tostring(adc_pin_1), adc.read(adc_pin_1))
        end
        if adc_pin_2 and adc_pin_2 ~= 255 then
            log.debug("adc", "adc" .. tostring(adc_pin_2), adc.read(adc_pin_2))
        end
        if adc_pin_3 and adc_pin_3 ~= 255 then
            log.debug("adc", "adc" .. tostring(adc_pin_3), adc.read(adc_pin_3))
        end
        if adc_pin_4 and adc_pin_4 ~= 255 then
            log.debug("adc", "adc" .. tostring(adc_pin_4), adc.read(adc_pin_4))
        end
        if adc_pin_5 and adc_pin_5 ~= 255 then
            log.debug("adc", "adc" .. tostring(adc_pin_5), adc.read(adc_pin_5))
        end
        sys.wait(500)
    end

    if adc_pin_0 and adc_pin_0 ~= 255 then adc.close(adc_pin_0) end
    if adc_pin_1 and adc_pin_1 ~= 255 then adc.close(adc_pin_1) end
    if adc_pin_2 and adc_pin_2 ~= 255 then adc.close(adc_pin_2) end
    if adc_pin_3 and adc_pin_3 ~= 255 then adc.close(adc_pin_3) end
    if adc_pin_4 and adc_pin_4 ~= 255 then adc.close(adc_pin_4) end
    if adc_pin_5 and adc_pin_5 ~= 255 then adc.close(adc_pin_5) end

end)
-- 用户代码已结束---------------------------------------------
-- 结尾总是这一句
sys.run()
-- sys.run()之后后面不要加任何语句!!!!!