PROJECT = "aliyundemo"
VERSION = "1.0.0"
local sys = require "sys"
local libfota = require("libfota")
require "aliyun"

--根据自己的服务器修改以下参数
tPara = {
 Registration = false,           --是否是预注册 已预注册为false  true or false,
 DeviceName = "", --设备名称
 ProductKey = "",     --产品key
 ProductSecret = "",  --产品secret
 DeviceSecret = "", --设备secret
 InstanceId = "iot-你的实例id",   --如果没有注册需要填写实例id，在实例详情页面
 --新版已经合并, 没有了地域, 1883同时兼容加密和非加密通信，非加密会下线  阿里云资料：https://help.aliyun.com/document_detail/147356.htm?spm=a2c4g.73742.0.0.4782214ch6jkXb#section-rtu-6kn-kru
 mqtt_port = 1883,                 --mqtt端口
 mqtt_isssl = true,                --是否使用ssl加密连接，true为无证书最简单的加密
 }

 -- 统一联网函数
sys.taskInit(function()
    local device_id = mcu.unique_id():toHex()
    -----------------------------
    -- 统一联网函数, 可自行删减
    ----------------------------
    if wlan and wlan.connect then
        -- wifi 联网, ESP32系列均支持
        local ssid = "kfyy123"
        local password = "kfyy123456"
        log.info("wifi", ssid, password)
        -- TODO 改成自动配网
        -- LED = gpio.setup(12, 0, gpio.PULLUP)
        wlan.init()
        wlan.setMode(wlan.STATION) -- 默认也是这个模式,不调用也可以
        device_id = wlan.getMac()
        wlan.connect(ssid, password, 1)
    elseif mobile then
        -- Air780E/Air600E系列
        --mobile.simid(2) -- 自动切换SIM卡
        -- LED = gpio.setup(27, 0, gpio.PULLUP)
        device_id = mobile.imei()
    elseif w5500 then
        -- w5500 以太网, 当前仅Air105支持
        w5500.init(spi.HSPI_0, 24000000, pin.PC14, pin.PC01, pin.PC00)
        w5500.config() --默认是DHCP模式
        w5500.bind(socket.ETH0)
        -- LED = gpio.setup(62, 0, gpio.PULLUP)
    elseif socket or mqtt then
        -- 适配的socket库也OK
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

 --阿里云客户端是否处于连接状态
local sConnected

local publishCnt = 1

--[[
函数名：pubqos1testackcb
功能  ：发布1条qos为1的消息后收到PUBACK的回调函数
参数  ：
		usertag：调用mqttclient:publish时传入的usertag
		result：任意数字表示发布成功，nil表示失败
返回值：无
]]
local function publishTestCb(result,para)
    log.info("testALiYun.publishTestCb",result,para)
    sys.timerStart(publishTest,20000)
    publishCnt = publishCnt+1
end

--发布一条QOS为1的消息
function publishTest()
    if sConnected then
        --注意：在此处自己去控制payload的内容编码，aLiYun库中不会对payload的内容做任何编码转换
        -- aliyun.publish(topic,qos,payload,cbFnc,cbPara)
        aliyun.publish("/"..tPara.ProductKey.."/"..tPara.DeviceName.."/user/get",1,"LUATOS_CESHI",publishTestCb,"publishTest_"..publishCnt)
    end
end

---数据接收的处理函数
-- @string topic，UTF8编码的消息主题
-- @string payload，原始编码的消息负载
local function rcvCbFnc(topic,payload,qos,retain,dup)
    log.info("testALiYun.rcvCbFnc",topic,payload,qos,retain,dup)
end

--- 连接结果的处理函数
-- @bool result，连接结果，true表示连接成功，false或者nil表示连接失败
local function connectCbFnc(result)
    log.info("testALiYun.connectCbFnc",result)
    sConnected = result
    if result then
        --订阅主题
        --根据自己的项目需要订阅主题，下面注释掉的一行代码中的主题是非法的，所以不能打开，一旦打开，会导致订阅失败
        --订阅OTA主题
        aliyun.subscribe("/ota/device/upgrade/"..tPara.ProductKey.."/"..tPara.DeviceName,1)
        if not verRpted then        
            --上报固件版本号给云端
            verRpt()
        end
        --上报固件版本号给云端
        sys.timerStart(verRpt,10000)
        -- aliyun.subscribe(topic,qos)
        -- aliyun.subscribe("/"..tPara.ProductKey.."/"..tPara.DeviceName.."/user/ceshi",1)
        
        --使用掉电不消失的kv文件区来储存的deviceSecret，deviceToken
        local used = fskv.get("deviceSecret")
        local total = fskv.get("deviceToken")
        local cid = fskv.get("clientid")
        --储存到kv分区的返回值
        -- log.info("kv分区的返回值",used,total,cid)
        local Secret = aliyun.getDeviceSecret()
        local Token = aliyun.getDeviceToken()
        local Clid = aliyun.getClientid()
         --如果三元组不为空，就把三元组写入到kv区
        if tPara.DeviceName and tPara.ProductKey then
            fskv.set("DeviceName",tPara.DeviceName)
            fskv.set("ProductKey",tPara.ProductKey)
        end
        if not tPara.Registration then
            if Secret == nil then
                log.info("掉电重连")
            else
                fskv.set("deviceSecret",aliyun.getDeviceSecret())
            end
        else
            if Token == nil and Clid == nil then
                log.info("掉电重连")
            else
                fskv.set("deviceToken",aliyun.getDeviceToken())
                fskv.set("clientid",aliyun.getClientid())
            end
        end

        --注册数据接收的处理函数
        aliyun.on("receive",rcvCbFnc)
        --PUBLISH消息测试
        publishTest()
    end
end

aliyun.on("connect",connectCbFnc)

--根据掉电不消失的kv文件区来储存的deviceSecret,clientid,deviceToken来判断是进行正常连接还是掉电重连
sys.taskInit(function()
    local _, device_id = sys.waitUntil("net_ready")
    socket.sntp()
    sys.wait(500)
    log.info("已联网", "开始初始化aliyun库")
    fskv.init()
    local name = fskv.get("DeviceName")
    local key = fskv.get("ProductKey")
    local used = fskv.get("deviceSecret")
    local total = fskv.get("deviceToken")
    local cid = fskv.get("clientid")
    local host = tPara.InstanceId..".mqtt.iothub.aliyuncs.com"
    --判断是否是同一三元组，不是的话就重新连接
    if name == tPara.DeviceName and key == tPara.ProductKey then
        if not tPara.Registration then
            if used == nil then
                aliyun.setup(tPara)
            else
                aliyun.clientGetDirectDataTask(name,tPara.ProductKey,host,tPara.mqtt_port,tPara.mqtt_isssl,tPara.Registration,used,total,cid)
            end
        else
            if total == nil and cid == nil then
                aliyun.setup(tPara)
            else
                aliyun.clientGetDirectDataTask(name,tPara.ProductKey,host,tPara.mqtt_port,tPara.mqtt_isssl,tPara.Registration,used,total,cid)
            end
        end
    else
        fskv.del("deviceToken")
        fskv.del("clientid")
        fskv.del("DeviceName")
        fskv.del("deviceSecret")
        fskv.del("ProductKey")
        --删除kv区的数据，重新建立连接
        aliyun.setup(tPara)
    end
end)


--[[
函数名：verRpt
功能  ：上报固件版本号给云端
参数  ：无
返回值：无
]]
function verRpt()
    log.info("aliyunOta.verRpt")
    -- aliyun.publish(topic,qos,payload,cbFnc,cbPara)
    aliyun.publish("/ota/device/inform/"..tPara.ProductKey.."/"..tPara.DeviceName,1,"{\"id\":1,\"params\":{\"version\":\"".._G.VERSION.."\"}}")
end

-- 用户代码已结束---------------------------------------------
-- 结尾总是这一句
sys.run()
-- sys.run()之后后面不要加任何语句!!!!!