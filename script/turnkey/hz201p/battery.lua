function voltage_to_percentage(voltage)
    local min_voltage = 3600
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
    repeat
        local voltage = adc.get(adc.CH_VBAT)
        local percentage = voltage_to_percentage(voltage)
        log.info("battery", "voltage:", voltage, "percentage:", percentage)
        --低于3.3V时，关机
        if voltage < 3300 then
            pm.shutdown()
        end
        attributes.set("battery", percentage)
        attributes.set("vbat", voltage)
        sys.wait(60000)
    until nil
end)

--充电状态检测
local function chargeCheck()
    log.info("chargeCheck", gpio.get(42))
    attributes.set("isCharging", gpio.get(42) == 0)
end
gpio.setup(42, chargeCheck, 0, gpio.BOTH)
attributes.set("isCharging", gpio.get(42) == 0)

local function exitSleepMode()
    pm.power(pm.WORK_MODE, 0)--退出休眠模式
    --上报所有参数
    sys.timerStart(attributes.setAll, 6000)
    --重启一下
    --pm.reboot()
end

sys.subscribe("SLEEP_CMD_RECEIVED", function(on)
    if on then
        log.info("battery","enter sleepMode wait")
        pm.power(pm.WORK_MODE, 1)--进入休眠模式
    else
        log.info("battery","exit sleepMode wait")
        exitSleepMode()
    end
end)

sys.subscribe("POWERKEY_PRESSED", function()
    log.info("battery","POWERKEY_PRESSED")
    if attributes.get("sleepMode") then
        attributes.set("sleepMode", false)
        exitSleepMode()
    end
end)
