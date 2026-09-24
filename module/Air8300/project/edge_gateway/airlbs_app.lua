--[[
@module  airlbs_app
@summary Airlbs基站定位应用模块
@version 1.1
@date    2026.09.18
@usage
本文件为 airlbs "多基站+多wifi" 定位应用模块，核心业务逻辑为：
1、等待网络就绪
2、发起 NTP 授时
3、循环做基站+WiFi 定位请求（每 15 分钟一次）

对外接口：
1、sys.publish("Airlbs_LOCATION_UPDATE", lat, lng)，定位成功时通知订阅者模块；
    lat/lng 为字符串格式，如 "34.8074150" / "114.2941589"，定位失败时为 nil
]]

local airlbs = require "airlbs"

-- 扫描基站/wifi 做定位的超时时间，最小5S,最大60S
local timeout = 10

-- 此服务为收费服务，需自行联系销售申请或者在 https://iot.openluat.com/finance/order 购买
-- 以下为合宙LBS平台开通的项目id和秘钥（当前已配置为实际项目凭证）
-- https://iot.openluat.com/lbs/bs 在此网址中的我的项目下
local airlbs_project_id = "lblKo3"
local airlbs_project_key = "DKqM6sHJkHV23WCzgzTbk7QW7HYGCJxp"

-- 定位请求间隔（毫秒），每 15 分钟一次
local LOCATE_INTERVAL = 15 * 60 * 1000

local lat, lng = nil, nil

-- 多基站+多wifi定位任务
local function airlbs_multi_cells_wifi_task_func()
    -- 等待默认网卡连接成功
    while not socket.adapter(socket.dft()) do
        log.warn("airlbs", "等待 IP_READY", socket.dft())
        sys.waitUntil("IP_READY", 1000)
    end

    log.info("airlbs", "recv IP_READY", socket.dft())

    -- 说明：NTP 授时已由 time_sync 模块统一负责，此处不再重复 socket.sntp()，
    --       避免两处同时授时、互相覆盖 NTP_UPDATE 事件（进度不同步）。

    -- WiFi 扫描用于"基站+WiFi"融合定位。
    -- 注意：当默认网卡就是 WiFi STA（正在用 WiFi 供网）时不扫描 ——
    --       部分固件下 scan 会让 STA 短暂掉线，进而触发 exnetif 切网、
    --       云端链路被重建，白白多产生一次鉴权。仅在非 WiFi 供网时扫描。
    local wifi_info = nil
    if wlan and socket.dft() ~= socket.LWIP_STA then
        wlan.init() -- 初始化wlan
        wlan.scan() -- 扫描wifi
        sys.waitUntil("WLAN_SCAN_DONE", timeout * 1000)
        wifi_info = wlan.scanResult() -- 获取扫描结果
        log.info("airlbs", "wifi_info", #wifi_info)
    else
        log.info("airlbs", "当前由 WiFi 供网或 wlan 不可用, 跳过 WiFi 扫描")
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
            log.info("airlbs", "定位返回数据", data_str)
            lat = data_str:match("\"lat\":([0-9.-]+)")
            lng = data_str:match("\"lng\":([0-9.-]+)")
            log.info("airlbs", "lat", lat, "lng", lng)
            -- 发布定位数据更新消息，通知其他模块
            sys.publish("Airlbs_LOCATION_UPDATE", lat, lng)
        else
            log.warn("airlbs", "定位失败, 请检查凭证是否有效，或项目是否欠费(可能缺少余额)")
        end

        -- 逆地理编码（可选，获取地址描述）
        -- 定位失败时 lat/lng 为 nil，此时不应发起请求（无效请求，白耗服务配额）
        if lat and lng then
            local addr_ok, address = airlbs.get_address({ lat = lat, lng = lng })
            if addr_ok then
                log.info("airlbs.get_address", address)
            else
                log.info("airlbs.get_address失败", address)
            end
        else
            log.warn("airlbs", "定位失败, 跳过逆地理编码")
        end

        -- 循环 15 分钟一次定位
        sys.wait(LOCATE_INTERVAL)
    end
end

-- 创建并启动定位任务
sys.taskInit(airlbs_multi_cells_wifi_task_func)
