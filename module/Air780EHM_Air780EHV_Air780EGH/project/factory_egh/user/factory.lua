--[[
@module  factory
@summary Air780EGH/EGP/EGG 出厂固件产测模块（内置 GNSS 核心板）
@version 2.0
@date    2026.10.14
@usage
本模块为 Air780EGH/EGP/EGG 出厂固件的产测模式，与正常模式（irtu_main）通过 test_done 分流。
产测通过 USB 虚拟串口 uart.VUART_0 收发指令，波特率 115200，指令以 # 结尾。

指令集：
- 通用指令：VERSION/IMEI/IMSI/ICCID/CSQ/MUID/VBAT/ECNPICFG/LED/FLYMODE/RST/TEST_DONE/PCBA_TEST_DONE
- 写号指令：MODEL/MODEL?(OTP PROD)、HVERSION(OTP PCB)
- GNSS 产测：GPSTEST(内置 GNSS 定位 + NMEA 透传上位机)

管脚：
  GPIO27 NET_STATUS 状态灯(高亮)
  GPIO23 VREF 上拉(main.lua 常开)
  UART2  内置 GNSS 固定串口(115200)，电源由 pm.power(pm.GPS) 控制，无外挂供电脚

说明：
- Air780EGH/EGP/EGG 的内置 GNSS 由模组电源轨 pm.GPS 供电，exgnss.setup 不传 gnss_volgpio；
  与 Air8780G 外挂方案（GPIO21 供电）不同，故本文件无 GNSS_POWER_PIN / gnssPower。
- 本套不做加速度（gsensor）产测：EGG/EGP 的 DA221 走内置 exvib 库（中断 WAKEUP2），
  并非 Air8780G 的 I2C1(0x27) 访问方式，且 EGH 核心板未引出 gsensor，故不设 GS_STATE。
- 无外置看门狗、无音频 codec，故无 WD_TEST/RECORD/PLAY 等指令。
]]

local factory = {}

local prodmeta = require("prodmeta")
-- 内置 GNSS（pcall 守卫：固件未开 LUAT_USE_LIBGNSS 或缺 exgnss 库时不影响其它产测项）
local ok_exgnss, exgnss = pcall(require, "exgnss")

-- ============================================================
-- 硬编码管脚定义
-- ============================================================
local NET_LED_PIN = 27    -- 网络状态灯，高电平点亮
local gnssUartId = 2      -- 内置 GNSS 固定串口

-- 初始化变量
local usbRxCache = ""
local cacheTable = {}
local usbTrans = uart.VUART_0
local gnssOpened = false

local netLed = gpio.setup(NET_LED_PIN, 0)

log.info("factory", "Air780EGH/EGP/EGG 产测模式启动（内置 GNSS）")

-- ============================================================
-- 通用辅助函数
-- ============================================================
local function send_response(transId, data)
    table.insert(cacheTable, { transId = transId, data = data })
    sys.publish("DATA_SEND")
end

-- 关闭内置 GNSS：只走 exgnss/uart，不操作任何外挂供电 GPIO
local function gnssClose()
    if gnssOpened then
        pcall(exgnss.close_all)
        pcall(uart.on, gnssUartId, "receive")
        pcall(uart.close, gnssUartId)
        gnssOpened = false
    end
end

-- ============================================================
-- 指令表
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
    ["FLYMODE"] = function(id, findCom, data)
        local onoff = tonumber(data)
        if not onoff or onoff ~= 0 and onoff ~= 1 then return "ERROR" end
        log.info("FLYMODE", onoff)
        if onoff == 1 then
            netLed(0)
            gnssClose() -- 进飞行模式前关闭内置 GNSS
        end
        mobile.flymode(0, onoff == 1)
        return "OK"
    end,
    -- 内置 GNSS 产测：GPSTEST,1# 开启并把 NMEA 透传给 USB；GPSTEST,0# 关闭
    ["GPSTEST"] = function(id, findCom, data)
        if not ok_exgnss then
            log.error("GPSTEST", "exgnss 库不可用")
            return "ERROR"
        end
        if data == "0" then
            gnssClose()
        elseif data == "1" then
            gnssOpened = true
            local gnssotps = {
                gnssmode = 1, agps_enable = true, debug = true,
                uart = gnssUartId, uartbaud = 115200,
                bind = usbTrans,   -- NMEA 直接透传给 USB 上位机看定位
                auto_open = true,
                -- 内置 GNSS：不传 gnss_volgpio，电源走 pm.power(pm.GPS)
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
        -- 测试完成：关闭外设与内置 GNSS，写 test_done，延时重启进 iRTU 正常模式
        netLed(0)
        gnssClose()
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
