--[[
@module  factory
@summary Air8203V 出厂固件产测模块（V3：一套固件含产测 + 正常业务，外置 Air510w GNSS）
@version 1.0.0
@date    2026.10.23
@usage
本模块为 Air8203V 出厂固件的产测模式，V3 启动四段分流由 main.lua 完成：
  fskv model_retest → fskv model_firsttest → OTP1 空(首测) → OTP1 有值(正常)。
产测通过 USB 虚拟串口 uart.VUART_0 收发指令，波特率 115200，指令以 # 结尾。

- 首次产测：MODEL / HVERSION 写号入 OTP1（PROD=工业型号，PCB=硬件版本），
            TEST_DONE 校验 OTP1 非空 + 删除 model_firsttest 后重启进正常模式
- 返工产测：fskv 有 model_retest 标记，全程不动 OTP1，TEST_DONE 仅删返工标记后重启
- 返工指令 MODEL_RETEST#CONFIRM / MODEL_RETEST? 由 retest 模块在 proc 前拦截

硬件管脚 / 指令（唯一权威：旧 Air8203V 产测固件 lib/factory.lua v1.9）：
  GPIO27 网络灯(高亮) / GPIO23 VREF(SIM上拉+gsensor供电+GNSS备电, main.lua 常开)
  GPIO24 BLE_RESET(NPN反相, 高=复位) / 蓝牙 Air5101 走 UART1/9600 + exril_5101
  GPIO25 外置 Air510w GNSS ON_OFF(三极管反相: 低=开 高=关)，NMEA 走 UART2/115200
  GPIO26 音频 PA(自定义, 勿与官方 GPIO22 混用) / GPIO20 es8311 codec 电源 / I2C0
  DA221 加速度 I2C1/0x27(ID 0x01 期望 0x13)
  GPIO21 光敏防拆(GL5528, 暗=高亮=低, 双边沿+100ms 防抖)
  RS485 UART3(pin52/53 复用 GPIO34/35) + 方向 GPIO1 + 隔离供电 GPIO37，9600

指令集（24 条，与旧产测一致 + 新增 TTS）：
  VERSION/LED/IMEI/IMSI/ICCID/CSQ/MUID/VBAT/GS_STATE/BLE_TEST/BLERESTART/LSENSE/
  GPSTEST/RECORD/PLAY/TTS/ECNPICFG/FLYMODE/HVERSION/MODEL/MODEL?/RST/TEST_DONE/PCBA_TEST_DONE
]]

local factory = {}

log.info("测试模式", "启动中")

local prodmeta = require("prodmeta")
-- V3 返工 / 首测双标记（fskv model_retest / model_firsttest）
local retest = require("retest")
local isRetest = retest.is_set()
log.info("测试模式", "本次产测类型:", isRetest and "返工产测（不动OTP1）" or "首次产测（写号入OTP1）")
-- Air5101 蓝牙：底层走官方扩展库 exril_5101（UART1/9600 独占，AT/收发/看门狗库封装）
-- 喂狗任务在 main.lua（两模式共用），本文件改看门狗配置调全局 ble_wdt_config()
local exril_5101 = require("exril_5101")

-- ============================================================
-- 硬编码管脚定义（主控 Air780EHV，与旧 Air8203V 产测固件一致）
-- ============================================================
local NET_LED_PIN = 27        -- 网络灯, 高电平点亮
local VREF_PIN = 23           -- VREF: SIM上拉+gsensor供电+GNSS备电; 常开, 飞行模式拉低
local BLE_RESET_PIN = 24      -- BLE复位, 经NPN: 高→复位, 低=非复位态
local GNSS_UART_ID = 2        -- UART2: 外置 Air510w GNSS, 115200
local GNSS_ONOFF_PIN = 25     -- 510w ON_OFF(三极管反相): 低=开, 高=关
local AUDIO_PA_PIN = 26       -- 音频PA, 高电平打开(自定义, 官方 AUDIOPA_EN 是 GPIO22 勿混用)
local AUDIO_DAC_PIN = 20      -- es8311 codec 控制脚, 官方默认 GPIO20
local AUDIO_I2C_ID = 0        -- es8311 在 I2C0
local recordPath = "/record.amr"
-- DA221 加速度：I2C1 / 0x27，ID 寄存器 0x01 期望 0x13
local GSENSOR_I2C_ID = 1
local GSENSOR_I2C_ADDR = 0x27
-- RS485：UART3(GPIO34/35 复用)，方向 GPIO1(高发 DE/低收 RE)，隔离供电 GPIO37
local U485_UART_ID = 3
local U485_BAUD = 9600
local U485_DIR_PIN = 1
local U485_POWER_PIN = 37
-- 光敏防拆：GPIO21（暗=高亮=低，GL5528+分压）
local LSENSE_PIN = 21

