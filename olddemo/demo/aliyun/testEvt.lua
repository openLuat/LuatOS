
local sys = require "sys"
local aliyun = require "aliyun"

--[[
函数名：pubqos1testackcb
功能  ：发布1条qos为1的消息后收到PUBACK的回调函数
参数  ：
		usertag：调用mqttclient:publish时传入的usertag
		result：任意数字表示发布成功，nil表示失败
返回值：无
]]
local publishCnt = 1
local function publishTestCb(result,para)
    log.info("aliyun", "发布后的反馈", result,para)
    sys.timerStart(publishTest,20000)
    publishCnt = publishCnt+1
end

--发布一条QOS为1的消息
function publishTest()
    --注意：在此处自己去控制payload的内容编码，aLiYun库中不会对payload的内容做任何编码转换
    -- aliyun.publish(topic,qos,payload,cbFnc,cbPara)
    log.info("aliyun", "上行数据")
    aliyun.publish("/"..aliyun.opts.ProductKey.."/"..aliyun.opts.DeviceName.."/user/update",1,"LUATOS_CESHI",publishTestCb,"publishTest_"..publishCnt)
end

---数据接收的处理函数
-- @string topic，UTF8编码的消息主题
-- @string payload，原始编码的消息负载
local function rcvCbFnc(topic,payload,qos,retain,dup)
    log.info("aliyun", "收到下行数据", topic,payload,qos,retain,dup)
end

--- 连接结果的处理函数
-- @bool result，连接结果，true表示连接成功，false或者nil表示连接失败
local function connectCbFnc(result)
    log.info("aliyun","连接结果", result)
    if result then
        sys.publish("aliyun_ready")
        log.info("aliyun", "连接成功")
        --订阅主题
        --根据自己的项目需要订阅主题
        -- aliyun.subscribe(topic,qos)
        -- aliyun.subscribe("/".. aliyun.opts.ProductKey.."/".. aliyun.opts.DeviceName.."/user/ceshi",1)

        --PUBLISH消息测试
        publishTest()
    else
        log.warn("aliyun", "连接失败")
    end
end

-- 连接状态的处理函数
aliyun.on("connect",connectCbFnc)

-- 数据接收的处理函数
aliyun.on("receive",rcvCbFnc)

-- 一型一密的注册回调函数, 2024.6.17 添加
-- aliyun.on("reg", function(result)
--     aliyun.store(result)
-- end)

-- 数据发送的处理函数, 一般不需要
-- aliyun.on("receive", sentCbFnc)

-- OTA状态的处理函数
-- aliyun.on("ota",function(result)
--     if result == 0 then
--         log.info("aliyun", "OTA成功")
--         rtos.reboot()
--     end
-- end)
