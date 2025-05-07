log.info("测试模式", "启动中")
OTP_ZONE = 2

local paramTable = {
}
local es8311PowerPin = 25
local vbackup = gpio.setup(24, 0)
local uartRxCache = ""
local nowTransId
local usbRxCache = ""
local cacheTable = {}
local usbCacheTable = {}
local paPin = 23
local blueLed = gpio.setup(1, 0)
local redLed = gpio.setup(16, 0, nil, nil, 4)

pcb.gnssPower(false)

gpio.setup(paPin, 0)

pm.request(pm.IDLE)

local uartTrans = 1
local usbTrans = uart.VUART_0
local gnssUartId = 2
local gnssTransFlag = false

local Gsensori2cId = 0
local da267Addr = 0x26
local intPin = 39
local es8311i2cId = 0

local powerKeyTest = false

local recordPath = "/record.amr"

local function nmeaToUart1(id, len)
    local result
    while 1 do
        local data = uart.read(gnssUartId, len)
        if not data or #data == 0 then
            break
        end
        if gnssTransFlag then
            table.insert(cacheTable,{transId = nowTransId, data = data})
            sys.publish("DATA_SEND")
        end
    end
end

audio.on(0, function(id, event, buff)
    log.info("audio.on", id, event)
    -- 使用play来播放文件时只有播放完成回调
    if event == audio.RECORD_DATA then -- 录音数据

    elseif event == audio.RECORD_DONE then -- 录音完成
        sys.publish("AUDIO_RECORD_DONE")
    else
        local succ, stop, file_cnt = audio.getError(0)
        if not succ then
            if stop then
                log.info("用户停止播放")
            else
                log.info("第", file_cnt, "个文件解码失败")
            end
        end
        log.info("播放完成一个音频")
        sys.publish("AUDIO_PLAY_DONE")
    end
end)

sys.taskInit(function()
    mcu.altfun(mcu.I2C, Gsensori2cId, 23, 2, 0)
    mcu.altfun(mcu.I2C, Gsensori2cId, 24, 2, 0)
    mcu.altfun(mcu.I2C, es8311i2cId, 13, 2, 0)
    mcu.altfun(mcu.I2C, es8311i2cId, 14, 2, 0)
    local codecIsInit = false
    while true do
        local result, param1, param2 = sys.waitUntil("CONTROL")
        log.info("CONTROL", param1)
        if param1 == "RECORD" or param1 == "PLAY" then
            if not codecIsInit then
                codecIsInit = true
                es8311PowerPin = pcb.es8311PowerPin()
                i2c.setup(es8311i2cId, i2c.SLOW)
                i2s.setup(0, 0, 16000, 16, i2s.MONO_R, i2s.MODE_LSB, 16)
                audio.config(0, paPin, 1, 3, 100, es8311PowerPin, 1, 100)
                audio.setBus(0, audio.BUS_I2S, {
                    chip = "es8311",
                    i2cid = es8311i2cId,
                    i2sid = 0,
                    voltage = audio.VOLTAGE_1800
                }) -- 通道0的硬件输出通道设置为I2S
                audio.vol(0, 80)
                audio.micVol(0, 80)
                audio.pm(0, audio.POWEROFF)
            end
        end
        if param1 == "GNSS" then
            pcb.gnssPower(false)
            sys.wait(10)
            pcb.gnssPower(true)
        elseif param1 == "GSENSOR" then
            vbackup(1)
            sys.wait(50)
            i2c.setup(Gsensori2cId, i2c.SLOW)
            i2c.send(Gsensori2cId, da267Addr, 0x01, 1)
            local data = i2c.recv(Gsensori2cId, da267Addr, 1)
            if not data or data == "" or string.byte(data) ~= 0x13 then
                table.insert(cacheTable, {transId = param2, data = "ERROR#"})
            else
                table.insert(cacheTable, {transId = param2, data = "OK#"})
            end
            vbackup(0)
            i2c.close(Gsensori2cId)
            sys.publish("DATA_SEND")
        elseif param1 == "RECORD" then
            audio.pm(0, audio.RESUME)
            local err = audio.record(0, audio.AMR, 5, 7, recordPath)
            result = sys.waitUntil("AUDIO_RECORD_DONE", 10000)
            audio.pm(0, audio.POWEROFF)
            if result then
                table.insert(cacheTable, {transId = param2, data = "OK#"})
            else
                table.insert(cacheTable, {transId = param2, data = "ERROR#"})
            end
            sys.publish("DATA_SEND")
        elseif param1 == "PLAY" then
            local err = audio.play(0, recordPath)
            result = sys.waitUntil("AUDIO_PLAY_DONE", 10000)
            audio.pm(0, audio.POWEROFF)
            if result then
                table.insert(cacheTable, {transId = param2, data = "OK#"})
            else
                table.insert(cacheTable, {transId = param2, data = "ERROR#"})
            end
            sys.publish("DATA_SEND")
        end
    end
end)

