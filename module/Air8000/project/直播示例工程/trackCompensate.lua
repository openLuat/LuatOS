--[[
@module  trackCompensate
@summary GNSS轨迹拐点补偿模块，通过速度航向平滑算法减少定位漂移
@version 1.0
@date    2026.01.29
@author  Auto
@usage
本模块实现以下功能：
1. 航向平滑：根据历史航向数据进行加权平均，减少航向跳变
2. 速度平滑：过滤速度突变，防止轨迹偏离实际路网
3. 距离阈值过滤：过滤超出合理范围的漂移点
4. 拐点检测：检测急转弯点并优化轨迹
]]

local trackCompensate = {}

local moduleName = "trackCompensate"
local logSwitch = true

-- 统一日志前缀
local logPrefix = "[TRACK_COMP]"

-- 历史数据缓存（用于平滑计算）
local historyBuffer = {}
local MAX_HISTORY = 5  -- 保存最近5个定位点

-- 配置参数
local config = {
    -- 距离阈值（米），超过此距离认为漂移，进行补偿
    -- 原值50米太小,改为500米以避免正常移动被误判为漂移
    distanceThreshold = 500,

    -- 速度突变阈值（km/h），超过此值认为异常
    speedChangeThreshold = 30,

    -- 航向跳变阈值（度），超过此值进行平滑
    courseChangeThreshold = 30,

    -- 是否启用拐点补偿
    enableCornerCompensate = true,

    -- 最小转弯半径（米），小于此值认为是急转弯
    minTurnRadius = 10,
}

local function logF(...)
    if logSwitch then
        log.info(moduleName, logPrefix, ...)
    end
end

-- 计算两点之间的距离（Haversine公式，单位：米）
local function calculateDistance(lat1, lng1, lat2, lng2)
    local R = 6371000  -- 地球半径（米）
    local lat1Rad = math.rad(lat1)
    local lat2Rad = math.rad(lat2)
    local deltaLat = math.rad(lat2 - lat1)
    local deltaLng = math.rad(lng2 - lng1)

    local a = math.sin(deltaLat / 2) * math.sin(deltaLat / 2) +
              math.cos(lat1Rad) * math.cos(lat2Rad) *
              math.sin(deltaLng / 2) * math.sin(deltaLng / 2)

    local c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a))

    return R * c
end

-- 计算方位角（0-360度）
local function calculateBearing(lat1, lng1, lat2, lng2)
    local lat1Rad = math.rad(lat1)
    local lat2Rad = math.rad(lat2)
    local deltaLng = math.rad(lng2 - lng1)

    local x = math.sin(deltaLng) * math.cos(lat2Rad)
    local y = math.cos(lat1Rad) * math.sin(lat2Rad) -
              math.sin(lat1Rad) * math.cos(lat2Rad) * math.cos(deltaLng)

    local bearing = math.atan2(x, y)
    bearing = math.deg(bearing)
    bearing = (bearing + 360) % 360

    return bearing
end

