
--[[

8. Air8000内部ADC接口为12bits 外部直流分压为0-3.4V
9. Air8000内部具有2个ADC接口，ADC0 -- AIO3 ADC1 -- AIO4
10. 特殊通道, CPU内部温度Temp -- adc.CH_CPU 主供电脚电压 VBAT -- adc.CH_VBAT
11. 设置分压(adc.setRange)要在adc.open之前设置，否则无效!!
]]

local testAdc = {}

-- adc.setRange(adc.ADC_RANGE_1_2) -- 关闭分压
adc.setRange(adc.ADC_RANGE_MAX) -- 启用分压

local rtos_bsp = rtos.bsp()
function adc_pin() -- 根据不同开发板，设置ADC编号
    log.info("main", "define ADC pin in main.lua")
    return 0,1,255,255, adc.CH_CPU ,adc.CH_VBAT
end
local adc_pin_0,adc_pin_1,adc_pin_2,adc_pin_3,adc_pin_temp,adc_pin_vbat=adc_pin()


function testAdc.dotest()
    if adc_pin_0 and adc_pin_0 ~= 255 then adc.open(adc_pin_0) end
    if adc_pin_1 and adc_pin_1 ~= 255 then adc.open(adc_pin_1) end
    if adc_pin_2 and adc_pin_2 ~= 255 then adc.open(adc_pin_2) end
    if adc_pin_3 and adc_pin_3 ~= 255 then adc.open(adc_pin_3) end
    if adc_pin_temp and adc_pin_temp ~= 255 then adc.open(adc_pin_temp) end
    if adc_pin_vbat and adc_pin_vbat ~= 255 then adc.open(adc_pin_vbat) end

    -- 下面是循环打印, 接地不打印0也是正常现象
    -- ADC的精度都不会太高, 若需要高精度ADC, 建议额外添加adc芯片
    while true do
        if adc_pin_0 and adc_pin_0 ~= 255 then --adc0
            log.debug("adc", "adc" .. tostring(adc_pin_0), adc.read(adc_pin_0)) -- 若adc.get报nil, 改成adc.read
        end
        if adc_pin_1 and adc_pin_1 ~= 255 then --adc1
            log.debug("adc", "adc" .. tostring(adc_pin_1), adc.get(adc_pin_1))
        end
        if adc_pin_temp and adc_pin_temp ~= 255 then
            log.debug("adc", "CPU TEMP", adc.get(adc_pin_temp))
        end
        if adc_pin_vbat and adc_pin_vbat ~= 255 then
            log.debug("adc", "VBAT", adc.get(adc_pin_vbat))
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
