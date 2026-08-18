--[[
@module  factory_h
@summary Air8201H 产测功能模块（UART + USB 双通道版本）
@version 1.0
@date    2026.07.15
@usage
Air8201H 生产测试模式，通过 UART(串口1) + USB(VUART_0) 双通道接收测试指令
适配 Air8201 项目结构，使用 OTP 存储测试结果

通信协议：
  上位机发送命令格式: CMD# 或 CMD,param#
  设备回复格式: result#
  支持同时通过 UART 和 USB 通信
]]

local factory_h = {}

-- OTP 存储区
local OTP_ZONE = 2

-- ==================== 硬件版本管理（内联 pcb 逻辑） ====================

local hversion = "1.0.3"
local test_done = false

-- 读取 OTP 存储区参数，解析硬件版本号和测试状态
local function load_otp_params()
    if not otp then return end
    local len_data = otp.read(OTP_ZONE, 0, 1)
    if not len_data or #len_data == 0 then return end
    local len = string.byte(len_data)
    local otpdata = otp.read(OTP_ZONE, 1, len)
    if not otpdata or #otpdata == 0 then return end
    local obj, result, errMsg = json.decode(otpdata)
    if result == 1 and obj then
        test_done = obj.test or false
        hversion = obj.pcb or hversion
    end
    log.info("factory_h", "hversion:", hversion, "test_done:", test_done)
end

-- GNSS 电源控制（根据硬件版本选择不同引脚）
local function gnssPower(onoff)
    if hversion == "1.0.2" then
        gpio.setup(2, onoff and 1 or 0)
        gpio.setup(26, onoff and 1 or 0)
        gpio.setup(27, onoff and 1 or 0)
    else
        gpio.setup(25, onoff and 1 or 0)
        gpio.setup(26, onoff and 1 or 0)
    end
end

-- ES8311 电源引脚（根据硬件版本）
local function es8311PowerPin()
    if hversion == "1.0.2" then
        return 25
    else
        return 2
    end
end

-- 加载 OTP 参数
load_otp_params()

-- ==================== 产测核心变量 ====================

local es8311 = require "es8311"

local paramTable = {}
local vbackup = gpio.setup(24, 0)
local uartRxCache = ""
local nowTransId
local usbRxCache = ""
local cacheTable = {}
local usbCacheTable = {}
local paPin = 23
local blueLed = gpio.setup(1, 0)
local redLed = gpio.setup(16, 0, nil, nil, 4)

-- 关闭 GNSS 电源
gnssPower(false)

-- 关闭 PA 功放
gpio.setup(paPin, 0)

-- 请求保持 IDLE 模式（不自动休眠）
pm.request(pm.IDLE)

local uartTrans = 1           -- UART 串口通道
local usbTrans = uart.VUART_0 -- USB 虚拟串口通道
local gnssUartId = 2
local gnssTransFlag = false

local Gsensori2cId = 1
local da267Addr = 0x26
local intPin = 39
local es8311i2cId = 0

local powerKeyTest = false

local recordPath = "/record.amr"

-- ==================== GNSS 数据转发 ====================

local function nmeaToUart1(id, len)
    while 1 do
        local data = uart.read(gnssUartId, len)
        if not data or #data == 0 then
            break
        end
        if gnssTransFlag then
            table.insert(cacheTable, {
                transId = nowTransId,
                data = data
            })
            sys.publish("DATA_SEND")
        end
    end
end

-- ==================== 音频回调 ====================

local function audio_cb(request_index, event, param)
    log.info("audio_cb", request_index, event, param)
end

-- ==================== 硬件控制任务 ====================

