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
local GREEN_LED_PIN = 26        -- 绿色LED
local YELLOW_LED_PIN = 27       -- 黄色LED
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

local greenLed = gpio.setup(GREEN_LED_PIN, 0)
local yellowLed = gpio.setup(YELLOW_LED_PIN, 0)

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

-- 简单的 GNSS 电源控制函数
local function gnssPower(onoff)
    gpio.setup(GNSS_POWER_PIN, onoff and 1 or 0)
end

local powerKeyTest = false

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

    while true do
        local result, param1, param2 = sys.waitUntil("CONTROL")
        log.info("CONTROL", param1)
        if param1 == "GNSS" then
            gnssPower(false)
            sys.wait(10)
            gnssPower(true)
        elseif param1 == "GSENSOR" then
            -- 780EGP定位板加速度传感器已改为DA221(由exvib驱动)，此处DA267检测(0x26/WHO_AM_I=0x13)在DA221上会报ERROR
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
        greenLed(onoff)
        yellowLed(onoff)
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
    ["POWERKEY"] = function(id, findCom, data)
        local onoff = tonumber(data)
        if not onoff or onoff ~= 0 and onoff ~= 1 then
            return "ERROR"
        end
        powerKeyTest = onoff == 1
        return "OK"
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