-- audio_v2 + es8311 运行时状态（开机在 CONTROL 任务里初始化一次）
local es8311 = nil            -- es8311 I2C 驱动（audio_v2 新框架）
local audio_v2_ok = false     -- true: RECORD/PLAY 走 audio_v2 同步接口(~5s)
local exaudio = nil           -- 旧 exaudio（audio_v2 不可用时兜底，开机预初始化一次）
local old_audio_ok = false    -- true: RECORD/PLAY 走 record_start/play_start(~6.4s)

-- 初始化变量
local usbRxCache = ""
local cacheTable = {}
local usbTrans = uart.VUART_0

local netLed = gpio.setup(NET_LED_PIN, 0)

-- VREF / BLE复位 / GNSS ON_OFF 初始电平（main.lua 已置 VREF，这里重复置位幂等）
gpio.setup(VREF_PIN, 1)
gpio.setup(BLE_RESET_PIN, 0)
gpio.setup(GNSS_ONOFF_PIN, 1)  -- 默认拉高=关 510w（待机省电，非断电）

-- 光敏防拆：双边沿中断 + 100ms 软件防抖；LSENSE# 先清标志再等中断
local lsense_triggered = false
gpio.debounce(LSENSE_PIN, 100)
gpio.setup(LSENSE_PIN, function()
    lsense_triggered = true
    log.info("LSENSE", "光敏中断触发")
end, gpio.PULLUP, gpio.BOTH)

-- ============================================================
-- 通用辅助函数
-- ============================================================
local function send_response(transId, data)
    table.insert(cacheTable, { transId = transId, data = data })
    sys.publish("DATA_SEND")
end

-- ============================================================
-- RS485 独立测试（不走 USB 虚拟串口，方案同旧 8203V/Air8782）：
-- 上电即供电常开 + 接收方向监听；PC 经"485转USB"发 U485_TEST#，
-- 设备匹配后切发送方向回 "485TEST\r\n"，PC 收到判 OK；其余指令走 USB。
-- ============================================================
pins.setup(53, "UART3_RX")      -- PIN53/GPIO35 -> UART3_RX
pins.setup(52, "UART3_TX")      -- PIN52/GPIO34 -> UART3_TX
gpio.setup(U485_POWER_PIN, 1)   -- 485 隔离供电常开
gpio.setup(U485_DIR_PIN, 0)     -- RE 使能, 默认接收

sys.taskInit(function()
    uart.setup(U485_UART_ID, U485_BAUD)
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
        gpio.setup(U485_DIR_PIN, 1)             -- DE 使能, 发送
        sys.wait(10)                            -- 等 DE 稳定
        uart.write(U485_UART_ID, "485TEST\r\n")
        sys.wait(20)                            -- 等 TX 发完(10字节@9600≈11ms)
        gpio.setup(U485_DIR_PIN, 0)             -- RE 使能, 接收
        log.info("U485", "已通过 485 回复 485TEST")
    end
end)

-- GNSS NMEA 透传
local gnssTransFlag = false
-- GPSTEST 重入保护：重发 GPSTEST,1# 不重复开关 510w（反复冷启会一直定不上位）
local gnssTestOn = false

local function nmeaToUsb(id, len)
    while true do
        local data = uart.read(GNSS_UART_ID, 512)
        if not data or #data == 0 then
            break
        end
        if gnssTransFlag then
            uart.write(usbTrans, data)
        end
    end
end

-- 510w ON_OFF（三极管反相）：高=关
local function gnssPowerOff()
    gpio.setup(GNSS_ONOFF_PIN, 1)
