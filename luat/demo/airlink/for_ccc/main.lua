-- LuaTools需要PROJECT和VERSION这两个信息
PROJECT = "air8000_factory"
VERSION = "001.000.012"

log.info("main", PROJECT, VERSION)

-- 引入必要的库文件(lua编写), 内部库不需要require
sys = require("sys")

if wdt then
    --添加硬狗防止程序卡死，在支持的设备上启用这个功能
    wdt.init(9000)--初始化watchdog设置为9s
    sys.timerLoopStart(wdt.feed, 3000)--3s喂一次狗
end

-- log.setLevel(log.LOG_ERROR)

local uartid = 1 -- 根据实际设备选取不同的uartid

--初始化
uart.setup(
    uartid,--串口id
    115200,--波特率
    8,--数据位
    1--停止位
)

local topic_uart_receive = "air8000_uart1_receive"

-- --循环发数据
-- sys.timerLoopStart(uart.write,1000, uartid, "test")
uart.on(uartid, "sent", function(id)
    log.info("uart", "sent", id)
end)

-- 收取数据会触发回调, 这里的"receive" 是固定值
uart.on(uartid, "receive", function(id, len)
    log.info("uart", "receive", id,len)
    data = uart.read(id, len)
    if data and len==#data then
        log.info("uart", "receive", data)
        sys.publish(topic_uart_receive,data)
    elseif #data > 2 then
        log.info("uart", "receive", data:toHex())
        uart.write(uartid, "ERROR\r\n")
    end
end)

local function ble_callback(ble_device, ble_event, ble_param)
    if ble_event == ble.EVENT_SCAN_INIT then
        log.info("ble", "scan init")
    elseif ble_event == ble.EVENT_SCAN_REPORT then
        log.info("ble", "scan report", ble_param.rssi, ble_param.adv_addr:toHex(), ble_param.data:toHex())
    elseif ble_event == ble.EVENT_SCAN_STOP then
        log.info("ble", "scan stop")
    end
end

sys.taskInit(function()
    while 1 do
        local ret, data = sys.waitUntil(topic_uart_receive)
        if ret then
            if data:sub(1,11) == "AT+WIFI_OFF" then--关闭wifi------------
                local result = airlink.power(false)
                log.info("关闭wifi")
                if not result then
                    uart.write(uartid, "OK\r\n")
                else
                    uart.write(uartid, "ERROR\r\n")
                end
            elseif data:sub(1,10) == "AT+WIFI_ON" then--开启wifi
                airlink.power(true)
                while airlink.ready() ~= true do
                    sys.wait(100)
                end
                local result = wlan.init()
                log.info("开启wifi",result)
                if result then
                    uart.write(uartid, "OK\r\n")
                else
                    uart.write(uartid, "ERROR\r\n")--------------
                end
            elseif data:sub(1,12) == "AT+WIFI_SCAN" then--wifi扫描---------------
                while airlink.ready() ~= true do
                    sys.wait(100)
                end
                wlan.init()
                wlan.scan()
                log.info("扫描wifi")
                sys.waitUntil("WLAN_SCAN_DONE", 5000)
                local results = wlan.scanResult()
                for k,v in pairs(results) do
                    uart.write(uartid, string.format("+WIFISCAN: %s,%s,%s\r\n",
                                    v["bssid"]:toHex(), v["rssi"], v["channel"]))
                end
                if results then
                    uart.write(uartid, "OK\r\n")
                else
                    uart.write(uartid, "ERROR\r\n")
                end
            elseif data:sub(1,16) == "AT+WIFI_CONNECT=" then -- 连接指定ssid/passwd--------
                wlan.init()

                local SSID = data:sub(17,data:find(",")-1)
                local PWD = data:sub(data:find(",")+1,data:find('\r')-1)

                log.info("SSID", SSID,"PWD", PWD)
                wlan.connect(SSID, PWD)
                sys.wait(8000)
                iperf.server(socket.LWIP_STA)
                sys.wait(5000)
                log.info("连接指定wifi")
                local code, headers, body = http.request("GET", "https://httpbin.air32.cn/get", nil, nil, {adapter=socket.LWIP_STA}).wait()
                log.info("http", code, headers, body and #body)
                if code == 200 then
                    uart.write(uartid, "OK\r\n")
                else
                    uart.write(uartid, "ERROR\r\n")
                end

            elseif data:sub(1,11) == "AT+BLE_Init" then--初始化蓝牙
                bluetooth_device = bluetooth.init()
                ble_device = bluetooth_device:ble(ble_callback)
                log.info("初始化蓝牙")
                if ble_device then
                    uart.write(uartid, "OK\r\n")
                else
                    uart.write(uartid, "ERROR\r\n")
                end
            elseif data:sub(1,11) == "AT+BLE_Scan" then--蓝牙扫描

                -- 扫描模式
                sys.wait(1000)
                local result = ble_device:scan_create() -- 使用默认参数, addr_mode=0, scan_interval=100, scan_window=100
                -- ble_device:scan_create(0, 10, 10) -- 使用自定义参数
                sys.wait(100)
                log.info("开始扫描")
                ble_device:scan_start()

                sys.wait(5000)
                log.info("停止扫描")
                ble_device:scan_stop()
                if result then
                    uart.write(uartid, "OK\r\n")
                else
                    uart.write(uartid, "ERROR\r\n")
                end

            elseif data:sub(1,11) == "AT+ResetAll" then--整体复位
                uart.write(uartid, "Reset all\r\n")
                sys.wait(500)
                rtos.reboot()

            elseif #data > 2 then
                log.info("uart", data:toHex())
                uart.write(uartid, "ERROR\r\n")
            end
        end
    end
end)


-- 用户代码已结束---------------------------------------------
-- 结尾总是这一句
sys.run()
-- sys.run()之后后面不要加任何语句!!!!!
