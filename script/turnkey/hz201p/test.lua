local cacheTable = {}
local rxCache = ""

local vbackup = gpio.setup(24, 1)
local gnssReset = gpio.setup(27, 1)
local gnssEnvPower = gpio.setup(26, 1)
local es8311Power = gpio.setup(25, 1)
local gnssPower = gpio.setup(2, 1)
local blueLed = gpio.setup(1, 0)
local redLed = gpio.setup(16, 0, nil, nil, 4)

pm.request(pm.IDLE)


local transUartId = 1
if not fskv.get("pabaDone") then
    transUartId = 1
else
    transUartId = uart.VUART_0
end
local gnssUartId = 2
local gnssIsDownload = false
local gnssIsTrans = false
local gnssTransFlag = false
uart.setup(transUartId, 115200)

local Gsensori2cId = 1
local da267Addr = 0x26
local intPin = 39

local ES8311i2cId = 0

local function NMEA2UART1(id, len)
    local result
    while 1 do
        local data = uart.read(gnssUartId, len)
        if not data or #data == 0 then
            break
        end
        if gnssTransFlag then
            table.insert(cacheTable, data)
            sys.publish("UART1_SEND")
        end
    end
end

-- amr数据存放buffer，尽可能地给大一些
local amr_buff = zbuff.create(20 * 1024)
-- 创建一个amr的encoder
local encoder = nil

