--[[
@module  factory
@summary Air878x 系列出厂固件产测模块（融合 8780/8780V/8780G/8781/8782 产测指令）
@version 1.0
@date    2026.09.21
@author  李源龙（融合自产测代码 air201_func_test_tool）
@usage
本模块为 Air878x 出厂固件的产测模式，与正常模式（irtu_main）通过 test_done 分流。
产测通过 USB 虚拟串口 uart.VUART_0 收发指令，波特率 115200，指令以 # 结尾。

指令集（按版本融合）：
- 通用指令：VERSION/IMEI/IMSI/ICCID/CSQ/MUID/VBAT/ECNPICFG/LED/WD_TEST/FLYMODE/RST/TEST_DONE/PCBA_TEST_DONE
- 写号指令：MODEL/MODEL?(OTP PROD)、HVERSION(OTP PCB)
- 8780V 专属：RECORD(录音5s)/PLAY(回放)
- 8780G 专属：GPSTEST(内置GNSS透传)/GS_STATE(DA221加速度ID)
- 8782 专属：LDO(排针3.3V)/U232_TEST(232回环)/485独立测试(U485_TEST)

管脚（板子统一，与产测代码一致）：
  GPIO27 NET_STATUS 状态灯(高亮)
  GPIO24 看门狗喂狗脚(NPN反相)
  GPIO23 VREF 上拉(main.lua 常开)
  GPIO22 音频PA_EN / GPIO20 codec电源 (仅8780V)
  GPIO21 GNSS供电使能 (仅8780G)
  GPIO25 232供电 / GPIO26 485供电 / GPIO31 485方向 (仅8782)
]]

local factory = {}

-- ==================== 版本选择（与 factory_config 保持一致） ====================
local factory_config = require "factory_config"
local VER = factory_config.get_ver()
-- ============================================================================

local prodmeta = require("prodmeta")
-- 153c/153d 外置硬件看门狗（NPN 反相极性硬编码，8782 也用此库）
-- Air8700 板载【无】外置看门狗，仅 878x 系列使用；8700 上 WD_TEST 返回 ERROR
local ok_wdt, exair153x_wdt = pcall(require, "exair153x_wdt")
-- 内置 GNSS（仅8780G 使用，pcall 守卫缺库不崩）
local ok_exgnss, exgnss = pcall(require, "exgnss")

log.info("测试模式", "启动中 版本:", VER)

-- ============================================================
-- 硬编码管脚定义（板子统一，与产测代码一致）
-- ============================================================
local NET_LED_PIN = 27    -- 网络状态灯，高电平点亮
local WD_FEED_PIN = 24    -- 看门狗喂狗脚（NPN 反相）
-- 8780V 音频
local AUDIO_PA_PIN  = 22  -- 音频 PA_EN，高电平打开
local AUDIO_DAC_PIN = 20  -- codec(es8311) 电源控制脚
local AUDIO_I2C_ID  = 0   -- es8311 在 I2C0
local recordPath = "/record.amr"
-- 8780G GNSS/加速度
local GNSS_POWER_PIN = 21 -- 内置 GNSS 供电使能
local gnssUartId = 2      -- 内置 GNSS 串口
local GSENSOR_I2C_ID = 1
local GSENSOR_I2C_ADDR = 0x27
-- 8782 232/485
local U232_POWER_PIN = 25 -- UART3 转 232 供电
local U485_POWER_PIN = 26 -- UART2 转 485 供电
local U485_DIR_PIN   = 31 -- 485 方向控制脚(DE/RE)
local U232_UART_ID = 3
local U485_UART_ID = 2
local LDO_PIN = 23        -- LDO 输出

-- 初始化变量
local usbRxCache = ""
local cacheTable = {}
local usbTrans = uart.VUART_0
local gnssOpened = false

local netLed = gpio.setup(NET_LED_PIN, 0)
-- 外置看门狗（自动喂狗，超时档位由硬件 STRAP 配置）
-- Air8700 板载无外置看门狗，跳过初始化（仅保留软狗）
if VER ~= "8700" and exair153x_wdt then
    exair153x_wdt.init({ wdt_pin = WD_FEED_PIN, auto_feed_period_s = 180 })
end

-- ============================================================
-- 通用辅助函数
-- ============================================================
local function send_response(transId, data)
    table.insert(cacheTable, { transId = transId, data = data })
    sys.publish("DATA_SEND")
end

-- GNSS 电源控制（8780G）
local function gnssPower(onoff)
    gpio.setup(GNSS_POWER_PIN, onoff and 1 or 0)
end