-- 航向平滑处理
local function smoothCourse(currentCourse)
    if #historyBuffer < 2 then
        return currentCourse
    end

    -- 获取历史航向数据
    local courses = {}
    for i = math.max(1, #historyBuffer - 2), #historyBuffer do
        table.insert(courses, historyBuffer[i].course)
    end

    -- 检测航向跳变（如从359度跳到1度）
    local avgCourse = 0
    local sumSin = 0
    local sumCos = 0

    for _, c in ipairs(courses) do
        sumSin = sumSin + math.sin(math.rad(c))
        sumCos = sumCos + math.cos(math.rad(c))
    end

    avgCourse = math.deg(math.atan2(sumSin, sumCos))
    avgCourse = (avgCourse + 360) % 360

    -- 如果当前航向与历史平均航向差异过大，进行平滑
    local diff = math.abs(currentCourse - avgCourse)
    if diff > 180 then
        diff = 360 - diff
    end

    if diff > config.courseChangeThreshold then
        logF("航向跳变补偿", currentCourse, "→", avgCourse, "差值", diff)
        return avgCourse
    end

    return currentCourse
end

-- 速度平滑处理
local function smoothSpeed(currentSpeed, distance, timeDiff)
    if #historyBuffer < 1 then
        return currentSpeed
    end

    local last = historyBuffer[#historyBuffer]
    if not last.speed or last.speed == 0 then
        return currentSpeed
    end

    -- 计算实际移动速度
    local calcSpeed = 0
    if timeDiff > 0 then
        calcSpeed = (distance / timeDiff) * 3.6  -- m/s → km/h
    end

    -- 如果计算速度与GNSS速度差异过大，使用计算速度
    local speedDiff = math.abs(currentSpeed - calcSpeed)
    if speedDiff > config.speedChangeThreshold and calcSpeed > 0 then
        logF("速度突变补偿", currentSpeed, "→", calcSpeed, "差值", speedDiff)
        return calcSpeed
    end

    return currentSpeed
end

-- 拐点补偿算法
local function compensateCorner(lat, lng, course, speed)
    if #historyBuffer < 2 then
        return lat, lng, course
    end

    local last = historyBuffer[#historyBuffer]
    local prev = historyBuffer[#historyBuffer - 1]

    -- 计算三个点的角度变化
    local bearing1 = calculateBearing(prev.lat, prev.lng, last.lat, last.lng)
    local bearing2 = calculateBearing(last.lat, last.lng, lat, lng)

    local angleDiff = math.abs(bearing2 - bearing1)
    if angleDiff > 180 then
        angleDiff = 360 - angleDiff
    end

    -- 检测急转弯
    if angleDiff > 90 and config.enableCornerCompensate then
        -- 计算预估位置（基于速度和航向）
        local estimatedLat, estimatedLng

        if speed > 5 then  -- 有一定速度才补偿
            local timeDiff = 3  -- 假设3秒间隔
            local distance = (speed / 3.6) * timeDiff  -- km/h → m/s

            -- 沿当前航向预估位置
            estimatedLat = lat + (distance / 6371000) * math.cos(math.rad(bearing2))
            estimatedLng = lng + (distance / 6371000) * math.sin(math.rad(bearing2)) / math.cos(math.rad(lat))

            -- 检查预估位置与原始位置的距离
            local diff = calculateDistance(lat, lng, estimatedLat, estimatedLng)
            if diff < config.distanceThreshold then
                logF("拐点补偿", lat, lng, "→", estimatedLat, estimatedLng, "角度", angleDiff)
                return estimatedLat, estimatedLng, bearing2
            end
        end
    end

    return lat, lng, course
end

-- 添加历史数据
local function addHistory(lat, lng, course, speed)
    table.insert(historyBuffer, {
        lat = lat,
        lng = lng,
        course = course,
        speed = speed,
        time = os.time()
    })

    -- 保持缓冲区大小
    if #historyBuffer > MAX_HISTORY then
        table.remove(historyBuffer, 1)
    end
end

-- 主补偿函数
function trackCompensate.compensate(lat, lng, course, speed)
    lat = lat or 0
    lng = lng or 0
    course = course or 0
    speed = speed or 0

    logF("========== 轨迹补偿开始 ==========")
    logF("输入参数", "纬度:", lat, "经度:", lng, "航向:", course, "速度:", speed)
    logF("历史数据量:", #historyBuffer)

    -- 无效数据直接返回
    if lat == 0 or lng == 0 then
        logF("无效数据，直接返回")
        return lat, lng, course, speed
    end

    local resultLat = lat
    local resultLng = lng
    local resultCourse = course
    local resultSpeed = speed

    -- 计算与上一个点的距离
    local distance = 0
    local timeDiff = 0
    if #historyBuffer > 0 then
        local last = historyBuffer[#historyBuffer]
        distance = calculateDistance(last.lat, last.lng, lat, lng)
        timeDiff = os.time() - last.time

        -- 距离漂移检测
        if distance > config.distanceThreshold then
            logF("警告：距离漂移！", "距离:", distance, "米", "阈值:", config.distanceThreshold, "米")
            logF("过滤漂移点，返回历史位置", last.lat, last.lng)
            -- 过滤掉漂移点，返回历史最后位置，但不添加到缓存
            resultLat = last.lat
            resultLng = last.lng
            -- 注意：这里不调用addHistory,避免重复添加历史位置导致后续点全部被过滤
            return resultLat, resultLng, resultCourse, resultSpeed
        end

        logF("距离正常:", distance, "米")
    end

    -- 速度平滑
    resultSpeed = smoothSpeed(speed, distance, timeDiff)

    -- 速度平滑
    resultSpeed = smoothSpeed(speed, distance, timeDiff)
    logF("速度平滑", "原始:", speed, "→", "结果:", resultSpeed)

    -- 航向平滑
    resultCourse = smoothCourse(course)
    logF("航向平滑", "原始:", course, "→", "结果:", resultCourse)

    -- 拐点补偿
    if config.enableCornerCompensate then
        resultLat, resultLng, resultCourse = compensateCorner(lat, lng, resultCourse, resultSpeed)
        logF("拐点补偿后位置", resultLat, resultLng)
    end

    -- 添加到历史缓存
    addHistory(resultLat, resultLng, resultCourse, resultSpeed)
    logF("添加到历史缓存，当前历史数量:", #historyBuffer)

    logF("补偿结果", lat, lng, "→", resultLat, resultLng)
    logF("========== 轨迹补偿结束 ==========")

    return resultLat, resultLng, resultCourse, resultSpeed
end

-- 配置模块参数
function trackCompensate.setConfig(cfg)
    if type(cfg) ~= "table" then
        return false
    end

    if cfg.distanceThreshold then
        config.distanceThreshold = cfg.distanceThreshold
    end

    if cfg.speedChangeThreshold then
        config.speedChangeThreshold = cfg.speedChangeThreshold
    end

    if cfg.courseChangeThreshold then
        config.courseChangeThreshold = cfg.courseChangeThreshold
    end

    if cfg.enableCornerCompensate ~= nil then
        config.enableCornerCompensate = cfg.enableCornerCompensate
    end

    if cfg.minTurnRadius then
        config.minTurnRadius = cfg.minTurnRadius
    end

    logF("配置更新", json.encode(config))
    return true
end

-- 清空历史数据
function trackCompensate.clearHistory()
    historyBuffer = {}
    logF("历史数据已清空")
end

-- 获取当前配置
function trackCompensate.getConfig()
    return config
end

-- 获取历史数据数量
function trackCompensate.getHistoryCount()
    return #historyBuffer
end

return trackCompensate