sys.taskInit(function()
    -- I2C1 引脚配置: GPIO23(SCL), GPIO24(SDA) 切 I2C1 功能（GSensor）
    mcu.altfun(mcu.I2C, Gsensori2cId, 23, 2, 0)
    mcu.altfun(mcu.I2C, Gsensori2cId, 24, 2, 0)

    -- audio_v2 + es8311 初始化
    audio_v2.debug(true)
    audio_v2.on(audio_cb)
    audio_v2.config_pa_power_ctrl(true, paPin, 1, 200)
    audio_v2.config_codec_power_ctrl(false, nil, nil, 600, 0)
    audio_v2.config(audio_v2.CFG_PARAM_I2S_MODE, audio_v2.CFG_VALUE_I2S_MODE_LSB)
    audio_v2.config(audio_v2.CFG_PARAM_I2S_FRAME_BITS, 16, 16)
    audio_v2.config(audio_v2.CFG_PARAM_I2S_CHANNEL_TYPE, audio_v2.CFG_VALUE_I2S_CHANNEL_TYPE_RIGHT)

    i2c.setup(es8311i2cId)
    gpio.setup(es8311PowerPin(), 1)
    log.info("es8311", "powerPin=" .. es8311PowerPin() .. ", hver=" .. hversion)
    sys.wait(100)

    if es8311.init(es8311i2cId, 0x01) then
        es8311.set_sample_rate(es8311i2cId, 16000, 256)
        es8311.set_data_bits(es8311i2cId, 16)
        es8311.set_format(es8311i2cId)
        es8311.resume(es8311i2cId)
        es8311.set_voice_vol(es8311i2cId, 80)
        es8311.set_mic_vol(es8311i2cId, 85)
    else
        log.error("es8311", "初始化失败, 跳过codec配置")
    end

    while true do
        local result, param1, param2, param3, param4 = sys.waitUntil("CONTROL")
        log.info("CONTROL", param1)
        if param1 == "GNSS" then
            gnssPower(false)
            sys.wait(10)
            gnssPower(true)
        elseif param1 == "GSENSOR" then
            vbackup(1)
            sys.wait(50)
            i2c.setup(Gsensori2cId, i2c.SLOW)
            i2c.send(Gsensori2cId, da267Addr, 0x01, 1)
            local data = i2c.recv(Gsensori2cId, da267Addr, 1)
            if not data or data == "" or string.byte(data) ~= 0x13 then
                table.insert(cacheTable, {
                    transId = param2,
                    data = "ERROR#"
                })
            else
                table.insert(cacheTable, {
                    transId = param2,
                    data = "OK#"
                })
            end
            vbackup(0)
            i2c.close(Gsensori2cId)
            sys.publish("DATA_SEND")
        elseif param1 == "RECORD" then
            log.info("cmd", "RECORD 开始录音")
            audio_v2.record(recordPath, 5, audio_v2.DATA_CODEC_TYPE_AMR_NB)
            while not audio_v2.is_all_done() do
                sys.wait(200)
            end
            table.insert(cacheTable, {
                transId = param2,
                data = "OK#"
            })
            sys.publish("DATA_SEND")
        elseif param1 == "PLAY" then
            log.info("cmd", "PLAY 开始播放")
            audio_v2.play(recordPath)
            while not audio_v2.is_all_done() do
                sys.wait(200)
            end
            table.insert(cacheTable, {
                transId = param2,
                data = "OK#"
            })
            sys.publish("DATA_SEND")
        end
    end
end)

-- ==================== 电源键检测 ====================

local function powerOff()
    pm.shutdown()
end

local function powerKeyCb()
    if gpio.get(46) == 1 then
        if powerKeyTest then
            table.insert(cacheTable, {
                transId = nowTransId,
                data = "POWERKEY_RELEASE#"
            })
        end
        if sys.timerIsActive(powerOff) then
            sys.timerStop(powerOff)
        end
    else
        if powerKeyTest then
            table.insert(cacheTable, {
                transId = nowTransId,
                data = "POWERKEY_PRESS#"
            })
        end
        sys.timerStart(powerOff, 3000)
    end
    if powerKeyTest then
        sys.publish("DATA_SEND")
    end
end
gpio.debounce(46, 100)
gpio.setup(46, powerKeyCb, gpio.PULLUP, gpio.BOTH)

-- ==================== 命令处理表 ====================