-- 音频初始化（8780V）：audio_v2 优先，旧 exaudio 兜底
-- 在独立任务中初始化，避免阻塞主流程
local audio_v2_ok = false
local old_audio_ok = false

-- ============================================================
-- 232/485 回环测试通用逻辑（8782）
-- ============================================================
local function uartLoopbackTest(uartId, powerPin, testStr, needDirSwitch)
    -- 打开对应转换芯片供电
    gpio.setup(powerPin, 1)
    sys.wait(50) -- 等待供电稳定

    -- 485需要先切发送方向, 发送完成后切回接收
    if needDirSwitch then
        gpio.setup(U485_DIR_PIN, 1) -- DE使能, 发送
        sys.wait(10)
    end

    uart.setup(uartId, 9600)
    local rxData = ""
    uart.on(uartId, "receive", function(id, len)
        local data = uart.read(uartId, 64)
        if data and #data > 0 then
            rxData = rxData .. data
        end
    end)

    uart.write(uartId, testStr)

    if needDirSwitch then
        sys.wait(50) -- 等发送完成
        gpio.setup(U485_DIR_PIN, 0) -- RE使能, 接收
    end

    -- 等待回环数据(超时2s)
    local waitTime = 0
    while waitTime < 2000 and #rxData < #testStr do
        sys.wait(100)
        waitTime = waitTime + 100
    end

    -- 清理: 关闭串口, 关闭供电
    uart.on(uartId, "receive")
    uart.close(uartId)
    gpio.setup(powerPin, 0)

    -- 比对判定
    if rxData == testStr then
        return "OK"
    else
        log.error("UART_LOOPBACK", "回环测试失败, 期望:", testStr, "实际:", rxData)
        return "ERROR"
    end
end

