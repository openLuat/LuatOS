-- 模块名称和日志开关
local moduleName = "common"
local logSwitch = true

-- 引入依赖模块
local trackCompensate = require "trackCompensate"  -- 轨迹补偿模块，用于平滑GPS轨迹
local exgnss = require "exgnss"                 -- GNSS扩展库，统一管理GNSS生命周期

-- 配置exgnss参数
-- gnssmode: 1为卫星全定位(GPS+北斗)，2为单北斗
-- agps_enable: 启用AGPS辅助定位，加速首次定位
-- debug: 是否输出exgnss调试信息
-- hz: 定位频率，1表示1Hz即每秒定位一次
exgnss.setup({
    gnssmode = 1,       -- 1为卫星全定位，2为单北斗
    agps_enable = true, -- 启用AGPS
    debug = true,       -- 是否输出调试信息
    hz = 1,            -- 定位频率1Hz
})

-- 本地日志输出函数
local function logF(...)
    if logSwitch then
        log.info(moduleName, ...)
    end
end

-- 模块导出表
local common = {}

-- GNSS工作模式：CAPTURE(捕获定位), TRACKING(追踪定位), STATIC_LBS(LBS静止), STATIC_GNSS(GNSS静止)
-- local mode = "CAPTURE"  -- 默认为捕获模式
local mode = "STATIC_GNSS"  -- 当前设置为GNSS静止模式

-- 保存上一次的GPS位置信息
-- 包含：经纬度、经纬度类型(E/W, N/S)、定位状态
local lastGPSLocation

-- exgnss应用标签，用于引用计数管理
-- 使用独立的标签可以避免与其他模块的GNSS应用冲突
local gnssAppTag = "common_app"

-- JT808协议0x0200位置信息报文的状态位定义
local STATE_BIT_LOCAT = 0x02  -- bit1: 定位状态，1表示已定位，0表示未定位
local STATE_BIT_NS = 0x04      -- bit2: 南北纬标识，1表示南纬，0表示北纬
local STATE_BIT_EW = 0x08      -- bit3: 东西经标识，1表示西经，0表示东经