local function powerOff()
    pm.shutdown()
end

local function powerKeyCb()
    if gpio.get(46) == 1 then
        if powerKeyTest then
            table.insert(cacheTable, {transId = nowTransId, data = "POWERKEY_RELEASE#"})
        end
        if sys.timerIsActive(powerOff) then
            sys.timerStop(powerOff)
        end
    else
        if powerKeyTest then
            table.insert(cacheTable, {transId = nowTransId, data = "POWERKEY_PRESS#"})
        end
        sys.timerStart(powerOff, 3000)
    end
    if powerKeyTest then
        sys.publish("DATA_SEND")
    end
end
gpio.debounce(46, 100)
gpio.setup(46, powerKeyCb, gpio.PULLUP, gpio.BOTH)

local procTable = {
    ["VERSION"] = function()
        return PROJECT .. "_" .. VERSION
    end,
    ["LED"] = function(id, findCom, data)
        local onoff = tonumber(data)
        if not onoff or onoff ~= 0 and onoff ~= 1 then
            return "ERROR"
        end
        blueLed(onoff)
        redLed(onoff)
        return "OK"
    end,
    ["IMEI"] = function(id, findCom, data)
        return mobile.imei()
    end,
    ["IMSI"] = function(id, findCom, data)
        return mobile.imsi()
    end,
    ["ICCID"] = function(id, findCom, data)
        return mobile.iccid()
    end,
    ["CSQ"] = function(id, findCom, data)
        return mobile.csq()
    end,
    ["MUID"] = function(id, findCom, data)
        return mobile.muid()
    end,
    ["GPSTEST"] = function(id, findCom, data)
        log.info("data", data)
        local item = "OK"
        if data == "0" then
            gnssTransFlag = false
            pcb.gnssPower(false)
            uart.on(gnssUartId, "receive")
            uart.close(gnssUartId)
        elseif data == "1" then
            gnssTransFlag = true
            uart.on(gnssUartId, "receive", nmeaToUart1)
            uart.setup(gnssUartId, 115200)
            pcb.gnssPower(true)
            sys.timerStart(uart.write, 500, gnssUartId, "$CFGTP,1000000,500000,7,0,800,0*7D\r\n")
        else
            item = "ERROR"
        end
        return item
    end,
    ["GPSDOWNLOAD"] = function(id, findCom, data)
        local item = "OK"
        if data == "0" then
            pcb.gnssPower(false)
            gpio.close(12)
            gpio.close(13)
        elseif data == "1" then
            gpio.setup(12)
            gpio.setup(13)
            sys.publish("CONTROL", "GNSS", id)
        else
            item = "ERROR"
        end
        return item
    end,
    ["GS_STATE"] = function(id, findCom, data)
        sys.publish("CONTROL", "GSENSOR", id)
        return
    end,
    ["RECORD"] = function(id, findCom, data)
        sys.publish("CONTROL", "RECORD", id)
        return
    end,
    ["PLAY"] = function(id, findCom, data)
        sys.publish("CONTROL", "PLAY", id)
        return
    end,
    ["POWERKEY"] = function(id, findCom, data)
        local onoff = tonumber(data)
        if not onoff or onoff ~= 0 and onoff ~= 1 then
            return "ERROR"
        end
        powerKeyTest = onoff == 1
        return "OK"
    end,
    ["ECNPICFG"] = function(id, findCom, data)
        mobile.nstOnOff(true, id)
        mobile.nstInput("AT+ECNPICFG?\r\n")
        mobile.nstInput(nil)
        mobile.nstOnOff(false, id)
        return
    end,
    ["VBAT"] = function(id, findCom, data)
        adc.open(adc.CH_VBAT)
        local vbat = adc.get(adc.CH_VBAT)
        adc.close(adc.CH_VBAT)
        return tostring(vbat)
    end,
    ["FLYMODE"] = function(id, findCom, data)
        local onoff = tonumber(data)
        if not onoff or onoff ~= 0 and onoff ~= 1 then
            return "ERROR"
        end
        mobile.flymode(0, onoff == 1)
        return "OK"
    end,
    ["GSENSORPWR"] = function(id, findCom, data)
        local onoff = tonumber(data)
        if not onoff or onoff ~= 0 and onoff ~= 1 then
            return "ERROR"
        end
        vbackup(onoff)
        return "OK"
    end,
    ["HVERSION"] = function(id, findCom, data)
        log.info("findcom?", id, findCom, data)
        if not findCom then
            return pcb.hver()
        end
        if not string.match(data, "^%d+%.%d+%.%d+$") then
            return "ERROR"
        end
        paramTable.pcb = data
        pcb.sethver(data)
        mobile.flymode(0, true)
        sys.taskInit(function()
            sys.wait(100)
            otp.erase(OTP_ZONE)
            local jsonData = json.encode(paramTable)
            otp.write(OTP_ZONE, string.char(string.len(jsonData)), 0)
            otp.write(OTP_ZONE, jsonData, 1)
            sys.timerStart(pm.reboot, 3000)
        end)
        return "OK"
    end,
    ["PCBA_TEST_DONE"] = function(id, findCom, data)
        sys.timerStart(pm.shutdown, 3000)
        return "OK"
    end,
    ["TEST_DONE"] = function(id, findCom, data)
        paramTable.test = 1
        paramTable.pcb = pcb.hver()
        mobile.flymode(0, true)
        sys.taskInit(function()
            sys.wait(100)
            local jsonData = json.encode(paramTable)
            log.info("测试模式", "写入OTP", jsonData)
            otp.erase(OTP_ZONE)
            otp.write(OTP_ZONE, string.char(string.len(jsonData)), 0)
            otp.write(OTP_ZONE, jsonData, 1)
            log.info("result", jsonData)
            sys.timerStart(pm.reboot, 3000)
        end)
        return "OK"
    end,
    ["CLEAR"] = function(id, findCom, data)
        paramTable.test = 1
        mobile.flymode(0, true)
        sys.taskInit(function()
            sys.wait(100)
            local jsonData = "{}"
            otp.erase(OTP_ZONE)
            otp.write(OTP_ZONE, string.char(string.len(jsonData)), 0)
            otp.write(OTP_ZONE, jsonData, 1)
            sys.timerStart(pm.reboot, 3000)
        end)
        return "OK"
    end
}

