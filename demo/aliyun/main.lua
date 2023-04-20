PROJECT = "aliyundemo"
VERSION = "1.0.0"
local sys = require "sys"
require "aliyun"

--根据自己的服务器修改以下参数
tPara = {
 Registration = false,           --是否是预注册 已预注册为false  true or false,
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
        --注册数据接收的处理函数
        aliyun.on("receive",rcvCbFnc)
        --PUBLISH消息测试
        publishTest()
    end
end

aliyun.on("connect",connectCbFnc)


aliyun.setup(tPara)




-- 用户代码已结束---------------------------------------------
-- 结尾总是这一句
sys.run()
-- sys.run()之后后面不要加任何语句!!!!!