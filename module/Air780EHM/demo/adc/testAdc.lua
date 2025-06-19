
--[[
1. Air101，Air103 模块上的ADC0脚-PA1, 0~2.4v,不要超过范围使用!!!
2. Air101，Air103模块上的ADC1脚-PA4, 0~2.4v,不要超过范围使用!!!
3. Air103 模块上的ADC2脚-PA2, 0~2.4v,不要超过范围使用!!! 
4. Air103 模块上的ADC3脚-PA3, 0~2.4v,不要超过范围使用!!! 
5. Air101,Air103 adc.CH_CPU 为内部温度 ，adc.CH_VBAT为VBAT
6. Air105 adc参考电压是1.88V，所有通道一致，
7. Air105内部分压没有隔离措施，在开启内部分压后，量程有所变化，具体看寄存器手册，1~5分压后能测到3.6，6通道能接近5V，但是不能直接测5V，可以测4.2V 0通道是始终开启无法关闭分压。
8. Air780E内部ADC接口为12bits 外部直流分压为0-3.4V
9. Air780E内部具有2个ADC接口，ADC0 -- AIO3 ADC1 -- AIO4 
10. 特殊通道, CPU内部温度Temp -- adc.CH_CPU 主供电脚电压 VBAT -- adc.CH_VBAT
11. 设置分压(adc.setRange)要在adc.open之前设置，否则无效!!
]]

local testAdc = {}

function adc_pin()
    --Air780EPM开发板ADC编号
    -- 默认不开启分压,范围是0-1.1v精度高
    -- 开启分压后，外部输入最大不可超过3.3V
    -- 设置分压要在adc.open之前设置，否则无效!!
    -- adc.setRange(adc.ADC_RANGE_MAX)
    return 0,1,255,255,adc.CH_CPU ,adc.CH_VBAT
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
