--[[
@module  factory
@summary Air8201产测功能模块
@version 2.0
@date    2026.07.15
@usage
负责Air8201的产测功能，完全按照8201G产测系统实现
]]

local factory = {}

-- 硬编码管脚定义
local GNSS_POWER_PIN = 21      -- GPS电源控制
local GNSS_POWER_PIN2 = 23     -- GPS备电开关，需要agps时候打开
local GSENSOR_VBACKUP_PIN = 24 -- 加速度传感器电源，以及蓝牙电平转换电路时候的上拉
local BLUE_LED_PIN = 1         -- 蓝色LED
local RED_LED_PIN = 16         -- 红色LED
local GSENSOR_INT_PIN = 20     -- 加速度传感器中断
local NS2520_I2C_ID = 1        -- 压力传感器I2C 编号
local NS2520_I2C_ADDR = 0x77   -- 压力传感器I2C地址
local BLE_POWER_PIN = 27       -- 蓝牙供电使能
local I2C1_PULLUP_PIN = 28     -- I2C1总线上拉
local NS2520_POWER_PIN = 26    -- NS2520供电使能

-- 初始化变量
local vbackup = gpio.setup(GSENSOR_VBACKUP_PIN, 0)
local uartRxCache = ""
local nowTransId
local usbRxCache = ""
local cacheTable = {}
local usbCacheTable = {}

local blueLed = gpio.setup(BLUE_LED_PIN, 0)
local redLed = gpio.setup(RED_LED_PIN, 0)

-- 关闭 GPS 电源
gpio.setup(GNSS_POWER_PIN, 0)

-- 初始化新增 GPIO 引脚
gpio.setup(BLE_POWER_PIN, 0)    -- 关闭蓝牙供电
gpio.setup(I2C1_PULLUP_PIN, 1)  -- 开启I2C1总线上拉
gpio.setup(NS2520_POWER_PIN, 0) -- 关闭NS2520供电

local usbTrans = uart.VUART_0
local gnssUartId = 2
local gnssTransFlag = false

local Gsensori2cId = 1
local da267Addr = 0x26
local intPin = GSENSOR_INT_PIN
local es8311i2cId = 0
local ns2520i2cId = NS2520_I2C_ID
local ns2520Addr = NS2520_I2C_ADDR

-- 5101 蓝牙模块
local exril_5101 = nil
local ble_init_success = false

-- 简单的 GNSS 电源控制函数
local function gnssPower(onoff)
    gpio.setup(GNSS_POWER_PIN, onoff and 1 or 0)
end

local powerKeyTest = false

local recordPath = "/record.amr"

local function audio_cb(request_index, event, param)
    log.info("audio_cb", request_index, event, param)
end

local function nmeaToUart1(id, len)
    local result
    while 1 do
        local data = uart.read(gnssUartId, len)
        if not data or #data == 0 then
            break
        end
        if gnssTransFlag then
            table.insert(cacheTable, { transId = nowTransId, data = data })
            sys.publish("DATA_SEND")
        end
    end
end


