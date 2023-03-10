PROJECT = "aliyundemo"
VERSION = "1.0.0"
local sys = require "sys"
require "aliyun"

--根据自己的服务器修改以下参数
local mqtt_host = "你的实例id.mqtt.iothub.aliyuncs.com" --你公共实例的地址
local mqtt_port = 1883 --端口
local mqtt_isssl = true -- 是否为ssl加密连接,默认不加密,true为无证书最简单的加密，table为有证书的加密
local ProductKey = "你的key" --产品证书
local ProductSecret = "你的产品密钥"   --产品密钥
local DeviceName = "你的设备id"   --设备id
local Registration = false  --如果预注册了的话就不需要改   false   true
local InstanceId = "iot-你的实例id"  --如果没有注册需要填写实例id，在阿里云的实例详情页面
local DeviceSecret = "你的设备秘钥"  --一机一密需要的设备密钥

---数据接收的处理函数
-- @string topic，UTF8编码的消息主题
-- @number qos，消息质量等级
-- @string payload，原始编码的消息负载
local function rcvCbFnc(topic,qos,payload)
    log.info("aliyun.rcvCbFnc",topic,qos,payload)
end

--- 连接结果的处理函数
-- @bool result，连接结果，true表示连接成功，false或者nil表示连接失败
local function connectCbFnc(result)
    log.info("aliyun.connectCbFnc",result)
    if result then
        --订阅主题，不需要考虑订阅结果，如果订阅失败，aliyun库中会自动重连
        --根据自己的项目需要订阅主题，下面注释掉的一行代码中的主题是非法的，所以不能打开，一旦打开，会导致订阅失败
        --aliyun.subscribe({["/"..PRODUCT_KEY.."/"..getDeviceName().."/get"]=0, ["/"..PRODUCT_KEY.."/"..getDeviceName().."/get"]=1})
        aliyun.subscriber("/ht6f7kmyFFQ/861551056421746/user/ceshi",1)
        --注册数据接收的处理函数
        aliyun.on("receive",rcvCbFnc)
        aliyun.publish("/"..ProductKey.."/"..DeviceName.."/user/get",0,"LUATOS_CESHI")
    end
end

aliyun.on("connect",connectCbFnc)

--一型一密
-- aliyun.operation(Registration,DeviceName,ProductKey,ProductSecret,InstanceId,mqtt_host,mqtt_port,mqtt_isssl)

--一机一密
aliyun.confiDentialTask(DeviceName,ProductKey,DeviceSecret,mqtt_host,mqtt_port,mqtt_isssl)


-- 用户代码已结束---------------------------------------------
-- 结尾总是这一句
sys.run()
-- sys.run()之后后面不要加任何语句!!!!!