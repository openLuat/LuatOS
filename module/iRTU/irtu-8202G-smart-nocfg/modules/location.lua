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

    -- 启动 NMEA 1Hz 采样常驻任务（默认待机，nmea_stream_start 后才开始采样）
    sys.taskInit(nmea_stream_task)

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

-- 寻宠模式：主动打开 GPS（DEFAULT 常开，无超时）
-- 开机进入寻宠模式时立即调用，GPS 后台持续定位；
-- 定位成功后由 GPS 定位成功事件（LOCATION_SUCCESS/GNSS_STATE FIXED）驱动 5s 高频上报
function location.start_find_gps()
    if not location_state._gps_started then
        location_state._gps_started = true
        exgnss.open(exgnss.DEFAULT, {tag = "gps_find"})
        log.info("location", "寻宠模式 GPS 已开启（常开）")
    end
end

-- 关闭常开 GPS（与 start_find_gps 对应，GNSS 开关策略关闭时调用）
-- exgnss.close 只是注销本"gnss应用"，所有 gnss 应用都关闭后才会真正断电 GNSS
function location.stop_find_gps()
    if location_state._gps_started then
        location_state._gps_started = false
        exgnss.close(exgnss.DEFAULT, {tag = "gps_find"})
        log.info("location", "常开 GPS 已关闭")
    end
end

-- ====== NMEA 1Hz 流式采样（TLV 1294 数据源，004.000.019 新增） ======
-- GNSS 开启期间每秒采样一次定位五元组（经度/纬度/速度/航向/海拔），
-- 滚动保留最近 10 个有效样本（对应 10 秒），供 active_mode 组装 TLV 1294 二进制字段上报。
local NMEA_STREAM_KEEP = 10   -- 滚动缓冲容量（样本数）

local nmea_stream = {
    on = false,     -- 采样任务运行标志
    buf = {},       -- 最近 N 个有效样本 {lat, lng, speed, course, altitude}
}

-- 数值舍入到最近整数并钳位到 int16 范围（防 string.pack 溢出报错）
local function to_i16(v)
    v = math.floor(v + 0.5)
    if v > 32767 then return 32767 end
    if v < -32768 then return -32768 end
    return v
end

-- 1Hz 采样任务（常驻协程）：nmea_stream.on 为 true 时每秒读一次 RMC/GGA，
-- 仅定位有效（rmc.valid）时入缓冲；缓冲超容量丢弃最旧样本。
-- 采样期间上报协程阻塞（等网络/发数据）不影响本任务继续采样。
local function nmea_stream_task()
    while true do
        if nmea_stream.on then
            local rmc = exgnss.rmc(2)
            if rmc and rmc.valid and rmc.lat and rmc.lng then
                local alt = 0
                local gga = exgnss.gga(2)
                if gga and gga.altitude then alt = gga.altitude end
                table.insert(nmea_stream.buf, {
                    lat      = tonumber(rmc.lat) or 0,
                    lng      = tonumber(rmc.lng) or 0,
                    speed    = tonumber(rmc.speed) or 0,   -- 单位：节(knots)
                    course   = tonumber(rmc.course) or 0,  -- 单位：度（北向起顺时针）
                    altitude = alt,                        -- 单位：米（GGA）
                })
                if #nmea_stream.buf > NMEA_STREAM_KEEP then
                    table.remove(nmea_stream.buf, 1)
                end
            end
            sys.wait(1000)
        else
            sys.wait(500)
        end
    end
end

-- 开启 1Hz NMEA 采样（GNSS 开启时调用）
function location.nmea_stream_start()
    if not nmea_stream.on then
        nmea_stream.on = true
        log.info("location", "NMEA 1Hz 采样开启")
    end
end

-- 停止采样并清空缓冲（GNSS 关闭时调用）
function location.nmea_stream_stop()
    if nmea_stream.on then
        nmea_stream.on = false
        nmea_stream.buf = {}
        log.info("location", "NMEA 1Hz 采样停止，缓冲已清空")
    end
end

