--[[
@module  factory
@summary Air8784产测功能模块
@version 2.0
@date    2026.09.11
@author  王世豪
@usage
负责Air8784的产测功能。主控 Air780EHM。
外设及测试项：
  - 基础信息: VERSION/IMEI/IMSI/ICCID/CSQ/MUID/VBAT
  - 校准位: ECNPICFG (mobile.ecnpicfg 只读)
  - 飞行模式: FLYMODE,<1/0># 进入/退出(mobile.flymode, 仅主 LTE)
  - LED: 主LED GPIO24 + SMS_LED GPIO26 + NET_STATUS GPIO27, 一条指令同开同关
  - 按键: soc 按键 GPIO20, up 按键 GPIO21 (KEY,<pin>,<onoff># 开启/关闭, 按下上报 KEY20_PRESS#/KEY21_PRESS#)
  - 充电: ADC0 检测充电芯片电压(TP4055, 无充电控制脚), CHG# 返回电压值
  - 音频: Air1103 语音芯片(GPIO22 供电, UART1 2M 波特率, 仅 PCM), RECORD#/PLAY#
写号使用 prodmeta 库写入 OTP（key: PROD=工业型号, PCB=硬件版本）。
校准位读取用 mobile.ecnpicfg() 只读接口。
]]

local factory = {}
local prodmeta = require("prodmeta")

log.info("测试模式", "启动中")

-- 硬编码管脚定义 (主控 Air780EHM)
local LED_PIN = 24          -- 主 LED, 高电平点亮
local SMS_LED_PIN = 26      -- SMS 指示灯, 高电平点亮
local NET_STATUS_PIN = 27   -- 网络状态灯, 高电平点亮
local SOC_KEY_PIN = 20      -- soc 按键(按下拉低)
local UP_KEY_PIN = 21       -- up 按键(按下拉低)
local AUDIO_EN_PIN = 22     -- 1103_EN, 拉高给 Air1103 供电
local VREF_PIN = 23         -- 全局上拉 VREF(在 main.lua 打开, 此处仅记录)

-- Air1103 音频
local AUDIO_UART_ID = 1     -- UART1 接 Air1103 串口(固定 2M 波特率)
local recordPath = "/record.pcm"

-- 初始化变量
local uartRxCache = ""
local nowTransId
local usbRxCache = ""
local cacheTable = {}

local usbTrans = uart.VUART_0

-- LED: 默认全灭
local led = gpio.setup(LED_PIN, 0)
local smsLed = gpio.setup(SMS_LED_PIN, 0)
local netStatusLed = gpio.setup(NET_STATUS_PIN, 0)

-- 1103_EN: 默认关闭, 音频测试时再开
gpio.setup(AUDIO_EN_PIN, 0)

-- 按键检测开关(keyed by pin)
local keyTestState = { [SOC_KEY_PIN] = false, [UP_KEY_PIN] = false }
local keyPinNames = { [SOC_KEY_PIN] = "KEY20", [UP_KEY_PIN] = "KEY21" }

-- 按键中断回调: 按下(电平0)上报 PRESS, 松开(电平1)上报 RELEASE
local function makeKeyCb(pin)
    return function()
        local level = gpio.get(pin)
        if not keyTestState[pin] then
            return
        end
        local name = keyPinNames[pin]
        if level == 0 then
            table.insert(cacheTable, { transId = usbTrans, data = name .. "_PRESS#" })
        else
            table.insert(cacheTable, { transId = usbTrans, data = name .. "_RELEASE#" })
        end
        sys.publish("DATA_SEND")
    end
end
gpio.debounce(SOC_KEY_PIN, 50)
gpio.debounce(UP_KEY_PIN, 50)
gpio.setup(SOC_KEY_PIN, makeKeyCb(SOC_KEY_PIN), gpio.PULLUP, gpio.BOTH)
gpio.setup(UP_KEY_PIN, makeKeyCb(UP_KEY_PIN), gpio.PULLUP, gpio.BOTH)

-- 音频 CONTROL 任务: 打开 Air1103 供电 + 初始化 exaudio(air1103) + 处理录音/播放
sys.taskInit(function()
    local exaudio = require("exaudio")
    local audioInited = false

    -- 打开 Air1103 供电并初始化
    gpio.setup(AUDIO_EN_PIN, 1)
    sys.wait(200) -- 等 Air1103 上电稳定
    -- 注: 语音芯片现统一命名 Air1103; exaudio 3.9 起仅识别 model="air1103"
    if exaudio.setup({ model = "air1103", uart_id = AUDIO_UART_ID }) then
        audioInited = true
        log.info("factory", "Air1103 音频初始化成功")
    else
        log.error("factory", "Air1103 音频初始化失败")
    end

    while true do
        local result, param1, param2, param3 = sys.waitUntil("CONTROL")
        if param1 == "RECORD" then
            if not audioInited then
                table.insert(cacheTable, { transId = param2, data = "ERROR#" })
                sys.publish("DATA_SEND")
            else
                log.info("cmd", "RECORD 开始录音(Air1103 PCM 5s)")
                -- 清空旧录音文件
                if io.exists(recordPath) then os.remove(recordPath) end
                -- 先以 wb 打开录音文件(录音期间保持打开, RECORD_DONE 时关闭)
                local recordFile = io.open(recordPath, "wb")
                if not recordFile then
                    log.error("cmd", "无法打开录音文件", recordPath)
                    table.insert(cacheTable, { transId = param2, data = "ERROR#" })
                    sys.publish("DATA_SEND")
                else
                    local done = false
                    local function rec_cb(event)
                        if event == exaudio.RECORD_DONE then
                            if recordFile then recordFile:close(); recordFile = nil end
                            done = true
                        end
                    end
                    -- 参照官方 demo: 用函数 path 手动落盘(不用字符串 path, 避免 exaudio 内部 "ab" 追加写不创建文件)
                    local ok = exaudio.record_start({
                        format = exaudio.PCM_16000,
                        time = 5,
                        path = function(buff, size)
                            if buff and size > 0 and recordFile then
                                recordFile:write(buff:query())
                            end
                        end,
                        cbfnc = rec_cb,
                    })
                    local w = 0
                    while not done and w < 10000 do
                        sys.wait(100)
                        w = w + 100
                    end
                    if recordFile then recordFile:close(); recordFile = nil end
                    local sz = io.fileSize(recordPath) or 0
                    log.info("cmd", "RECORD 完成", ok, "大小", sz)
                    local reply = (ok and done and sz > 0) and "OK" or "ERROR"
                    table.insert(cacheTable, { transId = param2, data = reply .. "#" })
                    sys.publish("DATA_SEND")
                end
            end
        elseif param1 == "PLAY" then
            if not audioInited then
                table.insert(cacheTable, { transId = param2, data = "ERROR#" })
                sys.publish("DATA_SEND")
            elseif not io.exists(recordPath) or (io.fileSize(recordPath) or 0) == 0 then
                log.error("cmd", "PLAY 无录音文件")
                table.insert(cacheTable, { transId = param2, data = "ERROR#" })
                sys.publish("DATA_SEND")
            else
                log.info("cmd", "PLAY 开始播放(Air1103 PCM 流式)")
                local done = false
                local function play_cb(event)
                    if event == exaudio.PLAY_DONE then
                        done = true
                    end
                end
                exaudio.play_start({ type = 2, cbfnc = play_cb, priority = 1, sampling_rate = 16000, sampling_depth = 16, signed_or_unsigned = true })
                local file = io.open(recordPath, "rb")
                if file then
                    local bufSize = 3200
                    while true do
                        local d = file:read(bufSize)
                        if not d or #d == 0 then break end
                        -- 最后一帧不足 bufSize 补静音, 保证 320B 对齐(与官方 demo 一致)
                        if #d < bufSize then
                            d = d .. string.rep("\0", bufSize - #d)
                        end
                        exaudio.play_stream_write(d)
                        -- Air1103 下行按 320B/10ms=32KB/s 消费, 按此节奏喂数据防溢出
                        sys.wait(math.max(20, math.floor(#d / 32)))
                    end
                    file:close()
                    exaudio.finish() -- 标记数据喂完, 排空后触发 PLAY_DONE
                end
                local w = 0
                while not done and w < 15000 do
                    sys.wait(100)
                    w = w + 100
                end
                log.info("cmd", "PLAY 完成", done)
                table.insert(cacheTable, { transId = param2, data = (done and "OK" or "ERROR") .. "#" })
                sys.publish("DATA_SEND")
            end
        elseif param1 == "FLYMODE" then
            -- 飞行模式在协程里执行：mobile.flymode 同步阻塞且走 RPC，不能进 uart 回调
            local fid, onoff = param2, param3
            mobile.flymode(0, onoff == 1)
            log.info("factory", "飞行模式", onoff == 1 and "进入" or "退出", "完成")
            table.insert(cacheTable, { transId = fid, data = "OK#" })
            sys.publish("DATA_SEND")
        end
    end
end)

local procTable = {
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
        -- 电池电压：直接读取模组内部电池电压通道 adc.CH_VBAT，返回 mV（全产品统一）
        adc.open(adc.CH_VBAT)
        local vbat = adc.get(adc.CH_VBAT)
        adc.close(adc.CH_VBAT)
        if not vbat then
            return "ERROR"
        end
        return string.format("%.2f", vbat)
    end,
    ["CHG"] = function(id, findCom, data)
        -- 充电芯片电压：ADC0 直读，返回 mV。充电无需控制(TP4055 无控制脚)。
        -- 注：如 ADC0 前端有分压电阻，此处需按实际电路换算，当前直接返回 ADC0 读数(mV)
        adc.open(0)
        local v = adc.get(0)
        adc.close(0)
        if not v then return "ERROR" end
        return v
    end,
    ["LED"] = function(id, findCom, data)
        -- 一条指令同时打开/关闭三个灯(LED/SMS_LED/NET_STATUS)
        local onoff = tonumber(data)
        if not onoff or (onoff ~= 0 and onoff ~= 1) then
            return "ERROR"
        end
        led(onoff)
        smsLed(onoff)
        netStatusLed(onoff)
        return "OK"
    end,
    ["KEY"] = function(id, findCom, data)
        -- 按键测试: KEY,<pin>,<onoff>#  pin=20(soc)/21(up), onoff=1开启检测/0关闭
        local pinStr, onoffStr = string.match(data, "^(%d+),(%d+)$")
        local pin = tonumber(pinStr)
        local onoff = tonumber(onoffStr)
        if not pin or not onoff or keyTestState[pin] == nil or (onoff ~= 0 and onoff ~= 1) then
            return "ERROR"
        end
        keyTestState[pin] = (onoff == 1)
        log.info("factory", "按键检测", pin, "开启", tostring(keyTestState[pin]))
        return "OK"
    end,
    ["RECORD"] = function(id, findCom, data)
        sys.publish("CONTROL", "RECORD", id)
        return
    end,
    ["PLAY"] = function(id, findCom, data)
        sys.publish("CONTROL", "PLAY", id)
        return
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
    ["FLYMODE"] = function(id, findCom, data)
        -- 仅校验 + 转发：mobile.flymode 是同步阻塞且走 airlink RPC，不能在 uart 接收回调
        -- (proc 的调用链) 里直接调用，否则回调退不出、OK 回不出、整机卡死。
        -- 真正执行丢到 CONTROL 协程（见下方音频任务）里做。
        local onoff = tonumber(data)
        if not onoff or (onoff ~= 0 and onoff ~= 1) then
            return "ERROR"
        end
        log.info("factory", "飞行模式请求", onoff == 1 and "进入" or "退出")
        sys.publish("CONTROL", "FLYMODE", id, onoff)
        return -- 不立即回 OK，等 CONTROL 协程执行完再回
    end,
    ["HVERSION"] = function(id, findCom, data)
        -- 硬件版本：HVERSION,版本# 写 OTP PCB；HVERSION# 读回（未写返回 ERROR）
        if not findCom then
            local pcb = prodmeta.get("PCB")
            return pcb or "ERROR"
        end
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
        if not data or #data == 0 then
            return "ERROR"
        end
        local model = data:gsub("^%s*", ""):gsub("%s*$", "")
        if #model == 0 then
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
        -- 读回当前工业型号（OTP 的 PROD key）
        local v = prodmeta.get("PROD")
        return v or "ERROR"
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
        -- 清理外设再写入完成标记(reboot 前)
        pcall(gpio.setup, AUDIO_EN_PIN, 0)
        led(0)
        smsLed(0)
        netStatusLed(0)
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
