
--[[
1. Air8101内部ADC接口精度为12bits 外部直流分压为0-2.4V
2. Air8101内部具有6个ADC接口通道，ADC1对应ADC10，ADC2对应ADC12，ADC3对应13，ADC4对应ADC14，ADC5对应ADC15，ADC6 
3. 特殊通道, CPU内部温度Temp -- adc.CH_CPU 主供电脚电压 VBAT -- adc.CH_VBAT
]]

local testAdc = {}

local rtos_bsp = rtos.bsp()
function adc_pin()
    if rtos_bsp == "Air8101" then
        return 1,2,3,4,5,6,10,12,13,14,15,adc.CH_CPU ,adc.CH_VBAT 
    else
        log.info("main", "bsp not Air8101!!!")
        return 255,255,255,255,255,255,255,255,255,255,255, adc.CH_CPU ,adc.CH_VBAT 
    end
end

local adc_pin_1,adc_pin_2,adc_pin_3,adc_pin_4,adc_pin_5,adc_pin_6,adc_pin_10,adc_pin_12,
adc_pin_13,adc_pin_14,adc_pin_15,adc_pin_temp,adc_pin_vbat=adc_pin()

function testAdc.dotest()
    
    if adc_pin_1 and adc_pin_1 ~= 255 then adc.open(adc_pin_1) end
    if adc_pin_2 and adc_pin_2 ~= 255 then adc.open(adc_pin_2) end
    if adc_pin_3 and adc_pin_3 ~= 255 then adc.open(adc_pin_3) end
    if adc_pin_4 and adc_pin_4 ~= 255 then adc.open(adc_pin_4) end
    if adc_pin_5 and adc_pin_5 ~= 255 then adc.open(adc_pin_5) end
    if adc_pin_6 and adc_pin_6 ~= 255 then adc.open(adc_pin_6) end
    -- if adc_pin_10 and adc_pin_10 ~= 255 then adc.open(adc_pin_10) end
    -- if adc_pin_12 and adc_pin_12 ~= 255 then adc.open(adc_pin_12) end
    -- if adc_pin_13 and adc_pin_13 ~= 255 then adc.open(adc_pin_13) end
    -- if adc_pin_14 and adc_pin_14 ~= 255 then adc.open(adc_pin_14) end
    -- if adc_pin_15 and adc_pin_15 ~= 255 then adc.open(adc_pin_15) end
    if adc_pin_temp and adc_pin_temp ~= 255 then adc.open(adc_pin_temp) end
    if adc_pin_vbat and adc_pin_vbat ~= 255 then adc.open(adc_pin_vbat) end

    if adc_pin_1 and adc_pin_1 ~= 255 and mcu and mcu.ticks then
        sys.wait(1000)
        log.info("开始读取ADC")
        local ms_start = mcu.ticks()
        for i = 1, 100, 1 do
            adc.get(adc_pin_1)
        end
        local ms_end = mcu.ticks()
        log.info("结束读取ADC")
        log.info("adc", "读取耗时", "100次", ms_end - ms_start, "ms", "单次", (ms_end - ms_start) // 100, "ms")
    end

    -- 下面是循环打印, 接地不打印0也是正常现象
    -- ADC的精度都不会太高, 若需要高精度ADC, 建议额外添加adc芯片
    while true do
        if adc_pin_1 and adc_pin_1 ~= 255 then
            log.debug("adc", "adc" .. tostring(adc_pin_1), adc.get(adc_pin_1))
        end
        if adc_pin_2 and adc_pin_2 ~= 255 then
            log.debug("adc", "adc" .. tostring(adc_pin_2), adc.get(adc_pin_2))
        end
        if adc_pin_3 and adc_pin_3 ~= 255 then
            log.debug("adc", "adc" .. tostring(adc_pin_3), adc.get(adc_pin_3))
        end
        if adc_pin_4 and adc_pin_4 ~= 255 then
            log.debug("adc", "adc" .. tostring(adc_pin_4), adc.get(adc_pin_4)) -- 若adc.get报nil, 改成adc.read
        end
        if adc_pin_5 and adc_pin_5 ~= 255 then
            log.debug("adc", "adc" .. tostring(adc_pin_5), adc.get(adc_pin_5))
        end
        if adc_pin_6 and adc_pin_6 ~= 255 then
            log.debug("adc", "adc" .. tostring(adc_pin_6), adc.get(adc_pin_6))
        end
        -- ADC通道1~5和10~15是共用的，使用其中一个要关闭另一个
        -- if adc_pin_10 and adc_pin_10 ~= 255 then
        --     log.debug("adc", "adc" .. tostring(adc_pin_10), adc.get(adc_pin_10))
        -- end
        -- if adc_pin_12 and adc_pin_12 ~= 255 then
        --     log.debug("adc", "adc" .. tostring(adc_pin_12), adc.get(adc_pin_12)) -- 若adc.get报nil, 改成adc.read
        -- end
        -- if adc_pin_13 and adc_pin_13 ~= 255 then
        --     log.debug("adc", "adc" .. tostring(adc_pin_13), adc.get(adc_pin_13))
        -- end
        -- if adc_pin_14 and adc_pin_14 ~= 255 then
        --     log.debug("adc", "adc" .. tostring(adc_pin_14), adc.get(adc_pin_14))
        -- end
        -- if adc_pin_15 and adc_pin_15 ~= 255 then
        --     log.debug("adc", "adc" .. tostring(adc_pin_15), adc.get(adc_pin_15)) -- 若adc.get报nil, 改成adc.read
        -- end
        if adc_pin_temp and adc_pin_temp ~= 255 then
            log.debug("adc", "CPU TEMP", adc.get(adc_pin_temp))
        end
        if adc_pin_vbat and adc_pin_vbat ~= 255 then
            log.debug("adc", "VBAT", adc.get(adc_pin_vbat))
        end
        sys.wait(1000)
    end

    -- 若不再读取, 可关掉adc, 降低功耗, 非必须
    if adc_pin_1 and adc_pin_1 ~= 255 then adc.close(adc_pin_1) end
    if adc_pin_2 and adc_pin_2 ~= 255 then adc.close(adc_pin_2) end
    if adc_pin_3 and adc_pin_3 ~= 255 then adc.close(adc_pin_3) end
    if adc_pin_4 and adc_pin_4 ~= 255 then adc.close(adc_pin_4) end
    if adc_pin_5 and adc_pin_5 ~= 255 then adc.close(adc_pin_5) end
    if adc_pin_6 and adc_pin_6 ~= 255 then adc.close(adc_pin_6) end
    if adc_pin_10 and adc_pin_10 ~= 255 then adc.close(adc_pin_10) end
    if adc_pin_12 and adc_pin_12 ~= 255 then adc.close(adc_pin_12) end
    if adc_pin_13 and adc_pin_13 ~= 255 then adc.close(adc_pin_13) end
    if adc_pin_14 and adc_pin_14 ~= 255 then adc.close(adc_pin_14) end
    if adc_pin_15 and adc_pin_15 ~= 255 then adc.close(adc_pin_15) end
    if adc_pin_temp and adc_pin_temp ~= 255 then adc.close(adc_pin_temp) end
    if adc_pin_vbat and adc_pin_vbat ~= 255 then adc.close(adc_pin_vbat) end

end

return testAdc
