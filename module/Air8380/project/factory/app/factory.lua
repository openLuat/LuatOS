--[[
@module  factory
@summary Air8380产测功能模块（纯产测，不合并 iRTU）
@version 1.0
@date    2026.09.20
@usage
Air8380 基于 Air8000W 的网络网关产品，外设仅 CH390H 网口 + SPI NAND Flash。
产测包含：基础信息 + 校准位(ECNPICFG) + 写号(MODEL/HVERSION/MODEL?) + Flash 写读对比(FLASH_TEST) + 网口 WAN 联网检测(NET_TEST) + WiFi扫描(WIFI_TEST) + 系统控制。
无按键、无 LED。
写号使用 prodmeta 库写入 OTP（key: PROD=工业型号, PCB=硬件版本）；校准位读取用 mobile.ecnpicfg() 只读接口。
网口开机默认进入 WAN 模式（DHCP 客户端从上位网络拿 IP），NET_TEST 回复设备获取到的 IP。
FLASH_TEST/NET_TEST 含 sys.wait，走 CONTROL 事件模式异步执行。
硬件注意：网口与 Flash 共用 SPI1，两者必须同时上电——Flash 掉电会拖住共享 SPI 总线导致网口不通。
故开机即同时打开 GPIO1(网口)+GPIO2(Flash)，Flash 常上电 + CS 置高失选。
]]

local prodmeta = require "prodmeta"

local factory = {}

log.info("测试模式", "启动中")

-- 硬编码管脚定义（主控 Air8000W）
local CH390_POWER_PIN = 1      -- CH390H 网口供电使能 GPIO1
local FLASH_POWER_PIN = 2      -- SPI NAND Flash 供电使能 GPIO2

local CH390_SPI_ID   = 1       -- 网口使用 SPI1
local CH390_CS_PIN   = 12      -- 网口 CS = GPIO12
local CH390_IRQ_PIN  = 17      -- 网口中断 INT = GPIO17
local CH390_SPI_FREQ = 25600000

local FLASH_SPI_ID   = 1       -- Flash 使用 SPI1
local FLASH_CS_PIN   = 16      -- Flash CS = GPIO16
local FLASH_SPI_FREQ = 2 * 1000 * 1000  -- SPI NAND 只能半双工, 2MHz

local MOUNT_POINT     = "/little_flash"
local NET_DHCP_TIMEOUT = 10000          -- 等设备 WAN 口通过 DHCP 拿到 IP 的超时(ms)

-- 初始化变量
local usbRxCache = ""
local cacheTable = {}

-- 网口 WAN 模式状态
local wan_ip = nil  -- 设备 WAN 口通过 DHCP 从上游获取到的 IP

-- 订阅 IP_READY：设备 WAN 口拿到 IP 时记录（payload: ip, adapter）
sys.subscribe("IP_READY", function(ip, adapter)
    if adapter == socket.LWIP_ETH then
        wan_ip = ip
        log.info("NET", "WAN 获取 IP", ip)
    end
end)

local usbTrans = uart.VUART_0

-- 发送回复（CONTROL 事件任务里用）
local function send_response(id, data)
    table.insert(cacheTable, { transId = id, data = data })
    sys.publish("DATA_SEND")
end

