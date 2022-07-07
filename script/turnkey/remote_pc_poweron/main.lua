PROJECT = "poweron_tool"
VERSION = "1.0.0"

--测试支持硬件：ESP32C3
--测试固件版本：LuatOS-SoC_V0003_ESP32C3[_USB].soc

sys = require "sys"

---------------------------------------------------------------------------
--这些东西改成自己用的
local wifiName,wifiPassword = "wifi", "password"--wifi账号密码
local pcIp =  "255.255.255.255"--目标pc ip，广播就255.255.255.255
local pcMac = "112233445566" --写mac的hex值就行
--服务器使用介绍详见https://api.luatos.org/#poweron
local mqttAddr = "mqtt://apicn.luatos.org:1883"--这是公共服务器，只允许订阅和推送poweron/request/+、poweron/reply/+两个主题
local mqttUser,mqttPassword = "13xxxxxxxxx","888888"--你的erp账号和密码，连接mqtt服务器用，默认八个8 erp.openluat.com
local subscribeTopic,subscribePayload = "poweron/request/chenxuuu","poweron"
local replyTopic,replyPayload = "poweron/reply/chenxuuu","ok"
---------------------------------------------------------------------------

connected = false

-- 开发板上的2个LED
local LED_D4 = gpio.setup(12, 0)
local LED_D5 = gpio.setup(13, 0)

sys.taskInit(function()
    while true do
        if connected then
            LED_D4(1)
            sys.wait(1000)
        else
            LED_D4(0)
            sys.wait(200)
            LED_D4(1)
            sys.wait(200)
        end
    end
end)


function wakeUp(mac)
    log.info("socket", "begin socket")
    local sock = socket.create(socket.UDP) -- udp
    log.info("socket.bind", socket.bind(sock, "0.0.0.0", 23333)) --udp必须绑定端口
    local err = socket.connect(sock, pcIp, 7)--你电脑ip
    if err ~= 0 then log.info("socket", err) return end

    mac = mac:fromHex()
    local msg = string.rep(string.char(0xff),6)..string.rep(mac,16)
    local len = socket.send(sock, msg)
    log.info("socket", "sendlen", len)
    socket.close(sock)
    return len == #msg, len
end

sys.taskInit(function()
    log.info("wlan", "wlan_init:",  wlan.init())
    wlan.setMode(wlan.STATION)
    wlan.connect(wifiName,wifiPassword)
    -- 等到成功获取ip就代表连上局域网了
    local result, data = sys.waitUntil("IP_READY")
    log.info("wlan", "IP_READY", result, data)


    local mqttc = espmqtt.init({
        uri = mqttAddr,
        client_id = (esp32.getmac():toHex()),
        username = mqttUser,
        password = mqttPassword,
    })
    log.info("mqttc", mqttc)
    if mqttc then
        log.info("mqttc", "what happen")
        local ok, err = espmqtt.start(mqttc)
        log.info("mqttc", "start", ok, err)
        if ok then
            connected = true
            while 1 do
                log.info("mqttc", "wait ESPMQTT_EVT 30s")
                local result, c, ret, topic, data = sys.waitUntil("ESPMQTT_EVT", 30000)
                log.info("mqttc", result, c, ret)
                if result == false then
                    -- 没消息, 没动静
                    log.info("mqttc", "wait timeout")
                elseif ret == espmqtt.EVENT_DISCONNECTED then--断线了
                    log.info("mqttc", "disconnected!!!")
                    break
                elseif c == mqttc then
                    -- 是当前mqtt客户端的消息, 处理之
                    if ret == espmqtt.EVENT_CONNECTED then
                        -- 连接成功, 通常就是定义一些topic
                        espmqtt.subscribe(mqttc, subscribeTopic)
                    elseif ret == espmqtt.EVENT_DATA then
                        -- 服务器来消息了, 如果data很长(超过4kb), 可能会分多次接收, 导致topic为空字符串
                        log.info("mqttc", topic, data)
                        if data == subscribePayload then--收到payload信息是开机
                            LED_D5(1)
                            log.info("poweron","发送开机请求啦！")
                            wakeUp(pcMac)
                            espmqtt.publish(mqttc, replyTopic, replyPayload)--回一条
                            LED_D5(0)
                        end
                    else
                        -- qos > 0 的订阅信息有响应, 会进这个分支
                        -- 默认情况下mqtt是自动重连的, 不需要用户关心
                        log.info("mqttc", "event", ret)
                    end
                else
                    log.info("mqttc", "not this mqttc")
                end
            end
            connected = false
        else
            log.warn("mqttc", "bad start", err)
        end
        espmqtt.destroy(mqttc)
        log.warn("reboot", "device will reboot")
        rtos.reboot()
    end
end)


sys.run()
