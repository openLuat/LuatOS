--[[
@module  airlbs_app.lua
@summary Airlbs基站定位应用（8301出厂固件）
@version 1.0
@date    2026.09.22
@author  江访
@usage

本文件为airlbs"多基站"、"多基站+多wifi"两种应用场景的定位功能演示，核心业务逻辑为：
1. 等待网络就绪
2. 发起NTP授时
3. 循环定位请求

本文件的对外接口有一个：
1、sys.publish("Airlbs_LOCATION_UPDATE", lat, lng)，通过publish通知订阅者模块定位结果（经纬度）;
    lat/lng 为字符串格式，如 "34.8074150" / "114.2941589"，定位失败时为 nil;
]]

local airlbs = require "airlbs"

local timeout = 10 -- 扫描基站/wifi 做 基站/wifi定位 的超时时间，最小5S,最大60S

--  此服务为收费服务，需自行联系销售申请或者在 https://iot.openluat.com/finance/order 购买

--  以下为合宙LBS平台开通的项目id和秘钥
--  以下项目密钥和id请根据实际项目进行修改，https://iot.openluat.com/lbs/bs 在此网址中我的项目下
local airlbs_project_id = "uhgTXu"
local airlbs_project_key = "zZ9XUVilgkww0nMmO9ib6KWozHB5oJZo"
local lat, lng = nil, nil

--[[
多基站+多wifi定位任务

@local
@function airlbs_multi_cells_wifi_task_func
]]
local function airlbs_multi_cells_wifi_task_func()
    while not socket.adapter(socket.dft()) do
        log.warn("airlbs_multi_cells_wifi_func", "wait IP_READY", socket.dft())
        -- 在此处阻塞等待默认网卡连接成功的消息"IP_READY"
        -- 或者等待1秒超时退出阻塞等待状态;
        -- 注意：此处的1000毫秒超时不要修改的更长；
        -- 因为当使用exnetif.set_priority_order配置多个网卡连接外网的优先级时，会隐式的修改默认使用的网卡
        sys.waitUntil("IP_READY", 1000)
    end

    -- 检测到了IP_READY消息
    log.info("airlbs_multi_cells_wifi_func", "recv IP_READY", socket.dft())

    socket.sntp() --进行NTP授时
    sys.waitUntil("NTP_UPDATE", 1000)

    -- 如需wifi定位,需要硬件以及固件支持wifi扫描功能
    local wifi_info = nil
    if wlan then
        wlan.init()     --初始化wlan
        wlan.scan()     --扫描wifi
        sys.waitUntil("WLAN_SCAN_DONE", timeout * 1000) --等待扫描完成
        wifi_info = wlan.scanResult() --获取扫描结果
        log.info("scan", "wifi_info", #wifi_info) --打印扫描结果
    end

    while 1 do
        local result, data = airlbs.request({
            project_id = airlbs_project_id,   -- 项目ID
            project_key = airlbs_project_key, -- 项目密钥
            wifi_info = wifi_info,            -- wifi信息
            timeout = timeout * 1000,         -- 实际的超时时间(单位：ms)
        })
        if result then
            local data_str = json.encode(data)
            log.info("airlbs多基站+多wifi定位返回的经纬度数据为", data_str) -- 解析经纬度
            lat = data_str:match("\"lat\":([0-9.-]+)") -- 匹配lat
            log.info("airlbs", "lat", lat) -- 打印lat
            lng = data_str:match("\"lng\":([0-9.-]+)") -- 匹配lng
            log.info("airlbs", "lng", lng) -- 打印lng
            -- 发布定位数据更新消息，通知其他模块
            sys.publish("Airlbs_LOCATION_UPDATE", lat, lng)
        else
            log.warn("请检查project_id和project_key") -- 打印提示信息
        end
        --获取具体地址
        local result2, address = airlbs.get_address({
            lat = lat,
            lng = lng
        })
        if result2 then
            log.info("airlbs.get_address", address)
        else
            log.info("airlbs.get_address失败", address)
        end
        sys.wait(60000)
        -- 循环60S一次基站+wifi定位，请求频率可根据自己所购买的套餐进行计算
    end
end

-- 多基站+多wifi定位
sys.taskInit(airlbs_multi_cells_wifi_task_func)
