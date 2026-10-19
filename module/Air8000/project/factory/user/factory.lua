--[[
@module  factory
@summary Air8000 系列出厂固件产测模块（V3）
@version 1.0
@date    2026.10.16
@usage
本模块为 Air8000 出厂固件的产测模式，V3 启动分流由 main.lua 完成（fskv 返工标记 → OTP1 判空）。
产测通过 USB 虚拟串口 uart.VUART_0 收发指令，波特率 115200，指令以 # 结尾。
- 首次产测：MODEL/HVERSION 写号入 OTP1，TEST_DONE 校验 OTP1 非空后重启进正常模式
- 返工产测：fskv 有 model_retest 标记，TEST_DONE 删除标记（不动 OTP1）后重启进正常模式
- 返工指令 MODEL_RETEST#CONFIRM / MODEL_RETEST? 由 retest 模块在 proc 前拦截

指令集：
- 通用指令：VERSION/IMEI/IMSI/ICCID/CSQ/MUID/VBAT/ECNPICFG/LED/WD_TEST/FLYMODE/RST/TEST_DONE/PCBA_TEST_DONE
- 写号指令：MODEL/MODEL?(OTP PROD)、HVERSION(OTP PCB)
- 返工指令：MODEL_RETEST#CONFIRM/MODEL_RETEST?（V3，见 retest.lua）
- 8000T 专属：RECORD(录音5s)/PLAY(回放)，exaudio 新框架
- 8000G 专属：GPSTEST(内置GNSS透传)

管脚（依据 demo/pins/pins_Air8000.json，避开 LCD/I2S/CH390 占用）：
  GPIO21(pin24)  状态灯
  GPIO160(pin96) 外置看门狗喂狗脚（经 exair153x_wdt，NPN 反相极性在库内处理）
  音频(仅8000T)：es8311 在硬件I2C0，pa_ctrl=162/dac_ctrl=164（开发板；核心板为17/16）
  GNSS(仅8000G)：默认 uart2/115200，模组内置 GNSS 直供电，无需独立电源使能脚
]]

local factory = {}

-- ==================== 版本选择（与 factory_config 保持一致） ====================
local factory_config = require "factory_config"
local VER = factory_config.get_ver()
-- 非4G版本（8000W WiFi / 8000D ETH）调用任何 mobile.* 会崩溃，与正常模式同一判据
local NETDEV = factory_config.get_netdev()
local MOBILE_SUPPORT = (NETDEV == "4g" or NETDEV == "multiple")
-- ============================================================================

local prodmeta = require("prodmeta")
-- V3 返工标记（fskv model_retest）：区分首测/返工，返工通过后删标记
local retest = require("retest")
local isRetest = retest.is_set()
log.info("测试模式", "本次产测类型:", isRetest and "返工产测（不动OTP1）" or "首次产测（写号入OTP1）")
-- 153c/153d 外置硬件看门狗
local ok_wdt, exair153x_wdt = pcall(require, "exair153x_wdt")
-- 内置 GNSS（仅8000G 使用，pcall 守卫缺库不崩）
local ok_exgnss, exgnss = pcall(require, "exgnss")

log.info("测试模式", "启动中 版本:", VER)

-- ============================================================
-- 管脚定义（依据 pins_Air8000.json）
-- ============================================================
local NET_LED_PIN = factory_config.get_led_pin()       -- 状态灯，高电平点亮：GPIO21(pin24)
local WD_CFG = factory_config.get_wdt()                -- 外置看门狗配置
local WD_FEED_PIN = WD_CFG and WD_CFG.pin or 160       -- 喂狗脚：GPIO160(pin96)
-- 8000T 音频（exaudio 新框架）
local AUDIO_PA_PIN  = 162  -- 开发板音频 PA 控制（核心板为 17）
local AUDIO_DAC_PIN = 164  -- 开发板 codec 电源控制（核心板为 16）
local AUDIO_I2C_ID  = 0    -- es8311 在硬件 I2C0（pin80/81）
local recordPath = "/record.amr"
-- 8000G GNSS
local gpsCfg = factory_config.get_gps()
local gnssUartId = gpsCfg and gpsCfg.uart or 2          -- 内置 GNSS 串口：uart2
local gnssUartBaud = gpsCfg and gpsCfg.uartbaud or 115200

