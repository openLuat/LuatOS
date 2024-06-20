function voltage_to_percentage(voltage)
    local min_voltage = 3400
    local max_voltage = 4190

    if voltage <= min_voltage then
        return 0
    elseif voltage >= max_voltage then
        return 100
    else
        local percentage = (voltage - min_voltage) / (max_voltage - min_voltage) * 100
        return math.floor(percentage + 0.5) -- 四舍五入
    end
end

adc.open(adc.CH_VBAT)
sys.taskInit(function ()
    while true do
        local voltage = adc.get(adc.CH_VBAT)
        local percentage = voltage_to_percentage(voltage)
        log.info("battery", "voltage:", voltage, "percentage:", percentage)
        attributes.set("battery", percentage)
        attributes.set("vbat", voltage)
        sys.wait(60000)
    end
end)
