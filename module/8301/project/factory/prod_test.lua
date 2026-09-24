--[[
@module  prod_test
@summary Air8301 产测功能模块（产测模式主控，纯产测不合并业务）
@version 1.0
@date    2026.09.24
@usage
Air8301 基于 Air8000W 主控（4G+WiFi+BLE+SPI屏）：
  4.3寸 ST6201 SPI 屏 + GT911 触摸 + 双RS485 + 双RS232 + 双CH390以太网 + SPI NAND Flash
  + DI/DO + 蜂鸣器 + 状态灯 + Air153D外部看门狗 + RELOAD按键。

产测架构：
  1. 开机即初始化屏幕（复用业务模式 drv/ + ui/ + app/ 的屏幕与硬件部分），测试员点击屏幕手动测试；
  2. 同时注册 USB 虚拟串口（uart.VUART_0 115200，# 结尾）指令接口，供上位机自动化测试。

测试项：基础信息 + 校准位(ECNPICFG) + 写号(MODEL/HVERSION) + 232自回环(U232_TEST) +
  485(1发2收)(U485_TEST) + 网口获取IP(ETH_TEST) + 看门狗(WD_TEST) + 蜂鸣器(BUZZER_TEST) +
  继电器(DO_TEST) + Flash写读(FLASH_TEST) + RELOAD按键(RELOAD_TEST) + 系统控制。

写号使用 prodmeta 库写入 OTP（key: PROD=工业型号, PCB=硬件版本）；校准位读取用 mobile.ecnpicfg()。
232/485/ETH/Flash 测试复用产测 app 层的消息流（RS232_SEND_REQUEST/RS485_SEND_REQUEST/
STATUS_ETH_UPDATED/FLASH_MOUNT_STATUS），不直接操作 UART/SPI，避免与屏幕终端冲突。
含 sys.wait 的测试走 CONTROL 事件模式异步执行。

模式隔离：本模块仅在 test_done 未置位时由 main.lua 加载；业务模块在 test_done 已置位时加载。
]]

local prod_test = {}
local prodmeta = require "prodmeta"

log.info("测试模式", "启动中")

-- ================= 屏幕启动（产测模式专属编排） =================
exwin = require "exwin"
require "prod_app_main"
require "prod_ui_main"

-- ================= 外部看门狗（复用 prod_watchdog_app 已初始化的 exair153x_wdt 实例） =================
local exair153x_wdt = require "exair153x_wdt"

-- ================= 串口命令接口 =================
local usbTrans = uart.VUART_0
local usbRxCache = ""
local cacheTable = {}

-- 异步/主动上报回复函数（CONTROL 事件任务或按键回调里用）
local function send_response(id, data)
    table.insert(cacheTable, { transId = id, data = data })
    sys.publish("DATA_SEND")
end

-- ================= 网口 IP 缓存（订阅 prod_network_app 的 STATUS_ETH_UPDATED） =================
local eth1_ip = ""
local eth2_ip = ""
sys.subscribe("STATUS_ETH_UPDATED", function(e1, ip1, e2, ip2)
    eth1_ip = ip1 or ""
    eth2_ip = ip2 or ""
    log.info("prod_test", "ETH状态更新: eth1=", eth1_ip, "eth2=", eth2_ip)
end)

-- ================= Flash 挂载状态缓存（订阅 flash_app 的 FLASH_MOUNT_STATUS） =================
local flash_mounted = false
sys.subscribe("FLASH_MOUNT_STATUS", function(mounted)
    flash_mounted = mounted and true or false
end)

-- ================= 232/485 回环测试捕获 =================
-- 订阅 prod_rs232_app/prod_rs485_app 的收数消息捕获回环数据，无需直接操作 UART，避免与屏幕终端冲突
local uartCap = { active = false, port = 0, data = nil }

local function rs232_capture(port, data)
    if uartCap.active and port == uartCap.port and data then
        uartCap.data = (uartCap.data or "") .. data
    end
end

local function rs485_capture(port, data)
    if uartCap.active and port == uartCap.port and data then
        uartCap.data = (uartCap.data or "") .. data
    end
end

sys.subscribe("RS232_DATA_RECEIVED", rs232_capture)
sys.subscribe("RS485_DATA_RECEIVED", rs485_capture)

-- ================= RELOAD 按键检测 =================
local reloadTest = false
sys.subscribe("KEY_EVENT", function(evt)
    if not reloadTest then return end
    if evt == "reload_down" then
        send_response(usbTrans, "RELOAD_PRESS#")
    elseif evt == "reload_up" then
        send_response(usbTrans, "RELOAD_RELEASE#")
    end
end)

