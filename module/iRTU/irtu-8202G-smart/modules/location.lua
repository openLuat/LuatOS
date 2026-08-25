--[[
@module location
@summary 定位模块
@version 2.0
@date    2026.05.21
@usage
Air8202G 项目定位模块。
集中管理 GPS、WiFi 扫描、基站定位（lbsLoc2/AirLBS）的采集逻辑。
]]

local location = {}
local config = require("config")
local tools = require("tools")
local airlbs = require("airlbs")
local lbsLoc2 = require("lbsLoc2")
local exgnss = require("exgnss")

-- 定位状态缓存
local location_state = {
    last_gps_time = 0,
    last_gps_data = nil,
    last_lbs_time = 0,
    last_lbs_data = nil,
    first_wifi_scan = false
}

-- 初始化
function location.init()
    log.info("location", "初始化定位模块")

    local gnssotps = {
        gnssmode = 1,
        agps_enable = true,
        debug = true,
    }
    exgnss.setup(gnssotps)
    sys.subscribe("GNSS_STATE", location.gnss_state_callback)

    -- 初始化 WiFi（只需一次）
    wlan.init()
    log.info("location", "WiFi初始化完成")

    log.info("location", "定位模块初始化完成")
end

-- GPS 状态回调
function location.gnss_state_callback(event)
    if event == "FIXED" then
        local rmc_data = exgnss.rmc(2)
        if rmc_data then
            location_state.last_gps_time = os.time()
            location_state.last_gps_data = rmc_data
            sys.publish("LOCATION_SUCCESS", "gps", rmc_data)
        end
    elseif event == "LOSE" then
        log.warn("location", "GPS信号丢失")
    elseif event == "CLOSE" then
        log.info("location", "GPS关闭")
    end
end