-- 取最近 10 个有效样本，编码为 TLV 1294 二进制载荷
-- 每样本 10 字节 = 经度差/纬度差/速度/航向/海拔 各 2 字节有符号 int16 大端，时间正序（最早在前）：
--   经度差 = (样本经度 - ref_lng) × 100000，1LSB ≈ 1.1m，范围 ±0.33°
--   纬度差 = (样本纬度 - ref_lat) × 100000，同上
--   速度   = km/h × 10（RMC 节值 × 1.852 换算），1LSB = 0.1km/h
--   航向   = 度 × 10，1LSB = 0.1°（静止时航向不可信）
--   海拔   = 米，1LSB = 1m
-- ref_lat/ref_lng 为本次报文 512/513 字段坐标（服务端用它加差值还原每秒绝对坐标）。
-- @return string 二进制载荷（样本数 × 10 字节），无数据返回 ""
-- @return number 实际样本数
function location.get_nmea_stream(ref_lat, ref_lng)
    if not ref_lat or not ref_lng then return "", 0 end
    local n = math.min(#nmea_stream.buf, NMEA_STREAM_KEEP)
    if n == 0 then return "", 0 end
    local parts = {}
    for i = 1, n do
        local s = nmea_stream.buf[i]
        parts[i] = string.pack(">i2i2i2i2i2",
            to_i16((s.lng - ref_lng) * 100000),
            to_i16((s.lat - ref_lat) * 100000),
            to_i16(s.speed * 1.852 * 10),
            to_i16(s.course * 10),
            to_i16(s.altitude))
    end
    return table.concat(parts), n
end

-- GPS定位模式定位（GPS常开，不阻塞）
-- 到点上报告时直接判断 GPS 是否已定位成功（is_fix）：
--   - 已定位成功 → 直接 exgnss.rmc(2) 取坐标发送（gps_status=2）
--   - 未定位成功 → 不使用缓存 GPS 数据，立即降级基站（不等待，GPS 后台继续定位）
-- GPS 常开持续在后台定位，定位成功后由定位成功事件驱动 5s 高频上报
function location.get_find_mode_location()
    -- 确保GPS正在运行（常开，无超时）
    location.start_find_gps()

    -- 1. 直接判断 GPS 是否已定位成功（不阻塞等待）
    local fix = false
    if exgnss.is_fix then
        fix = exgnss.is_fix()
    end
    log.info("location", "GPS定位模式 is_fix=", tostring(fix))

    if fix then
        -- 已定位成功：直接取 RMC 坐标
        local rmc_data = exgnss.rmc(2)
        if rmc_data and rmc_data.valid and rmc_data.lat and rmc_data.lng then
            location_state.last_gps_time = os.time()
            location_state.last_gps_data = rmc_data
            log.info("location", "GPS定位成功:", rmc_data.lat, rmc_data.lng)
            return {lat = rmc_data.lat, lng = rmc_data.lng}, 2
        end
    end

    -- 2. 未定位成功（掉星/搜星中）：不使用缓存 GPS 数据，立即降级基站（不等待，GPS 后台继续定位）
    --    30s 保底定时器检测到 GPS 未定位成功时走这里，上报 LBS 数据
    log.info("location", "GPS未定位成功，不使用缓存，直接使用基站备选定位")
    local lbs_data = location.get_lbs_location()
    if lbs_data then
        return lbs_data, get_lbs_status()
    end

    return nil, 3
end

-- 上报定位采集入口（GNSS 优先锁定策略）
-- 规则：开机以来只要 GNSS 定位成功过一次，之后所有上报不再使用 LBS：
--   - GNSS 开且当前定位成功 → 用当前实时坐标
--   - 当前未定位成功（GNSS 关或掉星）→ 用最近一次 GNSS 定位成功坐标
--   - gps_status 恒为 2
-- 开机以来从未 GNSS 定位成功 → 走 LBS 定位（gps_status 为 4/5，失败为 3）
-- @param boolean gnss_on 当前 GNSS 开关状态（是否尝试读实时定位）
-- @return table {gps="lat,lng"或nil, gps_status=2/3/4/5}
function location.get_report_location(gnss_on)
    -- 判定依据：last_gps_data 只有在定位成功时才会被写入（FIXED 回调 / 定位成功路径），
    -- 非 nil 即代表开机以来 GNSS 至少成功过一次
    local last = location_state.last_gps_data
    if last and last.lat and last.lng then
        -- 曾定位成功：先尝试当前实时定位
        if gnss_on then
            local fix = false
            if exgnss.is_fix then
                fix = exgnss.is_fix()
            end
            if fix then
                local rmc_data = exgnss.rmc(2)
                if rmc_data and rmc_data.valid and rmc_data.lat and rmc_data.lng then
                    local lat = tonumber(rmc_data.lat)
                    local lng = tonumber(rmc_data.lng)
                    if lat and lng then
                        -- 刷新缓存（作为下一次"最近一次成功"的坐标）
                        location_state.last_gps_time = os.time()
                        location_state.last_gps_data = rmc_data
                        log.info("location", "GNSS当前定位成功:", lat, lng)
                        return { gps = string.format("%.5f,%.5f", lat, lng), gps_status = 2 }
                    end
                end
            end
        end
        -- 当前未定位成功：沿用最近一次 GNSS 成功坐标，状态仍报 2
        local lat = tonumber(last.lat)
        local lng = tonumber(last.lng)
        if lat and lng then
            log.info("location", "GNSS当前未定位成功，沿用最近一次成功坐标:", lat, lng,
                "(距今", os.time() - (location_state.last_gps_time or 0), "秒)")
            return { gps = string.format("%.5f,%.5f", lat, lng), gps_status = 2 }
        end
    end

    -- 开机以来从未 GNSS 定位成功：走 LBS
    log.info("location", "开机以来 GNSS 从未定位成功，使用 LBS 定位")
    local result = { gps = nil, gps_status = 3 }
    local lbs_data = location.get_lbs_location()
    if lbs_data then
        result.gps = string.format("%.5f,%.5f", lbs_data.lat, lbs_data.lng)
        result.gps_status = get_lbs_status()
    end
    return result
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
