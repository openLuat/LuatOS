local driver = {}

local dtulib = require "dtulib"
local lbsLoc = require "lbsLoc"
local config = require "irtu_config"

local dtu = config.get()

local writeIdle = {true, true, true}
local recvBuff, writeBuff = {{}, {}, {}, {},{},{}}, {{}, {}, {}, {},{},{}}
local flowCount, timecnt = {0, 0, 0, 0}, 1
local trackFile = {}
local sens = {
    vib = false,
}
local openFlag = false
local tid
local gpsUartId = 2
local lbs = {lat = 0, lng = 0}
local latdata, lngdata = 0, 0
local datalink = {}
local netready

driver.pios = {}

local function setupPios()
    -- for i = 1, 38 do
    --     driver.pios["pio" .. i] = gpio.setup(i, nil, gpio.PULLDOWN)
    -- end

    -- 设置GPIO16为下拉
    driver.pios.pio16 = gpio.setup(16, nil, gpio.PULLDOWN)
end

local function blinkPwm(ledPin, light, dark)
    ledPin(1)
    sys.wait(light)
    ledPin(0)
    sys.wait(dark)
end

local function netledTask(led)
    local ledpin = gpio.setup(led, 1)
    while true do
        while mobile.status() == 3 or mobile.status() == 2 or mobile.status() == 0 do
            blinkPwm(ledpin, 100, 100)
            netready(0)
        end
        while mobile.status() == 1 or mobile.status() == 5 do
            if driver.getDatalink() then
                netready(1)
                blinkPwm(ledpin, 200, 1800)
            else
                netready(0)
                blinkPwm(ledpin, 500, 500)
            end
        end
        sys.wait(10000)
    end
end

local function updateNetPins()
    -- 更新网络引脚
    if not dtu.pins or not dtu.pins[2] or not driver.pios[dtu.pins[2]] then
        netready = gpio.setup(26, 0)
    else
        netready = gpio.setup(tonumber(dtu.pins[2]:sub(4, -1)), 0)
        driver.pios[dtu.pins[2]] = nil
    end
    -- 更新网络引脚
    local ledPin = 27
    if dtu.pins and dtu.pins[1] and driver.pios[dtu.pins[1]] then
        ledPin = tonumber(dtu.pins[1]:sub(4, -1))
        driver.pios[dtu.pins[1]] = nil
    end
    -- 初始化网络LED任务
    sys.taskInit(netledTask, ledPin)
end

local function clearTrackFile()
    trackFile = {}
end

function driver.setLocation(lat, lng)
    lbs.lat, lbs.lng = lat, lng
    latdata, lngdata = lat, lng
    log.info("基站定位请求的结果:", lat, lng)
end

local function deviceMessage(format)
    if format:lower() ~= "hex" then
        return json.encode({
            sta = {
                openFlag and 1 or 0,
                sens.vib and 1 or 0,
                sens.acc and 1 or 0,
                sens.act and 1 or 0,
                sens.chg and 1 or 0,
                sens.und and 1 or 0,
                sens.vcc,
                mobile.csq(),
            },
        })
    else
        return pack.pack(">b7fb", 0x55, openFlag and 1 or 0, sens.vib and 1 or 0,
        sens.acc and 1 or 0, sens.act and 1 or 0, sens.chg and 1 or 0, sens.und and 1 or 0,
        sens.vcc, mobile.csq())
    end
end

local function locateMessage(format)
    local isFix = libgnss.isFix()
    local a, b, speed = libgnss.getIntLocation(2)
    local gsvTable = libgnss.getGsv()
    local ggaTable = libgnss.getGga()
    local altitude = 0
    local azimuth = 0
    local sateCnt = 0
    if ggaTable then
        altitude = tonumber(ggaTable["altitude"]) or 0
        sateCnt = tonumber(ggaTable["satellites_tracked"]) or 0
    end
    if gsvTable and gsvTable["sats"] and gsvTable["sats"][1] and gsvTable["sats"][1]["azimuth"] then
        azimuth = gsvTable["sats"][1]["azimuth"]
    end
    local rmc = libgnss.getRmc(format:lower() ~= "hex" and 2 or 1)
    local lat, lng = rmc.lat, rmc.lng
    log.info("rmc", lat, lng, rmc.speed, speed)
    if format:lower() ~= "hex" then
        return json.encode({
            msg = {isFix, os.time(), lng, lat, altitude, azimuth, speed, sateCnt},
        })
    else
        return pack.pack(">b2i3H3b1", 0xAA, isFix and 1 or 0, os.time(), lng, lat,
            tonumber(string.match(altitude .. "", ".%d*")), azimuth, speed, sateCnt)
    end
end