-- 获取 AirLBS 定位（支持免费/付费双模式）
-- 免费模式：lbsLoc2 单基站定位（精度较低）
-- 付费模式：AirLBS 多基站+WiFi混合定位（精度更高，需项目ID和密钥）
-- @return table|nil {lat, lng} 或 nil
function location.get_lbs_location()
    local airlbs_mode = config.AIRLBS_CONFIG and config.AIRLBS_CONFIG.MODE or 0

    -- 付费模式：使用 AirLBS
    if airlbs_mode == 1 then
        local project_id = config.AIRLBS_CONFIG.PROJECT_ID
        local project_key = config.AIRLBS_CONFIG.PROJECT_KEY
        if not project_id or project_id == "" or not project_key or project_key == "" then
            log.warn("location", "AirLBS项目ID或密钥未配置，无法使用付费模式")
            return nil
        end

        -- 缓存有效期内直接返回
        if location_state.last_lbs_data and (os.time() - location_state.last_lbs_time) < config.LOCATION_CONFIG.CACHE_DURATION then
            return location_state.last_lbs_data
        end

        -- 扫描 WiFi 辅助定位（仅第一次联网前等待，后续直接扫）
        local wifi_info = nil
        if not location_state.first_wifi_scan then
            while not socket.adapter(socket.dft()) do
                sys.waitUntil("IP_READY", 1000)
            end
            socket.sntp()
            sys.waitUntil("NTP_UPDATE", 1000)
            sys.wait(4000)
            location_state.first_wifi_scan = true
        end
        wlan.scan()
        local ok = sys.waitUntil("WLAN_SCAN_DONE", config.LOCATION_CONFIG.WIFI_TIMEOUT * 1000)
        local results = wlan.scanResult()
        if ok and results and #results > 0 then
            wifi_info = {}
            for i = 1, math.min(#results, 30) do
                table.insert(wifi_info, results[i])
            end
            log.info("location", "WiFi扫描结果数:", #wifi_info)
        end

        -- 像 demo 一样直接请求
        local request_args = {
            project_id = project_id,
            project_key = project_key,
            timeout = config.LOCATION_CONFIG.LBS_TIMEOUT * 1000
        }
        if wifi_info then
            request_args.wifi_info = wifi_info
        end

        log.info("location", "请求AirLBS付费定位, project_id:", project_id)
        local result, data = airlbs.request(request_args)
        if result and data then
            local lat = tonumber(data.lat)
            local lng = tonumber(data.lng)
            if lat and lng then
                log.info("location", "AirLBS付费定位成功:", lat, lng)
                local result_data = {lat = lat, lng = lng}
                location_state.last_lbs_time = os.time()
                location_state.last_lbs_data = result_data
                return result_data
            end
        end
        log.warn("location", "AirLBS付费定位失败")
        return nil
    end

    -- 免费模式：使用 lbsLoc2 单基站定位

    -- 缓存有效期内直接返回
    if location_state.last_lbs_data and (os.time() - location_state.last_lbs_time) < config.LOCATION_CONFIG.CACHE_DURATION then
        return location_state.last_lbs_data
    end

    log.info("location", "请求lbsLoc2免费定位")
    local lat, lng = lbsLoc2.request(config.LOCATION_CONFIG.LBS_TIMEOUT * 1000)
    if lat and lng then
        lat = tonumber(lat)
        lng = tonumber(lng)
        log.info("location", "lbsLoc2免费定位成功:", lat, lng)
        local result = {lat = lat, lng = lng}
        location_state.last_lbs_time = os.time()
        location_state.last_lbs_data = result
        return result
    end

    log.warn("location", "lbsLoc2免费定位失败")
    return nil
end

-- 获取 GPS 定位数据（带超时）
function location.get_gnss_location(timeout)
    if location_state.last_gps_data and (os.time() - location_state.last_gps_time) < config.LOCATION_CONFIG.CACHE_DURATION then
        return location_state.last_gps_data, 2  -- gps_status=2 定位成功
    end

    exgnss.open(exgnss.TIMERORSUC, {
        tag = "gps_location",
        val = timeout or config.LOCATION_CONFIG.GPS_TIMEOUT,
        cb = location.gps_callback
    })

    local result = sys.waitUntil("LOCATION_SUCCESS", (timeout or config.LOCATION_CONFIG.GPS_TIMEOUT) * 1000)
    if result and location_state.last_gps_data then
        return location_state.last_gps_data, 2
    end

    log.warn("location", "GPS定位超时")
    return nil, 3  -- gps_status=3 定位失败
end

function location.gps_callback(tag)
    local rmc_data = exgnss.rmc(2)
    if rmc_data then
        location_state.last_gps_time = os.time()
        location_state.last_gps_data = rmc_data
        sys.publish("LOCATION_SUCCESS", "gps", rmc_data)
    end
end

-- 获取基站定位状态码（4=免费, 5=付费）
local function get_lbs_status()
    local airlbs_mode = config.AIRLBS_CONFIG and config.AIRLBS_CONFIG.MODE or 0
    return airlbs_mode == 1 and 5 or 4
end

-- GPS定位模式定位（GPS常开）
-- 优先 GPS：有缓存直接用；无缓存则等待 GPS 定位成功（GPS_TIMEOUT 秒），超时才降级基站
-- 开机即寻宠模式场景：首报必须给足 GPS 搜星时间，避免误用基站
function location.get_find_mode_location()
    -- 确保GPS正在运行（常开，无超时）
    if not location_state._gps_started then
        location_state._gps_started = true
        exgnss.open(exgnss.DEFAULT, {tag = "gps_find"})
        log.info("location", "GPS定位模式GPS已常开")
    end

    -- 检查GPS缓存（GPS_TIMEOUT 秒内有效）
    if location_state.last_gps_data and (os.time() - location_state.last_gps_time) < config.LOCATION_CONFIG.GPS_TIMEOUT then
        log.info("location", "GPS定位模式GPS使用缓存数据")
        return {lat = location_state.last_gps_data.lat, lng = location_state.last_gps_data.lng}, 2
    end

    -- GPS无有效数据：等待 GPS 定位成功（GPS_TIMEOUT 秒），GPS常开期间 FIXED 事件会发布 LOCATION_SUCCESS
    log.info("location", "GPS定位模式等待GPS定位，超时", config.LOCATION_CONFIG.GPS_TIMEOUT, "秒后降级基站")
    local ok = sys.waitUntil("LOCATION_SUCCESS", config.LOCATION_CONFIG.GPS_TIMEOUT * 1000)
    if ok and location_state.last_gps_data then
        log.info("location", "GPS定位成功:", location_state.last_gps_data.lat, location_state.last_gps_data.lng)
        return {lat = location_state.last_gps_data.lat, lng = location_state.last_gps_data.lng}, 2
    end

    -- GPS超时，降级基站
    log.info("location", "GPS定位超时，使用AirLBS备选定位")
    local lbs_data = location.get_lbs_location()
    if lbs_data then
        return lbs_data, get_lbs_status()
    end

    return nil, 3
end

-- 主入口：根据工作模式采集定位信息
-- @param number work_mode 设备模式
-- @param boolean is_low_power 是否低电量
-- @param boolean is_moving 是否运动中（智能模式使用）
-- @return table 包含 gps/gps_status 数据
function location.get_location(work_mode, is_low_power, is_moving)
log.info("location", "获取定位, work_mode:", work_mode, "低电量:", is_low_power, "运动中:", is_moving)

    local result = {
        gps = nil,        -- 经纬度字符串 "lat,lng" 或 nil
        gps_status = 0    -- 0=未开启, 1=定位中, 2=GPS定位成功, 3=定位失败, 4=免费基站成功, 5=付费基站成功
    }

    -- 低电量：仅使用基站定位
    if is_low_power then
        log.info("location", "低电量模式，使用基站定位")
        local lbs_data = location.get_lbs_location()
        if lbs_data then
            result.gps = string.format("%.5f,%.5f", lbs_data.lat, lbs_data.lng)
            result.gps_status = get_lbs_status()
        end
        return result
    end

    -- 根据模式选择定位方式
    if work_mode == config.DEVICE_MODE.FIND then
        -- GPS定位模式：GPS优先，基站备选
        local gps_data, gps_status = location.get_find_mode_location()
        if gps_data and gps_data.lat and gps_data.lng then
            result.gps = string.format("%.5f,%.5f", gps_data.lat, gps_data.lng)
            result.gps_status = gps_status
        else
            -- GPS失败，尝试基站
            local lbs_data = location.get_lbs_location()
            if lbs_data then
                result.gps = string.format("%.5f,%.5f", lbs_data.lat, lbs_data.lng)
                result.gps_status = get_lbs_status()
            else
                result.gps_status = 3
            end
        end
    elseif work_mode == config.DEVICE_MODE.SMART then
        -- 智能模式：运动中 GPS 优先（失败降级基站），静止只用基站
        log.info("location", "智能模式定位, is_moving=", tostring(is_moving))
        if is_moving then
            log.info("location", "智能模式运动中，GPS优先定位")
            local gps_data, gps_status = location.get_gnss_location(config.LOCATION_CONFIG.GPS_TIMEOUT)
            if gps_data and gps_data.lat and gps_data.lng then
                result.gps = string.format("%.5f,%.5f", gps_data.lat, gps_data.lng)
                result.gps_status = 2
            else
                log.info("location", "智能模式GPS失败，降级基站")
                local lbs_data = location.get_lbs_location()
                if lbs_data then
                    result.gps = string.format("%.5f,%.5f", lbs_data.lat, lbs_data.lng)
                    result.gps_status = get_lbs_status()
                else
                    result.gps_status = 3
                end
            end
        else
            log.info("location", "智能模式静止中，基站定位")
            local lbs_data = location.get_lbs_location()
            if lbs_data then
                result.gps = string.format("%.5f,%.5f", lbs_data.lat, lbs_data.lng)
                result.gps_status = get_lbs_status()
            else
                result.gps_status = 3
            end
        end
    else
        -- 常规模式：基站定位
        local lbs_data = location.get_lbs_location()
        if lbs_data then
            result.gps = string.format("%.5f,%.5f", lbs_data.lat, lbs_data.lng)
            result.gps_status = get_lbs_status()
        else
            result.gps_status = 3
        end
    end

    log.info("location", "定位采集完成, gps:", result.gps, "gps_status:", result.gps_status)
    return result
end

-- 消息处理
function location.handle_locate_request(params)
    local work_mode = params.work_mode or -1
    local is_low_power = params.is_low_power or false
    local data = location.get_location(work_mode, is_low_power)
    sys.publish("LOCATE_RESPONSE", data)
end

-- 关闭定位
function location.close()
    log.info("location", "关闭定位")
    location_state._gps_started = false
    -- 只关闭自己开启的 gps_location 应用，AGPS 保活应用(libagps)由 exgnss 内部到时自动关闭
    -- 这样保活 20 秒内 GPS 继续运行让星历解析完成，下次定位可热启动
    if exgnss.is_active and exgnss.is_active(exgnss.TIMERORSUC, {tag = "gps_location"}) then
        exgnss.close(exgnss.TIMERORSUC, {tag = "gps_location"})
    end
end

return location
