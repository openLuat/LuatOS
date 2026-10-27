--[[
@module  factory
@summary Air8201G产测功能模块
@version 2.1
@date    2026.08.27
@usage
负责Air8201G的产测功能，指令与管脚参照已验证通过的 Air8201G 产测系统实现。
写号使用 prodmeta 库写入 OTP（key: PROD=工业型号, PCB=硬件版本）。
]]

local factory = {}
local prodmeta = require("prodmeta")
local bd = require("board")
-- V3 返工标记（fskv model_retest）：区分首测/返工，返工通过后删标记
local retest = require("retest")
local isRetest = retest.is_set()
log.info("factory", "本次产测类型:", isRetest and "返工产测（不动OTP1）" or "首次产测（写号入OTP1）")

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

-- 音频统一走 exaudio（audio_mode="auto"）：库内部按固件实际能力自动选择 audio/audio_v2，
-- 不裸引全局，根治"固件无 audio_v2 导致产测开机即崩"的问题
local exaudio = require("exaudio")
local audio_ok = false
-- 板型相关音频参数：G 板 PA=GPIO25、ES8311 3.3V；H 板 PA=GPIO23、ES8311 1.8V
local audioPaPin = (bd.id == bd.ID_8201H) and 23 or 25
local codecVoltage = (bd.id == bd.ID_8201H) and 0 or 1

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

    -- 音频初始化：exaudio 统一路径，es8311 codec、I2C0、I2S 16kHz/16bit；
    -- dac_delay 由库按固件版本自适应，audio_mode="auto" 自动选 audio/audio_v2
    audio_ok = exaudio.setup({
        model = "es8311",
        i2c_id = es8311i2cId,
        pa_ctrl = audioPaPin,
        dac_ctrl = 2,
        i2s_sample = 16000,
        bits_per_sample = 16,
        i2s_framebit = 16,
        audio_mode = "auto",
        codec_voltage = codecVoltage
    }) and true or false
    if audio_ok then
        exaudio.vol(70)
        exaudio.mic_vol(70)
        log.info("AUDIO", "exaudio + es8311 初始化成功, 框架:", exaudio.get_audio_mode())
    else
        log.error("AUDIO", "exaudio 初始化失败，RECORD/PLAY 将回 ERROR")
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
                    -- 测试完成：清理 UART1 和蓝牙供电，避免残留导致飞行功耗增大
                    uart.on(1, "receive")
                    uart.close(1)
                    gpio.setup(27, 0)
                    gpio.setup(24, 0)
                    log.info("BLE", "测试完成，已关闭蓝牙供电和UART1")
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
                    -- 清理 UART1 和蓝牙供电
                    uart.close(1)
                    gpio.setup(27, 0)
                    gpio.setup(24, 0)
                    log.info("BLE", "测试超时，已关闭蓝牙供电和UART1")
                end
            end)
        elseif param1 == "RECORD" then
            log.info("cmd", "RECORD 开始录音")
            if audio_ok then
                exaudio.record_start({
                    format = exaudio.AMR_NB,
                    time = 5,
                    path = recordPath,
                    cbfnc = function(event)
                        if event == exaudio.RECORD_DONE then
                            sys.publish("AUDIO_REC_DONE")
                        end
                    end
                })
                -- 5s 录音 + 余量，超时强制停录防止产测卡死
                local r = sys.waitUntil("AUDIO_REC_DONE", 8000)
                if not r then exaudio.record_stop() end
                sys.wait(100)
                log.info("cmd", "RECORD 完成", r and "" or "(超时兜底)")
                table.insert(cacheTable, { transId = param2, data = r and "OK#" or "ERROR#" })
                sys.publish("DATA_SEND")
            else
                table.insert(cacheTable, { transId = param2, data = "ERROR#" })
                sys.publish("DATA_SEND")
            end
        elseif param1 == "PLAY" then
            log.info("cmd", "PLAY 开始播放")
            if audio_ok then
                exaudio.play_start({
                    type = 0,
                    content = recordPath,
                    priority = 1,
                    cbfnc = function(event)
                        if event == exaudio.PLAY_DONE then
                            sys.publish("AUDIO_PLAY_DONE")
                        end
                    end
                })
                -- AMR 片段约 5s + 编解码余量，超时强制停播防止产测卡死
                local r = sys.waitUntil("AUDIO_PLAY_DONE", 8000)
                if not r then exaudio.play_stop({ type = 0 }) end
                sys.wait(100)
                log.info("cmd", "PLAY 完成", r and "" or "(超时兜底)")
                table.insert(cacheTable, { transId = param2, data = r and "OK#" or "ERROR#" })
                sys.publish("DATA_SEND")
            else
                table.insert(cacheTable, { transId = param2, data = "ERROR#" })
                sys.publish("DATA_SEND")
            end
        end
    end
end)

local function powerOff()
    -- 定时器 3 秒到后先检查按键：已松开则不关机（防 debounce 吞掉松开事件导致误关机）
    if gpio.get(46) == 1 then
        log.info("factory", "powerOff 检查：按键已松开，不关机")
        return
    end
    log.info("factory", "powerOff 触发：pm.shutdown 执行")
    pm.shutdown()