-- ================= Flash 测试（写入 → 读出 → 对比） =================
-- 供电策略：Flash 与网口共用 SPI1，供电已在开机时同时打开（见 net_wan_start），
-- 这里测试结束后不关 Flash 供电，只把 CS 置高失选，网口还要继续用这条总线。
local function flash_test()
    -- 1. 开供电（幂等：开机已上电，重复打开无害）
    gpio.setup(FLASH_POWER_PIN, 1)
    sys.wait(30) -- 供电稳定

    -- 2. SPI 初始化（SPI NAND 只能半双工）
    local spi_device = spi.deviceSetup(FLASH_SPI_ID, FLASH_CS_PIN, 0, 0, 8, FLASH_SPI_FREQ, spi.MSB, 1, 0)
    if not spi_device then
        log.error("FLASH_TEST", "SPI 初始化失败")
        gpio.setup(FLASH_CS_PIN, 1)  -- 保持 Flash 上电，仅 CS 置高失选
        return "ERROR"
    end

    -- 3. 初始化 Flash 设备
    local flash_device = lf.init(spi_device)
    if not flash_device then
        log.error("FLASH_TEST", "lf.init 失败")
        spi_device:close()
        gpio.setup(FLASH_CS_PIN, 1)  -- 保持 Flash 上电，仅 CS 置高失选
        return "ERROR"
    end

    -- 4. 挂载文件系统（首次可能触发格式化，失败重试一次）
    if not lf.mount(flash_device, MOUNT_POINT) then
        if not lf.mount(flash_device, MOUNT_POINT) then
            log.error("FLASH_TEST", "挂载失败")
            gpio.setup(FLASH_CS_PIN, 1)  -- 保持 Flash 上电，仅 CS 置高失选
            return "ERROR"
        end
    end

    -- 5. 写入测试图案（约 4KB）
    local test_file = MOUNT_POINT .. "/factory_test.txt"
    local test_data = ""
    for i = 1, 200 do
        test_data = test_data .. string.format("Air8380-FlashTest-%04d,", i)
    end
    local f = io.open(test_file, "wb")
    if not f then
        log.error("FLASH_TEST", "打开文件失败")
        lf.unmount(MOUNT_POINT)
        gpio.setup(FLASH_CS_PIN, 1)  -- 保持 Flash 上电，仅 CS 置高失选
        return "ERROR"
    end
    f:write(test_data)
    f:close()

    -- 6. 读回对比
    local read_data = io.readFile(test_file)
    if not read_data or read_data ~= test_data then
        log.error("FLASH_TEST", "读写不一致", read_data and #read_data or 0, #test_data)
        lf.unmount(MOUNT_POINT)
        gpio.setup(FLASH_CS_PIN, 1)  -- 保持 Flash 上电，仅 CS 置高失选
        return "ERROR"
    end

    -- 7. 清理
    log.info("FLASH_TEST", "读写一致", #test_data, "字节")
    os.remove(test_file)
    lf.unmount(MOUNT_POINT)
    spi_device:close()
    gpio.setup(FLASH_CS_PIN, 1)  -- 保持 Flash 上电，仅 CS 置高失选
    return "OK"
end

-- ================= 网口 WAN 模式（开机默认 WAN 上联，DHCP 客户端） =================

-- 恢复 CH390 所需的 SPI1 总线（flash 测试会重配/关闭 SPI1）
local function ch390_spi_restore()
    local result = spi.setup(CH390_SPI_ID, nil, 0, 0, 8, CH390_SPI_FREQ)
    log.info("NET", "恢复 CH390 SPI1 总线", result)
end

-- 上电 + SPI + netdrv 初始化 CH390 为 WAN 模式（DHCP 客户端从上位网络拿 IP）
local function net_wan_start()
    -- 1. 开供电：网口与 Flash 共用 SPI1，必须同时上电！
    --    Flash 掉电时其引脚会拖住/干扰 SPI 总线，导致 CH390 读 VID/PID 全 0、网口不通
    gpio.setup(CH390_POWER_PIN, 1)
    gpio.setup(FLASH_POWER_PIN, 1)
    gpio.setup(FLASH_CS_PIN, 1)   -- Flash CS 置高失选，避免其驱动 MISO 干扰 CH390
    sys.wait(50)

    -- 2. SPI1 初始化（CH390 走 legacy 总线 API，需全双工 25.6MHz）
    local result = spi.setup(CH390_SPI_ID, nil, 0, 0, 8, CH390_SPI_FREQ)
    if result ~= 0 then
        log.error("NET", "SPI 初始化失败", result)
        gpio.setup(CH390_POWER_PIN, 0)
        return
    end

    -- 3. 注册 CH390（中断模式，INT 接 GPIO17）
    local ok = netdrv.setup(socket.LWIP_ETH, netdrv.CH390, {
        spi = CH390_SPI_ID,
        cs = CH390_CS_PIN,
        irq = CH390_IRQ_PIN,
    })
    if ok ~= true then
        log.error("NET", "CH390 注册失败", tostring(ok))
        gpio.setup(CH390_POWER_PIN, 0)
        return
    end

    -- 4. 等 CH390 初始化完成
    sys.wait(1000)

    -- 5. 开启 DHCP 客户端（WAN 模式：设备从上游路由器/测试电脑拿 IP）
    wan_ip = nil
    netdrv.dhcp(socket.LWIP_ETH, true)
    log.info("NET", "WAN 模式就绪，等待 DHCP 获取 IP")
end

-- ================= 网口测试（回复设备 WAN 口获取到的 IP） =================
local function net_test()
    -- 诊断：读 link 与 MAC（不判定，仅日志）
    log.info("NET_TEST", "link", tostring(netdrv.link(socket.LWIP_ETH)), "MAC", tostring(netdrv.mac(socket.LWIP_ETH)))

    -- 设备 WAN 口已通过 DHCP 拿到 IP（IP_READY 事件里记录的）
    local ip = wan_ip or socket.localIP(socket.LWIP_ETH)
    if ip and ip ~= "" and ip ~= "0.0.0.0" then
        log.info("NET_TEST", "设备已获取 IP", ip)
        return ip
    end

    -- 尚未拿到，等设备向上游发起 DHCP 拿 IP，超时判定
    local timeout = 0
    while timeout < NET_DHCP_TIMEOUT do
        sys.wait(200)
        timeout = timeout + 200
        ip = wan_ip or socket.localIP(socket.LWIP_ETH)
        if ip and ip ~= "" and ip ~= "0.0.0.0" then
            log.info("NET_TEST", "设备获取 IP 成功", ip, timeout, "ms")
            return ip
        end
    end
    log.error("NET_TEST", "等设备获取 IP 超时", timeout, "ms")
    return "ERROR"
end

-- ================= WiFi 扫描测试（扫描附近热点，返回热点数量） =================
local function wifi_test()
    -- Air8000W 内置 WiFi，wlan 为核心库；扫描前先初始化（已初始化则幂等无害）
    if not wlan or not wlan.scan or not wlan.scanResult then
        log.error("WIFI_TEST", "wlan 不可用")
        return "ERROR"
    end
    if wlan.init then
        pcall(wlan.init)
    end
    wlan.scan()
    -- 扫描是异步 API，启动后马上返回；等 WLAN_SCAN_DONE 消息（最多 10s）
    if not sys.waitUntil("WLAN_SCAN_DONE", 10000) then
        log.error("WIFI_TEST", "扫描超时")
        return "ERROR"
    end
    local results = wlan.scanResult()
    if not results or type(results) ~= "table" then
        log.error("WIFI_TEST", "扫描结果为空")
        return "ERROR"
    end
    local count = #results
    for i, v in ipairs(results) do
        log.info("WIFI_TEST", i, v.ssid, v.rssi)
    end
    log.info("WIFI_TEST", "扫描到", count, "个热点")
    return tostring(count)
end

-- 开机默认进入 WAN 联网模式（设备从上位拿 IP，NET_TEST 回复设备拿到的 IP）
sys.taskInit(net_wan_start)

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
        -- 飞行模式开关：FLYMODE,1# 开飞行模式，FLYMODE,0# 关飞行模式（只操作主 LTE，adapter=0）
        local onoff = tonumber(data)
        if not onoff or onoff ~= 0 and onoff ~= 1 then
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
    ["MODEL_RETEST"] = function(id, findCom, data)
        -- V3 返工指令：MODEL_RETEST,CONFIRM# 写返工标记并重启；不带魔法字/魔法字错 → ERROR
        if not findCom then
            log.error("factory", "MODEL_RETEST 缺少魔法字")
            return "ERROR"
        end
        local magic = data:gsub("^%s*", ""):gsub("%s*$", "")
        if magic ~= "CONFIRM" then
            log.error("factory", "MODEL_RETEST 魔法字错误:", magic)
            return "ERROR"
        end
        fskv.set("retest_flag", true)
        log.info("factory", "收到返工指令，写入返工标记，重启进入产测模式")
        sys.timerStart(pm.reboot, 500) -- 延时确保 OK# 发出
        return "OK"
    end,
    ["MODEL_RETEST?"] = function(id, findCom, data)
        -- 查询当前返工标记状态（回 true#/false#）
        return fskv.get("retest_flag") and "true" or "false"
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
    ["FLASH_TEST"] = function(id, findCom, data)
        -- Flash 写读对比，含 sys.wait，走 CONTROL 事件异步处理
        sys.publish("CONTROL", "FLASH_TEST", id)
        return
    end,
    ["NET_TEST"] = function(id, findCom, data)
        -- 网口 WAN 联网检测（回复设备从上游 DHCP 获取到的 IP），含 sys.wait，走 CONTROL 事件异步处理
        sys.publish("CONTROL", "NET_TEST", id)
        return
    end,
    ["WIFI_TEST"] = function(id, findCom, data)
        -- WiFi 扫描测试（返回热点数量），含 sys.wait，走 CONTROL 事件异步处理
        sys.publish("CONTROL", "WIFI_TEST", id)
        return
    end,
    ["TEST_DONE"] = function(id, findCom, data)
        -- V3：返工产测 → 删除返工标记后重启（恢复正常模式）；首次产测 → 直接重启（OTP1 已写号）
        if fskv.get("retest_flag") then
            fskv.del("retest_flag")
            log.info("TEST_DONE", "返工产测完成，删除返工标记，3秒后重启恢复正常模式")
        else
            log.info("TEST_DONE", "首次产测完成，3秒后重启进入正常模式")
        end
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
        local result, param1, param2 = sys.waitUntil("CONTROL")
        log.info("CONTROL", param1)
        if param1 == "FLASH_TEST" then
            -- 先停掉 CH390（IRQ 模式中断 + 1s 心跳仍会抢 SPI1），避免 flash 测试期间抢 SPI1
            netdrv.ctrl(socket.LWIP_ETH, netdrv.CTRL_UPDOWN, 0)
            local r = flash_test()
            ch390_spi_restore()  -- 恢复 SPI1 到 CH390 的 25.6MHz 全双工
            netdrv.ctrl(socket.LWIP_ETH, netdrv.CTRL_UPDOWN, 1)  -- 重启 CH390，恢复 WAN 联网
            send_response(param2, r .. "#")
        elseif param1 == "NET_TEST" then
            send_response(param2, net_test() .. "#")
        elseif param1 == "WIFI_TEST" then
            send_response(param2, wifi_test() .. "#")
        end
    end
end)

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
