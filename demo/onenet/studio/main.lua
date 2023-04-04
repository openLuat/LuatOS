-- LuaTools需要PROJECT和VERSION这两个信息
PROJECT = "onenetdemo"
VERSION = "1.0.0"

--[[
本demo需要mqtt库, 大部分能联网的设备都具有这个库
mqtt也是内置库, 无需require

本demo演示的是 OneNet Studio, 注意区分
https://open.iot.10086.cn/studio/summary
https://open.iot.10086.cn/doc/v5/develop/detail/iot_platform
]]

-- sys库是标配
_G.sys = require("sys")
--[[特别注意, 使用mqtt库需要下列语句]]
_G.sysplus = require("sysplus")

-- 根据自己的设备修改以下参数
----------------------------------------------
-- OneNet Studio
mqtt_host = "studio-mqtt.heclouds.com"
mqtt_port = 1883
mqtt_isssl = false
local pid = "KzUSNA8BPh" -- 产品id
local device = "abcdef" -- 设备名称, 按需设置, 如果是Cat.1系列通常用mobile.imei()
local device_secret = "21BhRAyik1mGCWoFNMFj+INgCr7QZw/pDTXnHpRaf3U=" -- 设备密钥
client_id, user_name, password = iotauth.onenet(pid, device, device_secret)

-- 下面是常用的topic, 完整topic可参考 https://open.iot.10086.cn/doc/v5/develop/detail/639
pub_topic = "$sys/" .. pid .. "/" .. device .. "/thing/property/post"
sub_topic = "$sys/" .. pid .. "/" .. device .. "/thing/property/set"
pub_custome = "$sys/" .. pid .. "/" .. device .. "/custome/up"
pub_custome_reply = "$sys/" .. pid .. "/" .. device .. "/custome/up_reply"
sub_custome = "$sys/" .. pid .. "/" .. device .. "/custome/down/+"
sub_custome_reply = "$sys/" .. pid .. "/" .. device .. "/custome/down_reply/"
------------------------------------------------

local mqttc = nil
local payloads = {}
LED = function() end

-- if wdt then
--     wdt.init(9000)
--     sys.timerLoopStart(wdt.feed, 3000)
-- end

function on_downlink(topic, payload)
    -- 演示多种处理方式

    -- 方式一, 将数据publish出去, 在另外一个sys.subscribe内处理
    sys.publish("mqtt_payload", data, payload)

    -- 方式二, 将数据加入队列, 然后通知task处理
    -- table.insert(payloads, {topic, payload})

    -- 方式三, 直接处理
    if payload.startsWith("{") and payload.endsWith("}") then
        -- 可能是json,尝试解析
        local jdata = json.decode(payload)
        if jdata then
            -- 属性设置
            if topic == sub_topic then
                local params = jdata.params
                if params then
                    local power_switch = jdata.params.power_switch
                    if power_switch then
                        if power_switch == 1 then
                            log.info("led", "on")
                            LED(1)
                        else
                            log.info("led", "off")
                            LED(1)
                        end
                    end
                    -- 继续处理其他参数
                end
            end
        end
    end
end

-- 统一联网函数, 可自行删减
sys.taskInit(function()
    if mqtt == nil then
        while 1 do
            sys.wait(1000)
            log.info("bsp", "本固件未包含mqtt库, 请查证")
        end
    end
    local device_id = mcu.unique_id():toHex()
    -----------------------------
    -- 统一联网函数, 可自行删减
    ----------------------------
    if wlan and wlan.connect then
        -- wifi 联网, ESP32系列均支持
        local ssid = "uiot"
        local password = "12345678"
        log.info("wifi", ssid, password)
        mcu.setClk(240)
        -- TODO 改成自动配网
        -- LED = gpio.setup(12, 0, gpio.PULLUP)
        wlan.init()
        wlan.setMode(wlan.STATION) -- 默认也是这个模式,不调用也可以
        device_id = wlan.getMac():toHex()
        wlan.connect(ssid, password, 1)
    elseif mobile then
        -- Air780E/Air600E系列
        -- mobile.simid(2) -- 自动切换SIM卡
        LED = gpio.setup(27, 0, gpio.PULLUP)
        device_id = mobile.imei()
    elseif w5500 then
        -- w5500 以太网, 当前仅Air105支持
        w5500.init(spi.HSPI_0, 24000000, pin.PC14, pin.PC01, pin.PC00)
        w5500.config() -- 默认是DHCP模式
        w5500.bind(socket.ETH0)
        LED = gpio.setup(62, 0, gpio.PULLUP)
    elseif mqtt then
        -- 适配的mqtt库也OK
        -- 没有其他操作, 单纯给个注释说明
    else
        -- 其他不认识的bsp, 循环提示一下吧
        while 1 do
            sys.wait(1000)
            log.info("bsp", "本bsp可能未适配网络层, 请查证")
        end
    end
    -- 默认都等到联网成功
    sys.waitUntil("IP_READY")
    sys.publish("net_ready", device_id)
end)

