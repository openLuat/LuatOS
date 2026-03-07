sys.taskInit(function()
    sys.wait(2000)
    log.info("780EPM开发板adc通道测试")
    adc.setRange(adc.ADC_RANGE_MAX) -- 设置内部分压到3.6V，需要用2004版本固件

    while true do
        -- -- 遍历ADC通道
        for i = 0, 3 do
            if adc.open(i) then
                local voltage = adc.get(i)
                log.info("adc" .. i .. "当前电压", voltage, "mV")
                -- sys.wait(1000)
            else
                log.info("adc" .. i .. "打开失败")
            end
        end

        -- 获取CPU温度
        if adc.open(adc.CH_CPU) then
            local cpuTemp = adc.get(adc.CH_CPU)
            log.info("CPU当前温度", cpuTemp / 1000, "℃")
        end

        -- 获取VBAT电压
        if adc.open(adc.CH_VBAT) then
            local vbatVoltage = adc.get(adc.CH_VBAT)
            log.info("vbat当前电压", vbatVoltage, "mV")
        end

        sys.wait(2000)
    end
end)
