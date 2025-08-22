--[[
@module  airlbs_app.lua
@summary Airlbs应用
@version 1.0
@date    2025.08.13
@author  王城钧
@usage

本文件为airlbs“多基站”、“多基站+多wifi”两种应用场景的定位功能演示，核心业务逻辑为：
1. 等待网络就绪 
2. 发起NTP授时 
3. 循环定位请求 

本文件没有对外接口，直接在main.lua中require "airlbs_app"就可以加载运行；
]]

local airlbs = require "airlbs"

local timeout = 10 -- 扫描基站/wifi 做 基站/wifi定位 的超时时间，最小5S,最大60S

--  此服务为收费服务，需自行联系销售申请或者在 https://iot.openluat.com/finance/order 购买

--  以下为合宙LBS平台开通的项目id和秘钥
--  以下项目密钥和id请根据实际项目进行修改，https://iot.openluat.com/lbs/bs 在此网址中我的项目下
local airlbs_project_id = "此处换成自己的项目id"
local airlbs_project_key = "此处换成自己的项目key"

--多基站定位
local function airlbs_multi_cells_task_func()
    while not socket.adapter(socket.dft()) do
        log.warn("lbsloc2_task_func", "wait IP_READY", socket.dft())
        -- 在此处阻塞等待默认网卡连接成功的消息"IP_READY"
        -- 或者等待1秒超时退出阻塞等待状态;
        -- 注意：此处的1000毫秒超时不要修改的更长；
        -- 因为当使用exnetif.set_priority_order配置多个网卡连接外网的优先级时，会隐式的修改默认使用的网卡
        -- 当exnetif.set_priority_order的调用时序和此处的socket.adapter(socket.dft())判断时序有可能不匹配
        -- 此处的1秒，能够保证，即使时序不匹配，也能1秒钟退出阻塞状态，再去判断socket.adapter(socket.dft())
        sys.waitUntil("IP_READY", 1000)
    end

    -- 检测到了IP_READY消息
    log.info("airlbs_multi_cells_func", "recv IP_READY", socket.dft())
    socket.sntp() -- 进行NTP授时
    sys.waitUntil("NTP_UPDATE", 1000) 
    while 1 do
        if airlbs_project_id and airlbs_project_key then
            local result, data = airlbs.request({
                project_id = airlbs_project_id,-- 项目ID
                project_key = airlbs_project_key,-- 项目密钥
                timeout = timeout * 1000, -- 实际的超时时间(单位：ms)
            })
            if result then
                log.info("airlbs多基站定位返回的经纬度数据为", json.encode(data))
            end
        else
            log.warn("请检查project_id和project_key")
        end
        sys.wait(20000) -- 循环20S一次多基站定位
    end
end

--多基站+多wifi定位
local function airlbs_multi_cells_wifi_task_func()
    while not socket.adapter(socket.dft()) do
        log.warn("airlbs_multi_cells_wifi_func", "wait IP_READY", socket.dft())
        -- 在此处阻塞等待默认网卡连接成功的消息"IP_READY"
        -- 或者等待1秒超时退出阻塞等待状态;
        -- 注意：此处的1000毫秒超时不要修改的更长；
        -- 因为当使用exnetif.set_priority_order配置多个网卡连接外网的优先级时，会隐式的修改默认使用的网卡
        -- 当exnetif.set_priority_order的调用时序和此处的socket.adapter(socket.dft())判断时序有可能不匹配
        -- 此处的1秒，能够保证，即使时序不匹配，也能1秒钟退出阻塞状态，再去判断socket.adapter(socket.dft())
        sys.waitUntil("IP_READY", 1000)
    end

    -- 检测到了IP_READY消息
    log.info("airlbs_multi_cells_wifi_func", "recv IP_READY", socket.dft())

    socket.sntp() --进行NTP授时
    sys.waitUntil("NTP_UPDATE", 1000)

    -- 如需wifi定位,需要硬件以及固件支持wifi扫描功能
    local wifi_info = nil
    if wlan then
        wlan.init()--初始化wlan
        wlan.scan()--扫描wifi
        sys.waitUntil("WLAN_SCAN_DONE", timeout * 1000)--等待扫描完成
        wifi_info = wlan.scanResult()--获取扫描结果
        log.info("scan", "wifi_info", #wifi_info)--打印扫描结果
    end

    while 1 do
        local result, data = airlbs.request({
            project_id = airlbs_project_id,-- 项目ID
            project_key = airlbs_project_key,-- 项目密钥
            wifi_info = wifi_info,-- wifi信息
            timeout = timeout * 1000,-- 实际的超时时间(单位：ms)
        })
        if result then
            local data_str = json.encode(data)
            log.info("airlbs多基站+多wifi定位返回的经纬度数据为", data_str)-- 解析经纬度
            local lat = data_str:match("\"lat\":([0-9.-]+)")-- 匹配lat
            log.info("airlbs", "lat", lat)-- 打印lat
            local lng = data_str:match("\"lng\":([0-9.-]+)")-- 匹配lng
            log.info("airlbs", "lng", lng)-- 打印lng
        else        
            log.warn("请检查project_id和project_key")-- 打印提示信息
        end
        sys.wait(20000) -- 循环20S一次基站+wifi定位
    end

end

--多基站定位
sys.taskInit(airlbs_multi_cells_task_func)

--多基站+多wifi定位
sys.taskInit(airlbs_multi_cells_wifi_task_func)