local function openGPS(uid, baud, sleep)
    libgnss.clear()
    uart.setup(uid, baud)
    pm.power(pm.GPS, true)
    libgnss.bind(uid)
    gpsUartId = uid
    log.info("----------------------------------- GPS START -----------------------------------")
    if openFlag then return end
    openFlag = true
    tid = sys.timerLoopStart(function()
        sys.publish("GPS_MSG_REPORT")
    end, sleep * 1000)
end

local function closeGPS()
    openFlag = false
    if tid then
        sys.timerStop(tid)
    end
    pm.power(pm.GPS, false)
    uart.close(gpsUartId)
    log.info("----------------------------------- GPS CLOSE -----------------------------------")
end

function driver.isGpsOpen()
    return openFlag
end

function driver.getADC(id)
    adc.open(id)
    local adcValue = adc.get(id)
    adc.close(id)
    if adcValue ~= 0xFFFF then
        return adcValue
    end
end

function driver.getLat()
    return latdata
end

function driver.getLng()
    return lngdata
end

function driver.getRealLocation()
    lbsLoc.request(function(result, lat, lng, addr, time, locType)
        if result then
            latdata = lat
            lngdata = lng
            driver.setLocation(lat, lng)
        end
    end)
    return latdata, lngdata
end

local function parseCommand(str)
    local t = str:match("(.+)\r\n") and dtulib.split(str:match("(.+)\r\n"), ',')
        or dtulib.split(str, ',')
    local first = table.remove(t, 1)
    local second = table.remove(t, 1) or ""
    if tonumber(second) and tonumber(second) > 0 and tonumber(second) < 8 then
        return cmd[first]["pipe"](t, second) .. "\r\n"
    elseif cmd[first][second] then
        return cmd[first][second](t, str) .. "\r\n"
    else
        return "ERROR\r\n"
    end
end

cmd = {}
cmd.config = {
    ["A"] = function(t)
        if t[1] ~= nil and t[2] ~= nil and t[3] ~= nil then
            t[2] = t[2] == "nil" and "" or t[2]
            t[3] = t[3] == "nil" and "" or t[3]
            dtu.apn = t
            log.info("APN配置成功", dtu.apn[1], dtu.apn[2], dtu.apn[3])
            mobile.flymode(0, true)
            mobile.apn(0, 1, dtu.apn[1], dtu.apn[2], dtu.apn[3])
            mobile.flymode(0, false)
            config.save()
            return "OK"
        end
    end,
    ["0"] = function(t)
        local password = ""
        dtu.plate, dtu.reg, dtu.param_ver, dtu.flow, dtu.fota, dtu.uartReadTime, dtu.pwrmod, password, dtu.log =
            unpack(t)
        if password == dtu.password or dtu.password == "" or dtu.password == nil then
            dtu.password = password
            config.save()
            sys.timerStart(dtulib.restart, 5000, "Setting parameters have been saved!")
            return "OK"
        else
            return "PASSWORD ERROR"
        end
    end,
    ["readconfig"] = function(t)
        if t[1] == dtu.password or dtu.password == "" or dtu.password == nil then
            return config.export("string")
        else
            return "PASSWORD ERROR"
        end
    end,
}
cmd.rrpc = {
    ["getfwver"] = function() return "rrpc,getfwver," .. _G.PROJECT .. "_" .. _G.VERSION .. "_" .. rtos.version() end,
    ["getnetmode"] = function() return "rrpc,getnetmode," .. (mobile.status() and mobile.status() or 1) end,
    ["getver"] = function() return "rrpc,getver," .. _G.VERSION end,
    ["getcsq"] = function() return "rrpc,getcsq," .. (mobile.csq() or "error ") end,
    ["getadc"] = function(t) return "rrpc,getadc," .. driver.getADC(tonumber(t[1]) or 0) end,
    ["reboot"] = function()
        sys.timerStart(dtulib.restart, 1000, "Remote reboot!")
        return "OK"
    end,
    ["getimei"] = function() return "rrpc,getimei," .. (mobile.imei() or "error") end,
    ["getmuid"] = function() return "rrpc,getmuid," .. (mobile.muid() or "error") end,
    ["getimsi"] = function() return "rrpc,getimsi," .. (mobile.imsi() or "error") end,
    ["getvbatt"] = function() return "rrpc,getvbatt," .. driver.getADC(adc.CH_VBAT) end,
    ["geticcid"] = function() return "rrpc,geticcid," .. (mobile.iccid() or "error") end,
    ["getproject"] = function() return "rrpc,getproject," .. _G.PROJECT end,
    ["getcorever"] = function() return "rrpc,getcorever," .. rtos.version() end,
    ["getlocation"] = function() return "rrpc,location," .. (lbs.lat or 0) .. "," .. (lbs.lng or 0) end,
    ["getreallocation"] = function()
        lbsLoc.request(function(result, lat, lng, addr, time, locType)
            if result then
                lbs.lat, lbs.lng = lat, lng
                driver.setLocation(lat, lng)
            end
        end)
        return "rrpc,getreallocation," .. (lbs.lat or 0) .. "," .. (lbs.lng or 0)
    end,
    ["gettime"] = function()
        local t = os.date("*t")
        return "rrpc,gettime," .. string.format("%04d-%02d-%02d %02d:%02d:%02d", t.year, t.month, t.day, t.hour, t.min, t.sec)
    end,
    ["setpio"] = function(t)
        if driver.pios["pio" .. t[1]] and (tonumber(t[2]) == 0 or tonumber(t[2]) == 1) then
            gpio.setup(tonumber(t[1]), tonumber(t[2]))
            return "OK"
        end
        return "ERROR"
    end,
    ["getpio"] = function(t)
        if driver.pios["pio" .. t[1]] then
            return "rrpc,getpio" .. t[1] .. "," .. gpio.get(t[1])
        end
        return "ERROR"
    end,
    ["netstatus"] = function(t)
        if t == nil or t == "" or t[1] == nil or t[1] == "" then
            return "rrpc,netstatus," .. (driver.getDatalink() and "RDY" or "NORDY")
        else
            return "rrpc,netstatus," .. (t[1] and (t[1] .. ",") or "") ..
                (driver.getDatalink(tonumber(t[1])) and "RDY" or "NORDY")
        end
    end,
    ["gps_wakeup"] = function()
        sys.publish("REMOTE_WAKEUP")
        return "rrpc,gps_wakeup,OK"
    end,
    ["gps_getsta"] = function(t) return "rrpc,gps_getsta," .. deviceMessage(t[1] or "json") end,
    ["gps_getmsg"] = function(t) return "rrpc,gps_getmsg," .. locateMessage(t[1] or "json") end,
    ["gps_close"] = function()
        sys.publish("REMOTE_CLOSE")
        return "rrpc,gps_close,ok"
    end,
    ["upconfig"] = function()
        sys.publish("UPDATE_DTU_CNF")
        return "rrpc,upconfig,OK"
    end,
    ["function"] = function(t)
        log.info("rrpc,function:", table.concat(t, ","))
        return "rrpc,function," .. (loadstring(table.concat(t, ","))() or "OK")
    end,
    ["simcross"] = function(t)
        if tonumber(t[1]) == 1 or tonumber(t[1]) == 0 or tonumber(t[1]) == 2 then
            mobile.flymode(0, true)
            mobile.simid(tonumber(t[1]))
            mobile.flymode(0, false)
            return "simcross,ok," .. t[1]
        else
            return "simcross,error," .. t[1]
        end
    end,
}