local procTable = {
    ["VERSION"] = function(id, findCom, data)
        return _G.PROJECT .. "_" .. _G.VERSION
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
            gnssPower(false)
            uart.on(gnssUartId, "receive")
            uart.close(gnssUartId)
            -- 取消自动关闭定时器
            if sys.timerIsActive(gnssPower, false) then
                sys.timerStop(gnssPower)
            end
        elseif data == "1" then
            gnssTransFlag = true
            uart.on(gnssUartId, "receive", nmeaToUart1)
            uart.setup(gnssUartId, 115200)
            gnssPower(true)
            sys.timerStart(uart.write, 500, gnssUartId, "$CFGTP,1000000,500000,7,0,800,0*7D\r\n")

            -- 35秒后自动关闭GPS
            sys.timerStart(function()
                log.info("GPSTEST", "GPS测试超时(35s)，自动关闭")
                gnssTransFlag = false
                gnssPower(false)
                uart.on(gnssUartId, "receive")
                uart.close(gnssUartId)
            end, 35000)
        else
            item = "ERROR"
        end
        return item
    end,
    ["GPSDOWNLOAD"] = function(id, findCom, data)
        local item = "OK"
        if data == "0" then
            gnssPower(false)
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
        local rfa = require("rfa")
        local resp = rfa.dispatch("AT+ECNPICFG?")
        resp = resp:gsub(',%s*"rfCTDone":%d+', '')
        resp = resp:gsub('%s*$', '\r\n')
        table.insert(cacheTable, { transId = id, data = resp })
        sys.publish("DATA_SEND")
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
        audio_v2.shutdown(true, false, true)
        es8311.power_down(es8311i2cId)
        gpio.setup(25, 0) -- 关闭 PA 功放
        gpio.setup(2, 0)  -- 关闭 ES8311 电源引脚
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
            return hversion
        end
        if not string.match(data, "^%d+%.%d+%.%d+$") then
            return "ERROR"
        end
        paramTable.pcb = data
        hversion = data
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
    ["MODEL"] = function(id, findCom, data)
        if not data or #data == 0 then
            return "ERROR"
        end
        fskv.set("device_model", data)
        log.info("factory_h", "保存型号:", data)
        return "OK"
    end,
    ["PCBA_TEST_DONE"] = function(id, findCom, data)
        sys.timerStart(pm.shutdown, 3000)
        return "OK"
    end,
    ["TEST_DONE"] = function(id, findCom, data)
        paramTable.test = 1
        paramTable.pcb = hversion
        test_done = true
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
        test_done = false
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

-- ==================== 命令解析与处理 ====================

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
            table.insert(cacheTable, {
                transId = id,
                data = reply .. "#"
            })
            sys.publish("DATA_SEND")
        end
    else
        table.insert(cacheTable, {
            transId = id,
            data = "ERROR#"
        })
        sys.publish("DATA_SEND")
    end
    return true, data:sub(h1 + 1)
end

-- ==================== 通信初始化 ====================

-- 初始化 UART（串口1）和 USB 虚拟串口
uart.setup(uartTrans, 115200)
uart.setup(usbTrans, 115200)

-- UART 接收回调
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

-- USB 接收回调
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

-- UART 发送完成回调
uart.on(uartTrans, "sent", function(id)
    sys.publish("UART_SENT_DONE")
end)

-- USB 发送完成回调
uart.on(usbTrans, "sent", function(id)
    sys.publish("USB_SENT_DONE")
end)

-- ==================== 数据发送任务 ====================

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

-- ==================== 基站信息定时更新 ====================

sys.taskInit(function()
    sys.wait(1000)
    while true do
        mobile.reqCellInfo(15)
        sys.waitUntil("CELL_INFO_UPDATE", 15000)
        sys.wait(180000)
    end
end)

-- ==================== 模块接口 ====================

--[[
启动 Air8201H 产测模式
]]
function factory_h.init()
    log.info("factory_h", "启动Air8201H产测模式（UART+USB双通道）")
    -- 所有初始化逻辑已通过上面的代码自动执行
end

--[[
获取产测状态
@return table 状态信息
]]
function factory_h.get_status()
    return {
        hversion = hversion,
        test_done = test_done,
        gnssTransFlag = gnssTransFlag,
        powerKeyTest = powerKeyTest
    }
end

return factory_h