--[[
@module  mygps
@summary 定位模块（LBS + GNSS 按需同步接口）
@version 2.0
@date    2026-05-27
@description
    本版本（v2.0）业务定位：
      1. LBS 定位：上报时按需触发，同步返回成功/失败
      2. GNSS 定位：上报周期内每 N 次（默认 30min/次）触发一次，超时 60s 失败放弃
      3. 不再独立 timerLoopStart 定时定位，统一由 report 模块调度
      4. 所有定位接口均为同步阻塞（在 task 中调用），返回值清晰
]]

local mygps = {}

-- 导入库
local exgnss = require "exgnss"
local lbsLoc2 = require "lbsLoc2"

-- ========== 硬编码常量 ==========
local LBS_ENABLED        = true       -- 是否启用 LBS
local GNSS_ENABLED       = true       -- 是否启用 GNSS（按需触发，非常驻）
local LBS_TIMEOUT_MS     = 15000      -- LBS 单次定位超时(毫秒)
local GNSS_TIMEOUT_SEC   = 60         -- GNSS 单次定位超时(秒)：1 分钟内无定位结果则放弃
local GNSS_NMEA_DEBUG    = false      -- GNSS NMEA 调试日志开关
-- =================================

-- 当前位置（缓存最近一次成功的定位）
local current_location = {
    lat = 0,
    lng = 0,
    accuracy = 0,
    source = "none",        -- "GNSS" / "LBS" / "none"
    timestamp = 0,
    speed = 0,
    heading = 0,
    altitude = 0,
    satellites_total = 0,
    satellites_visible = 0
}

-- 最近一次 GNSS 定位结果（独立于 current_location，专用于 GNSS 字段上报）
-- gnss_last_result.ok == true 时 lat/lng 有效
local gnss_last_result = {
    ok = false,            -- 本次 GNSS 是否定位成功
    lat = 0,
    lng = 0,
    timestamp = 0,         -- 最近一次 GNSS 尝试时间
}

-- 初始化定位模块
function mygps.init()
    log.info("GPS", "Initializing GPS module v2.0...")
    log.info("GPS", "LBS enabled:", LBS_ENABLED, "GNSS enabled:", GNSS_ENABLED,
                    "LBS_TIMEOUT:", LBS_TIMEOUT_MS, "ms",
                    "GNSS_TIMEOUT:", GNSS_TIMEOUT_SEC, "s")

    if GNSS_ENABLED then
        exgnss.setup({
            gnssmode=1,
            debug = GNSS_NMEA_DEBUG
        })
        log.info("GPS", "GNSS setup done")
    end

    log.info("GPS", "GPS init complete (按需调用模式)")
end

--[[
执行一次 LBS 定位（同步接口，必须在 task 中调用）
@return boolean, number, number  成功=true,lat,lng；失败=false,0,0
]]
function mygps.do_lbs_once_sync()
    if not LBS_ENABLED then
        log.warn("GPS", "LBS 已禁用")
        return false, 0, 0
    end

    -- 等待网络就绪（最多 1 秒）
    if not socket.adapter(socket.dft()) then
        log.warn("GPS", "等待 IP_READY ...")
        sys.waitUntil("IP_READY", 1000)
        if not socket.adapter(socket.dft()) then
            log.error("GPS", "LBS 失败：网络未就绪")
            return false, 0, 0
        end
    end

    -- 基站扫描（先做一次，确保有最新基站数据）
    log.info("GPS", "LBS 开始：触发基站扫描 mobile.reqCellInfo(15)")
    mobile.reqCellInfo(15)
    sys.waitUntil("CELL_INFO_UPDATE", 3000)

    -- 同步请求 LBS
    log.info("GPS", "LBS 请求中, timeout=" .. LBS_TIMEOUT_MS .. "ms ...")
    local lat, lng, t = lbsLoc2.request(LBS_TIMEOUT_MS)
    log.info("GPS", "LBS 返回值: lat=" .. tostring(lat) .. " lng=" .. tostring(lng)
                    .. " t=" .. tostring(t and json.encode(t) or "nil"))

    if lat and lng then
        local lat_num = tonumber(lat) or 0
        local lng_num = tonumber(lng) or 0
        if lat_num ~= 0 and lng_num ~= 0 then
            current_location.lat = lat_num
            current_location.lng = lng_num
            current_location.accuracy = 1000
            current_location.source = "LBS"
            current_location.timestamp = os.time()
            log.info("GPS", "LBS 定位成功:", lat_num, lng_num)
            return true, lat_num, lng_num
        end
    end

    log.warn("GPS", "LBS 定位失败")
    return false, 0, 0
end