end

-- 开 510w：先高 200ms(等效冷启复位) → 拉低 + 等 500ms NMEA 输出
local function gnssPowerOn()
    gpio.setup(GNSS_ONOFF_PIN, 1)
    sys.wait(200)
    gpio.setup(GNSS_ONOFF_PIN, 0)
    sys.wait(500)
end

-- ============================================================
-- "4G让BLE重启"测试: 复位 BLE → 重配看门狗 → 读版本号校验
-- 返回: 成功 "Ble Version=xxx", 失败 "ERROR"
-- ============================================================
local function ble_reset_and_verify()
    gpio.setup(BLE_RESET_PIN, 1)   -- NPN 导通 → RESET 拉低复位
    sys.wait(200)
    gpio.setup(BLE_RESET_PIN, 0)
    sys.wait(600)                  -- 等 BLE 重启稳定
    -- 复位后默认回透传，重新切 AT
    local mok, mmsg = exril_5101.mode(exril_5101.MODE_AT, 3000)
    if not mok then
        log.error("BLERESTART", "BLE复位后切AT模式失败:", mmsg)
        return "ERROR"
    end
    -- 重配看门狗（超时必须 60s > 30s 喂狗间隔，否则 BLE 会复位主控打断产测）
    ble_wdt_config(true)
    local ver, err = exril_5101.get("ver", 3000)
    if ver then
        log.info("BLERESTART", "BLE 已恢复正常, 版本:", ver)
        return "Ble Version=" .. ver
    end
    log.error("BLERESTART", "BLE重启后校验无响应:", err)
    return "ERROR"
end

