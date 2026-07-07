
--[[
1. 各 BSP ADC 通道数与参考电压不同, 请按芯片手册查阅
2. 设置分压(adc.setRange)要在adc.open之前设置，否则无效!!
3. 特殊通道: CPU 内部温度 adc.CH_CPU, 主供电脚电压 adc.CH_VBAT
]]

local testAdc = {}

local rtos_bsp = rtos.bsp()
function adc_pin() -- 根据不同开发板，设置ADC编号
    if rtos_bsp == "ESP32C3" then -- ESP32C3开发板ADC编号
        return 0,1,2,3,adc.CH_CPU , 255
    elseif rtos_bsp == "ESP32C2" then -- ESP32C2开发板ADC编号
        return 0,1,2,3,adc.CH_CPU , 255
    elseif rtos_bsp == "ESP32S3" then -- ESP32S3开发板ADC编号
        return 0,1,2,3,adc.CH_CPU , 255
    elseif rtos_bsp == "EC618" then --Air780E开发板ADC编号
        -- 默认不开启分压,范围是0-1.2v精度高
        -- 设置分压要在adc.open之前设置，否则无效!!
        -- adc.setRange(adc.ADC_RANGE_3_8)
        return 0,1,255,255,adc.CH_CPU ,adc.CH_VBAT
    elseif string.find(rtos_bsp,"EC718") then --Air780EP开发板ADC编号
        -- 默认不开启分压,范围是0-1.6v精度高
        -- 开启分压后，外部输入最大不可超过3.3V
        -- 设置分压要在adc.open之前设置，否则无效!!
        -- adc.setRange(adc.ADC_RANGE_MAX)
        return 0,1,255,255,adc.CH_CPU ,adc.CH_VBAT
    elseif string.find(rtos_bsp,"UIS") then
        return 0,1,255,255, adc.CH_CPU ,adc.CH_VBAT
    else
        log.info("main", "define ADC pin in main.lua")
        return 255,255,255,255, adc.CH_CPU ,adc.CH_VBAT
    end
end
local adc_pin_0,adc_pin_1,adc_pin_2,adc_pin_3,adc_pin_temp,adc_pin_vbat=adc_pin()


function testAdc.dotest()
    if adc_pin_0 and adc_pin_0 ~= 255 then adc.open(adc_pin_0) end
    if adc_pin_1 and adc_pin_1 ~= 255 then adc.open(adc_pin_1) end
    if adc_pin_2 and adc_pin_2 ~= 255 then adc.open(adc_pin_2) end
    if adc_pin_3 and adc_pin_3 ~= 255 then adc.open(adc_pin_3) end
    if adc_pin_temp and adc_pin_temp ~= 255 then adc.open(adc_pin_temp) end
    if adc_pin_vbat and adc_pin_vbat ~= 255 then adc.open(adc_pin_vbat) end

    if adc_pin_0 and adc_pin_0 ~= 255 and mcu and mcu.ticks then
        sys.wait(1000)
        log.info("开始读取ADC")
        local ms_start = mcu.ticks()
        for i = 1, 100, 1 do
            adc.get(adc_pin_0)
        end
        local ms_end = mcu.ticks()
        log.info("结束读取ADC")
        log.info("adc", "读取耗时", "100次", ms_end - ms_start, "ms", "单次", (ms_end - ms_start) // 100, "ms")
    end

    -- 下面是循环打印, 接地不打印0也是正常现象
    -- ADC的精度都不会太高, 若需要高精度ADC, 建议额外添加adc芯片
    while true do
        if adc_pin_0 and adc_pin_0 ~= 255 then
            log.debug("adc", "adc" .. tostring(adc_pin_0), adc.get(adc_pin_0)) -- 若adc.get报nil, 改成adc.read
        end
        if adc_pin_1 and adc_pin_1 ~= 255 then
            log.debug("adc", "adc" .. tostring(adc_pin_1), adc.get(adc_pin_1))
        end
        if adc_pin_2 and adc_pin_2 ~= 255 then
            log.debug("adc", "adc" .. tostring(adc_pin_2), adc.get(adc_pin_2))
        end
        if adc_pin_3 and adc_pin_3 ~= 255 then
            log.debug("adc", "adc" .. tostring(adc_pin_3), adc.get(adc_pin_3))
        end
        if adc_pin_temp and adc_pin_temp ~= 255 then
            log.debug("adc", "CPU TEMP", adc.get(adc_pin_temp), "单位0.001摄氏度")
        end
        if adc_pin_vbat and adc_pin_vbat ~= 255 then
            log.debug("adc", "VBAT", adc.get(adc_pin_vbat), "单位毫伏(mV)")
        end
        sys.wait(1000)
    end

    -- 若不再读取, 可关掉adc, 降低功耗, 非必须
    if adc_pin_0 and adc_pin_0 ~= 255 then adc.close(adc_pin_0) end
    if adc_pin_1 and adc_pin_1 ~= 255 then adc.close(adc_pin_1) end
    if adc_pin_2 and adc_pin_2 ~= 255 then adc.close(adc_pin_2) end
    if adc_pin_3 and adc_pin_3 ~= 255 then adc.close(adc_pin_3) end
    if adc_pin_temp and adc_pin_temp ~= 255 then adc.close(adc_pin_temp) end
    if adc_pin_vbat and adc_pin_vbat ~= 255 then adc.close(adc_pin_vbat) end

end

return testAdc