function driver.userapi(str)
    return parseCommand(str)
end

local function read(uid, idx)
    log.error("uart.read--->", uid, idx)
    local s = table.concat(recvBuff[idx])
    recvBuff[idx] = {}
    flowCount[idx] = flowCount[idx] + #s
    log.info("UART_" .. uid .. " read:", #s, (s:sub(1, 100):toHex()))
    log.info("串口流量统计值:", flowCount[idx])
    if s:sub(1, 7) == "config," or s:sub(1, 5) == "rrpc," then
        return write(uid, driver.userapi(s))
    end
    log.info("这个里面的内容是", dtu.plate == 1 and mobile.imei() .. s or s)
    sys.publish("NET_SENT_RDY_" .. uid, dtu.plate == 1 and mobile.imei() .. s or s)
end

local function streamEnd(uid)
    if #recvBuff[uid] > 0 then
        sys.publish("NET_SENT_RDY_" .. uid, table.concat(recvBuff[uid]))
        recvBuff[uid] = {}
    end
end

function driver.write(uid, str, cid)
    uid = tonumber(uid)
    if not str or str == "" or not uid then return end
    if uid == uart.VUART_0 then return uart.write(uart.VUART_0, str) end
    if str ~= true then
        for i = 1, #str, 4096 do
            table.insert(writeBuff[uid], str:sub(i, i + 4095))
        end
        log.info("str的实际值是", str)
        log.warn("uart" .. uid .. ".write data length:", writeIdle[uid], #str)
    end
    if writeIdle[uid] and writeBuff[uid][1] then
        if 0 ~= uart.write(uid, writeBuff[uid][1]) then
            table.remove(writeBuff[uid], 1)
            writeIdle[uid] = false
            log.warn("UART_" .. uid .. " writing ...")
        end
    end
end

local function writeDone(uid)
    if uid == "32" or uid == 32 then
        return
    end
    if #writeBuff[uid] == 0 then
        writeIdle[uid] = true
        sys.publish("UART_" .. uid .. "_WRITE_DONE")
        log.warn("UART_" .. uid .. "write done!")
    else
        writeIdle[uid] = false
        uart.write(uid, table.remove(writeBuff[uid], 1))
        log.warn("UART_" .. uid .. "writing ...")
    end
end

function driver.publishNet(uid, data)
    if not uid or not data then return end
    sys.publish("NET_SENT_RDY_" .. uid, data)
end

function driver.subscribeNet(uid, cb)
    if not uid or not cb then return end
    sys.subscribe("NET_SENT_RDY_" .. uid, cb)
end

function driver.getDatalink(idx)
    if idx then
        return datalink[idx]
    else
        for _, v in pairs(datalink) do
            if v then return true end
        end
        return false
    end
end

function driver.setDatalink(cid, value)
    datalink[cid] = value
end

local function initUart(uconf)
    for i = 1, #uconf do
        local entry = uconf[i]
        if entry and entry[1] then
            driver.uartInit(i, uconf)
        end
    end
end

function driver.uartInit(i, uconf)
    local entry = uconf[i]
    if not entry or not entry[1] then return end
    entry[1] = tonumber(entry[1])
    local rs485us = tonumber(entry[7]) and tonumber(entry[7]) or 0
    local parity = uart.None
    if entry[4] == 0 then
        parity = uart.EVEN
    elseif entry[4] == 1 then
        parity = uart.Odd
    elseif entry[4] == 2 then
        parity = uart.None
    end
    if driver.pios[dtu.uconf[i][6]] then
        driver["dir" .. i] = tonumber(dtu.uconf[i][6]:sub(4, -1))
        driver.pios[dtu.uconf[i][6]] = nil
    else
        driver["dir" .. i] = nil
    end
    uart.setup(entry[1], entry[2], entry[3], entry[5], parity, uart.LSB, 4096,
        driver["dir" .. i], 0, rs485us)
    uart.on(entry[1], "sent", writeDone)
    local readHandler = function(uid, length)
        log.info("接收到的数据是", uid, length)
        table.insert(recvBuff[i], uart.read(entry[1], length or 8192))
        sys.timerStart(sys.publish, tonumber(dtu.uartReadTime) or 25, "UART_RECV_WAIT_" .. entry[1], entry[1], i)
    end
    if entry[1] == uart.VUART_0 or tonumber(dtu.uartReadTime) > 0 then
        uart.on(entry[1], "receive", readHandler)
    else
        uart.on(entry[1], "receive", function(uid, length)
            local str = uart.read(entry[1], length or 8192)
            sys.timerStart(streamEnd, 1000, i)
            table.insert(recvBuff[i], str)
        end)
    end
    sys.subscribe("UART_RECV_WAIT_" .. entry[1], read)
    sys.subscribe("UART_SENT_RDY_" .. entry[1], driver.write)
end

local function initGps()
    if dtu.gps and tonumber(dtu.gps.fun[1]) then
        local uidgps = tonumber(dtu.gps.fun[1])
        if uidgps ~= 1 and dtu.uconf[1] and tonumber(dtu.uconf[1][1]) == 1 then
            driver.uartInit(1, dtu.uconf)
        end
        if uidgps ~= 2 and dtu.uconf[2] and tonumber(dtu.uconf[2][1]) == 2 then
            driver.uartInit(2, dtu.uconf)
        end
        if uidgps ~= 3 and dtu.uconf[3] and tonumber(dtu.uconf[3][1]) == 3 then
            driver.uartInit(3, dtu.uconf)
        end
        if true then
            dtu.uconf[4] = {uart.VUART_0, 115200, 8, 2, 0}
            driver.uartInit(4, dtu.uconf)
        end
    end
end

local function subscribeGpsEvents()
    sys.subscribe("NTP_UPDATE", function()
        log.info("网络时间已同步")
    end)
    sys.subscribe("REMOTE_WAKEUP", function()
        sys.publish("GPS_GO")
        openGPS(2, 115200, 30)
        sens.wup = true
    end)
    sys.subscribe("REMOTE_CLOSE", function()
        log.info("GPS已关闭")
        closeGPS()
    end)
end

function driver.init()
    -- 获取配置
    dtu = config.get()
    -- 设置GPIO
    setupPios()
    -- 更新网络引脚
    -- updateNetPins()
    -- -- 初始化串口
    initUart(dtu.uconf or {})
    -- 初始化GPS
    initGps()
    -- 订阅GPS事件
    subscribeGpsEvents()
    -- -- 更新配置回调
    -- config.onUpdate(function(updated)
    --     if updated then
    --         dtu = updated
    --         -- 更新网络引脚
    --         updateNetPins()
    --     end
    -- end)
end

return driver