local function proc(id, data)
    nowTransId = id
    local h1, h2, cmd, findCom, text = nil, nil, nil, false, ""
    h1 = data:find("#")
    if not h1 then
        return false, data
    end
    text = data:sub(1, h1)
    h2 = string.find(text, ",")
    if h2 then
        cmd = string.sub(text, 1, h2 - 1)
        findCom = true
    else
        cmd = string.match(text, "(.+)#$")
    end
    log.info("cmd:", cmd, "text:", text)
    if procTable[cmd] then
        local reply = procTable[cmd](id, findCom, findCom and text:sub(h2 + 1, -2) or "")
        if reply then
            table.insert(cacheTable, {transId = id, data = reply .. "#"})
            sys.publish("DATA_SEND")
        end
    else
        table.insert(cacheTable, {transId = id, data = "ERROR#"})
        sys.publish("DATA_SEND")
    end
    return true, data:sub(h1 + 1)
end

uart.setup(uartTrans, 115200)
uart.setup(usbTrans, 115200)

uart.on(uartTrans, "receive", function(id, len)
    local result
    while 1 do
        local data = uart.read(uartTrans, 512)
        if not data or #data == 0 then
            break
        end
        uartRxCache = uartRxCache .. data
        while true do
            result, uartRxCache = proc(uartTrans, uartRxCache)
            if not result then
                break
            end
        end
    end
end)
uart.on(usbTrans, "receive", function(id, len)
    local result
    while 1 do
        local data = uart.read(usbTrans, 512)
        if not data or #data == 0 then
            break
        end
        usbRxCache = usbRxCache .. data
        while true do
            result, usbRxCache = proc(usbTrans, usbRxCache)
            if not result then
                break
            end
        end
    end
end)

uart.on(uartTrans, "sent", function(id)
    sys.publish("UART_SENT_DONE")
end)
uart.on(usbTrans, "sent", function(id)
    sys.publish("USB_SENT_DONE")
end)

sys.taskInit(function()
    while true do
        if #cacheTable > 0 then
            local data = table.remove(cacheTable, 1)
            if data.transId == uartTrans then
                uart.write(uartTrans, data.data)
                sys.waitUntil("UART_SENT_DONE")
            elseif data.transId == usbTrans then
                uart.write(usbTrans, data.data)
                sys.waitUntil("USB_SENT_DONE")
            end
        else
            sys.waitUntil("DATA_SEND")
        end
    end
end)


sys.taskInit(function()
    sys.wait(1000)
    while true do
        mobile.reqCellInfo(15)
        sys.waitUntil("CELL_INFO_UPDATE", 15000)
        sys.wait(180000)
    end
end)