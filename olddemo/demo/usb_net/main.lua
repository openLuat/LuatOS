PROJECT = "USB_NET"
VERSION = "1.0.0"

local function usb_cb(usb_id, class, app_id, event, param1, param2, param3)
    log.info("class", class, "event", event)
    if event == usb.EV_CONNECT then
        if class == usb.RNDIS then
            log.info("rndis设备已连接")
        elseif class == usb.CDC_ECM then
            log.info("ecm设备已连接")
        end
    end
    if event == usb.EV_DISCONNECT then
        if class == usb.RNDIS then
            log.info("rndis设备已断开连接")
        elseif class == usb.CDC_ECM then
            log.info("ecm设备已断开连接")
        end
    end
end

local function air8101_evb_init()
    local usb_power_en = gpio.setup(28, 0, gpio.PULLUP)
    sys.wait(500)
    usb_power_en(1)
end

local function air160x_evb_init()
    local usb_power_en = gpio.setup(12, 0, gpio.PULLUP)
    sys.wait(500)
    usb_power_en(1)
end

local function usb_control()
    usb.on(0, usb_cb)
    pm.power(pm.USB, false)
    usb.mode(0, usb.HOST)
    pm.power(pm.USB, true)
end

local function http_test()
    for i = 1, 5 do
        log.info("http下行")
        local url = "https://httpbin.luatos.com/bytes/2048"
        log.info("发起HTTP GET请求", url)
        local code, headers, body = http.request("GET", url, nil, nil, {
            timeout = 10000,
            adapter = socket.LWIP_USB
        }).wait()

        -- 打印HTTP请求的结果，包括响应码code和响应体长度#body。
        if code == 200 then
            log.info("HTTP请求成功", "响应码", code, "响应体长度", body and #body)
            sys.publish("打印网卡信息", "succeeded")
        else
            log.error("HTTP请求失败", "错误码", code)
            sys.publish("打印网卡信息", "failed")
        end
        sys.wait(1000)
    end
end

local function socket_test()
    local host = "115.120.239.161"
    local port = 25068
    local rxbuf = zbuff.create(8192)
    local function socket_cb(netc, event, param)
        if param ~= 0 then
            sys.publish("socket_disconnect")
            return
        end
        if event == socket.LINK then
        elseif event == socket.ON_LINE then
            socket.tx(netc, "hello,luatos!")
        elseif event == socket.EVENT then
            socket.rx(netc, rxbuf)
            socket.wait(netc)
            if rxbuf:used() > 0 then
                log.info("收到", rxbuf:toStr(0, rxbuf:used()):toHex())
                log.info("发送", rxbuf:used(), "bytes")
                socket.tx(netc, rxbuf)
            end
            rxbuf:del()
        elseif event == socket.TX_OK then
            socket.wait(netc)
            log.info("发送完成")
        elseif event == socket.CLOSED then
            sys.publish("socket_disconnect")
        end
    end

    local netc = socket.create(socket.LWIP_USB, socket_cb)
    socket.config(netc)
    -- socket.debug(netc, true)

    while true do
        socket.connect(netc, host, port)
        sys.waitUntil("socket_disconnect")
        socket.close(netc)
        sys.wait(5000)
    end
end

sys.taskInit(function()
    local bsp = rtos.bsp()
    log.info("bsp", bsp)
    if bsp == "Air8101" then
        log.info("use air8101 evb init")
        air8101_evb_init()
    elseif string.find(bsp, "Air160") then
        log.info("use air160x evb init")
        air160x_evb_init()
    else
        log.info("not support bsp")
        return
    end
    usb_control()

    while true do
        local result, ip, adapter = sys.waitUntil("IP_READY")
        log.info("result", result, ip, adapter)
        if result and adapter == socket.LWIP_USB then
            break
        end
    end
    sys.taskInit(socket_test)
    sys.taskInit(http_test)
end)

sys.run()
