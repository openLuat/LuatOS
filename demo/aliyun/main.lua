PROJECT = "aliyundemo"
VERSION = "1.0.0"
local sys = require "sys"
require "aliyun"

--根据自己的服务器修改以下参数
tPara = {
 Registration = true,           --是否是预注册 已预注册为false  true or false,
 DeviceName = "861551056421746", --设备名称
 ProductKey = "ht6f7kmyFFQ",     --产品key
 ProductSecret = "dAmJgeQyBe57AkGM",             --产品secret
 DeviceSecret = "", --设备secret
 InstanceId = "iot-06z00bm5n8dzc26",   --如果没有注册需要填写实例id，在实例详情页面
 --新版已经合并, 没有了地域, 1883同时兼容加密和非加密通信，非加密会下线  阿里云资料：https://help.aliyun.com/document_detail/147356.htm?spm=a2c4g.73742.0.0.4782214ch6jkXb#section-rtu-6kn-kru
 mqtt_port = 1883,                 --mqtt端口
 mqtt_isssl = true,                --是否使用ssl加密连接，true为无证书最简单的加密
 }

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
        aliyun.publish("/"..tPara.ProductKey.."/"..tPara.DeviceName.."/user/get",1,"LUATOS_CESHI",publishTestCb,"publishTest_"..publishCnt)
    end
end

---数据接收的处理函数
-- @string topic，UTF8编码的消息主题
-- @string payload，原始编码的消息负载
local function rcvCbFnc(topic,payload,qos)
    log.info("testALiYun.rcvCbFnc",topic,payload)
end

--- 连接结果的处理函数
-- @bool result，连接结果，true表示连接成功，false或者nil表示连接失败
local function connectCbFnc(result)
    log.info("testALiYun.connectCbFnc",result)
    sConnected = result
    if result then
        --订阅主题
        --根据自己的项目需要订阅主题，下面注释掉的一行代码中的主题是非法的，所以不能打开，一旦打开，会导致订阅失败
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
    fskv.init()
    fskv.set("DeviceName",tPara.DeviceName)
    local name = fskv.get("DeviceName")
    local used = fskv.get("deviceSecret")
    local total = fskv.get("deviceToken")
    local cid = fskv.get("clientid")
    local host = tPara.InstanceId..".mqtt.iothub.aliyuncs.com"
    --判断是否是同一DeviceName，不是的话就重新连接
    if name == tPara.DeviceName then
        -- fskv.del("deviceSecret")
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
        --删除kv区的数据，重新建立连接
        aliyun.setup(tPara)
    end
end)


-- 用户代码已结束---------------------------------------------
-- 结尾总是这一句
sys.run()
-- sys.run()之后后面不要加任何语句!!!!!