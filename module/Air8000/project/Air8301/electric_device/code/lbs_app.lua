--[[
@module  lbs_app
@summary 基站定位模块（基于 airlbs 扩展库，获取经纬度并广播）
@version 1.0
@date    2026.09.19
@author  嵌入式软件设计开发代理
@usage
使用合宙 airlbs 扩展库（付费基站定位，多基站 + WiFi 混合定位）获取设备经纬度：
1、等待网络就绪 + 系统时间同步（airlbs 鉴权需准确时间戳）；
2、调用 airlbs.request 获取 {lat, lng}；
3、定位成功后发布 "LOCATION_UPDATED"（lat, lng，number 类型）；
4、定位成功后每 60 秒刷新一次（与状态上报同频，保证每条上报都是最新坐标）；
5、定位失败按间隔重试，并保留上一次的有效坐标（不置空）。

⚠️ 前置条件（合宙收费服务）：
- 需联系合宙销售申请 AirLBS 的 project_id（6 位）与 project_key；
- 在 main.lua 中配置全局变量后本模块才会启用：
    AIRLBS_PROJECT_ID  = "xxxxxx"
    AIRLBS_PROJECT_KEY = "xxxxxxxx"
  未配置时模块自动跳过定位（不影响其他业务）。

发布消息：
- "LOCATION_UPDATED"   -- 定位更新 {lat(number), lng(number)}（protocol_app 订阅，随状态上报）

对外接口：
- lbs_app.get_location()  -- 获取最近一次定位结果 {lat, lng}，无有效定位返回 nil
]]

local airlbs = require "airlbs"

local lbs_app = {}

-- AirLBS 凭证（由 main.lua 在 require 本模块前定义全局变量）
local PROJECT_ID  = _G.AIRLBS_PROJECT_ID or ""
local PROJECT_KEY = _G.AIRLBS_PROJECT_KEY or ""

-- 定位节奏（毫秒）
-- 说明：成功间隔与状态上报间隔（business_app 每分钟一次）对齐，
--       保证每条上报携带的经纬度都是"刚查到的"最新值。
--       注意：AirLBS 为合宙收费服务（按调用计费），60s 间隔约 1440 次/天，
--             请确认所选套餐/QPS 与配额能够承受；如需降低成本可适当调大。
local LOC_TIMEOUT          = 15000            -- 单次定位超时
local LOC_SUCCESS_INTERVAL = 60 * 1000        -- 定位成功后的再次定位间隔（60 秒，与上报同频）
local LOC_FAIL_RETRY       = 3 * 60 * 1000    -- 定位失败后的重试间隔（3 分钟，保留旧坐标不置空）

-- 最近一次定位结果缓存
local last_lat = nil
local last_lng = nil

--[[
确保系统时间有效（airlbs 采用时间戳 + HMAC 鉴权，时间偏差过大会鉴权失败）

优先等待 ntp_app 的时间同步（NTP_SYNCED）；超时后自行发起一次 SNTP。

@local
@function ensure_time
@return boolean 时间是否有效
]]
local function ensure_time()
    -- 2023-11-14 之后视为有效时间（避免使用 1970 初始时间发起请求）
    if os.time() > 1700000000 then
        return true
    end
    log.info("lbs_app", "系统时间未同步，等待 NTP 同步 ...")
    if sys.waitUntil("NTP_SYNCED", 30000) then
        return true
    end
    -- 兜底：自行发起一次 SNTP
    socket.sntp()
    return sys.waitUntil("NTP_UPDATE", 10000) ~= nil
end

--[[
执行一次定位

@local
@function do_locate
@return boolean 是否定位成功
]]
local function do_locate()
    local ok, data = airlbs.request({
        project_id  = PROJECT_ID,
        project_key = PROJECT_KEY,
        timeout     = LOC_TIMEOUT,
    })
    if not ok or not data then
        return false
    end
    -- airlbs 返回的 lat/lng 可能为字符串或数字，统一转 number
    local lat = tonumber(data.lat)
    local lng = tonumber(data.lng)
    if not lat or not lng then
        log.warn("lbs_app", "定位返回数据异常:", data.lat, data.lng)
        return false
    end
    last_lat, last_lng = lat, lng
    log.info("lbs_app", "定位成功: 纬度=" .. lat .. ", 经度=" .. lng)
    -- 广播定位结果（protocol_app 订阅后随状态上报一起上传）
    sys.publish("LOCATION_UPDATED", lat, lng)
    return true
end

--[[
定位主任务：等待网络 → 等待时间同步 → 周期定位

@local
@function lbs_task
@return nil
]]
local function lbs_task()
    -- 未配置凭证：跳过定位（不阻塞其他业务）
    if PROJECT_ID == "" or PROJECT_KEY == "" then
        log.warn("lbs_app", "AirLBS 凭证未配置(AIRLBS_PROJECT_ID/AIRLBS_PROJECT_KEY)，定位功能不启用")
        return
    end

    -- 等待网络就绪（循环等待，不退出）
    while not socket.adapter(socket.dft()) do
        sys.waitUntil("IP_READY", 1000)
    end
    log.info("lbs_app", "网络已就绪，准备基站定位")

    -- 等待系统时间同步（避免 airlbs 鉴权失败）
    ensure_time()

    while true do
        if do_locate() then
            -- 定位成功：周期刷新
            sys.wait(LOC_SUCCESS_INTERVAL)
        else
            log.warn("lbs_app", "定位失败，稍后重试")
            sys.wait(LOC_FAIL_RETRY)
        end
    end
end

--[[
获取最近一次定位结果

@api lbs_app.get_location()
@return table|nil {lat, lng} 无有效定位时返回 nil
]]
function lbs_app.get_location()
    if last_lat and last_lng then
        return {lat = last_lat, lng = last_lng}
    end
    return nil
end

-- 启动定位任务
sys.taskInit(lbs_task)

return lbs_app