audio.on(0, function(id, event, buff)
    log.info("audio.on", id, event)
    -- 使用play来播放文件时只有播放完成回调
    if event == audio.RECORD_DATA then -- 录音数据
        codec.encode(encoder, buff, amr_buff)
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

local recordPath = "/record.amr"
sys.taskInit(function()
    mcu.altfun(mcu.I2C, Gsensori2cId, 23, 2, 0)
    mcu.altfun(mcu.I2C, Gsensori2cId, 24, 2, 0)
    mcu.altfun(mcu.I2C, ES8311i2cId, 13, 2, 0)
    mcu.altfun(mcu.I2C, ES8311i2cId, 14, 2, 0)
    local multimedia_id = 0
    local i2s_id = 0
    local i2s_mode = 0
    local i2s_sample_rate = 16000
    local i2s_bits_per_sample = 16
    local i2s_channel_format = i2s.MONO_R
    local i2s_communication_format = i2s.MODE_LSB
    local i2s_channel_bits = 16
    local pa_pin = 23
    local pa_on_level = 1
    local pa_delay = 100
    local power_pin = 255
    local power_on_level = 1
    local power_delay = 3
    local power_time_delay = 100
    local voice_vol = 100
    local mic_vol = 80
    local find_es8311 = false
    i2c.setup(Gsensori2cId, i2c.SLOW)
    i2c.setup(ES8311i2cId, i2c.FAST)
    if i2c.send(ES8311i2cId, 0x18, 0xfd) == true then
        find_es8311 = true
    end
    log.info("find_es8311?", find_es8311)
    i2s.setup(i2s_id, i2s_mode, i2s_sample_rate, i2s_bits_per_sample, i2s_channel_format, i2s_communication_format, i2s_channel_bits)
    audio.config(multimedia_id, pa_pin, pa_on_level, power_delay, pa_delay, power_pin, power_on_level, power_time_delay)
    audio.setBus(multimedia_id, audio.BUS_I2S, {
        chip = "es8311",
        i2cid = ES8311i2cId,
        i2sid = i2s_id,
        voltage = audio.VOLTAGE_1800
    }) -- 通道0的硬件输出通道设置为I2S
    audio.vol(multimedia_id, 80)
    audio.micVol(multimedia_id, 80)
    while true do
        local result, param1, param2, param3 = sys.waitUntil("CONTROL")
        log.info("CONTROL", param1, param2, param3)
        if param1 == "GNSS" then
            gnssReset(0)
            sys.wait(10)
            gnssReset(1)
        elseif param1 == "GSENSOR" then
            i2c.send(Gsensori2cId, da267Addr, 0x01, 1)
            local data = i2c.recv(Gsensori2cId, da267Addr, 1)
            if not data or data == "" or string.byte(data) ~= 0x13 then
                table.insert(cacheTable, "ERROR#")
            else
                table.insert(cacheTable, "OK#")
            end
            sys.publish("UART1_SEND")
        elseif param1 == "RECORD" then
            local err = audio.record(0, audio.AMR, 5, 7, recordPath)
            result = sys.waitUntil("AUDIO_RECORD_DONE", 10000)
            if result then
                table.insert(cacheTable, "OK#")
            else
                table.insert(cacheTable, "ERROR#")
            end
            sys.publish("UART1_SEND")
        elseif param1 == "PLAY" then
            local err = audio.play(0, recordPath)
            result = sys.waitUntil("AUDIO_PLAY_DONE", 10000)
            if result then
                table.insert(cacheTable, "OK#")
            else
                table.insert(cacheTable, "ERROR#")
            end
            sys.publish("UART1_SEND")
        end
    end
end)

local function powerKeyCb()
    if gpio.get(46) == 1 then
        table.insert(cacheTable, "POWERKEY_RELEASE#")
    else
        table.insert(cacheTable, "POWERKEY_PRESS#")
    end
    sys.publish("UART1_SEND")
end

local function proc(data)
    local item = nil
    local find = true
    local needNowReply = true
    local h = string.find(data, "#")
    if h then
        local cmd = string.sub(data, 1, h - 1)
        if string.find(cmd, "VERSION") then
            item = PROJECT .. "_" .. VERSION
        elseif string.find(cmd, "LED") then
            local onoff = string.match(cmd, "LED,(%d)")
            item = "OK"
            if onoff == "0" then
                blueLed(0)
                redLed(0)
            elseif onoff == "1" then
                blueLed(1)
                redLed(1)
            else
                item = "ERROR"
            end
        elseif string.find(cmd, "IMEI") then
            item = mobile.imei()
        elseif string.find(cmd, "IMSI") then
            item = mobile.imsi()
        elseif string.find(cmd, "ICCID") then
            item = mobile.iccid()
        elseif string.find(cmd, "CSQ") then
            item = mobile.csq()
        elseif string.find(cmd, "MUID") then
            item = mobile.muid()
        elseif string.find(cmd, "GPSTEST") then
            local onoff = string.match(cmd, "GPSTEST,(%d)")
            log.info("flag", onoff)
            item = "OK"
            if onoff == "0" then
                gnssTransFlag = false
                uart.close(gnssUartId)
            elseif onoff == "1" then
                gnssTransFlag = true
                uart.on(gnssUartId, "receive", NMEA2UART1)
                uart.setup(gnssUartId, 115200)
            else
                item = "ERROR"
            end
        elseif string.find(cmd, "GPSDOWNLOAD") then
            local onoff = string.match(cmd, "GPSDOWNLOAD,(%d)")
            item = "OK"
            if onoff == "0" then
                gpio.close(12)
                gpio.close(13)
            elseif onoff == "1" then
                gpio.setup(12)
                gpio.setup(13)
                sys.publish("CONTROL", "GNSS")
            else
                item = "ERROR"
            end
        elseif string.find(cmd, "GS_STATE") then
            sys.publish("CONTROL", "GSENSOR")
            needNowReply = false
        elseif string.find(cmd, "RECORD") then
            sys.publish("CONTROL", "RECORD")
            needNowReply = false
        elseif string.find(cmd, "PLAY") then
            sys.publish("CONTROL", "PLAY")
            needNowReply = false
        elseif string.find(cmd, "POWERKEY") then
            local onoff = string.match(cmd, "POWERKEY,(%d)")
            item = "OK"
            if onoff == "0" then
                gpio.close(46)
            elseif onoff == "1" then
                gpio.setup(46, powerKeyCb, gpio.PULLUP, gpio.BOTH)
            else
                item = "ERROR"
            end
        elseif string.find(cmd, "ECNPICFG") then
            item = "OK"
            mobile.nstOnOff(true, transUartId)
            mobile.nstInput("AT+ECNPICFG?\r\n")
            mobile.nstInput(nil)
            mobile.nstOnOff(false, transUartId)
            needNowReply = false
        elseif string.find(cmd, "PCBA_TEST_DONE") then
            item = "OK"
            fskv.set("pabaDone", true)
        elseif string.find(cmd, "TEST_DONE") then
            item = "OK"
            fskv.set("allDone", true)
        else
            find = false
            item = "ERROR"
        end
        if find then
            if not item then
                item = " "
            end
        end
        if needNowReply then
            item = item .. "#"
            table.insert(cacheTable, item)
            sys.publish("UART1_SEND")
        end
        return true, data:sub(h + 1)
    else
        return false, data
    end
end
gpio.debounce(46, 100)
uart.on(transUartId, "receive", function(id, len)
    local result
    while 1 do
        local data = uart.read(transUartId, 512)
        if not data or #data == 0 then
            break
        end
        rxCache = rxCache .. data
        while true do
            result, rxCache = proc(rxCache)
            if not result then
                break
            end
        end
    end
end)
uart.on(transUartId, "sent", function()
    sys.publish("SEND_DOWN")
end)


sys.taskInit(function()
    while true do
        while #cacheTable > 0 do
            uart.write(transUartId, table.remove(cacheTable, 1))
            sys.waitUntil("SEND_DOWN")
        end
        sys.waitUntil("UART1_SEND", 1000)
    end
end)

sys.taskInit(function()
    sys.wait(1000)
    while true do
        mobile.reqCellInfo(15)
        sys.waitUntil("CELL_INFO_UPDATE", 15000)
        sys.wait(1000)
    end
end)