-- 初始化变量
local usbRxCache = ""
local cacheTable = {}
local usbTrans = uart.VUART_0
local gnssOpened = false

local netLed = gpio.setup(NET_LED_PIN, 0)
-- 外置看门狗（自动喂狗，超时档位由硬件 STRAP 配置）
if exair153x_wdt and WD_CFG and WD_CFG.enable then
    exair153x_wdt.init({ wdt_pin = WD_FEED_PIN, auto_feed_period_s = WD_CFG.period or 180 })
end

-- ============================================================
-- 通用辅助函数
-- ============================================================
local function send_response(transId, data)
    table.insert(cacheTable, { transId = transId, data = data })
    sys.publish("DATA_SEND")
end

-- 8000T 音频初始化（exaudio 新框架，es8311）
local exaudio_ok = false
local ok_exaudio, exaudio = pcall(require, "exaudio")

-- dac_delay 版本自适应：rtos.version() 提取 V 后数字，
-- >=2026 单位为 100ms 填 6，<2026 单位为 1ms 填 600
local function get_dac_delay()
    local ver_num = tonumber((rtos.version() or ""):match("V(%d+)")) or 0
    if ver_num >= 2026 then
        return 6     -- 单位 100ms
    end
    return 600       -- 单位 1ms
end

local function audio_init()
    if VER ~= "8000T" then return false end
    if not ok_exaudio then
        log.warn("AUDIO", "固件无 exaudio，RECORD/PLAY 将回 ERROR")
        return false
    end
    local audio_setup_param = {
        model = "es8311",
        i2c_id = AUDIO_I2C_ID,
        dac_delay = get_dac_delay(),
        pa_ctrl = AUDIO_PA_PIN,
        dac_ctrl = AUDIO_DAC_PIN,
        audio_mode = "auto",
    }
    if exaudio.setup(audio_setup_param) then
        exaudio_ok = true
        log.info("AUDIO", "exaudio + es8311 初始化成功")
        return true
    end
    log.error("AUDIO", "exaudio 初始化失败")
    return false
end

-- ============================================================
-- 异步事件处理任务（含 sys.wait 的测试不能在 uart 回调里执行）
-- ============================================================
sys.taskInit(function()
    -- 8000T 音频预初始化
    if VER == "8000T" then
        audio_init()
    end

    -- 异步测试事件处理
    while true do
        local result, param1, param2 = sys.waitUntil("CONTROL")
        if param1 == "RECORD" then
            -- 录音测试（8000T）：录音5秒 AMR
            if VER == "8000T" and exaudio_ok then
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
        elseif param1 == "PLAY" then
            -- 播放测试（8000T）：播放录音文件
            if VER == "8000T" and exaudio_ok then
                if not io.exists(recordPath) or (io.fileSize(recordPath) or 0) == 0 then
                    send_response(param2, "ERROR#")
                else
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
        end
    end
end)