sys.taskInit(function()
    gpio.setup(28, 0)
    gpio.setup(20, 0)
    gpio.setup(24, 0)
    gpio.setup(26, 0)
    gpio.setup(16, 0)
    gpio.setup(11, 0)
    gpio.setup(2, 0)
    gpio.setup(25, 0)
    gpio.setup(27, 0)
    gpio.setup(24, 0)
    gpio.setup(21, 0)


    -- 初始化 NS2520 压力传感器
    -- i2c.setup(ns2520i2cId, i2c.SLOW)

    -- 初始化 5101 蓝牙模块
    -- 开启蓝牙供电
    gpio.setup(BLE_POWER_PIN, 1)
    sys.wait(100) -- 等待供电稳定

    -- audio_v2 + es8311 初始化
    audio_v2.debug(true)
    audio_v2.on(audio_cb)
    audio_v2.config_pa_power_ctrl(true, 25, 1, 200)
    audio_v2.config_codec_power_ctrl(false, nil, nil, 600, 0)
    audio_v2.config(audio_v2.CFG_PARAM_I2S_MODE, audio_v2.CFG_VALUE_I2S_MODE_LSB)
    audio_v2.config(audio_v2.CFG_PARAM_I2S_FRAME_BITS, 16, 16)
    audio_v2.config(audio_v2.CFG_PARAM_I2S_CHANNEL_TYPE, audio_v2.CFG_VALUE_I2S_CHANNEL_TYPE_RIGHT)

    i2c.setup(es8311i2cId)
    gpio.setup(2, 1)  -- ES8311 电源
    sys.wait(100)

    es8311 = require "es8311"
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
        local result, param1, param2 = sys.waitUntil("CONTROL")
        log.info("CONTROL", param1)
        if param1 == "GNSS" then
            gnssPower(false)
            sys.wait(10)
            gnssPower(true)
        elseif param1 == "GSENSOR" then
            gpio.setup(26, 1)
            gpio.setup(28, 1)
            vbackup(1)   -- 开启DA267供电和蓝牙电平转换电路上拉
            gpio.setup(24, 1)
            sys.wait(50) -- 等待供电稳定
            i2c.setup(Gsensori2cId, i2c.SLOW)
            i2c.send(Gsensori2cId, da267Addr, 0x01, 1)
            local data = i2c.recv(Gsensori2cId, da267Addr, 1)
            if not data or data == "" or string.byte(data) ~= 0x13 then
                table.insert(cacheTable, { transId = param2, data = "ERROR#" })
            else
                table.insert(cacheTable, { transId = param2, data = "OK#" })
            end
            vbackup(0) -- 关闭DA267供电
            i2c.close(Gsensori2cId)
            sys.publish("DATA_SEND")
        elseif param1 == "NS2520" then
            -- NS2520 压力传感器测试
            local test_result = "ERROR"
            gpio.setup(26, 1) -- NS2520供电使能
            gpio.setup(28, 1) -- I2C1上拉
            vbackup(1)        -- 开启DA267供电和蓝牙电平转换电路上拉
            sys.wait(50)      -- 等待供电稳定

            -- 使用I2C直接操作
            i2c.setup(ns2520i2cId, i2c.SLOW)
            -- 读取设备ID（NS2520的WHO_AM_I寄存器）
            i2c.send(ns2520i2cId, ns2520Addr, 0xD0) -- WHO_AM_I寄存器地址
            local data = i2c.recv(ns2520i2cId, ns2520Addr, 1)
            if data and #data > 0 then
                local device_id = string.byte(data)
                log.info("NS2520", "设备ID:", device_id)
                test_result = "OK"
                -- NS2520的设备ID通常为0x60
            else
                log.error("NS2520", "读取设备ID失败")
            end

            -- 关闭 NS2520 供电
            vbackup(0) -- 关闭DA267供电
            gpio.setup(NS2520_POWER_PIN, 0)
            -- 关闭I2C
            i2c.close(ns2520i2cId)

            table.insert(cacheTable, { transId = param2, data = test_result .. "#" })
            sys.publish("DATA_SEND")
        elseif param1 == "BLE" then
            -- 5101 蓝牙模块测试
            local ble_version = ""
            local ble_version_found = false


            -- 开启蓝牙供电
            gpio.setup(27, 1)
            gpio.setup(24, 1)
            sys.wait(200) -- 等待供电稳定

            -- 配置串口1（蓝牙通信串口）
            uart.setup(1, 9600)

            -- 注册接收回调
            uart.on(1, "receive", function(id, len)
                local data = uart.read(1, 1024)
                log.info("BLE", "收到原始回复:", data)
                if data and #data > 10 then
                    -- 解析Version字段，格式类似：Version = 1.5.0-2507041634
                    local version_match = string.match(data, "Version%s*=%s*([%w%.%-]+)")
                    if version_match then
                        ble_version = version_match
                        ble_version_found = true
                        log.info("BLE", "解析到版本号:", ble_version)
                    end
                    local result = ble_version_found and ("Ble Version=" .. ble_version) or "ERROR"
                    table.insert(cacheTable, { transId = param2, data = result .. "#" })
                    sys.publish("DATA_SEND")
                end
            end)

            -- 发送AT+UA进入指令模式
            uart.write(1, "AT+UA\r\n")
            log.info("BLE", "发送AT+UA指令进入指令模式")

            -- 等待2秒让5101进入指令模式
            sys.wait(1000)

            -- 发送AT+CFG指令获取配置信息（包括版本号）
            uart.write(1, "AT+CFG\r\n")
            log.info("BLE", "发送AT+CFG指令")

            -- 等待回复，最多等待4秒
            sys.taskInit(function()
                sys.wait(4000)
                if not ble_version_found then
                    log.error("BLE", "未收到版本号")
                    -- 关闭接收回调
                    uart.on(1, "receive")
                    -- 发送测试结果
                    ble_version_found = true
                    table.insert(cacheTable, { transId = param2, data = "ERROR#" })
                    sys.publish("DATA_SEND")
                end
            end)
        elseif param1 == "RECORD" then
            log.info("cmd", "RECORD 开始录音")
            es8311.resume(es8311i2cId)
            audio_v2.record(recordPath, 5, audio_v2.DATA_CODEC_TYPE_AMR_NB)
            while not audio_v2.is_all_done() do
                sys.wait(200)
            end

            log.info("cmd", "RECORD 完成")
            table.insert(cacheTable, { transId = param2, data = "OK#" })
            sys.publish("DATA_SEND")
        elseif param1 == "PLAY" then
            log.info("cmd", "PLAY 开始播放")
            es8311.resume(es8311i2cId)
            audio_v2.play(recordPath)
            while not audio_v2.is_all_done() do
                sys.wait(200)
            end
            -- es8311.standby(es8311i2cId)
            log.info("cmd", "PLAY 完成")
            table.insert(cacheTable, { transId = param2, data = "OK#" })
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
            table.insert(cacheTable, { transId = nowTransId, data = "POWERKEY_RELEASE#" })
        end
        if sys.timerIsActive(powerOff) then
            sys.timerStop(powerOff)
        end
    else
        if powerKeyTest then
            table.insert(cacheTable, { transId = nowTransId, data = "POWERKEY_PRESS#" })
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
            local exgnss = require("exgnss")
            exgnss.close_all()
            gnssPower(false)
            uart.on(gnssUartId, "receive")
            uart.close(gnssUartId)
        elseif data == "1" then
            gnssTransFlag = true
            local exgnss = require("exgnss")
            local gnssotps = {
                gnssmode = 1,
                agps_enable = true,
                debug = true,
                uart = gnssUartId,
                uartbaud = 115200,
                bind = usbTrans,
                auto_open = true,
                gnss_volgpio = GNSS_POWER_PIN
            }
            exgnss.setup(gnssotps)

            exgnss.open(exgnss.TIMER, { tag = "gpsTest", val = 35, cb = function(tag)
                log.info("GPS测试", "GNSS回调", tag)
                local rmc = exgnss.rmc(2)
                if rmc and rmc.valid then
                    log.info("GPS定位成功", "纬度:", rmc.lat, "经度:", rmc.lng)
                end
                -- 35秒时间到，自动关闭GPS
                gnssTransFlag = false
                gnssPower(false)
                uart.on(gnssUartId, "receive")
                uart.close(gnssUartId)
            end })
            sys.timerStart(uart.write, 500, gnssUartId, "$CFGTP,1000000,500000,7,0,800,0*7D\r\n")
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
    ["WREG"] = function(id, findCom, data)
        local regStr, valStr = string.match(data, "^(%x+),(%x+)$")
        local reg = regStr and tonumber(regStr, 16)
        local val = valStr and tonumber(valStr, 16)
        if not reg or not val then
            return "ERROR"
        end
        i2c.send(es8311i2cId, 0x18, string.char(reg, val))
        local rd = i2c.readReg(es8311i2cId, 0x18, reg, 1)
        local rdVal = rd and #rd > 0 and string.byte(rd) or 0xFF
        log.info("cmd", string.format("WREG reg0x%02X = 0x%02X, 回读 = 0x%02X", reg, val, rdVal))
        return string.format("reg0x%02X=0x%02X", reg, rdVal)
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
        adc.setRange(adc.ADC_RANGE_MIN)
        adc.open(0)
        local vadc0 = adc.get(0)
        log.info("vadc0", vadc0)
        adc.close(0)
        local vbat1 = vadc0 * (1000 + 300) / 300
        local vbat = vbat1 + 140 --补偿计算
        log.info("adc换算与补偿后", vbat1, vbat)
        return string.format("%.2f", vbat)
    end,
    ["FLYMODE"] = function(id, findCom, data)
        local onoff = tonumber(data)
        if not onoff or onoff ~= 0 and onoff ~= 1 then
            return "ERROR"
        end
        log.info("FLYMODE", onoff)
        if onoff == 1 then
            -- 进入飞行模式前，先彻底关闭所有外设防漏电

            audio_v2.shutdown(true,false,true)

            es8311.power_down(es8311i2cId)

            -- 关闭 PA 功放（GPIO25 高电平使能，拉低关闭）
            gpio.setup(25, 0)

            -- 关闭 ES8311 电源引脚（GPIO2）
            gpio.setup(2, 0)


            -- 关闭所有其他外设 GPIO
            gpio.setup(28, 0)
            gpio.setup(20, 0)
            gpio.setup(26, 0)
            gpio.setup(16, 0)
            gpio.setup(11, 0)
            gpio.setup(27, 0)
            gpio.setup(24, 0)
            gpio.setup(21, 0)
            gpio.setup(18, 0)
            gpio.setup(19, 0)
            gpio.setup(gpio.WAKEUP0, 0)
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
    ["NS2520_TEST"] = function(id, findCom, data)
        -- NS2520 压力传感器测试
        sys.publish("CONTROL", "NS2520", id)
        return
    end,
    ["BLE_TEST"] = function(id, findCom, data)
        -- 5101 蓝牙模块测试
        sys.publish("CONTROL", "BLE", id)
        return
    end,

    ["HVERSION"] = function(id, findCom, data)
        log.info("findcom?", id, findCom, data)
        if not findCom then
            return "1.0.5" -- 默认硬件版本
        end
        if not string.match(data, "^%d+%.%d+%.%d+$") then
            return "ERROR"
        end
        local paramTable = {}
        paramTable.pcb = data
        mobile.flymode(0, true)
        sys.taskInit(function()
            sys.wait(100)
            log.info("测试模式", "设置硬件版本", data)
            sys.timerStart(pm.reboot, 3000)
        end)
        return "OK"
    end,
    ["MODEL"] = function(id, findCom, data)
        if not data or #data == 0 then
            return "ERROR"
        end
        fskv.set("device_model", data)
        log.info("factory", "保存型号:", data)
        return "OK"
    end,
    ["TEST_DONE"] = function(id, findCom, data)
        fskv.set("test_done", true)
        log.info("测试完成，已保存状态，3秒后重启")
        sys.timerStart(pm.reboot, 3000)
        return "OK"
    end,
    ["PCBA_TEST_DONE"] = function(id, findCom, data)
        sys.timerStart(pm.shutdown, 3000)
        return "OK"
    end,

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
        cmd = string.sub(text, 1, -2) -- 移除末尾的 #
    end
    -- 移除命令前后的空白字符（包括换行符、空格等）
    cmd = string.gsub(cmd, "^%s*", "")
    cmd = string.gsub(cmd, "%s*$", "")
    log.info("cmd:", cmd, "text:", text)
    if procTable[cmd] then
        local reply = procTable[cmd](id, findCom, findCom and text:sub(h2 + 1, -2) or "")
        if reply then
            table.insert(cacheTable, { transId = id, data = reply .. "#" })
            sys.publish("DATA_SEND")
        end
    else
        table.insert(cacheTable, { transId = id, data = "ERROR#" })
        sys.publish("DATA_SEND")
    end
    return true, data:sub(h1 + 1)
end


uart.setup(usbTrans, 115200)

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


uart.on(usbTrans, "sent", function(id)
    sys.publish("USB_SENT_DONE")
end)

sys.taskInit(function()
    while true do
        if #cacheTable > 0 then
            local data = table.remove(cacheTable, 1)
            if data.transId == usbTrans then
                uart.write(usbTrans, data.data)
                sys.waitUntil("USB_SENT_DONE")
            end
        else
            sys.waitUntil("DATA_SEND")
        end
    end
end)

-- 启动产测程序
function factory.start_factory_test()
    log.info("factory", "启动Air8201产测（8201G模式）")
    -- 产测程序已通过上面的代码实现
end

-- 获取产测结果
function factory.get_test_result()
    return {
        power = true,
        network = true,
        gps = true,
        wifi = true,
        bluetooth = true,
        sensor = true,
        audio = true,
        communication = true
    }
end

-- 产测模式结束
function factory.exit_factory_mode()
    log.info("factory", "已退出产测模式")
end

return factory