--[[
执行一次 GNSS 定位（同步接口，必须在 task 中调用）
最长阻塞 GNSS_TIMEOUT_SEC 秒，1 分钟内无定位即视为失败
@return boolean, number, number  成功=true,lat,lng；失败=false,0,0
]]
function mygps.do_gnss_once_sync()
    if not GNSS_ENABLED then
        log.warn("GPS", "GNSS 已禁用")
        gnss_last_result.ok = false
        gnss_last_result.timestamp = os.time()
        return false, 0, 0
    end

    gnss_last_result.ok = false
    gnss_last_result.timestamp = os.time()

    log.info("GPS", "GNSS 开始, timeout=" .. GNSS_TIMEOUT_SEC .. "s ...")

    -- ⚠️ 关键设计（基于合宙官方 exgnss.lua 源码分析）：
    --   TIMERORSUC 模式下，cb 触发后 exgnss 内部会立即调用 fnc_close 关闭 GNSS 硬件，
    --   关闭后 libgnss.isFix()/rmc() 会立刻被清零/失效！
    --   因此【必须在 cb 内部】即时读取 is_fix 和 RMC 数据并快照保存，
    --   外层 task 拿到事件后再去读已经晚了（永远会是 false）。
    local GNSS_DONE_TOPIC = "GNSS_SYNC_DONE_" .. tostring(os.time())

    -- 用 upvalue table 在 cb→外层 task 之间传递快照（避免依赖 libgnss 状态）
    local snapshot = {
        fixed = false,
        lat = 0,
        lng = 0,
        speed = 0,
        course = 0,
        alt = 0,
        sv = 0,
        accuracy = 0,
    }

    local function gnss_done_cb(tag)
        -- 必须在此处立刻读取，cb 返回后 GNSS 会被 exgnss 内部关闭
        local now_fix = exgnss.is_fix()
        log.info("GPS", "GNSS 回调触发, tag=" .. tostring(tag)
                        .. " is_fix=" .. tostring(now_fix) .. " (cb 内即时读取)")

        if now_fix then
            local rmc = exgnss.rmc(0)
            if rmc and rmc.lat and rmc.lng then
                local lat_num = tonumber(rmc.lat) or 0
                local lng_num = tonumber(rmc.lng) or 0
                if lat_num ~= 0 and lng_num ~= 0 then
                    snapshot.fixed    = true
                    snapshot.lat      = lat_num
                    snapshot.lng      = lng_num
                    snapshot.speed    = rmc.speed or 0
                    snapshot.course   = rmc.course or 0
                    snapshot.accuracy = rmc.accuracy or 5
                    -- GGA 数据（高度 + 卫星数）一并在 cb 内快照
                    local gga = exgnss.gga(0)
                    if gga then
                        snapshot.alt = gga.alt or 0
                        snapshot.sv  = gga.sv or 0
                    end
                    log.info("GPS", "cb 内 RMC 快照成功: lat=" .. lat_num
                                    .. " lng=" .. lng_num
                                    .. " speed=" .. snapshot.speed
                                    .. " sv=" .. snapshot.sv)
                else
                    log.warn("GPS", "cb 内 RMC lat/lng 为 0")
                end
            else
                log.warn("GPS", "cb 内 is_fix=true 但 RMC 数据无效")
            end
        end

        sys.publish(GNSS_DONE_TOPIC)
    end

    -- TIMERORSUC 模式：定时启动，定位成功立即关闭，否则到 val 秒超时关闭
    -- ⚠️ 重要：exgnss.open() **无返回值**（参考官方 exgnss.lua 源码，返回值为 nil）
    -- 因此不能用 local ok = exgnss.open(...) 来判断是否打开成功！
    -- 真正判定"是否定位成功"只能在 cb 内部用 exgnss.is_fix() 进行（cb 返回后状态会失效）。
    exgnss.open(exgnss.TIMERORSUC, {
        tag = "report_gnss",
        val = GNSS_TIMEOUT_SEC,
        cb  = gnss_done_cb
    })

    -- 等待回调（额外加 5s 余量）
    local awakened = sys.waitUntil(GNSS_DONE_TOPIC, (GNSS_TIMEOUT_SEC + 5) * 1000)

    if not awakened then
        log.warn("GPS", "GNSS 等待回调超时（外层兜底），主动关闭")
        pcall(function() exgnss.close(exgnss.TIMERORSUC, {tag = "report_gnss"}) end)
        return false, 0, 0
    end

    -- ✅ 使用 cb 内捕获的快照进行判定（不再依赖 libgnss 当前状态）
    if not snapshot.fixed then
        log.warn("GPS", "GNSS 在 " .. GNSS_TIMEOUT_SEC .. "s 内未定位成功（cb 快照 fixed=false）")
        return false, 0, 0
    end

    local lat_num = snapshot.lat
    local lng_num = snapshot.lng

    -- 更新缓存（GNSS 优先级高于 LBS）
    current_location.lat = lat_num
    current_location.lng = lng_num
    current_location.accuracy = snapshot.accuracy
    current_location.source = "GNSS"
    current_location.timestamp = os.time()
    current_location.speed = snapshot.speed
    current_location.heading = snapshot.course
    current_location.altitude = snapshot.alt
    current_location.satellites_total = snapshot.sv
    current_location.satellites_visible = snapshot.sv

    gnss_last_result.ok = true
    gnss_last_result.lat = lat_num
    gnss_last_result.lng = lng_num

    log.info("GPS", "GNSS 定位成功:", lat_num, lng_num,
                    "速度:", snapshot.speed,
                    "卫星数:", snapshot.sv)
    return true, lat_num, lng_num
end

-- 获取当前位置（缓存的最近一次成功定位）
function mygps.get_location()
    return current_location
end

-- 获取最近一次 GNSS 定位结果（专用于 GNSS 字段上报）
-- @return table { ok=bool, lat=num, lng=num, timestamp=num }
function mygps.get_last_gnss_result()
    return gnss_last_result
end

-- 获取 GNSS 状态查询接口（保留兼容）
function mygps.get_gnss_status()
    if exgnss and exgnss.status then
        return exgnss.status()
    end
    return nil
end

-- 关闭所有定位服务
function mygps.stop_all()
    if GNSS_ENABLED then
        pcall(function() exgnss.close_all() end)
    end
    log.info("GPS", "已关闭所有定位服务")
end

return mygps
