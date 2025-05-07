--[[
1.本demo可直接在Air8000模组上运行
2. 执行逻辑为：
    (1)初始化wlan功能
    (2)连接wifi热点
    (3)等待网络连接成功
    (4)执行时间同步
    (5)等待时间同步成功
    (6)循环扫描wifi，如果扫描到wifi信息，则请求wifi定位
]] 

-- LuaTools需要PROJECT和VERSION这两个信息
PROJECT = "WLAN_LOCATION"
VERSION = "1.0.0"

-- sys库是标配
_G.sys = require("sys")
require "sysplus"

local taskName = "WIFI_LOCATION"
local result = false -- 用于保存结果
local data = nil -- 用于保存定位请求数据
local wifiList = {} -- 用于保存扫描到的wifi信息
local requestParam = {} -- 用于保存定位请求参数

local airlbs = require "airlbs"

local airlbsProjectId = "XXXXXX" -- 定位所需的项目key_id
local airlbsProjectKey = "XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX" -- 定位所需的项目key

local function wlan_location_task()
    sys.wait(200)
    wlan.init() -- wlan功能初始化
    -- socket.create(socket.LWIP_STA)
    sys.wait(100)
    wlan.connect("luatos1234", "12341234") -- 连接wifi
    result = sys.waitUntil("IP_READY", 30000) -- 等待网络就绪成功的消息，超时时间30秒
    if not result then
        log.info("等待网络就绪超时, 结束本次测试")
        return
    end
    socket.sntp(nil, socket.LWIP_STA) -- 同步网络时间
    result = sys.waitUntil("NTP_UPDATE", 30000) -- 等待时间同步成功的消息，超时时间30秒
    if not result then
        log.info("等待时间同步成功超时, 结束本次测试")
        return
    end
    while true do
        wlan.scan()
        result = sys.waitUntil("WLAN_SCAN_DONE", 20000) -- 等待WIFI扫描完成的消息，超时时间20秒
        if result then
            wifiList = wlan.scanResult()
            if #wifiList > 0 then
                for k, v in pairs(wifiList) do
                    log.info("scan", v["ssid"], v["rssi"], (v["bssid"]:toHex()))
                end
                local requestParam = {
                    project_id = airlbsProjectId, -- 定位所需的projectid
                    project_key = airlbsProjectKey, -- 定位所需的projectkey
                    wifi_info = wifiList, -- 用于定位的WiFi信息
                    adapter = socket.LWIP_STA, -- 网络适配器类型
                    timeout = 5000 -- 定位超时时间
                }
                result, data = airlbs.request(requestParam)
                if result then
                    log.info("airlbs请求成功", json.encode(data))
                else
                    log.info("airlbs请求失败")
                end
            else
                log.info("没有扫描到wifi")
            end
        else
            log.info("等待WIFI扫描结果超时")
        end
        sys.wait(20000) -- 等待20秒
    end
end

--  每隔6秒打印一次airlink统计数据, 调试用
sys.taskInit(function()
    while 1 do
        sys.wait(6000)
        airlink.statistics()
    end
end)

sysplus.taskInitEx(wlan_location_task, taskName)

-- 用户代码已结束---------------------------------------------
-- 结尾总是这一句
sys.run()
-- sys.run()之后后面不要加任何语句!!!!!