-- ============================================================
-- 指令表
-- ============================================================
local procTable = {
    -- 基础信息
    ["VERSION"] = function(id, findCom, data)
        return PROJECT .. "_" .. VERSION
    end,
    ["IMEI"] = function(id, findCom, data)
        if not MOBILE_SUPPORT then return "ERROR,unsupported" end
        local v = mobile.imei()
        if not v or v == "" then return "ERROR" end
        return v
    end,
    ["IMSI"] = function(id, findCom, data)
        if not MOBILE_SUPPORT then return "ERROR,unsupported" end
        local v = mobile.imsi()
        if not v or v == "" then return "ERROR" end
        return v
    end,
    ["ICCID"] = function(id, findCom, data)
        if not MOBILE_SUPPORT then return "ERROR,unsupported" end
        local v = mobile.iccid()
        if not v or v == "" then return "ERROR" end
        return v
    end,
    ["CSQ"] = function(id, findCom, data)
        if not MOBILE_SUPPORT then return "ERROR,unsupported" end
        local v = mobile.csq()
        if v == nil then return "ERROR" end
        return v
    end,
    ["MUID"] = function(id, findCom, data)
        if not MOBILE_SUPPORT then return "ERROR,unsupported" end
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
        if not MOBILE_SUPPORT then return "ERROR,unsupported" end
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
        if not exair153x_wdt or not WD_CFG or not WD_CFG.enable then return "ERROR" end
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
        if not MOBILE_SUPPORT then return "ERROR,unsupported" end
        local onoff = tonumber(data)
        if not onoff or onoff ~= 0 and onoff ~= 1 then return "ERROR" end
        log.info("FLYMODE", onoff)
        if onoff == 1 then
            netLed(0)
            -- 8000T 关闭音频外设
            if VER == "8000T" and exaudio_ok then
                pcall(exaudio.play_stop, { type = 1 })
            end
            -- 8000G 关闭 GNSS
            if VER == "8000G" and gnssOpened then
                pcall(exgnss.close_all)
                pcall(uart.on, gnssUartId, "receive")
                pcall(uart.close, gnssUartId)
                gnssOpened = false
            end
        end
        mobile.flymode(0, onoff == 1)
        return "OK"
    end,
    -- 8000T 音频
    ["RECORD"] = function(id, findCom, data)
        sys.publish("CONTROL", "RECORD", id)
        return
    end,
    ["PLAY"] = function(id, findCom, data)
        sys.publish("CONTROL", "PLAY", id)
        return
    end,
    -- 8000G GNSS
    ["GPSTEST"] = function(id, findCom, data)
        if VER ~= "8000G" then return "ERROR" end
        if not ok_exgnss then
            log.error("GPSTEST", "exgnss 不可用")
            return "ERROR"
        end
        if data == "0" then
            gnssOpened = false
            exgnss.close_all()
            uart.on(gnssUartId, "receive")
            uart.close(gnssUartId)
        elseif data == "1" then
            gnssOpened = true
            -- Air8000 内置 GNSS 默认 uart2/115200，gnssmode=1 全定位、agps_enable=true
            local gnssotps = {
                gnssmode = 1, agps_enable = true, debug = true,
                uart = gnssUartId, uartbaud = gnssUartBaud,
                bind = usbTrans,          -- NMEA 直接透传给 USB 上位机看定位
                auto_open = true,
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
        -- 测试完成：先关外设，再按 V3 区分首测 / 返工收尾
        netLed(0)
        if VER == "8000T" and exaudio_ok then
            pcall(exaudio.play_stop, { type = 1 })
        end
        if VER == "8000G" and gnssOpened then
            pcall(exgnss.close_all)
            pcall(uart.on, gnssUartId, "receive")
            pcall(uart.close, gnssUartId)
            gnssOpened = false
        end

        -- 收尾并安排重启：返回 false 表示收尾失败（已 log.error）
        local function finish_and_reboot()
            if isRetest then
                -- 返工产测：全程不动 OTP1，删除 fskv 返工标记并读回校验
                local ok, err = retest.clear_flag()
                if not ok then
                    log.error("factory", "返工标记删除失败，不重启:", err)
                    return false
                end
                log.info("测试完成（返工），返工标记已删除，3秒后重启进正常模式")
            else
                -- 首次产测：型号/硬件版本已由 MODEL/HVERSION 写入 OTP1，此处校验非空
                if next(prodmeta.get_all()) == nil then
                    log.error("factory", "OTP1 为空，未写号，禁止结束首测")
                    return false
                end
                log.info("测试完成（首测），OTP1 写号已就绪，3秒后重启进正常模式")
            end
            if pm and pm.reboot then
                sys.timerStart(pm.reboot, 3000)
            else
                log.error("factory", "固件不支持 pm.reboot，请手动重启")
                return false
            end
            return true
        end

        if finish_and_reboot() then
            return "OK"
        end
        return "ERROR"
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
-- V3 返工指令帧提取（命令内部含额外 #，会破坏 proc 解析，必须在 proc 前拦截）
-- 工厂工具帧以 # 结尾，只在收到完整帧（含尾 #）时提取，避免半截帧误判
-- @return string|nil frame, string|nil rest 命中返回帧文本与剩余缓存
-- ============================================================
local function extract_retest(cache)
    -- 查询帧：MODEL_RETEST?#
    local s, e = cache:find("^%s*MODEL_RETEST%?#")
    if s then
        return cache:sub(s, e), cache:sub(e + 1)
    end
    -- 设置帧：MODEL_RETEST#<参数>#（参数不含 #）
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
            send_response(usbTrans, (reply or "ERROR") .. "#")
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

return factory
