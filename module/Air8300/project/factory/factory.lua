--[[
@module  factory
@summary Air8300 产测功能模块（产测模式，与 8300 出厂固件双模合一）
@version 1.0
@date    2026.09.24
@usage
本模块由 8300 产测固件（lib/factory.lua v1.0）移植并入 8300 出厂固件，产测逻辑与管脚定义未改动。
加载时机：main.lua 依据 fskv 标记 test_done 分流，未完成产测时 require "factory" 进入产测模式。
产测模式与业务模式资源互斥（UART1/UART3/双网口/三色 LED），二者不会同时运行。

Air8300 基于 Air8000W 的工业网关，无屏幕。外设：
  双 CH390 以太网（SPI1，网口1 cs=21/pwr=16/irq=WAKEUP0，网口2 cs=20/pwr=17/irq=WAKEUP6，均为 DHCP 客户端）
  + 隔离 485（UART1，GPIO37 收发使能）+ 非隔离 485（UART3，GPIO36 收发使能 + GPIO29 供电）
  + 三色 LED（GPIO26=蓝 / GPIO27=红 / GPIO28=绿，高电平点亮）。
产测包含：基础信息 + 校准位(ECNPICFG) + 写号(MODEL/HVERSION/MODEL?) + 网口获取IP(ETH_TEST,1#/2#)
  + 485 一发一收(U485_TEST，A接A B接B) + 三色LED(LED_TEST) + 系统控制(RST/TEST_DONE)。
写号使用 prodmeta 库写入 OTP（key: PROD=工业型号, PCB=硬件版本）；校准位读取用 mobile.ecnpicfg()。
485 使用 uart.setup 内置 RS485 模式（固件自动控制 RE/DE）；ETH_TEST/U485_TEST 含 sys.wait，走 CONTROL 事件模式异步执行。
通信通道：USB 虚拟串口（uart.VUART_0 115200，指令以 # 结尾）。
硬件注意：双 CH390 共用 SPI1，必须同时上电（GPIO16+GPIO17），否则 SPI 信号电平混乱导致通讯失败。
]]

local prodmeta = require "prodmeta"
local exnetif = require "exnetif"

local factory = {}

log.info("测试模式", "启动中")

-- ================= 管脚定义 =================
-- 以太网（双 CH390，共用 SPI1，均 DHCP 客户端）
local ETH1_PWR = 16   -- 网口1 供电使能 GPIO16
local ETH2_PWR = 17   -- 网口2 供电使能 GPIO17
local ETH1_CS  = 21   -- 网口1 片选 GPIO21（→ socket.LWIP_ETH）
local ETH2_CS  = 20   -- 网口2 片选 GPIO20（→ socket.LWIP_USER1）

-- 485（隔离 UART1 发送 / 非隔离 UART3 接收）
local RS485_ISO_PORT     = 1   -- 隔离 485 串口 UART1
local RS485_ISO_RE_DE    = 37  -- 隔离 485 收发使能 GPIO37（高=发送 低=接收）
local RS485_NONISO_PORT  = 3   -- 非隔离 485 串口 UART3
local RS485_NONISO_RE_DE = 36  -- 非隔离 485 收发使能 GPIO36
local RS485_NONISO_PWR   = 29  -- 非隔离 485 供电 GPIO29
local RS485_BAUD         = 115200
local RS485_TX_DELAY     = 20000 -- 485 方向切换延时 us

-- 三色 LED（高电平点亮）
local LED_RED   = 27
local LED_GREEN = 28
local LED_BLUE  = 26

-- 网口 DHCP 获取 IP 超时(ms)
local ETH_DHCP_TIMEOUT = 10000

-- ================= 串口命令接口 =================
local usbTrans = uart.VUART_0
local usbRxCache = ""
local cacheTable = {}

-- 异步/主动上报回复函数（CONTROL 事件任务里用）
local function send_response(id, data)
    table.insert(cacheTable, { transId = id, data = data })
    sys.publish("DATA_SEND")
end

-- ================= 网口 IP 缓存（订阅 IP_READY） =================
local eth1_ip = ""
local eth2_ip = ""

-- IP_READY 事件回调（具名函数）
local function on_ip_ready(ip, adapter)
    if adapter == socket.LWIP_ETH then
        eth1_ip = ip or ""
        log.info("factory", "网口1 IP_READY", eth1_ip)
    elseif adapter == socket.LWIP_USER1 then
        eth2_ip = ip or ""
        log.info("factory", "网口2 IP_READY", eth2_ip)
    end
end
sys.subscribe("IP_READY", on_ip_ready)

-- ================= 以太网初始化（双 CH390，DHCP 客户端） =================
local function init_network()
    -- 双 CH390 共用 SPI1，必须同时上电，否则 SPI 信号电平混乱导致通讯失败
    gpio.setup(ETH1_PWR, 1, gpio.PULLUP)
    gpio.setup(ETH2_PWR, 1, gpio.PULLUP)
    -- 网口1 → socket.LWIP_ETH，网口2 → socket.LWIP_USER1（两者不能用同一适配器，否则第二路覆盖第一路）
    exnetif.set_priority_order({
        { ETHERNET = { pwrpin = ETH1_PWR, tp = netdrv.CH390, opts = { spi = 1, cs = ETH1_CS, irq = gpio.WAKEUP0 } } },
        { ETHUSER1 = { pwrpin = ETH2_PWR, tp = netdrv.CH390, opts = { spi = 1, cs = ETH2_CS, irq = gpio.WAKEUP6 } } },
    })
    log.info("factory", "双网口初始化完成（DHCP 客户端）")
end
sys.taskInit(init_network)

-- ================= 485 初始化（隔离 UART1 + 非隔离 UART3） =================
local u485_rx = { active = false, data = nil }

-- 非隔离 485 接收回调（485 测试捕获用，具名函数）
local function on_rs485_receive(id, len)
    if not u485_rx.active then return end
    local data = ""
    while true do
        local s = uart.read(RS485_NONISO_PORT, 1024)
        if not s or #s == 0 then break end
        data = data .. s
    end
    if #data > 0 then
        u485_rx.data = (u485_rx.data or "") .. data
    end
end

local function init_rs485()
    -- 引脚复用（8300 物理脚默认是 LCD 功能，需重映射到 485/UART）
    pins.setup(28, "GPIO37")    -- 隔离 485 收发使能脚
    pins.setup(27, "GPIO36")    -- 非隔离 485 收发使能脚
    pins.setup(25, "UART3_RX")  -- 非隔离 485 RX
    pins.setup(26, "UART3_TX")  -- 非隔离 485 TX
    pins.setup(18, "GPIO29")    -- 非隔离 485 供电脚
    gpio.setup(RS485_NONISO_PWR, 1, gpio.PULLUP) -- 开机拉高 GPIO29 供电

    -- 隔离 485（UART1，内置 RS485 模式，RE/DE 由固件自动控制）
    uart.setup(RS485_ISO_PORT, RS485_BAUD, 8, 1, uart.NONE, uart.LSB, 1024, RS485_ISO_RE_DE, 0, RS485_TX_DELAY)

    -- 非隔离 485（UART3，内置 RS485 模式）+ 接收回调（485 测试捕获用）
    uart.setup(RS485_NONISO_PORT, RS485_BAUD, 8, 1, uart.NONE, uart.LSB, 1024, RS485_NONISO_RE_DE, 0, RS485_TX_DELAY)
    uart.on(RS485_NONISO_PORT, "receive", on_rs485_receive)

    log.info("factory", "485 初始化完成（隔离 UART1 发送 / 非隔离 UART3 接收）")
end
init_rs485()

-- ================= 三色 LED 初始化（默认全灭） =================
gpio.setup(LED_RED, 0, gpio.PULLDOWN)
gpio.setup(LED_GREEN, 0, gpio.PULLDOWN)
gpio.setup(LED_BLUE, 0, gpio.PULLDOWN)

-- ================= 485 一发一收测试（隔离 UART1 发 / 非隔离 UART3 收） =================
local function u485_test()
    local test_str = "485TEST"
    u485_rx.active = true
    u485_rx.data = nil
    -- 发送前清空接收缓冲，避免历史残留误判
    uart.rxClear(RS485_NONISO_PORT)
    -- 隔离 485（UART1）发送，内置 RS485 模式自动控制 GPIO37（高=发送→延时→低=接收）
    uart.write(RS485_ISO_PORT, test_str)

    local waited = 0
    while (not u485_rx.data or #u485_rx.data < #test_str) and waited < 2000 do
        sys.wait(50)
        waited = waited + 50
    end
    u485_rx.active = false

    if u485_rx.data == test_str then
        log.info("U485_TEST", "隔离 UART1 发 / 非隔离 UART3 收成功")
        return "OK"
    end
    log.error("U485_TEST", "失败，期望", test_str, "实际", tostring(u485_rx.data))
    return "ERROR"
end

-- ================= 网口获取 IP 测试（8300 为 DHCP 客户端） =================
local function eth_test(port)
    -- 最多等 10s 拿到该网口 IP，拿到即回复；超时返回 ERROR
    local waited = 0
    while waited < ETH_DHCP_TIMEOUT do
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

-- ================= 重启任务（RST 指令用，延时确保 OK# 回复已发出） =================
local function reboot_later()
    sys.wait(500)
    pm.reboot()
end

-- ================= 指令处理函数（具名，供 procTable 引用） =================
local function cmd_version(id, findCom, data)
    return PROJECT .. "_" .. VERSION
end

local function cmd_imei(id, findCom, data)
    local v = mobile.imei()
    if not v or v == "" then return "ERROR" end
    return v
end

local function cmd_imsi(id, findCom, data)
    local v = mobile.imsi()
    if not v or v == "" then return "ERROR" end
    return v
end

local function cmd_iccid(id, findCom, data)
    local v = mobile.iccid()
    if not v or v == "" then return "ERROR" end
    return v
end

local function cmd_csq(id, findCom, data)
    local v = mobile.csq()
    if v == nil then return "ERROR" end
    return v
end

local function cmd_muid(id, findCom, data)
    local v = mobile.muid()
    if not v or v == "" then return "ERROR" end
    return v
end

local function cmd_vbat(id, findCom, data)
    -- 电池电压：读取模组内部电池电压通道 adc.CH_VBAT，返回 mV（全产品统一）
    adc.open(adc.CH_VBAT)
    local vbat = adc.get(adc.CH_VBAT)
    adc.close(adc.CH_VBAT)
    if not vbat then
        return "ERROR"
    end
    return string.format("%.2f", vbat)
end

local function cmd_flymode(id, findCom, data)
    -- 飞行模式开关：FLYMODE,1# 开，FLYMODE,0# 关（只操作主 LTE，adapter=0）
    local onoff = tonumber(data)
    if not onoff or (onoff ~= 0 and onoff ~= 1) then
        return "ERROR"
    end
    log.info("FLYMODE", onoff)
    mobile.flymode(0, onoff == 1)
    return "OK"
end

local function cmd_ecnpicfg(id, findCom, data)
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
end

local function cmd_hversion(id, findCom, data)
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
end

local function cmd_model(id, findCom, data)
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
end

local function cmd_model_query(id, findCom, data)
    -- 读回当前工业型号（OTP 的 PROD key）
    local v = prodmeta.get("PROD")
    return v or "ERROR"
end

local function cmd_eth_test(id, findCom, data)
    -- 网口获取 IP 测试（8300 为 DHCP 客户端），含 sys.wait，走 CONTROL 事件异步
    local port = tonumber(data)
    if not port or (port ~= 1 and port ~= 2) then
        return "ERROR"
    end
    sys.publish("CONTROL", "ETH_TEST", id, port)
    return
end

local function cmd_u485_test(id, findCom, data)
    -- 485 一发一收测试（隔离 UART1 发 / 非隔离 UART3 收，A接A B接B），含 sys.wait，走 CONTROL 事件异步
    sys.publish("CONTROL", "U485_TEST", id)
    return
end

local function cmd_led_test(id, findCom, data)
    -- 三色 LED：LED_TEST,R# 红 / G# 绿 / B# 蓝 / 0# 全灭（高电平点亮，点亮前先全灭）
    local color = (data or ""):gsub("^%s*", ""):gsub("%s*$", ""):upper()
    gpio.set(LED_RED, 0)
    gpio.set(LED_GREEN, 0)
    gpio.set(LED_BLUE, 0)
    if color == "R" then
        gpio.set(LED_RED, 1)
    elseif color == "G" then
        gpio.set(LED_GREEN, 1)
    elseif color == "B" then
        gpio.set(LED_BLUE, 1)
    elseif color == "0" or color == "OFF" then
        -- 保持全灭
    else
        return "ERROR"
    end
    return "OK"
end

local function cmd_rst(id, findCom, data)
    -- 单独重启（RST#）：不写 test_done，收到即重启（500ms 延时确保 OK# 回复发出）
    log.info("factory", "重启设备")
    sys.taskInit(reboot_later)
    return "OK"
end

local function cmd_test_done(id, findCom, data)
    -- 标记测试完成并重启进入用户模式
    fskv.set("test_done", true)
    log.info("测试完成，已保存状态，3秒后重启")
    sys.timerStart(pm.reboot, 3000)
    return "OK"
end

-- ================= 指令表 =================
local procTable = {
    ["VERSION"]   = cmd_version,
    ["IMEI"]      = cmd_imei,
    ["IMSI"]      = cmd_imsi,
    ["ICCID"]     = cmd_iccid,
    ["CSQ"]       = cmd_csq,
    ["MUID"]      = cmd_muid,
    ["VBAT"]      = cmd_vbat,
    ["FLYMODE"]   = cmd_flymode,
    ["ECNPICFG"]  = cmd_ecnpicfg,
    ["HVERSION"]  = cmd_hversion,
    ["MODEL"]     = cmd_model,
    ["MODEL?"]    = cmd_model_query,
    ["ETH_TEST"]  = cmd_eth_test,
    ["U485_TEST"] = cmd_u485_test,
    ["LED_TEST"]  = cmd_led_test,
    ["RST"]       = cmd_rst,
    ["TEST_DONE"] = cmd_test_done,
}

-- ================= CONTROL 事件任务（异步测试） =================
local function control_task()
    while true do
        local result, param1, param2, param3 = sys.waitUntil("CONTROL")
        log.info("CONTROL", param1)
        if param1 == "U485_TEST" then
            send_response(param2, u485_test() .. "#")
        elseif param1 == "ETH_TEST" then
            send_response(param2, eth_test(param3) .. "#")
        end
    end
end
sys.taskInit(control_task)

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

-- USB 虚拟串口接收回调（具名函数）
local function on_usb_receive(id, len)
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
end
uart.on(usbTrans, "receive", on_usb_receive)

-- USB 虚拟串口发送完成回调（具名函数）
local function on_usb_sent(id)
    sys.publish("USB_SENT_DONE")
end
uart.on(usbTrans, "sent", on_usb_sent)

-- 应答发送任务（具名函数）
local function usb_send_task()
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
end
sys.taskInit(usb_send_task)

return factory