-- ============================================================
-- 异步事件处理任务（含 sys.wait 的测试不能在 uart 回调里执行）
-- ============================================================
sys.taskInit(function()
    -- 音频初始化（仅8780V）
    if VER == "8780V" then
        local function audio_cb(request_index, event, param)
            log.info("audio_cb", request_index, event, param)
        end
        if audio_v2 then
            audio_v2.debug(true)
            audio_v2.on(audio_cb)
            audio_v2.config_pa_power_ctrl(true, AUDIO_PA_PIN, 1, 200)  -- PA 使能 GPIO22
            audio_v2.config_codec_power_ctrl(false, nil, nil, 600, 0)  -- codec 电源手动 GPIO20
            audio_v2.config(audio_v2.CFG_PARAM_I2S_MODE, audio_v2.CFG_VALUE_I2S_MODE_LSB)
            audio_v2.config(audio_v2.CFG_PARAM_I2S_FRAME_BITS, 16, 16)
            audio_v2.config(audio_v2.CFG_PARAM_I2S_CHANNEL_TYPE, audio_v2.CFG_VALUE_I2S_CHANNEL_TYPE_RIGHT)
            i2c.setup(AUDIO_I2C_ID)
            gpio.setup(AUDIO_DAC_PIN, 1)   -- codec(es8311) 电源 GPIO20 常开
            sys.wait(100)
            local ok_es, es8311 = pcall(require, "es8311")
            if ok_es and es8311 and es8311.init(AUDIO_I2C_ID, 0x01) then
                es8311.set_sample_rate(AUDIO_I2C_ID, 16000, 256)
                es8311.set_data_bits(AUDIO_I2C_ID, 16)
                es8311.set_format(AUDIO_I2C_ID)
                es8311.resume(AUDIO_I2C_ID)
                es8311.set_voice_vol(AUDIO_I2C_ID, 75)
                es8311.set_mic_vol(AUDIO_I2C_ID, 75)
                audio_v2_ok = true
                log.info("AUDIO", "audio_v2 + es8311 初始化成功")
            else
                log.error("AUDIO", "es8311 初始化失败，回退旧 exaudio")
            end
        else
            local ok_exaudio, exaudio = pcall(require, "exaudio")
            if ok_exaudio and type(audio) == "table" then
                gpio.setup(AUDIO_PA_PIN, 1)
                gpio.setup(AUDIO_DAC_PIN, 1)
                sys.wait(100)
                local audio_setup_param = {
                    model = "es8311", i2c_id = AUDIO_I2C_ID,
                    pa_ctrl = AUDIO_PA_PIN, dac_ctrl = AUDIO_DAC_PIN,
                    dac_delay = exaudio.DAC_DELAY, bits_per_sample = 16
                }
                if exaudio.setup(audio_setup_param) then
                    old_audio_ok = true
                    log.info("AUDIO", "旧 exaudio 预初始化成功")
                else
                    log.error("AUDIO", "旧 exaudio 预初始化失败")
                end
            else
                log.warn("AUDIO", "固件无音频支持，RECORD/PLAY 将回 ERROR")
            end
        end
    end

    -- 异步测试事件处理
    while true do
        local result, param1, param2 = sys.waitUntil("CONTROL")
        if param1 == "RECORD" then
            -- 录音测试（8780V）：录音5秒AMR
            if VER == "8780V" then
                if audio_v2_ok then
                    if audio_v2.record(recordPath, 5, audio_v2.DATA_CODEC_TYPE_AMR_NB) then
                        local wait = 0
                        while not audio_v2.is_all_done() and wait < 15000 do
                            sys.wait(200); wait = wait + 200
                        end
                        send_response(param2, "OK#")
                    else
                        send_response(param2, "ERROR#")
                    end
                elseif old_audio_ok then
                    local ok_exaudio, exaudio = pcall(require, "exaudio")
                    local test_result = "ERROR"
                    local function record_end_callback(event)
                        if event == exaudio.RECORD_DONE then test_result = "OK" end
                    end
                    if exaudio.record_start({ format = exaudio.AMR_NB, time = 5, path = recordPath, cbfnc = record_end_callback }) then
                        local wait = 0
                        while test_result ~= "OK" and wait < 15000 do
                            sys.wait(100); wait = wait + 100
                        end
                    end
                    send_response(param2, test_result .. "#")
                else
                    send_response(param2, "ERROR#")
                end
            else
                send_response(param2, "ERROR#")
            end
        elseif param1 == "PLAY" then
            -- 播放测试（8780V）：播放录音文件
            if VER == "8780V" then
                if audio_v2_ok then
                    if not io.exists(recordPath) or (io.fileSize(recordPath) or 0) == 0 then
                        send_response(param2, "ERROR#")
                    else
                        if audio_v2.play(recordPath) then
                            local wait = 0
                            while not audio_v2.is_all_done() and wait < 15000 do
                                sys.wait(200); wait = wait + 200
                            end
                            send_response(param2, "OK#")
                        else
                            send_response(param2, "ERROR#")
                        end
                    end
                elseif old_audio_ok then
                    if not io.exists(recordPath) or (io.fileSize(recordPath) or 0) == 0 then
                        send_response(param2, "ERROR#")
                    else
                        local ok_exaudio, exaudio = pcall(require, "exaudio")
                        local test_result = "ERROR"
                        local function play_end_callback(event)
                            if event == exaudio.PLAY_DONE then test_result = "OK" end
                        end
                        if exaudio.play_start({ type = 0, content = recordPath, cbfnc = play_end_callback, priority = 1 }) then
                            local wait = 0
                            while test_result ~= "OK" and wait < 15000 do
                                sys.wait(100); wait = wait + 100
                            end
                        end
                        send_response(param2, test_result .. "#")
                    end
                else
                    send_response(param2, "ERROR#")
                end
            else
                send_response(param2, "ERROR#")
            end
        elseif param1 == "U232_TEST" then
            -- 232 回环测试（8782）
            send_response(param2, uartLoopbackTest(U232_UART_ID, U232_POWER_PIN, "232TEST", false) .. "#")
        end
    end
end)

-- ============================================================
-- 8782 485 独立测试（不走 USB 虚拟串口）
-- 485 口上电即监听，PC 端通过 485 转 USB 发 U485_TEST，
-- 设备收到后切发送方向回 "485TEST\r\n"，PC 收到即判 OK
-- ============================================================
if VER == "8782" then
    sys.taskInit(function()
        gpio.setup(U485_POWER_PIN, 1)   -- 485 供电常开
        sys.wait(50)                    -- 等供电稳定
        uart.setup(U485_UART_ID, 9600)
        gpio.setup(U485_DIR_PIN, 0)     -- RE 使能, 接收

        local rxBuf = ""
        uart.on(U485_UART_ID, "receive", function(id, len)
            local data = uart.read(U485_UART_ID, 128)
            if data and #data > 0 then
                rxBuf = rxBuf .. data
                if string.find(rxBuf, "U485_TEST", 1, true) then
                    rxBuf = ""
                    sys.publish("U485_RECV")
                end
            end
        end)

        while true do
            sys.waitUntil("U485_RECV")
            gpio.setup(U485_DIR_PIN, 1)   -- DE 使能, 发送
            sys.wait(10)
            uart.write(U485_UART_ID, "485TEST\r\n")
            sys.wait(20)
            gpio.setup(U485_DIR_PIN, 0)   -- RE 使能, 接收
        end
    end)
end