-- 编码基站信息为JT808协议格式
-- @param s 基站信息数组，包含mcc/mnc/tac/cid等字段
-- @return boolean, string 成功返回true和编码后的字符串，失败返回false
local function enCellInfo(s)
    if not s or #s <= 0 then
        return false
    end
    logF("enCellInfo", #s)
    local ret = "" .. api.NumToBigBin(1, 1)  -- 基站数量
    -- 编码基站详细信息：MCC(移动国家码,2字节) + MNC(移动网络码,1字节) + TAC(跟踪区码,2字节) + CID(小区ID,4字节) + 保留(1字节)
    ret = ret .. api.NumToBigBin(s[1].mcc, 2) .. api.NumToBigBin(s[1].mnc, 1) .. api.NumToBigBin(s[1].tac, 2) .. api.NumToBigBin(s[1].cid, 4) .. api.NumToBigBin(31, 1)
    return true, ret
end

-- 获取当前GNSS工作模式对应的数值编码
-- @return number 模式编码：1=CAPTURE, 2=STATIC_GNSS, 4=STATIC_LBS, 8=TRACKING
local function getMode()
    local result = 0
    if mode == "STATIC_LBS" then
        result = 4
    elseif mode == "STATIC_GNSS" then
        result = 2
    elseif mode == "CAPTURE" then
        result = 1
    elseif mode == "TRACKING" then
        result = 8
    end
    return result
end

-- 客户端位置信息打包函数
-- 获取当前位置信息并打包成JT808协议格式
-- 优先级：GNSS定位 > 上次GPS位置 > 基站定位
-- 包含经纬度、速度、航向、高度、时间、卫星信息、电池信息、WiFi信息、基站信息等
-- @return string JT808格式的位置信息字符串
function common.monitorRecord()

    -- 初始化lastGPSLocation表
    if lastGPSLocation == nil then
        lastGPSLocation = {}
        lastGPSLocation.lngType = "E"      -- 默认东经
        lastGPSLocation.lng = 0
        lastGPSLocation.latType = "N"      -- 默认北纬
        lastGPSLocation.lat = 0
        lastGPSLocation.isFix = 0          -- 0表示未定位，1表示已定位
    end

    local lat, lng
    local speed, totalStats, course, altitude = 0, 0, 0, 0
    log.info("位置坐标打包", exgnss.is_active(exgnss.DEFAULT, {tag = gnssAppTag}) and exgnss.is_fix(), lastGPSLocation.lng, lastGPSLocation.lat)

    -- 情况1: GNSS已打开且已定位，使用GNSS数据
    if exgnss.is_active(exgnss.DEFAULT, {tag = gnssAppTag}) and exgnss.is_fix() then
        local data = exgnss.rmc(2)    -- 获取RMC数据，参数2表示最近2秒内的数据
        local gga = exgnss.gga(2)    -- 获取GGA数据，包含高度信息
        local vtg = exgnss.vtg()     -- 获取VTG数据，包含速度和航向
        if data and data.valid then
            -- 从VTG获取速度(km/h)
            speed = math.floor((vtg and vtg.speed_kph or 0))
            -- 从RMC获取航向(度)
            course = math.floor(data.course or 0)
            -- 从GGA获取高度(米)
            if gga then
                altitude = gga.altitude or 0
            end
            -- 标记为已定位
            lastGPSLocation.isFix = 1
            -- 判断经纬度类型：正值表示东经/北纬，负值表示西经/南纬
            lastGPSLocation.lngType = data.lng > 0 and "E" or "W"
            lastGPSLocation.latType = data.lat > 0 and "N" or "S"
            -- exgnss返回的是浮点数经纬度(度)，JT808需要整数格式(度*1000000)
            lng = math.floor(data.lng * 1000000)
            lat = math.floor(data.lat * 1000000)
            -- 如果经纬度为0，使用上次的位置
            if (not lng or lng == 0) or (not lat or lat == 0) then
                lng = lastGPSLocation.lng
                lat = lastGPSLocation.lat
                lastGPSLocation.isFix = 0
            end
        end

        -- 轨迹补偿：平滑航向、速度，处理拐点
        -- 减少GPS漂移导致的轨迹抖动
        local compensatedLat, compensatedLng, compensatedCourse, compensatedSpeed =
            trackCompensate.compensate(lat, lng, course, speed)
        if compensatedLat and compensatedLng and compensatedLat ~= 0 and compensatedLng ~= 0 then
            lat = compensatedLat
            lng = compensatedLng
            course = compensatedCourse
            speed = compensatedSpeed
        end

        logF("本次位置汇报使用GPS定位数据(已补偿)", lat, lng)

    -- 情况2: GNSS未定位但有上次GPS位置，使用上次位置
    elseif lastGPSLocation.lng ~= 0 and lastGPSLocation.lat ~= 0 then
        logF("use last gps")
        lat = lastGPSLocation.lat
        lng = lastGPSLocation.lng
        logF("本次位置汇报使用上次定位数据")
        lastGPSLocation.isFix = 0  -- 标记为未定位

    -- 情况3: 没有GNSS数据也没有上次位置，使用基站定位
    else
        logF("use lbs")
        lastGPSLocation.isFix = 0
        logF("本次位置汇报使用基站定位数据")
        lat = 0  -- 基站定位的经纬度由服务器端计算
        lng = 0
    end

    -- 更新lastGPSLocation
    if lng ~= nil and lat ~= nil then
        lastGPSLocation.lng = lng
        lastGPSLocation.lat = lat
    else
        logF(moduleName, "no location")
        logF("本次位置汇报没有定位数据")
    end

    -- 获取当前时间并转换为BCD格式
    local tTime = os.date("*t", os.time())
    local status = 0
    -- 设置定位状态位
    if lastGPSLocation.isFix > 0 then
        status = status + STATE_BIT_LOCAT
    end
    -- 设置南纬位
    if lastGPSLocation.latType == "S" then
        status = status + STATE_BIT_NS
    end
    -- 设置西经位
    if lastGPSLocation.lngType == "W" then
        status = status + STATE_BIT_EW
    end

    -- 时间转换为BCD格式：年月日时分秒
    tTime = api.NumToBCDBin(tTime.year % 100, 1) .. api.NumToBCDBin(tTime.month, 1) .. api.NumToBCDBin(tTime.day, 1) .. api.NumToBCDBin(tTime.hour, 1) .. api.NumToBCDBin(tTime.min, 1) .. api.NumToBCDBin(tTime.sec, 1)

    -- 构建JT808基础定位信息包
    local baseInfo = jt808.makeLocatBaseInfoMsg(0, status, lat, lng, math.floor(altitude), speed, course, tTime)

    -- 添加卫星信号强度信息(0x65附件)
    -- logF("位置上报", "GPS状态", exgnss.is_active(exgnss.DEFAULT, {tag = gnssAppTag}), json.encode(exgnss.gsv() or {}))
    if exgnss.is_active(exgnss.DEFAULT, {tag = gnssAppTag}) then
        local tmp = {}
        local gsv = exgnss.gsv()  -- 获取卫星信息
        if gsv then
            if gsv.total_sats > 0 then
                -- 收集所有有效卫星的信号强度(SNR)
                for i = 1, gsv.total_sats do
                    if gsv.sats[i].snr and gsv.sats[i].snr ~= 0 then
                        table.insert(tmp, gsv.sats[i].snr)
                    end
                end
                -- 按信号强度降序排序
                table.sort(tmp, function(a, b)
                    return a > b
                end)
                totalStats = #tmp
                log.info("GNSS", "可见卫星数量", totalStats, json.encode(tmp))
                -- 添加0x65附件：卫星信号强度
                baseInfo = baseInfo .. api.NumToBigBin(0x65, 1)  -- 附件ID
                baseInfo = baseInfo .. api.NumToBigBin((#tmp > 3 and 3 or #tmp), 1)  -- 卫星数量(最多3个)
                for i = 1, (#tmp > 3 and 3 or #tmp) do
                    baseInfo = baseInfo .. api.NumToBigBin(tmp[i], 1)  -- 信号强度
                end
            end
        end
    else
        log.info("位置上报", "GPS处于关闭状态")
    end

    -- 添加里程信息(0x01附件)
    baseInfo = baseInfo .. api.NumToBigBin(0x01, 1) .. api.NumToBigBin(4, 1) .. api.NumToBigBin(0, 4) -- 01 里程 4byte

    -- 添加充电状态和电量信息(0x04附件)
    baseInfo = baseInfo .. api.NumToBigBin(0x04, 1) .. api.NumToBigBin(2, 1) .. api.NumToBigBin(charge.isCharge() and 0 or 1, 1) .. api.NumToBigBin(charge.getBatteryPercent(), 1) -- 04 充电状态,电量百分比 2 byte     0 充电，  1 未充电

    -- 添加电池电压信息(0x2B附件)
    baseInfo = baseInfo .. api.NumToBigBin(0x2B, 1) .. api.NumToBigBin(4, 1) .. api.NumToBigBin(charge.getVbat(), 2) .. api.NumToBigBin(0, 2) -- 2B 电池电压 4byte mv

    -- 添加信号强度信息(0x30附件)
    baseInfo = baseInfo .. api.NumToBigBin(0x30, 1) .. api.NumToBigBin(1, 1) .. api.NumToBigBin(mobile.csq(), 1) -- 30 信号强度 1byte

    -- 添加卫星个数信息(0x31附件)
    baseInfo = baseInfo .. api.NumToBigBin(0x31, 1) .. api.NumToBigBin(1, 1) .. api.NumToBigBin(totalStats, 1) -- 31 卫星个数 1byte

    -- 添加崩溃日志级别信息(0x5F附件)
    baseInfo = baseInfo .. api.NumToBigBin(0x5F, 1) .. api.NumToBigBin(8, 1) .. manage.getLastCrashLevel()

    -- 添加GNSS工作模式信息(0x64附件)
    baseInfo = baseInfo .. api.NumToBigBin(0x64, 1) .. api.NumToBigBin(1, 1) .. api.NumToBigBin(getMode(), 1)

    -- 添加WiFi信息(0x54附件)
    local results = wlan.scanResult()
    logF("wifi.scan", "results", results and #results or 0)
    if results and #results > 3 then
        baseInfo = baseInfo .. api.NumToBigBin(0x54, 1)  -- WiFi附件ID
        if #results >= 6 then
            -- 最多上报6个WiFi热点
            baseInfo = baseInfo .. api.NumToBigBin((6 * 7) + 1, 1) .. api.NumToBigBin(6, 1)  -- 6个WiFi * (6字节BSSID + 1字节RSSI) + 1字节计数
            for i = 1, 6 do
                baseInfo = baseInfo .. api.StrToBin(results[i]["bssid"]:toHex(), 6) .. api.NumToBigBin(results[i]["rssi"] + 255, 1)
            end
        else
            baseInfo = baseInfo .. api.NumToBigBin((#results * 7) + 1, 1) .. api.NumToBigBin(#results, 1)
            for i = 1, #results do
                baseInfo = baseInfo .. api.StrToBin(results[i]["bssid"]:toHex(), 6) .. api.NumToBigBin(results[i]["rssi"] + 255, 1)
            end
        end
    end

    -- 添加基站信息(0x5D附件)
    local result, lbs = enCellInfo({mobile.scell()})
    if result then
        baseInfo = baseInfo .. api.NumToBigBin(0x5D, 1) .. api.NumToBigBin(#lbs, 1) .. lbs
    end

    -- 添加代码软件版本号(0x66附件)
    local bspVer = rtos.version():sub(2)  -- BSP版本
    local x, y, z = string.match(_G.VERSION, "(%d+).(%d+).(%d+)")  -- 应用版本
    baseInfo = baseInfo .. api.NumToBigBin(0x66, 1) .. api.NumToBigBin(4, 1) .. api.StrToBin(bspVer, 2) ..api.StrToBin(x, 1)..api.StrToBin(z, 1)

    -- 添加GNSS软件版本号(0x67附件)
    -- exgnss暂时没有获取GNSS版本号的接口 Air8000也不需要，使用0作为占位
    baseInfo = baseInfo .. api.NumToBigBin(0x67, 1) .. api.NumToBigBin(2, 1) .. api.NumToBigBin(0, 2)

    return baseInfo
end

-- 获取当前GNSS工作模式
-- @return string 当前模式：CAPTURE/TRACKING/STATIC_LBS/STATIC_GNSS
function common.getNowMode()
    return mode
end

-- 快速上传模式开关
local fastUpload = false

-- 数据缓存队列，用于批量上传
local dataCache = {}

-- 等待上传次数计数器，每采集30次上传一次
local waitUploadTimes = 0

-- 上传缓存中的所有数据
-- 清空dataCache队列并逐个发送
local function uploadCache()
    waitUploadTimes = 0
    while 1 do
        if #dataCache <= 0 then
            break
        end
        local data = table.remove(dataCache, 1)
        srvs.dataSend(data)
    end
end

-- 退出快速上传模式的回调函数
-- 由定时器触发，自动关闭快速上传模式
local function exitFastUploadMode()
    fastUpload = false
    log.info("common", "定时器时间到, 退出快速上传模式")
end

-- 设置快速上传模式
-- @param time 快速上传持续时间(分钟)，0表示退出快速上传模式
-- 正常模式：每5分钟上传一次
-- 快速模式：每3秒上传一次
function common.setfastUpload(time)
    if mode ~= "TRACKING" then
        log.warn("common", "当前不是跟踪模式,但设置快速上传", mode)
        -- return
    end
    uploadCache()  -- 先上传缓存中的数据
    if time == 0 then
        log.info("common", "退出快速上传模式")
        fastUpload = false
        sys.timerStop(exitFastUploadMode)
    else
        log.info("common", "进入快速上传模式,时间: %d分钟", time)
        fastUpload = true
        -- 修改上报周期时, 立即触发一条,并触发系统状态变化
        srvs.dataSend()
        if mreport then
            mreport.send()
        end
        sys.publish("SYS_STATUS_RUN")
        -- 启动定时器，time分钟后自动退出快速上传模式
        sys.timerStart(exitFastUploadMode, time * 60 * 1000)
    end
end

-- 主任务：GNSS定位状态机
-- 管理4种工作模式的切换：CAPTURE -> TRACKING -> STATIC_GNSS/STATIC_LBS -> CAPTURE
sys.taskInit(function()
    local result, firstCapture = nil, true  -- firstCapture: 首次捕获标志

    -- 等待时间同步成功
    while not netWork.timeSync() do
        sys.wait(1000)
    end

    -- AGPS已集成到exgnss中，无需手动调用

    -- 主循环
    while true do
        uploadCache()  -- 上传缓存中的数据

        -- ==================== CAPTURE模式：捕获定位 ====================
        -- 目标：等待GNSS定位成功，进入TRACKING模式
        if mode == "CAPTURE" then
            wlan.scan()  -- 扫描WiFi，用于辅助定位
            local times = 0
            log.info("common", "真正打开GNSS，模式: CAPTURE, 标签:", gnssAppTag)
            exgnss.open(exgnss.DEFAULT, {tag = gnssAppTag})  -- 打开GNSS

            while true do
                srvs.dataSend()  -- 发送数据

                -- 检查是否定位成功
                if exgnss.is_fix() then
                    mode = "TRACKING"  -- 切换到追踪模式
                    firstCapture = false
                    break
                end

                -- 等待GNSS状态事件，最长30秒
                result = sys.waitUntil("GNSS_STATE", 30 * 1000)
                if result == "FIXED" then
                    mode = "TRACKING"  -- 定位成功，切换到追踪模式
                    firstCapture = false
                    break
                end

                times = times + 1

                -- 判定是否切换到STATIC_LBS模式
                -- 首次捕获最多尝试10次，之后最多尝试4次
                -- 如果4次未定位且当前静止，切换到LBS定位模式
                if times >= (firstCapture and 10 or 4) then
                    firstCapture = false
                    if not manage.isRun() then
                        mode = "STATIC_LBS"  -- 切换到LBS静止模式
                        break
                    end
                    times = 0  -- 继续尝试定位
                end
            end

        -- ==================== TRACKING模式：追踪定位 ====================
        -- 目标：持续追踪定位，直到定位丢失或检测到静止
        elseif mode == "TRACKING" then
            manage.wake("READ_GNSS_DATA")  -- 唤醒读取GNSS数据
            sys.wait(2000)  -- 等待2秒，确保读到NMEA数据
            srvs.dataSend()  -- 发送数据
            manage.sleep("READ_GNSS_DATA")

            while true do
                -- 检查定位状态
                if not exgnss.is_fix() then
                    mode = "CAPTURE"  -- 定位丢失，切换到捕获模式
                    break
                end

                manage.wake("READ_GNSS_DATA")
                result = sys.waitUntil("GNSS_STATE", 3000)  -- 等待3秒，确保读到NMEA数据，但这期间有可能丢失定位
                if result == "LOSE" then
                    manage.sleep("READ_GNSS_DATA")
                    mode = "CAPTURE"  -- 定位丢失，切换到捕获模式
                    break
                end

                -- 处理数据上传
                if fastUpload then
                    -- 快速上传模式：立即上传
                    srvs.dataSend()
                else
                    -- 正常模式：缓存数据，每30次上传一次(约5分钟)
                    if #dataCache > 60 then
                        -- 缓存超过60条，删除最旧的
                        local item = table.remove(dataCache, 1)
                        item:free()
                    end
                    local item = zbuff.create(200)
                    item:copy(nil, common.monitorRecord())
                    table.insert(dataCache, item)
                    waitUploadTimes = waitUploadTimes + 1

                    -- 每30次上传一次
                    if waitUploadTimes >= 30 then
                        uploadCache()
                    end
                end

                manage.sleep("READ_GNSS_DATA")
                result = sys.waitUntil("GNSS_STATE", 7000)

                if result == "LOSE" then
                    mode = "CAPTURE"  -- 定位丢失，切换到捕获模式
                    break
                end

                -- 检测到静止，关闭GNSS进入STATIC_GNSS模式
                -- 此时lastGPSLocation已在monitorRecord中更新
                if not manage.isRun() then
                    log.info("common", "检测到静止，关闭GNSS进入STATIC_GNSS")
                    mode = "STATIC_GNSS"
                    break
                end
            end

        -- ==================== STATIC_LBS模式：LBS静止 ====================
        -- 目标：关闭GNSS，使用LBS定位，定期上传数据
        elseif mode == "STATIC_LBS" then
            manage.sleep("READ_GNSS_DATA")
            exgnss.close(exgnss.DEFAULT, {tag = gnssAppTag})  -- 关闭GNSS
            lastGPSLocation.lat = 0
            lastGPSLocation.lng = 0

            -- 循环等待运动检测
            while not manage.isRun() do
                srvs.dataSend()  -- 定期上传数据
                -- 等待运动事件，最长20分钟
                if sys.waitUntil("SYS_STATUS_RUN", 20 * 60 * 1000) then
                    mode = "CAPTURE"  -- 检测到运动，切换到捕获模式
                    break
                end
            end

        -- ==================== STATIC_GNSS模式：GNSS静止 ====================
        -- 目标：关闭GNSS，定期上传上次定位数据
        elseif mode == "STATIC_GNSS" then
            manage.sleep("READ_GNSS_DATA")
            exgnss.close(exgnss.DEFAULT, {tag = gnssAppTag})  -- 关闭GNSS

            -- 循环等待运动检测
            while not manage.isRun() do
                log.info("common", "STATIC_GNSS循环, isRun:", manage.isRun())
                srvs.dataSend()  -- 定期上传数据
                -- 等待运动事件，最长20分钟
                if sys.waitUntil("SYS_STATUS_RUN", 20 * 60 * 1000) then
                    mode = "CAPTURE"  -- 检测到运动，切换到捕获模式
                    break
                end
                sys.wait(5000)  -- 等待5秒,避免频繁调用
            end

            -- 循环退出说明检测到运动,切换到CAPTURE模式
            if manage.isRun() then
                log.info("common", "检测到运动,退出STATIC_GNSS模式,进入CAPTURE")
                mode = "CAPTURE"
            end
        end

        -- 这里应该稍微等一下，防止异常情况
        sys.wait(500)
    end
end)

return common