-- ============================================================
-- 异步事件处理任务（含 sys.wait 的测试不能在 uart 回调里执行）
-- 开机先初始化音频一次（audio_v2 优先，旧 exaudio 兜底）
-- ============================================================
sys.taskInit(function()
    local function audio_cb(request_index, event, param)
        log.info("audio_cb", request_index, event, param)
    end
    if audio_v2 then
        audio_v2.debug(true)
        audio_v2.on(audio_cb)
        audio_v2.config_pa_power_ctrl(true, AUDIO_PA_PIN, 1, 200)   -- PA 使能 GPIO26, 高有效
        audio_v2.config_codec_power_ctrl(false, nil, nil, 600, 0)   -- codec 电源手动 GPIO20
        audio_v2.config(audio_v2.CFG_PARAM_I2S_MODE, audio_v2.CFG_VALUE_I2S_MODE_LSB)
        audio_v2.config(audio_v2.CFG_PARAM_I2S_FRAME_BITS, 16, 16)
        audio_v2.config(audio_v2.CFG_PARAM_I2S_CHANNEL_TYPE, audio_v2.CFG_VALUE_I2S_CHANNEL_TYPE_RIGHT)
        i2c.setup(AUDIO_I2C_ID)
        gpio.setup(AUDIO_DAC_PIN, 1)
        sys.wait(100)
        es8311 = require "es8311"
        -- 8203V 为标准 3.3V 电平（旧 exaudio 未用 1.8V），es8311.init(i2c) 默认即可
        if es8311.init(AUDIO_I2C_ID) then
            es8311.set_sample_rate(AUDIO_I2C_ID, 16000, 256)
            es8311.set_data_bits(AUDIO_I2C_ID, 16)
            es8311.set_format(AUDIO_I2C_ID)
            es8311.resume(AUDIO_I2C_ID)
            es8311.set_voice_vol(AUDIO_I2C_ID, 80)
            es8311.set_mic_vol(AUDIO_I2C_ID, 85)
            audio_v2_ok = true
            log.info("AUDIO", "audio_v2 + es8311 初始化成功（录音/播放走同步接口，约 5s）")
        else
            log.error("AUDIO", "es8311 初始化失败（chip id 读不到），将回退旧 exaudio")
        end
    else
        log.warn("AUDIO", "固件不支持 audio_v2，回退旧 exaudio")
    end

    -- 旧 exaudio 兜底：开机 setup 预初始化一次（i2c+i2s+读 chip id 约 2.7s），
    -- RECORD/PLAY 只 record_start/play_start（约 6.4s），省掉每条指令重复 setup
    if not audio_v2_ok then
        gpio.setup(AUDIO_PA_PIN, 1)
        gpio.setup(AUDIO_DAC_PIN, 1)
        sys.wait(100)
        exaudio = require "exaudio"
        local audio_setup_param = {
            model = "es8311",
            i2c_id = AUDIO_I2C_ID,
            pa_ctrl = AUDIO_PA_PIN,
            dac_ctrl = AUDIO_DAC_PIN,
            -- dac_delay 不写死：单位随固件版本变化（V2026 起为 100ms），用库自适应值
            dac_delay = exaudio.DAC_DELAY,
            bits_per_sample = 16
        }
        if exaudio.setup(audio_setup_param) then
            old_audio_ok = true
            log.info("AUDIO", "旧 exaudio 已预初始化（RECORD/PLAY 走异步回调，约 6.4s）")
        else
            log.error("AUDIO", "旧 exaudio 预初始化失败，RECORD/PLAY 将回 ERROR")
        end
    end

    while true do
        local result, param1, param2, param3 = sys.waitUntil("CONTROL")
        if param1 == "BLE_TEST" then
            -- 读 Air5101 版本号；无响应则 GPIO24 复位后重试一次
            local function read_ble_ver()
                local mok, mmsg = exril_5101.mode(exril_5101.MODE_AT, 3000)
                if not mok then
                    log.warn("BLE_TEST", "切AT模式失败:", mmsg)
                    return nil
                end
                local ver, err = exril_5101.get("ver", 3000)
                if not ver then
                    log.warn("BLE_TEST", "读版本号失败:", err)
                end
                return ver
            end
            local ver = read_ble_ver()
            if not ver then
                log.warn("BLE_TEST", "BLE无响应, 复位后重试")
                gpio.setup(BLE_RESET_PIN, 1)
                sys.wait(200)
                gpio.setup(BLE_RESET_PIN, 0)
                sys.wait(600)
                ver = read_ble_ver()
            end
            if ver then
                send_response(param2, "Ble Version=" .. ver .. "#")
            else
                log.error("BLE_TEST", "BLE复位后仍无响应")
                send_response(param2, "ERROR#")
            end
        elseif param1 == "RECORD" then
            -- 录音 5s(AMR)
            if audio_v2_ok then
                log.info("RECORD", "开始录音(audio_v2)")
                es8311.resume(AUDIO_I2C_ID)
                if audio_v2.record(recordPath, 5, audio_v2.DATA_CODEC_TYPE_AMR_NB) then
                    local wait = 0
                    while not audio_v2.is_all_done() and wait < 15000 do
                        sys.wait(200); wait = wait + 200
                    end
                    log.info("RECORD", "录音完成")
                    send_response(param2, "OK#")
                else
                    log.error("RECORD", "录音启动失败")
                    send_response(param2, "ERROR#")
                end
            elseif old_audio_ok then
                local test_result = "ERROR"
                local function record_end_callback(event)
                    if event == exaudio.RECORD_DONE then
                        log.info("RECORD", "录音完成")
                        test_result = "OK"
                    end
                end
                if exaudio.record_start({ format = exaudio.AMR_NB, time = 5, path = recordPath, cbfnc = record_end_callback }) then
                    log.info("RECORD", "录音开始, 完成回调置 OK 即返回")
                    local wait = 0
                    while test_result ~= "OK" and wait < 15000 do
                        sys.wait(100); wait = wait + 100
                    end
                else
                    log.error("RECORD", "录音启动失败")
                end
                send_response(param2, test_result .. "#")
            else
                log.error("RECORD", "音频未初始化（audio_v2 与旧 exaudio 均不可用）")
                send_response(param2, "ERROR#")
            end
        elseif param1 == "PLAY" then
            -- 播放 RECORD 录制的文件；本 handler 不能 return 提前退出（会结束整个 CONTROL 任务）
            local function file_ready()
                return io.exists(recordPath) and (io.fileSize(recordPath) or 0) > 0
            end
            if audio_v2_ok then
                if not file_ready() then
                    log.error("PLAY", "录音文件不存在或为空, 请先执行 RECORD#", recordPath)
                    send_response(param2, "ERROR#")
                else
                    log.info("PLAY", "开始播放(audio_v2)")
                    es8311.resume(AUDIO_I2C_ID)
                    if audio_v2.play(recordPath) then
                        local wait = 0
                        while not audio_v2.is_all_done() and wait < 15000 do
                            sys.wait(200); wait = wait + 200
                        end
                        log.info("PLAY", "播放完成")
                        send_response(param2, "OK#")
                    else
                        log.error("PLAY", "播放启动失败")
                        send_response(param2, "ERROR#")
                    end
                end
            elseif old_audio_ok then
                if not file_ready() then
                    log.error("PLAY", "录音文件不存在或为空, 请先执行 RECORD#", recordPath)
                    send_response(param2, "ERROR#")
                else
                    local test_result = "ERROR"
                    local function play_end_callback(event)
                        if event == exaudio.PLAY_DONE then
                            log.info("PLAY", "播放完成")
                            test_result = "OK"
                        end
                    end
                    if exaudio.play_start({ type = 0, content = recordPath, cbfnc = play_end_callback, priority = 1 }) then
                        log.info("PLAY", "音频播放开始")
                        local wait = 0
                        while test_result ~= "OK" and wait < 15000 do
                            sys.wait(100); wait = wait + 100
                        end
                    else
                        log.error("PLAY", "播放启动失败")
                    end
                    send_response(param2, test_result .. "#")
                end
            else
                log.error("PLAY", "音频未初始化（audio_v2 与旧 exaudio 均不可用）")
                send_response(param2, "ERROR#")
            end
        elseif param1 == "TTS" then
            -- TTS 朗读文本（仅支持中文）；param2=串口id, param3=待朗读文本
            local ttsText = param3
            local ttsResult = "ERROR"
            if audio_v2_ok then
                log.info("TTS", "开始朗读(audio_v2):", ttsText)
                es8311.resume(AUDIO_I2C_ID)
                local ttsOk, ttsReq = audio_v2.tts(ttsText)
                if ttsOk then
                    local wait = 0
                    while not audio_v2.is_all_done() and wait < 20000 do
                        sys.wait(200); wait = wait + 200
                    end
                    if audio_v2.is_all_done() then
                        ttsResult = "OK"
                        log.info("TTS", "朗读完成")
                    else
                        log.error("TTS", "朗读超时(20s)")
                        audio_v2.stop(ttsReq)
                    end
                else
                    log.error("TTS", "TTS 启动失败")
                end
            elseif old_audio_ok then
                local function tts_end_callback(event)
                    if event == exaudio.PLAY_DONE then
                        log.info("TTS", "朗读完成")
                        ttsResult = "OK"
                    end
                end
                log.info("TTS", "开始朗读(旧exaudio):", ttsText)
                if exaudio.play_start({ type = 1, content = ttsText, cbfnc = tts_end_callback, priority = 1 }) then
                    local wait = 0
                    while ttsResult ~= "OK" and wait < 20000 do
                        sys.wait(100); wait = wait + 100
                    end
                    if ttsResult ~= "OK" then
                        log.error("TTS", "朗读超时(20s)")
                        exaudio.play_stop({ type = 1 })
                    end
                else
                    log.error("TTS", "TTS 启动失败")
                end
            else
                log.error("TTS", "音频未初始化（audio_v2 与旧 exaudio 均不可用）")
            end
            send_response(param2, ttsResult .. "#")
        elseif param1 == "BLERESTART" then
            send_response(param2, ble_reset_and_verify() .. "#")
        elseif param1 == "LSENSE" then
            -- 等见光触发中断，5s 超时
            local wait = 0
            while not lsense_triggered and wait < 5000 do
                sys.wait(100); wait = wait + 100
            end
            if lsense_triggered then
                send_response(param2, "OK#")
                log.info("LSENSE", "检测到亮光变化，光敏正常")
            else
                send_response(param2, "ERROR#")
                log.error("LSENSE", "5秒内未检测到亮光变化")
            end
        end
    end
end)