-- ============================================================
-- 指令表（按版本融合）
-- ============================================================
local procTable = {
    -- 基础信息
    ["VERSION"] = function(id, findCom, data)
        return PROJECT .. "_" .. VERSION
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
    ["VBAT"] = function(id, findCom, data)
        if type(adc.open) ~= "function" then
            log.error("VBAT", "固件不支持 adc")
            return "ERROR"
        end
        adc.open(adc.CH_VBAT)
        local vbat = adc.get(adc.CH_VBAT)
        adc.close(adc.CH_VBAT)
        if not vbat then return "ERROR" end
        return string.format("%.2f", vbat)
    end,
    ["ECNPICFG"] = function(id, findCom, data)
        if type(mobile.ecnpicfg) ~= "function" then
            log.error("ECNPICFG", "固件未开启 LUAT_USE_MOBILE_ECNPICFG 宏")
            return "ERROR"
        end
        local passed, status = mobile.ecnpicfg()
        log.info("ECNPICFG", "passed:", passed)
        if passed == true then return "true"
        elseif passed == false then return "false" end
        return "ERROR"
    end,
    -- 硬件功能
    ["LED"] = function(id, findCom, data)
        local onoff = tonumber(data)
        if not onoff or onoff ~= 0 and onoff ~= 1 then return "ERROR" end
        netLed(onoff)
        return "OK"
    end,
    ["WD_TEST"] = function(id, findCom, data)
        -- Air8700 板载无外置看门狗，WD_TEST 直接返回 ERROR
        if VER == "8700" or not exair153x_wdt then return "ERROR" end
        -- WD_TEST#: 触发看门狗强制复位；WD_TEST,1#: 恢复正常喂狗
        if data == "" then
            exair153x_wdt.trigger_reset()
            return "OK"
        end
        local onoff = tonumber(data)
        if not onoff or onoff ~= 0 and onoff ~= 1 then return "ERROR" end
        if onoff == 1 then exair153x_wdt.feed() end
        return "OK"
    end,
    ["FLYMODE"] = function(id, findCom, data)
        local onoff = tonumber(data)
        if not onoff or onoff ~= 0 and onoff ~= 1 then return "ERROR" end
        log.info("FLYMODE", onoff)
        if onoff == 1 then
            netLed(0)
            -- 8780V 关闭音频外设
            if VER == "8780V" then
                pcall(gpio.setup, AUDIO_PA_PIN, 0)
                pcall(gpio.setup, AUDIO_DAC_PIN, 0)
            end
            -- 8780G 关闭 GNSS
            if VER == "8780G" and gnssOpened then
                pcall(exgnss.close_all)
                pcall(uart.close, gnssUartId)
                gnssOpened = false
            end
        end
        mobile.flymode(0, onoff == 1)
        return "OK"
    end,
    -- 8780V 音频
    ["RECORD"] = function(id, findCom, data)
        sys.publish("CONTROL", "RECORD", id)
        return
    end,
    ["PLAY"] = function(id, findCom, data)
        sys.publish("CONTROL", "PLAY", id)
        return
    end,
    -- 8780G GPS/加速度
    ["GPSTEST"] = function(id, findCom, data)
        if VER ~= "8780G" then return "ERROR" end
        if not ok_exgnss or not libgnss then
            log.error("GPSTEST", "固件无 libgnss（LUAT_USE_LIBGNSS）或 exgnss 不可用")
            return "ERROR"
        end
        if data == "0" then
            gnssOpened = false
            exgnss.close_all()
            gnssPower(false)
            uart.on(gnssUartId, "receive")
            uart.close(gnssUartId)
        elseif data == "1" then
            gnssOpened = true
            local gnssotps = {
                gnssmode = 1, agps_enable = true, debug = true,
                uart = gnssUartId, uartbaud = 115200,
                bind = usbTrans,          -- NMEA 直接透传给 USB 上位机看定位
                auto_open = true,
                gnss_volgpio = GNSS_POWER_PIN -- GNSS 供电使能脚
            }
            exgnss.setup(gnssotps)
            exgnss.open(exgnss.DEFAULT, { tag = "gpsTest", cb = function(tag)
                local rmc = exgnss.rmc(2)
                if rmc and rmc.valid then
                    log.info("GPS定位成功", "纬度:", rmc.lat, "经度:", rmc.lng)
                end
            end })
            -- 提高 NMEA 输出频率，方便上位机快速看到定位
            sys.timerStart(uart.write, 500, gnssUartId, "$CFGTP,1000000,500000,7,0,800,0*7D\r\n")
        else
            return "ERROR"
        end
        return "OK"
    end,
    ["GS_STATE"] = function(id, findCom, data)
        if VER ~= "8780G" then return "ERROR" end
        -- 模组内置 DA221 加速度传感器：软复位后读芯片 ID（寄存器 0x01，期望 0x13）
        i2c.setup(GSENSOR_I2C_ID, i2c.SLOW)
        i2c.send(GSENSOR_I2C_ID, GSENSOR_I2C_ADDR, {0x00, 0x24}, 1) -- 软件复位
        i2c.send(GSENSOR_I2C_ID, GSENSOR_I2C_ADDR, 0x01, 1)         -- 读芯片 ID
        local chipid = i2c.recv(GSENSOR_I2C_ID, GSENSOR_I2C_ADDR, 1)
        i2c.close(GSENSOR_I2C_ID)
        if chipid and string.byte(chipid) == 0x13 then
            return "OK"
        else
            log.error("GS_STATE", "读取DA221芯片ID失败", chipid)
            return "ERROR"
        end
    end,
    -- 8782 LDO/232
    ["LDO"] = function(id, findCom, data)
        if VER ~= "8782" then return "ERROR" end
        local onoff = tonumber(data)
        if not onoff or onoff ~= 0 and onoff ~= 1 then return "ERROR" end
        gpio.setup(LDO_PIN, onoff)
        return "OK"
    end,
    ["U232_TEST"] = function(id, findCom, data)
        if VER ~= "8782" then return "ERROR" end
        sys.publish("CONTROL", "U232_TEST", id)
        return
    end,
    -- 写号（OTP）
    ["MODEL"] = function(id, findCom, data)
        if not data or #data == 0 then return "ERROR" end
        local model = data:gsub("^%s*", ""):gsub("%s*$", "")
        if #model == 0 then return "ERROR" end
        local ok, err = prodmeta.set("PROD", model)
        if not ok then
            log.error("factory", "写PROD失败", err)
            return "ERROR"
        end
        log.info("factory", "写号成功", model)
        return "OK"
    end,
    ["MODEL?"] = function(id, findCom, data)
        local v = prodmeta.get("PROD")
        return v or "ERROR"
    end,
    ["HVERSION"] = function(id, findCom, data)
        if not findCom then
            local pcb = prodmeta.get("PCB")
            return pcb or "ERROR"
        end
        local ver = data:gsub("^%s*", ""):gsub("%s*$", "")
        if #ver == 0 then return "ERROR" end
        local ok, err = prodmeta.set("PCB", ver)
        if not ok then
            log.error("factory", "写PCB失败", err)
            return "ERROR"
        end
        log.info("factory", "硬件版本写入", ver)
        return "OK"
    end,
    -- 完成
    ["RST"] = function(id, findCom, data)
        log.info("factory", "重启设备")
        if not (pm and pm.reboot) then
            log.error("factory", "固件不支持 pm.reboot")
            return "ERROR"
        end
        sys.taskInit(function()
            sys.wait(800) -- 留足时间把 OK# 发出去再重启
            pm.reboot()
        end)
        return "OK"
    end,
    ["TEST_DONE"] = function(id, findCom, data)
        -- 测试完成：关闭外设，写 test_done，延时重启进 iRTU 正常模式
        netLed(0)
        if VER == "8780V" then
            pcall(gpio.setup, AUDIO_PA_PIN, 0)
            pcall(gpio.setup, AUDIO_DAC_PIN, 0)
        end
        if VER == "8780G" then
            if gnssOpened then
                pcall(exgnss.close_all)
                pcall(uart.on, gnssUartId, "receive")
                pcall(uart.close, gnssUartId)
                gnssOpened = false
            end
            pcall(gpio.setup, GNSS_POWER_PIN, 0)
            pcall(i2c.close, GSENSOR_I2C_ID)
        end
        fskv.set("test_done", true)
        log.info("测试完成，已保存状态，3秒后重启")
        if pm and pm.reboot then
            sys.timerStart(pm.reboot, 3000)
        else
            log.error("factory", "固件不支持 pm.reboot，请手动重启（test_done 已写入）")
        end
        return "OK"
    end,
    ["PCBA_TEST_DONE"] = function(id, findCom, data)
        if not (pm and pm.shutdown) then
            log.error("factory", "固件不支持 pm.shutdown")
            return "ERROR"
        end
        sys.timerStart(pm.shutdown, 3000)
        return "OK"
    end,
}

-- ============================================================
-- 指令解析
-- ============================================================
local function proc(id, data)
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
            send_response(id, reply .. "#")
        end
    else
        send_response(id, "ERROR#")
    end
    return true, data:sub(h1 + 1)
end

-- ============================================================
-- 串口收发（USB 虚拟串口 VUART_0）
-- ============================================================
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

return factory