sys.taskInit(function()
    -- 等待联网
    sys.waitUntil("net_ready")

    -- 打印一下上报(pub)和下发(sub)的topic名称
    -- 上报: 设备 ---> 服务器
    -- 下发: 设备 <--- 服务器
    -- 可使用mqtt.x等客户端进行调试
    log.info("mqtt", "pub", pub_topic)
    log.info("mqtt", "sub", sub_topic)
    log.info("mqtt", mqtt_host, mqtt_port, client_id, user_name, password)

    -------------------------------------
    -------- MQTT 演示代码 --------------
    -------------------------------------

    mqttc = mqtt.create(nil, mqtt_host, mqtt_port, mqtt_isssl, ca_file)

    mqttc:auth(client_id, user_name, password) -- client_id必填,其余选填
    -- mqttc:keepalive(240) -- 默认值240s
    mqttc:autoreconn(true, 3000) -- 自动重连机制

    mqttc:on(function(mqtt_client, event, data, payload)
        -- 用户自定义代码
        log.info("mqtt", "event", event, mqtt_client, data, payload)
        if event == "conack" then
            -- 联上了
            sys.publish("mqtt_conack")
            local topics = {}
            -- 物模型的topic
            topics[sub_topic] = 2

            -- 透传模式的topic
            -- 首先是 上报后, 服务器会回复
            if pub_custome_reply then
                topics[pub_custome_reply] = 1
            end
            -- 然后是 服务器的下发
            if sub_custome then
                topics[sub_custome] = 1
            end
            -- mqtt_client:subscribe(sub_topic, 2)--单主题订阅
            mqtt_client:subscribe(topics) -- 多主题订阅
        elseif event == "recv" then
            -- 打印收到的内容, 时间生产环境建议注释掉, 不然挺多的
            log.info("mqtt", "downlink", "topic", data, "payload", payload)
            on_downlink(topic, payload)
        elseif event == "sent" then
            log.info("mqtt", "sent", "pkgid", data)
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
            if topic == "close" then
                break
            end
            mqttc:publish(topic, data, qos)
        end
        -- 如果没有其他task上报, 可以写个空等待
        -- sys.wait(60000000)
    end
    mqttc:close()
    mqttc = nil
end)

-- 这里演示在另一个task里上报数据, 会定时上报数据,不需要就注释掉
sys.taskInit(function()
    local qos = 1 -- QOS0不带puback, QOS1是带puback的
    while true do
        sys.wait(15000)
        log.info("准备发布数据", mqttc and mqttc:ready())
        -- onenet 使用的是OneJson, 就是规范化的Json结构
        -- https://open.iot.10086.cn/doc/v5/develop/detail/508
        if mqttc and mqttc:ready() then
            local data = {}
            data["id"] = tostring(mcu.ticks())
            data["params"] = {}
            -- 业务自定义数据
            -- 例如: 
            -- 上传一个Power属性, 类型是整型, 值为1
            data["params"]["Power"] = {
                value = 1
            }
            -- 上传一个WF属性, 类型浮点, 值为2.35
            data["params"]["Power2"] = {
                value = 2.35
            }
            -- 上传一个字符串
            data["params"]["Power3"] = {
                value = "abcdefg"
            }

            -- ==========================================================
            -- 鉴于onenet支持定位功能, 这里增加基站数据数据的上报
            -- 下面的基站定位与合宙提供的基站定位是不同的, 按需选用
            -- 每日300w配额, 是通过额外的HTTP API获取坐标的 https://open.iot.10086.cn/doc/v5/develop/detail/722
            -- 非必须, 不需要就注释掉
            if mobile then
                local infos = mobile.getCellInfo()
                if infos then
                    local LBS = {}
                    for _, v in pairs(infos) do
                        local cell = {
                            cid = v.cid,
                            lac = v.lac,
                            mcc = v.mcc,
                            mnc = v.mnc,
                            networkType = 5, -- LTE,
                            ss = v.rssi,
                            ta = v.snr
                        }
                        table.insert(LBS, cell)
                    end
                    data["params"]["$OneNET_LBS"] = {
                        value = LBS
                    }
                end
            end
            -- 还有wifi定位,但wifi联网设备才有
            if wlan and wlan.connect and wlan.ready() then
                local WINFO = {
                    macs = "FC:D7:33:55:92:6A,-77|B8:F8:83:E6:24:DF,-60"
                }
                data["params"]["$OneNET_LBS_WIFI"] = {
                    value = WINFO
                }
            end
            -- ==========================================================
            local updata = json.encode(data)
            log.info("mqtt", "待上报数据", updata)
            local pkgid = mqttc:publish(pub_topic, updata, qos)
        end
    end
end)


-- -- ======================================================================
-- -- -- 以下是演示与uart结合, 简单的mqtt-uart透传实现,不需要就注释掉
-- local uart_id = 1
-- uart.setup(uart_id, 9600)
-- uart.on(uart_id, "receive", function(id, len)
--     local data = ""
--     while 1 do
--         local tmp = uart.read(uart_id)
--         if not tmp or #tmp == 0 then
--             break
--         end
--         data = data .. tmp
--     end
--     log.info("uart", "uart收到数据长度", #data)
--     sys.publish("mqtt_pub", pub_custome, data)
-- end)
-- sys.subscribe("mqtt_payload", function(topic, payload)
--     if topic == sub_custome then
--         log.info("uart", "uart发送数据长度", #payload)
--         uart.write(1, payload)
--     end
-- end)
-- ======================================================================

-- 用户代码已结束---------------------------------------------
-- 结尾总是这一句
sys.run()
-- sys.run()之后后面不要加任何语句!!!!!