-- ============================================================
-- 指令表（24 条）
-- ============================================================
local procTable = {
    ["VERSION"] = function(id, findCom, data)
        return PROJECT .. "_" .. VERSION
    end,
    ["LED"] = function(id, findCom, data)
        local onoff = tonumber(data)
        if not onoff or onoff ~= 0 and onoff ~= 1 then
            return "ERROR"
        end
        netLed(onoff)
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
    ["VBAT"] = function(id, findCom, data)
        -- adc.CH_VBAT 读出即 mV，保留 2 位小数（全产品统一 mV，不要再 /1000）
        if type(adc.open) ~= "function" then
            log.error("VBAT", "固件不支持 adc")
            return "ERROR"
        end
        adc.open(adc.CH_VBAT)
        local vbat = adc.get(adc.CH_VBAT)
        adc.close(adc.CH_VBAT)
        if not vbat then
            log.error("VBAT", "读取电池电压失败")
            return "ERROR"
        end
        log.info("VBAT", "vbat(mV):", vbat)
        return string.format("%.2f", vbat)
    end,
    ["GS_STATE"] = function(id, findCom, data)
        -- DA221：软复位 → 读 ID(0x01 期望 0x13)；供电/上拉 VREF 已常开
        i2c.setup(GSENSOR_I2C_ID, i2c.SLOW)
        i2c.send(GSENSOR_I2C_ID, GSENSOR_I2C_ADDR, {0x00, 0x24}, 1)
        i2c.send(GSENSOR_I2C_ID, GSENSOR_I2C_ADDR, 0x01, 1)
        local chipid = i2c.recv(GSENSOR_I2C_ID, GSENSOR_I2C_ADDR, 1)
        i2c.close(GSENSOR_I2C_ID)
        if chipid and string.byte(chipid) == 0x13 then
            return "OK"
        end
        log.error("GS_STATE", "读取DA221芯片ID失败", chipid)
        return "ERROR"
    end,
    ["BLE_TEST"] = function(id, findCom, data)
        sys.publish("CONTROL", "BLE_TEST", id)
        return
    end,
    ["BLERESTART"] = function(id, findCom, data)
        sys.publish("CONTROL", "BLERESTART", id)
        return
    end,
    ["LSENSE"] = function(id, findCom, data)
        lsense_triggered = false   -- 清标志后由 CONTROL 任务等中断
        sys.publish("CONTROL", "LSENSE", id)
        return
    end,
    ["GPSTEST"] = function(id, findCom, data)
        -- GPSTEST,1#: 开 510w + UART2 NMEA 透传 USB；GPSTEST,0#: 关
        if data == "1" then
            if gnssTestOn then
                log.warn("GPSTEST", "GNSS测试已在进行中, 忽略重复 GPSTEST,1#")
                return "OK"
            end
            gnssTestOn = true
            gnssTransFlag = true
            uart.setup(GNSS_UART_ID, 115200)
            uart.on(GNSS_UART_ID, "receive", nmeaToUsb)
            sys.taskInit(function()   -- gnssPowerOn 含 sys.wait，异步执行
                gnssPowerOn()
                log.info("GPSTEST", "510w 已开启, NMEA 透传到 VUART_0")
            end)
            return "OK"
        elseif data == "0" then
            gnssTestOn = false
            gnssTransFlag = false
            uart.on(GNSS_UART_ID, "receive")
            uart.close(GNSS_UART_ID)
            gnssPowerOff()
            log.info("GPSTEST", "510w 已关闭")
            return "OK"
        end
        return "ERROR"
    end,
    ["RECORD"] = function(id, findCom, data)
        sys.publish("CONTROL", "RECORD", id)
        return
    end,
    ["PLAY"] = function(id, findCom, data)
        sys.publish("CONTROL", "PLAY", id)
        return
    end,
    ["TTS"] = function(id, findCom, data)
        -- TTS,待朗读文本# ；文本为空直接 ERROR，不进 CONTROL 占用音频
        local text = data and data:gsub("^%s*", ""):gsub("%s*$", "") or ""
        if #text == 0 then
            log.error("TTS", "文本为空")
            return "ERROR"
        end
        sys.publish("CONTROL", "TTS", id, text)
        return
    end,
    ["ECNPICFG"] = function(id, findCom, data)
        -- RF 校准标志只读；C 层被 LUAT_USE_MOBILE_ECNPICFG 宏包着，缺宏为 nil，直接调会崩 VM
        if type(mobile.ecnpicfg) ~= "function" then
            log.error("ECNPICFG", "固件未开启 LUAT_USE_MOBILE_ECNPICFG 宏")
            return "ERROR"
        end
        local passed, status = mobile.ecnpicfg()
        log.info("ECNPICFG", "passed:", passed,
                 "rfCaliDone:", status and status.rfCaliDone,
                 "rfNSTDone:", status and status.rfNSTDone,
                 "rfCTDone:", status and status.rfCTDone)
        if passed == true then return "true"
        elseif passed == false then return "false" end
        return "ERROR"
    end,
    ["FLYMODE"] = function(id, findCom, data)
        local onoff = tonumber(data)
        if not onoff or onoff ~= 0 and onoff ~= 1 then
            return "ERROR"
        end
        log.info("FLYMODE", onoff)
        if onoff == 1 then
            -- 进飞行前关外设防漏电
            if audio_v2_ok then
                -- shutdown 去激活驱动后 codec 不应答 I2C，禁止再 es8311.power_down（会超时刷屏）
                audio_v2.shutdown(true, true, true)
            end
            -- DA221 挂起（0x11=0x80；VREF 仍常开，ID 仍可读）
            i2c.setup(GSENSOR_I2C_ID, i2c.SLOW)
            i2c.send(GSENSOR_I2C_ID, GSENSOR_I2C_ADDR, {0x11, 0x80}, 1)
            i2c.close(GSENSOR_I2C_ID)
            -- 510w：关 UART2 + ON_OFF 高（待机，非断电）
            if gnssTestOn or gnssTransFlag then
                gnssTestOn = false
                gnssTransFlag = false
                uart.on(GNSS_UART_ID, "receive")
                uart.close(GNSS_UART_ID)
            end
            gpio.setup(VREF_PIN, 0)
            gpio.setup(NET_LED_PIN, 0)
            gpio.setup(AUDIO_PA_PIN, 0)
            gpio.setup(AUDIO_DAC_PIN,0)
            gpio.setup(GNSS_ONOFF_PIN, 1)
            gpio.setup(U485_POWER_PIN, 0)
            gpio.setup(U485_DIR_PIN, 0)
            uart.close(U485_UART_ID)
            gpio.setup(LSENSE_PIN, nil, gpio.PULLUP)   -- 关光敏中断，保留上拉避免悬空
            -- BLE：先关看门狗 + 进低功耗(P3)，等回包后再 flymode；
            -- 否则 flymode 先跑、关狗指令没发完，看门狗仍可能复位主控。板上无 BLE 供电脚只能软低功耗
            sys.taskInit(function()
                exril_5101.mode(exril_5101.MODE_AT, 3000)
                ble_wdt_config(false)
                exril_5101.power(exril_5101.P3)
                log.info("FLYMODE", "BLE 看门狗已关 + 已进低功耗，进入飞行模式")
                mobile.flymode(1, true)
                mobile.flymode(0, true)
            end)
        else
            mobile.flymode(1, false)
            mobile.flymode(0, false)
            gpio.setup(VREF_PIN, 1)
        end
        return "OK"
    end,
    ["HVERSION"] = function(id, findCom, data)
        -- HVERSION,版本# 写 OTP PCB；HVERSION# 读回（未写 ERROR）
        if not findCom then
            return prodmeta.get("PCB") or "ERROR"
        end
        local ver = data:gsub("^%s*", ""):gsub("%s*$", "")
        if #ver == 0 then return "ERROR" end
        local ok, err = prodmeta.set("PCB", ver)
        if not ok then
            log.error("factory", "写PCB失败", err)
            return "ERROR"
        end
        log.info("测试模式", "硬件版本写入", ver)
        return "OK"
    end,
    ["MODEL"] = function(id, findCom, data)
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
        if not ok then
            log.error("factory", "写PROD失败", err)
            return "ERROR"
        end
        log.info("factory", "写号成功", model)
        return "OK"
    end,
    ["MODEL?"] = function(id, findCom, data)
        return prodmeta.get("PROD") or "ERROR"
    end,
    ["RST"] = function(id, findCom, data)
        -- 不写收尾，重启后仍进产测（验证写号掉电不丢）
        if not (pm and pm.reboot) then
            log.error("factory", "固件不支持 pm.reboot")
            return "ERROR"
        end
        sys.taskInit(function()
            sys.wait(800)
            pm.reboot()
        end)
        return "OK"
    end,
    ["TEST_DONE"] = function(id, findCom, data)
        -- V3 收尾闸门（同步先做，失败直接 ERROR，不删标记/不重启）
        local function finish_gate()
            if not (pm and pm.reboot) then
                log.error("factory", "固件不支持 pm.reboot")
                return false
            end
            if isRetest then
                -- 返工：全程不动 OTP1，仅删 model_retest
                local ok, err = retest.clear_flag()
                if not ok then
                    log.error("factory", "返工标记删除失败，不重启:", err)
                    return false
                end
                log.info("factory", "返工标记已删除")
            else
                -- 首测：OTP1 必须非空（型号/版本已写），再删 model_firsttest
                local all = prodmeta.get_all()
                if type(all) ~= "table" or next(all) == nil then
                    log.error("factory", "OTP1 为空，未写号，禁止结束首测")
                    return false
                end
                local ok, err = retest.first_clear()
                if not ok then
                    log.error("factory", "首测标记删除失败，不重启:", err)
                    return false
                end
                log.info("factory", "OTP1 写号已就绪，首测标记已删除")
            end
            return true
        end

        if not finish_gate() then
            return "ERROR"
        end

        -- 闸门通过 → 回 OK，并异步关外设 + BLE 看门狗保持使能 + 3s 后重启进正常模式
        sys.taskInit(function()
            local gnss_was_on = gnssTestOn or gnssTransFlag
            gnssTestOn = false
            gnssTransFlag = false
            gnssPowerOff()
            if gnss_was_on then
                uart.on(GNSS_UART_ID, "receive")
                uart.close(GNSS_UART_ID)
            end
            if audio_v2_ok then
                audio_v2.shutdown(true, true, true)
            end
            gpio.setup(AUDIO_PA_PIN, 0)
            gpio.setup(AUDIO_DAC_PIN, 0)
            gpio.setup(NET_LED_PIN, 0)
            -- BLE 看门狗保持使能（重启进正常模式后 main.lua 喂狗任务继续喂）
            exril_5101.mode(exril_5101.MODE_AT, 3000)
            ble_wdt_config(true)
            log.info("factory", "外设已关闭, BLE 看门狗保持使能, 3秒后重启进正常模式")
            sys.timerStart(pm.reboot, 3000)
        end)
        return "OK"
    end,
    ["PCBA_TEST_DONE"] = function(id, findCom, data)
        -- 下板关机（不写收尾，不出货；出货用 TEST_DONE#）
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
        cmd = string.sub(text, 1, -2)   -- 移除末尾 #
    end
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
-- V3 返工指令帧提取（命令内部含额外 #，会破坏 proc 解析，必须在 proc 前拦截）
-- 只在收到完整帧（含尾 #）时提取，避免半截帧误判
-- ============================================================
local function extract_retest(cache)
    local s, e = cache:find("^%s*MODEL_RETEST%?#")
    if s then
        return cache:sub(s, e), cache:sub(e + 1)
    end
    s, e = cache:find("^%s*MODEL_RETEST#[^#]*#")
    if s then
        return cache:sub(s, e), cache:sub(e + 1)
    end
    return nil
end

-- ============================================================
-- 串口收发（USB 虚拟串口 VUART_0）
-- ============================================================
uart.setup(usbTrans, 115200)

uart.on(usbTrans, "receive", function(id, len)
    while true do
        local data = uart.read(usbTrans, 512)
        if not data or #data == 0 then
            break
        end
        usbRxCache = usbRxCache .. data
        -- 先拦截返工指令（首测/返工模式均可响应，用于重新置位返工标记）
        while true do
            local frame, rest = extract_retest(usbRxCache)
            if not frame then break end
            usbRxCache = rest
            local reply = retest.on_data(frame)
            send_response(usbTrans, (reply or "ERROR") .. "#")
        end
        while true do
            local result
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
