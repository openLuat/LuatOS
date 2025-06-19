-- LuaTools需要PROJECT和VERSION这两个信息
PROJECT = "oneNET_demo"
VERSION = "1.0.0"

-- sys库是标配
_G.sys = require("sys")
--[[特别注意, 使用mqtt库需要下列语句]]
_G.sysplus = require("sysplus")
lbsLoc2 = require("lbsLoc2")
local iotcloud = require("iotcloud")
mobile.simid(2, true)

local produt_id = "4qM5N1Sa4T"
local userid = "226691"
local userkey = "pk1M3FKXBvvmjF8If/xDfSFFmr96NZCEg00sxlLBMjjh9vOD5hpIs42rmAYnMh5b3m9B1+0rmYdqzUyoQVrxow=="
local device_name = mobile.imei()
local send_data_time = 5 * 60 * 1000 -- 定时发送数据的时间，单位ms

-- 统一联网函数
sys.taskInit(function()
    local device_id = mcu.unique_id():toHex()

    -- 默认都等到联网成功
    sys.waitUntil("IP_READY")
    sys.publish("net_ready", device_id)
end)

sys.taskInit(function()
    -- 等待联网
    local ret, device_id = sys.waitUntil("net_ready")

    --------    以下接入方式根据自己需要修改,相关参数修改为自己的    ---------

    -- ONENET云
    -- 动态注册
    iotcloudc = iotcloud.new(iotcloud.ONENET, {
        device_name = device_name,
        produt_id = produt_id,
        userid = userid,
        userkey = userkey
    })
    -- 一型一密
    -- iotcloudc = iotcloud.new(iotcloud.ONENET,{produt_id = "xxx",product_secret = "xxx"})
    -- 一机一密
    -- iotcloudc = iotcloud.new(iotcloud.ONENET,{produt_id = "xxx",device_name = "xxx",device_secret = "xxx"})

    if iotcloudc then
        iotcloudc:connect()
    end

end)

-- 发布和订阅的主题

local oneNET_sub = "$sys/" .. produt_id .. "/" .. device_name .. "/thing/property/post/reply"

local oneNET_pub = "$sys/" .. produt_id .. "/" .. device_name .. "/thing/property/post"

local function oneNET_send_data()
    log.info("oneNET 链接成功,准备开始发送数据")
    while 1 do
        -- 没有mobile库就没有基站定位
        mobile.reqCellInfo(15)
        -- 由于基站定位需要等待扫描周围基站，推荐扫描时间为15S
        sys.waitUntil("CELL_INFO_UPDATE", 15000)
        local lat, lng, t = lbsLoc2.request(5000)
        log.info("lbsLoc2", lat, lng, (json.encode(t or {})))
        -- 如果没扫描到基站则给lat和lng赋值为0
        if lat and lng then
            log.info("扫描到了，有位置信息")
        else
            lat = "0"
            lng = "0"
        end
        -- 读取CPU温度, 单位为0.001摄氏度, 是内部温度, 非环境温度
        adc.open(adc.CH_CPU)
        local cpu_temp = adc.get(adc.CH_CPU)
        adc.close(adc.CH_CPU)
        local gpio_pin = 6 -- GPIO编号
        local gpio_state = gpio.get(gpio_pin)
        local send_data = {
            id = "123",
            verson = VERSION,
            params = {
                gpio_state = {
                    value = gpio_state
                },
                cpu_temp = {
                    value = cpu_temp / 1000
                },
                lbs_lat = {
                    value = tonumber(lat)
                },
                lbs_lng = {
                    value = tonumber(lng)
                    -- value = lng
                }
            }
        }
        local send_data = json.encode(send_data)
        log.info("发送的数据为", send_data)
        -- 正式发布数据
        iotcloudc:publish(oneNET_pub, send_data)
        -- 循环发送数据的定时时间
        sys.wait(send_data_time)
    end

end

local con = 0
--oneNET断开后的处理函数，
local function oneNET_DISCONNECT()
    log.info("云平台断开了,隔一分钟重连一次,如果10次都没有连上则重启设备")
    while con < 10 do
        sys.wait(60*1000)
        log.info("oneNET reconnection",con)
        iotcloudc:connect()
    end
    pm.reboot()
end
sys.subscribe("iotcloud", function(cloudc, event, data, payload)
    -- 注意，此处不是协程内，复杂操作发消息给协程内进行处理
    if event == iotcloud.CONNECT then -- 云平台联上了
        log.info("iotcloud", "CONNECT", "oneNET平台连接成功")
        iotcloudc:subscribe({
            [oneNET_sub] = 1
        }) -- 订阅服务器下发数据的主题
        -- 链接成功，启动一个task专门用来定时发消息
        sys.taskInit(oneNET_send_data)

    elseif event == iotcloud.RECEIVE then
        log.info("收到服务器下发的数据")
        log.info("iotcloud", "topic", data, "payload", payload)

        -- 用户处理代码
        if payload then
            payload = json.decode(payload)
            if payload["code"] == 200 then
                log.info("服务器收到了刚刚上传的数据", payload["msg"])
            else
                log.info("服务器接收数据有误", "错误码为", payload["code"], "错误信息为",
                    payload["msg"])
            end
        end

    elseif event == iotcloud.SEND then
        log.info("发送数据成功")

    elseif event == iotcloud.DISCONNECT then -- 云平台断开了
       sys.taskInit(oneNET_DISCONNECT)
    end
end)

-- 用户代码已结束---------------------------------------------
-- 结尾总是这一句
sys.run()
-- sys.run()之后后面不要加任何语句!!!!!
