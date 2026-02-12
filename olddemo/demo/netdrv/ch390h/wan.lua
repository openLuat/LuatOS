-- 引入必要的库文件(lua编写), 内部库不需要require
sys = require("sys")
sysplus = require("sysplus")
-- spi id
local spi_id = 0
-- 片选引脚
local spi_cs = 8
-- 数据宽度
local spi_databits = 8
-- CPHA
local spi_cpha = 0
-- CPOL
local spi_cpol = 0
-- 时钟速率
local spi_speed = 25600000
-- 高低位顺序，可选，默认高位在前
local spi_bit_order = spi.MSB
-- 模式，可选，默认主模式
local spi_mode = spi.master
-- 通信方式，可选，默认全双工
local spi_communication = spi.full

log.info("bsp", rtos.bsp())
if rtos.bsp() == "Air1601" then
    spi_id = 1
end


local function ch390_init()
    local result = spi.setup(spi_id, nil, spi_cpha, spi_cpol, spi_databits, spi_speed, spi_bit_order, spi_mode, spi_communication)
    log.info("main", "open", result)
    if result ~= 0 then -- 返回值为0，表示打开成功
        log.info("main", "spi open error", result)
        return
    end

    netdrv.setup(socket.LWIP_USER0, netdrv.CH390, {
        spi = spi_id,
        cs = spi_cs
    })
    netdrv.dhcp(socket.LWIP_USER0, true)
end

local function http_srv_test()
    LEDA = gpio.setup(27, 0, gpio.PULLUP)
    httpsrv.start(80, function(client, method, uri, headers, body)
        log.info("httpsrv", method, uri, json.encode(headers), body)
        -- meminfo()
        if uri == "/led/1" then
            LEDA(1)
            return 200, {}, "ok"
        elseif uri == "/led/0" then
            LEDA(0)
            return 200, {}, "ok"
        end
        return 404, {}, "Not Found" .. uri
    end, socket.LWIP_USER0)
    iperf.server(socket.LWIP_USER0)
    if netdrv.on then
        netdrv.on(socket.LWIP_USER0, netdrv.EVT_SOCKET, function(id, event, params)
            log.info("netdrv", "socket event", id, event, json.encode(params or {}))
        end)
    else
        log.warn("netdrv", "not support netdrv.on")
    end
end

local function http_request_test()
    while 1 do
        sys.wait(5000)
        -- 正常请求
        local code, headers, body = http.request("GET", "http://httpbin.air32.cn/bytes/4096", nil, nil, {
            adapter = socket.LWIP_USER0
        }).wait()
        log.info("http", code, headers, body and #body)
        -- 故意失败1
        -- local code, headers, body = http.request("GET", "http://httpbin.air323.cn/status/404", nil, nil, {adapter=socket.LWIP_USER0, timeout=5000}).wait()
        -- log.info("http", code, headers, body and #body)
        -- -- 故意失败2
        -- local code, headers, body = http.request("GET", "http://112.125.89.8:40000/status/404", nil, nil, {adapter=socket.LWIP_USER0, timeout=5000}).wait()
        -- log.info("http", code, headers, body and #body)
        -- log.info("lua", rtos.meminfo())
        -- log.info("sys", rtos.meminfo("sys"))
    end
end

-- 根据自己的服务器修改以下参数
local mqtt_host = "lbsmqtt.airm2m.com"
local mqtt_port = 1884
local mqtt_isssl = false
local client_id = "abc"
local user_name = "user"
local password = "password"

local pub_topic = "/luatos/pub/" .. (mcu.unique_id():toHex())
local sub_topic = "/luatos/sub/" .. (mcu.unique_id():toHex())

local mqttc = nil

local function mqtt_test()
    -- 下面的是mqtt的参数均可自行修改
    client_id = mcu.unique_id():toHex()
    -- 打印一下上报(pub)和下发(sub)的topic名称
    -- 上报: 设备 ---> 服务器
    -- 下发: 设备 <--- 服务器
    -- 可使用mqtt.x等客户端进行调试
    log.info("mqtt", "pub", pub_topic)
    log.info("mqtt", "sub", sub_topic)

    -- 打印一下支持的加密套件, 通常来说, 固件已包含常见的99%的加密套件
    -- if crypto.cipher_suites then
    --     log.info("cipher", "suites", json.encode(crypto.cipher_suites()))
    -- end
    if mqtt == nil then
        while 1 do
            sys.wait(1000)
            log.info("bsp", "本bsp未适配mqtt库, 请查证")
        end
    end

    -------------------------------------
    -------- MQTT 演示代码 --------------
    -------------------------------------
    -- socket.dft(socket.LWIP_USER0)
    mqttc = mqtt.create(socket.LWIP_USER0, mqtt_host, mqtt_port, mqtt_isssl)

    mqttc:auth(client_id,user_name,password) -- client_id必填,其余选填
    -- mqttc:keepalive(240) -- 默认值240s
    mqttc:autoreconn(true, 3000) -- 自动重连机制

    mqttc:on(function(mqtt_client, event, data, payload)
        -- 用户自定义代码
        log.info("mqtt", "event", event, mqtt_client, data, payload)
        if event == "conack" then
            -- 联上了
            sys.publish("mqtt_conack")
            mqtt_client:subscribe(sub_topic)--单主题订阅
            -- mqtt_client:subscribe({[topic1]=1,[topic2]=1,[topic3]=1})--多主题订阅
        elseif event == "recv" then
            log.info("mqtt", "downlink", "topic", data, "payload", payload)
            sys.publish("mqtt_payload", data, payload)
        elseif event == "sent" then
            -- log.info("mqtt", "sent", "pkgid", data)
        -- elseif event == "disconnect" then
            -- 非自动重连时,按需重启mqttc
            -- mqtt_client:connect()
        end
    end)

    -- mqttc自动处理重连, 除非自行关闭
    mqttc:connect()
	sys.waitUntil("mqtt_conack")
    while true do
        -- 演示等待其他task发送过来的上报信息
        local ret, topic, data, qos = sys.waitUntil("mqtt_pub", 300000)
        if ret then
            -- 提供关闭本while循环的途径, 不需要可以注释掉
            if topic == "close" then break end
            mqttc:publish(topic, data, qos)
        end
        -- 如果没有其他task上报, 可以写个空等待
        --sys.wait(60000000)
    end
    mqttc:close()
    mqttc = nil
end

sys.taskInit(function()
    -- 初始化以太网
    ch390_init()
    -- 等以太网就绪
    while 1 do
        local result, ip, adapter = sys.waitUntil("IP_READY", 3000)
        log.info("ready?", result, ip, adapter)
        if adapter and adapter == socket.LWIP_USER0 then
            break
        end
    end
    sys.wait(200)
    -- http请求测试
    http_request_test()

    -- httpsrv测试
    -- http_srv_test()
    -- mqtt测试
    -- mqtt_test()
end)


