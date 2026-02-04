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
-- 支持自适应场景: person(人员) / vehicle(车辆)
local config = {
    -- 使用场景: "person" 或 "vehicle"
    -- person: 人员定位，速度慢，频繁转弯
    -- vehicle: 车辆定位，速度快，直线行驶多
    scene = "person",

    -- 人员定位参数
    personParams = {
        -- 距离阈值(米): 人员正常移动速度约1-2m/s,3秒间隔约3-6米
        -- 设置50米可以有效过滤漂移,同时不会误判正常移动
        distanceThreshold = 50,

        -- 速度突变阈值(km/h): 人员速度突变通常不超过10km/h
        speedChangeThreshold = 10,

        -- 航向跳变阈值(度): 人员移动方向变化频繁,允许更大的航向变化
        courseChangeThreshold = 60,

        -- 拐点检测角度(度): 人员可以在小巷转弯,角度变化大
        cornerAngleThreshold = 120,

        -- 最小转弯半径(米): 人员可以在狭小空间转弯
        minTurnRadius = 5,
    },

    -- 车辆定位参数
    vehicleParams = {
        -- 距离阈值(米): 城市车辆速度约20-40km/h,3秒间隔约17-34米
        -- 设置200米可以过滤漂移,同时允许隧道/高架桥等场景
        distanceThreshold = 200,

        -- 速度突变阈值(km/h): 车辆急加速急刹车可能超过30km/h
        speedChangeThreshold = 50,

        -- 航向跳变阈值(度): 车辆一般在道路上行驶,航向变化相对平滑
        courseChangeThreshold = 30,

        -- 拐点检测角度(度): 车辆急转弯角度通常在90-120度
        cornerAngleThreshold = 90,

        -- 最小转弯半径(米): 车辆最小转弯半径通常在5-10米
        minTurnRadius = 5,
    },

    -- 是否启用拐点补偿
    enableCornerCompensate = true,

    -- 自适应场景: true表示根据当前速度自动判断是人员还是车辆
    -- false表示使用固定的scene配置
    autoAdaptive = true,

    -- 自适应速度阈值(km/h): 低于此值认为是人员,高于此值认为是车辆
    adaptiveSpeedThreshold = 15,
}

local function logF(...)
    if logSwitch then
        log.info(moduleName, logPrefix, ...)
    end
end