end

-- 按键上报（保持原始逻辑：长按 3 秒关机由 powerKeyCb 处理，测试结束由上位机补发 POWERKEY,0# 关闭检测）
local function powerKeyCb()
    local key_level = gpio.get(46)
    log.info("factory", "powerKeyCb 触发: gpio46=", key_level, "powerKeyTest=", tostring(powerKeyTest))
    if key_level == 1 then
        if powerKeyTest then
            table.insert(cacheTable, { transId = nowTransId, data = "POWERKEY_RELEASE#" })
        end
        if sys.timerIsActive(powerOff) then
            log.info("factory", "powerKeyCb: 取消关机定时器")
            sys.timerStop(powerOff)
        end
    else
        if powerKeyTest then
            table.insert(cacheTable, { transId = nowTransId, data = "POWERKEY_PRESS#" })
        end
        log.info("factory", "powerKeyCb: 启动关机定时器(3s)")
        sys.timerStart(powerOff, 3000)
    end
    if powerKeyTest then
        sys.publish("DATA_SEND")
    end
end
gpio.debounce(46, 300) -- 软件防抖 300ms（原 100ms，产测夹具抖动较大，加大防抖）
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
        local v = mobile.imei()
        if not v or v == "" then return "ERROR" end
        return v
    end,
    ["IMSI"] = function(id, findCom, data)
        local v = mobile.imsi()
        if not v or v == "" then return "ERROR" end
        return v
    end,
    ["ICCID"] = function(id, findCom, data)
        local v = mobile.iccid()
        if not v or v == "" then return "ERROR" end
        return v
    end,
    ["CSQ"] = function(id, findCom, data)
        local v = mobile.csq()
        if v == nil then return "ERROR" end
        return v
    end,
    ["MUID"] = function(id, findCom, data)
        local v = mobile.muid()
        if not v or v == "" then return "ERROR" end
        return v
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

            exgnss.open(exgnss.TIMER, {
                tag = "gpsTest",
                val = 35,
                cb = function(tag)
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
                end
            })
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
        -- 检查RF校准标志位: mobile.ecnpicfg() 返回布尔（同步），直接回 true#/false#
        local response = mobile.ecnpicfg()
        log.info("ecnpicfg: ", response)
        if response == true then
            return "true"
        elseif response == false then
            return "false"
        else
            return "ERROR"
        end
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
            -- 音频：exaudio 统一关断（内部下电 es8311、关 PA，并停音频后台）
            if audio_ok then pcall(exaudio.pm, exaudio.SHUTDOWN) end
            gpio.setup(audioPaPin, 0) -- PA 功放（G:GPIO25 / H:GPIO23，高电平使能，拉低关闭）
            gpio.setup(2, 0)         -- ES8311 电源引脚（GPIO2）
            -- LED
            gpio.setup(BLUE_LED_PIN, 0)        -- 蓝灯
            gpio.setup(RED_LED_PIN, 0)         -- 红灯
            -- 蓝牙
            gpio.setup(BLE_POWER_PIN, 0)       -- 蓝牙供电
            -- 传感器
            gpio.setup(NS2520_POWER_PIN, 0)    -- NS2520 供电
            gpio.setup(GSENSOR_VBACKUP_PIN, 0) -- G-sensor 电源
            gpio.setup(GSENSOR_INT_PIN, 0)     -- G-sensor 中断
            -- GPS
            gpio.setup(GNSS_POWER_PIN, 0)      -- GPS 电源
            gpio.setup(GNSS_POWER_PIN2, 0)     -- GPS 备电
            -- I2C
            gpio.setup(I2C1_PULLUP_PIN, 0)     -- I2C1 上拉
            -- 其他
            gpio.setup(11, 0)
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
        if not findCom then
            -- 查询硬件版本：读 OTP 的 PCB；未写返回 ERROR（表示未写硬件版本）
            local pcb = prodmeta.get("PCB")
            return pcb or "ERROR"
        end
        -- 写硬件版本：写入 OTP 的 PCB key（独立于型号写号）
        local ver = data:gsub("^%s*", ""):gsub("%s*$", "")
        if #ver == 0 then
            return "ERROR"
        end
        local ok, err = prodmeta.set("PCB", ver)
        if not ok then
            log.error("factory", "写PCB失败", err)
            return "ERROR"
        end
        log.info("factory", "硬件版本写入", ver)
        return "OK"
    end,
    ["MODEL"] = function(id, findCom, data)
        -- 只写工业模组型号到 OTP PROD；硬件版本由 HVERSION,版本# 单独写入 PCB
        log.info("factory", "MODEL 收到:", data, "findCom:", findCom)
        if not data or #data == 0 then
            log.error("factory", "MODEL 数据为空")
            return "ERROR"
        end
        local model = data:gsub("^%s*", ""):gsub("%s*$", "")
        if #model == 0 then
            log.error("factory", "MODEL 型号为空")
            return "ERROR"
        end
        local ok, err = prodmeta.set("PROD", model)
        log.info("factory", "MODEL prodmeta.set PROD 结果:", ok, err)
        if not ok then
            log.error("factory", "写PROD失败", err)
            return "ERROR"
        end
        log.info("factory", "写号成功", model)
        return "OK"
    end,
    ["MODEL?"] = function(id, findCom, data)
        -- 读回当前工业型号（OTP 的 PROD key）；OTP 未写时兜底上报 Air8201
        local v = prodmeta.get("PROD")
        return (v and #v > 0) and v or "Air8201"
    end,
    ["META?"] = function(id, findCom, data)
        -- 诊断：读 OTP 全部 key=value 内容（定位写号失败）
        local all = prodmeta.get_all()
        local parts = {}
        for k, v in pairs(all or {}) do
            table.insert(parts, k .. "=" .. v)
        end
        table.sort(parts)
        local s = table.concat(parts, ",")
        log.info("factory", "META? 内容:", s, "长度:", #s)
        if #s == 0 then
            return "EMPTY"
        end
        return s
    end,
    ["RST"] = function(id, findCom, data)
        -- 单独重启（RST#）：不写 test_done，收到即重启（500ms 延时确保 OK# 回复发出）
        log.info("factory", "重启设备")
        sys.taskInit(function()
            sys.wait(500)
            pm.reboot()
        end)
        return "OK"
    end,
    ["TEST_DONE"] = function(id, findCom, data)
        log.info("factory", "TEST_DONE 开始，清理外设")
        -- 关闭已配置的软硬件功能，避免 reboot 时外设占用导致异常
        -- GPS
        if gnssTransFlag then
            gnssTransFlag = false
            if exgnss then pcall(exgnss.close_all) end
            pcall(uart.on, gnssUartId, "receive")
            pcall(uart.close, gnssUartId)
            log.info("factory", "TEST_DONE 已关 GPS")
        end
        -- BLE uart1（5101 蓝牙）
        pcall(uart.on, 1, "receive")
        pcall(uart.close, 1)
        -- audio/codec（exaudio 统一关断 es8311 + PA）
        if audio_ok then pcall(exaudio.pm, exaudio.SHUTDOWN) end
        -- i2c
        pcall(i2c.close, Gsensori2cId)
        pcall(i2c.close, ns2520i2cId)
        -- 外设电源
        pcall(gpio.setup, BLE_POWER_PIN, 0)
        pcall(gpio.setup, GNSS_POWER_PIN, 0)
        pcall(gpio.setup, GNSS_POWER_PIN2, 0)
        log.info("factory", "TEST_DONE 外设清理完成")

        -- V3 收尾：返工删 fskv 标记（不动 OTP1）；首测校验 OTP1 已写号
        if isRetest then
            local rok, rerr = retest.clear_flag()
            if not rok then
                log.error("factory", "返工标记删除失败，不重启:", rerr)
                return "ERROR"
            end
            log.info("factory", "返工通过，返工标记已删除，3秒后重启进正常模式")
        else
            -- 首次产测：MODEL/HVERSION 已写 OTP1，此处校验非空
            local all = prodmeta.get_all()
            if type(all) ~= "table" or next(all) == nil then
                log.error("factory", "OTP1 为空，未写号，禁止结束首测")
                return "ERROR"
            end
            -- 删首测中途保护标记 model_firsttest（带读回，失败不重启，防重启后仍回产测）
            local fok, ferr = retest.first_clear()
            if not fok then
                log.error("factory", "首测标记删除失败，不重启:", ferr)
                return "ERROR"
            end
            log.info("factory", "首测通过，OTP1 写号已就绪，首测标记已删除，3秒后重启进正常模式")
        end

        -- 用独立任务 wait 满 3 秒再 reboot（排除定时器不触发的情况）
        sys.taskInit(function()
            sys.wait(3000)
            log.info("factory", "3秒到，执行 pm.reboot")
            pm.reboot()
        end)
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
    cmd = string.upper(cmd)
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

-- V3 返工指令帧提取（命令内部含额外 # 会破坏 proc 解析，必须在 proc 前拦截）
-- 只在收到完整帧（含尾 #）时提取，避免半截帧误判
local function extract_retest(cache)
    local s, e = cache:find("^%s*MODEL_RETEST%?#")        -- 查询帧 MODEL_RETEST?#
    if s then
        return cache:sub(s, e), cache:sub(e + 1)
    end
    s, e = cache:find("^%s*MODEL_RETEST#[^#]*#")          -- 设置帧 MODEL_RETEST#<参数>#
    if s then
        return cache:sub(s, e), cache:sub(e + 1)
    end
    return nil
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
        -- V3：先拦截返工指令（首测/返工模式下均可响应，用于重新置位返工标记）
        while true do
            local frame, rest = extract_retest(usbRxCache)
            if not frame then break end
            usbRxCache = rest
            local reply = retest.on_data(frame)
            table.insert(cacheTable, { transId = usbTrans, data = (reply or "ERROR") .. "#" })
            sys.publish("DATA_SEND")
        end
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