-- ================= Flash 写读对比测试 =================
local function flash_test()
    -- 等待 flash_app 挂载 /flash（收到 NETWORK_INIT_DONE 后挂载，最多等 5s）
    local waited = 0
    while not flash_mounted and waited < 5000 do
        sys.wait(100)
        waited = waited + 100
    end

    local test_file = "/flash/factory_test.txt"
    local test_data = ""
    for i = 1, 200 do
        test_data = test_data .. string.format("Air8301-FlashTest-%04d,", i)
    end

    local f = io.open(test_file, "wb")
    if not f then
        log.error("FLASH_TEST", "打开文件失败（/flash 未挂载或异常）")
        return "ERROR"
    end
    f:write(test_data)
    f:close()

    local read_data = io.readFile(test_file)
    os.remove(test_file)

    if read_data == test_data then
        log.info("FLASH_TEST", "读写一致", #test_data, "字节")
        return "OK"
    end
    log.error("FLASH_TEST", "读写不一致", read_data and #read_data or 0, #test_data)
    return "ERROR"
end

-- ================= 232 自回环测试（单口，TX-RX 短接） =================
local function u232_loopback(port)
    local test_str = "232TEST"
    uartCap.active = true
    uartCap.port = port
    uartCap.data = nil
    -- 通过 prod_rs232_app 发送（全双工，无 RE/DE 方向控制）
    sys.publish("RS232_SEND_REQUEST", port, test_str)

    local waited = 0
    while (not uartCap.data or #uartCap.data < #test_str) and waited < 2000 do
        sys.wait(50)
        waited = waited + 50
    end
    uartCap.active = false

    if uartCap.data == test_str then
        log.info("U232_TEST", "Port", port, "回环成功")
        return "OK"
    end
    log.error("U232_TEST", "Port", port, "回环失败，期望", test_str, "实际", tostring(uartCap.data))
    return "ERROR"
end

-- ================= 485 测试（1号发 2号收，A接A B接B） =================
local function u485_test()
    local test_str = "485TEST"
    uartCap.active = true
    uartCap.port = 2   -- 2号485(UART11) 接收
    uartCap.data = nil
    -- 1号485(UART1) 发送（固件内置 RS485 模式自动控制 RE/DE）
    sys.publish("RS485_SEND_REQUEST", 1, test_str)

    local waited = 0
    while (not uartCap.data or #uartCap.data < #test_str) and waited < 2000 do
        sys.wait(50)
        waited = waited + 50
    end
    uartCap.active = false

    if uartCap.data == test_str then
        log.info("U485_TEST", "1发2收成功")
        return "OK"
    end
    log.error("U485_TEST", "1发2收失败，期望", test_str, "实际", tostring(uartCap.data))
    return "ERROR"
end

-- ================= 网口获取 IP 测试（8301 为 DHCP 客户端） =================
local function eth_test(port)
    -- 最多等 10s 拿到该网口 IP，拿到即回复；超时返回 ERROR
    local waited = 0
    while waited < 10000 do
        local ip = port == 1 and eth1_ip or eth2_ip
        if ip and ip ~= "" and ip ~= "0.0.0.0" then
            log.info("ETH_TEST", "Port", port, "IP", ip)
            return ip
        end
        sys.wait(200)
        waited = waited + 200
    end
    log.error("ETH_TEST", "Port", port, "获取 IP 超时")
    return "ERROR"
end

-- ================= 指令表 =================
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
        -- 电池电压：读取模组内部电池电压通道 adc.CH_VBAT，返回 mV（全产品统一）
        adc.open(adc.CH_VBAT)
        local vbat = adc.get(adc.CH_VBAT)
        adc.close(adc.CH_VBAT)
        if not vbat then
            return "ERROR"
        end
        return string.format("%.2f", vbat)
    end,
    ["FLYMODE"] = function(id, findCom, data)
        -- 飞行模式开关：FLYMODE,1# 开，FLYMODE,0# 关（只操作主 LTE，adapter=0）
        local onoff = tonumber(data)
        if not onoff or (onoff ~= 0 and onoff ~= 1) then
            return "ERROR"
        end
        log.info("FLYMODE", onoff)
        mobile.flymode(0, onoff == 1)
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
            log.error("prod_test", "写PCB失败", err)
            return "ERROR"
        end
        log.info("prod_test", "硬件版本写入", ver)
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
            log.error("prod_test", "写PROD失败", err)
            return "ERROR"
        end
        log.info("prod_test", "写号成功", model)
        return "OK"
    end,
    ["MODEL?"] = function(id, findCom, data)
        -- 读回当前工业型号（OTP 的 PROD key）
        local v = prodmeta.get("PROD")
        return v or "ERROR"
    end,
    ["U232_TEST"] = function(id, findCom, data)
        -- 232 自回环测试（TX-RX 短接），含 sys.wait，走 CONTROL 事件异步
        local port = tonumber(data)
        if not port or (port ~= 1 and port ~= 2) then
            return "ERROR"
        end
        sys.publish("CONTROL", "U232_TEST", id, port)
        return
    end,
    ["U485_TEST"] = function(id, findCom, data)
        -- 485 测试（1号发 2号收，A接A B接B），含 sys.wait，走 CONTROL 事件异步
        sys.publish("CONTROL", "U485_TEST", id)
        return
    end,
    ["ETH_TEST"] = function(id, findCom, data)
        -- 网口获取 IP 测试（8301 为 DHCP 客户端），含 sys.wait，走 CONTROL 事件异步
        local port = tonumber(data)
        if not port or (port ~= 1 and port ~= 2) then
            return "ERROR"
        end
        sys.publish("CONTROL", "ETH_TEST", id, port)
        return
    end,
    ["WD_TEST"] = function(id, findCom, data)
        -- Air153D 看门狗测试
        -- WD_TEST#:   触发强制复位（3次快速脉冲，设备约1s内重启），上位机检测重启即 PASS
        -- WD_TEST,1#: 手动喂狗（恢复正常）
        if data == "" then
            exair153x_wdt.trigger_reset()
            return "OK"
        elseif data == "1" then
            exair153x_wdt.feed()
            return "OK"
        end
        return "ERROR"
    end,
    ["BUZZER_TEST"] = function(id, findCom, data)
        -- 蜂鸣器测试：复用 buzzer_app，响 0.5 秒
        sys.publish("BUZZER_BEEP_REQUEST")
        return "OK"
    end,
    ["DO_TEST"] = function(id, findCom, data)
        -- 继电器测试：DO_TEST,ch,state# → ch=1/2 号继电器, state=1 导通 / 0 关闭
        local ch, state = data:match("^(%d+),(%d+)$")
        if not ch then
            return "ERROR"
        end
        ch = tonumber(ch)
        state = tonumber(state)
        if (ch ~= 1 and ch ~= 2) or (state ~= 0 and state ~= 1) then
            return "ERROR"
        end
        sys.publish("DO_SET_REQUEST", ch, state)
        return "OK"
    end,
    ["FLASH_TEST"] = function(id, findCom, data)
        -- SPI NAND Flash 写读对比，含 sys.wait，走 CONTROL 事件异步
        sys.publish("CONTROL", "FLASH_TEST", id)
        return
    end,
    ["RELOAD_TEST"] = function(id, findCom, data)
        -- RELOAD 按键检测：
        -- RELOAD_TEST,1# 开启检测，测试员按键后设备主动上报 RELOAD_PRESS#/RELOAD_RELEASE#
        -- RELOAD_TEST,0# 关闭检测
        local onoff = tonumber(data)
        if not onoff or (onoff ~= 0 and onoff ~= 1) then
            return "ERROR"
        end
        reloadTest = (onoff == 1)
        return "OK"
    end,
    ["RST"] = function(id, findCom, data)
        -- 单独重启（RST#）：不写 test_done，收到即重启（500ms 延时确保 OK# 回复发出）
        log.info("prod_test", "重启设备")
        sys.taskInit(function()
            sys.wait(500)
            pm.reboot()
        end)
        return "OK"
    end,
    ["TEST_DONE"] = function(id, findCom, data)
        fskv.set("test_done", true)
        log.info("测试完成，已保存状态，3秒后重启")
        sys.timerStart(pm.reboot, 3000)
        return "OK"
    end,
    ["PCBA_TEST_DONE"] = function(id, findCom, data)
        log.info("PCBA 测试完成，3秒后关机")
        sys.timerStart(pm.shutdown, 3000)
        return "OK"
    end,
}

-- ================= CONTROL 事件任务（异步测试） =================
sys.taskInit(function()
    while true do
        local result, param1, param2, param3 = sys.waitUntil("CONTROL")
        log.info("CONTROL", param1)
        if param1 == "U232_TEST" then
            send_response(param2, u232_loopback(param3) .. "#")
        elseif param1 == "U485_TEST" then
            send_response(param2, u485_test() .. "#")
        elseif param1 == "ETH_TEST" then
            send_response(param2, eth_test(param3) .. "#")
        elseif param1 == "FLASH_TEST" then
            send_response(param2, flash_test() .. "#")
        end
    end
end)

-- ================= 指令解析 =================
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

-- ================= 串口初始化 =================
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

return prod_test
