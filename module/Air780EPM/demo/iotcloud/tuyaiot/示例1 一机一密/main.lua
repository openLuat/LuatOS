
-- LuaTools需要PROJECT和VERSION这两个信息
PROJECT = "iotclouddemo"
VERSION = "1.0.0"

-- sys库是标配
_G.sys = require("sys")
--[[特别注意, 使用mqtt库需要下列语句]]
_G.sysplus = require("sysplus")

local iotcloud = require("iotcloud")

-- 统一联网函数
sys.taskInit(function()
    local device_id = mcu.unique_id():toHex()
    -----------------------------
    if mobile then
        device_id = mobile.imei()
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
    local ret, device_id = sys.waitUntil("net_ready")

    --------    以下接入方式根据自己需要修改,相关参数修改为自己的    ---------

    -- -- 涂鸦云 
    iotcloudc = iotcloud.new(iotcloud.TUYA,{device_name = "xxx",device_secret = "xxx"})

    if iotcloudc then
        iotcloudc:connect()
    else
        log.error("iotcloud", "创建失败, 请检查参数")
    end
    
end)

sys.subscribe("iotcloud", function(cloudc,event,data,payload)
    -- 注意，此处不是协程内，复杂操作发消息给协程内进行处理
    if event == iotcloud.CONNECT then -- 云平台联上了
        print("iotcloud","CONNECT", "云平台连接成功")
        iotcloudc : subscribe("tylink/${deviceId}/thing/property/set") -- 订阅信息
        iotcloudc : publish("tylink/${deviceId}/thing/property/report" , '{"data":{"device_status":"999"}}' , 1) -- 上报信息
    elseif event == iotcloud.RECEIVE then
        print("iotcloud","topic", data, "payload", payload)
        -- 用户处理代码
    elseif event ==  iotcloud.OTA then
        if data then
            rtos.reboot()
        end
    elseif event == iotcloud.DISCONNECT then -- 云平台断开了
        -- 用户处理代码
    end
end)


-- 用户代码已结束---------------------------------------------
-- 结尾总是这一句
sys.run()
-- sys.run()之后后面不要加任何语句!!!!!
