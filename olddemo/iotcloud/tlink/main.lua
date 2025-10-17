-- LuaTools需要PROJECT和VERSION这两个信息
PROJECT = "IOTCLOUD_TLINK"
VERSION = "1.0.0"

-- sys库是标配
_G.sys = require("sys")
--[[特别注意, 使用mqtt库需要下列语句]]
_G.sysplus = require("sysplus")

local iotcloud = require("iotcloud")

-- TLINK平台设备序列号
local serialNumber = "XXXXXXXXXXXXXX"
-- TLINK平台登录账号
local username = "XXXXXXXXXXXXXX"
-- TLINK平台登录密码
local password = "XXXXXXXXXXXXXX"

-- TLINK平台添加的传感器ID
local sensorsId = "XXXXXXXXXXXXXX"

-- TLINK平台添加的传感器对应的TOPIC，iotcloud库会自动为设备订阅通配主题，用户只需判断报文是否来自该传感器的TOPIC即可
local tlinkSubTopic = serialNumber .. "/" .. sensorsId

-- 是否使用自动重连
local autoReconnect = false
local connectConfig = {
    keepalive = 60 -- mqtt心跳设置为60秒
}

-- 手动重连定时器ID
local reconnectTimerId

if autoReconnect then
    connectConfig.autoreconn = 3000 -- 云平台断开3秒后自动重连
end

-- TLINK平台switch类型传感器回传报文
local function switchSensorPub(cloudc, switch)
    local tmp = {
        sensorDatas = {{
            sensorsId = sensorsId,
            switcher = switch
        }}
    }
    local payload = json.encode(tmp)
    log.info("回传的报文", payload)
    cloudc:publish(serialNumber, payload)
end

-- 将gpio27设置为输出模式，低电平，gpio27在开发板上控制的是蓝灯
local ledCtrl = gpio.setup(27, 0)

-- 订阅来自iotcloud库发布的消息主题
sys.subscribe("iotcloud", function(cloudc, event, data, payload)
    -- 注意，此处不是协程内，复杂操作发消息给协程内进行处理
    if event == iotcloud.CONNECT then -- 云平台连上了
        if not autoReconnect then
            if reconnectTimerId and sys.timerIsActive(reconnectTimerId) then
                sys.timerStop(reconnectTimerId)
            end
        end
        log.info("TLINK 云平台连接成功")
        -- cloudc:subscribe("test") -- 可以自由订阅主题，详情可参考TLINK开发文档
    elseif event == iotcloud.RECEIVE then
        log.info("TLINK 发布消息", "topic", data, "payload", payload)
        -- 判断主题是否来自sensorsId的报文
        if data == tlinkSubTopic then
            -- json解析
            local userPayload, result, err = json.decode(payload)
            -- 防止异常的措施，防止json解析失败代码运行异常
            if result == 1 and userPayload and type(userPayload) == "table" then
                if userPayload.sensorDatas and userPayload.sensorDatas[1] then
                    local switch = userPayload.sensorDatas[1].switcher
                    -- 如果开关状态等于1，则打开蓝灯，否则关闭蓝灯
                    if switch == 1 then
                        ledCtrl(1)
                    else
                        ledCtrl(0)
                    end
                    -- 回传报文
                    switchSensorPub(cloudc, switch)
                end
            end
        end
    elseif event == iotcloud.OTA then
        -- 用户处理代码
        -- TLINK 不会有这条消息上报，可忽略
    elseif event == iotcloud.DISCONNECT then -- 云平台断开了
        -- 用户处理代码
        log.info("云平台连接断开")
        if not autoReconnect then
            if reconnectTimerId and sys.timerIsActive(reconnectTimerId) then
                sys.timerStop(reconnectTimerId)
            end
            reconnectTimerId = sys.timerStart(function()
                cloudc:connect()
            end, 3000)
        end
    end
end)

sys.taskInit(function()
    -- 等待联网
    local result
    while true do
        log.info("等待联网")
        result = sys.waitUntil("IP_READY", 30000)
        if result then
            break
        end
    end
    log.info("联网成功")

    -- 创建TLINK云平台实例，在iotcloud TLINK平台中，device_name对应mqtt三元组的clientId，product_id对应mqtt三元组的username，product_secret对应mqtt三元组的password
    iotcloudc = iotcloud.new(iotcloud.TLINK, {
        device_name = serialNumber,
        produt_id = username,
        product_secret = password
    }, connectConfig)
    -- 创建成功，则连接，创建失败，就结束程序
    if iotcloudc then
        iotcloudc:connect()
    else
        log.error("iotcloud", "创建失败, 请检查参数")
    end
end)

-- 用户代码已结束---------------------------------------------
-- 结尾总是这一句
sys.run()
-- sys.run()之后后面不要加任何语句!!!!!