-- 获取当前使用的配置参数
local function getCurrentParams()
    if config.autoAdaptive then
        -- 根据最近历史数据的速度判断场景
        if #historyBuffer > 0 then
            local avgSpeed = 0
            local count = 0
            for i = math.max(1, #historyBuffer - 2), #historyBuffer do
                avgSpeed = avgSpeed + (historyBuffer[i].speed or 0)
                count = count + 1
            end
            avgSpeed = avgSpeed / count

            if avgSpeed >= config.adaptiveSpeedThreshold then
                logF("自适应场景判断: 当前平均速度", avgSpeed, "km/h → 使用车辆参数")
                return config.vehicleParams
            else
                logF("自适应场景判断: 当前平均速度", avgSpeed, "km/h → 使用人员参数")
                return config.personParams
            end
        end
    end

    -- 固定场景
    if config.scene == "vehicle" then
        return config.vehicleParams
    else
        return config.personParams
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
local function smoothCourse(currentCourse, params)
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

    if diff > params.courseChangeThreshold then
        logF("航向跳变补偿", currentCourse, "→", avgCourse, "差值:", diff, "阈值:", params.courseChangeThreshold)
        return avgCourse
    end

    return currentCourse
end

-- 速度平滑处理
local function smoothSpeed(currentSpeed, distance, timeDiff, params)
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
    if speedDiff > params.speedChangeThreshold and calcSpeed > 0 then
        logF("速度突变补偿", currentSpeed, "→", calcSpeed, "差值:", speedDiff, "阈值:", params.speedChangeThreshold)
        return calcSpeed
    end

    return currentSpeed
end

-- 拐点补偿算法
local function compensateCorner(lat, lng, course, speed, params)
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
    if angleDiff > params.cornerAngleThreshold and config.enableCornerCompensate then
        -- 计算预估位置（基于速度和航向）
        local estimatedLat, estimatedLng

        -- 根据场景调整最小速度阈值
        local minSpeed = 3
        if config.scene == "person" then
            minSpeed = 2  -- 人员低速移动也要补偿
        else
            minSpeed = 5  -- 车辆需要一定速度
        end

        if speed > minSpeed then
            local timeDiff = 3  -- 假设3秒间隔
            local distance = (speed / 3.6) * timeDiff  -- km/h → m/s

            -- 沿当前航向预估位置
            estimatedLat = lat + (distance / 6371000) * math.cos(math.rad(bearing2))
            estimatedLng = lng + (distance / 6371000) * math.sin(math.rad(bearing2)) / math.cos(math.rad(lat))

            -- 检查预估位置与原始位置的距离
            local diff = calculateDistance(lat, lng, estimatedLat, estimatedLng)
            if diff < params.distanceThreshold then
                logF("拐点补偿", lat, lng, "→", estimatedLat, estimatedLng, "角度:", angleDiff, "阈值:", params.cornerAngleThreshold)
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

    -- 获取当前场景的参数
    local params = getCurrentParams()

    logF("========== 轨迹补偿开始 ==========")
    logF("使用场景:", config.scene, "自适应:", config.autoAdaptive)
    logF("参数配置:", "距离阈值:", params.distanceThreshold, "速度突变阈值:", params.speedChangeThreshold, "航向阈值:", params.courseChangeThreshold)
    logF("输入参数", "纬度:", lat, "经度:", lng, "航向:", course, "速度:", speed)
    logF("历史数据量:", #historyBuffer)

    -- 无效数据直接返回
    if lat == 0 or lng == 0 then
        logF("无效数据，直接返回")
        return lat, lng, course, speed
    end

    -- 速度为0时不进行轨迹补偿,直接返回原始数据
    -- 避免速度为0时误判为漂移
    if speed == 0 then
        logF("速度为0,跳过轨迹补偿,直接返回原始数据")
        return lat, lng, course, speed
    end

    local resultLat = lat
    local resultLng = lng
    local resultCourse = course
    local resultSpeed = speed

    -- 计算与上一个点的距离
    local distance = 0
    local timeDiff = 0
    local last = nil
    if #historyBuffer > 0 then
        last = historyBuffer[#historyBuffer]
        distance = calculateDistance(last.lat, last.lng, lat, lng)
        timeDiff = os.time() - last.time

        logF("与上点距离:", distance, "米", "时间差:", timeDiff, "秒", "速度:", speed)
    end

    -- 速度平滑（仅当有历史数据时）
    if #historyBuffer > 0 then
        resultSpeed = smoothSpeed(speed, distance, timeDiff, params)
        logF("速度平滑", "原始:", speed, "→", "结果:", resultSpeed)
    end

    -- 航向平滑
    resultCourse = smoothCourse(course, params)
    logF("航向平滑", "原始:", course, "→", "结果:", resultCourse)

    -- 拐点补偿
    if config.enableCornerCompensate then
        resultLat, resultLng, resultCourse = compensateCorner(lat, lng, resultCourse, resultSpeed, params)
        logF("拐点补偿后位置", resultLat, resultLng)
    end

    -- 只有速度为0（静止状态）时，才进行漂移检测
    -- 运动状态下不进行漂移过滤，所有点都正常记录
    if speed == 0 and last and distance > params.distanceThreshold then
        logF("静止漂移警告：距离:", distance, "米", "阈值:", params.distanceThreshold, "米")
        logF("过滤静态漂移点，返回历史位置", last.lat, last.lng)
        -- 过滤掉漂移点，返回历史最后位置
        resultLat = last.lat
        resultLng = last.lng
        -- 注意：不添加到缓存，避免重复
        addHistory(resultLat, resultLng, resultCourse, resultSpeed)
        logF("添加到历史缓存，当前历史数量:", #historyBuffer)
        logF("补偿结果", lat, lng, "→", resultLat, resultLng)
        logF("========== 轨迹补偿结束 ==========")
        return resultLat, resultLng, resultCourse, resultSpeed
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

    -- 设置场景
    if cfg.scene then
        config.scene = cfg.scene
        logF("场景设置为:", cfg.scene)
    end

    -- 设置自适应模式
    if cfg.autoAdaptive ~= nil then
        config.autoAdaptive = cfg.autoAdaptive
        logF("自适应模式设置为:", cfg.autoAdaptive)
    end

    -- 设置自适应速度阈值
    if cfg.adaptiveSpeedThreshold then
        config.adaptiveSpeedThreshold = cfg.adaptiveSpeedThreshold
        logF("自适应速度阈值设置为:", cfg.adaptiveSpeedThreshold)
    end

    -- 设置人员参数
    if cfg.personParams then
        if cfg.personParams.distanceThreshold then
            config.personParams.distanceThreshold = cfg.personParams.distanceThreshold
        end
        if cfg.personParams.speedChangeThreshold then
            config.personParams.speedChangeThreshold = cfg.personParams.speedChangeThreshold
        end
        if cfg.personParams.courseChangeThreshold then
            config.personParams.courseChangeThreshold = cfg.personParams.courseChangeThreshold
        end
        if cfg.personParams.cornerAngleThreshold then
            config.personParams.cornerAngleThreshold = cfg.personParams.cornerAngleThreshold
        end
        if cfg.personParams.minTurnRadius then
            config.personParams.minTurnRadius = cfg.personParams.minTurnRadius
        end
        logF("人员参数更新:", json.encode(config.personParams))
    end

    -- 设置车辆参数
    if cfg.vehicleParams then
        if cfg.vehicleParams.distanceThreshold then
            config.vehicleParams.distanceThreshold = cfg.vehicleParams.distanceThreshold
        end
        if cfg.vehicleParams.speedChangeThreshold then
            config.vehicleParams.speedChangeThreshold = cfg.vehicleParams.speedChangeThreshold
        end
        if cfg.vehicleParams.courseChangeThreshold then
            config.vehicleParams.courseChangeThreshold = cfg.vehicleParams.courseChangeThreshold
        end
        if cfg.vehicleParams.cornerAngleThreshold then
            config.vehicleParams.cornerAngleThreshold = cfg.vehicleParams.cornerAngleThreshold
        end
        if cfg.vehicleParams.minTurnRadius then
            config.vehicleParams.minTurnRadius = cfg.vehicleParams.minTurnRadius
        end
        logF("车辆参数更新:", json.encode(config.vehicleParams))
    end

    -- 启用/禁用拐点补偿
    if cfg.enableCornerCompensate ~= nil then
        config.enableCornerCompensate = cfg.enableCornerCompensate
        logF("拐点补偿设置为:", cfg.enableCornerCompensate)
    end

    logF("配置更新完成")
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
