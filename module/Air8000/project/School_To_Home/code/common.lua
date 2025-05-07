local moduleName = "common"
local logSwitch = true
local function logF(...)
    if logSwitch then
        log.info(moduleName, ...)
    end
end

local common = {}

local mode = "CAPTURE"
local lastGPSLocation

-- 0200 状态位定义
-- 定位状态bit1
local STATE_BIT_LOCAT = 0x02
-- 是否南纬bit2
local STATE_BIT_NS = 0x04
-- 是否西经bit3
local STATE_BIT_EW = 0x08


local function enCellInfo(s)
    if not s or #s <= 0 then
        return false
    end
    logF("enCellInfo", #s)
    local ret = "" .. api.NumToBigBin(1, 1)
    ret = ret .. api.NumToBigBin(s[1].mcc, 2) .. api.NumToBigBin(s[1].mnc, 1) .. api.NumToBigBin(s[1].tac, 2) .. api.NumToBigBin(s[1].cid, 4) .. api.NumToBigBin(31, 1)
    return true, ret
end

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

-- 客户端位置信息打包
function common.monitorRecord()

    if lastGPSLocation == nil then
        lastGPSLocation = {}
        lastGPSLocation.lngType = "E"
        lastGPSLocation.lng = 0
        lastGPSLocation.latType = "N"
        lastGPSLocation.lat = 0
        lastGPSLocation.isFix = 0
    end

    local lat, lng
    local speed, totalStats, course, altitude = 0, 0, 0, 0
    log.info("位置坐标打包", gnss.isOpen() and gnss.isFix(), lastGPSLocation.lng, lastGPSLocation.lat)
    if gnss.isOpen() and gnss.isFix() then
        local item = libgnss.getRmc(3)
        local data = libgnss.getRmc(2)
        -- logF("test", item)
        local _1, fix, _2, latTyp, _3, lngTyp, spd, course2, _4 = string.match(item, "RMC,(%d%d%d%d%d%d)%.%d+,(%w),(%d*%.*%d*),([NS]*),(%d*%.*%d*),([EW]*),(.-),(.-),(%d%d%d%d%d%d),")
        speed = math.floor((api.FloatToNum(spd, 3) * 1.852) / 100)
        -- log.info("当前速度", "speed", spd, speed, api.FloatToNum(spd, 3))
        local gga = libgnss.getGga(2)
        if gga then
            altitude = gga.altitude
        end
        if course2 and tonumber(course2) then
            course = math.floor(tonumber(course2) or 0)
        end
        lastGPSLocation.isFix = 1
        lastGPSLocation.lngType = lngTyp
        lng = api.FloatToNum(string.format("%6f", data.lng), 6)
        lastGPSLocation.latType = latTyp
        lat = api.FloatToNum(string.format("%6f", data.lat), 6)
        if (not lng or lng == 0) or (not lat or lat == 0) then
            lng = lastGPSLocation.lng
            lat = lastGPSLocation.lat
            lastGPSLocation.isFix = 0
        end
        logF("本次位置汇报使用GPS定位数据", lat, lng)
    elseif lastGPSLocation.lng ~= 0 and lastGPSLocation.lat ~= 0 then
        logF("use last gps")
        lat = lastGPSLocation.lat
        lng = lastGPSLocation.lng
        logF("本次位置汇报使用上次定位数据")
        lastGPSLocation.isFix = 0
    else
        logF("use lbs")
        lastGPSLocation.isFix = 0
        logF("本次位置汇报使用基站定位数据")
        lat = 0
        lng = 0
    end
    if lng ~= nil and lat ~= nil then
        lastGPSLocation.lng = lng
        lastGPSLocation.lat = lat
    else
        logF(moduleName, "no location")
        logF("本次位置汇报没有定位数据")
    end
    local tTime = os.date("*t", os.time())
    local status = 0
    if lastGPSLocation.isFix > 0 then
        status = status + STATE_BIT_LOCAT
    end
    if lastGPSLocation.latType == "S" then
        status = status + STATE_BIT_NS
    end
    if lastGPSLocation.lngType == "W" then
        status = status + STATE_BIT_EW
    end

    tTime = api.NumToBCDBin(tTime.year % 100, 1) .. api.NumToBCDBin(tTime.month, 1) .. api.NumToBCDBin(tTime.day, 1) .. api.NumToBCDBin(tTime.hour, 1) .. api.NumToBCDBin(tTime.min, 1) .. api.NumToBCDBin(tTime.sec, 1)
    local baseInfo = jt808.makeLocatBaseInfoMsg(0, status, lat, lng, math.floor(altitude), speed, course, tTime)
    -- logF("位置上报", "GPS状态", gnss.isOpen(), json.encode(libgnss.getGsv() or {}))
    if gnss.isOpen() then
        local tmp = {}
        local gsv = libgnss.getGsv()
        if gsv then
            if gsv.total_sats > 0 then
                for i = 1, gsv.total_sats do
                    if gsv.sats[i].snr and gsv.sats[i].snr ~= 0 then
                        table.insert(tmp, gsv.sats[i].snr)
                    end
                end
                table.sort(tmp, function(a, b)
                    return a > b
                end)
                totalStats = #tmp
                log.info("GNSS", "可见卫星数量", totalStats, json.encode(tmp))
                baseInfo = baseInfo .. api.NumToBigBin(0x65, 1)
                baseInfo = baseInfo .. api.NumToBigBin((#tmp > 3 and 3 or #tmp), 1)
                for i = 1, (#tmp > 3 and 3 or #tmp) do
                    baseInfo = baseInfo .. api.NumToBigBin(tmp[i], 1)
                end
            end
        end
    else
        log.info("位置上报", "GPS处于关闭状态")
    end
    baseInfo = baseInfo .. api.NumToBigBin(0x01, 1) .. api.NumToBigBin(4, 1) .. api.NumToBigBin(0, 4) -- 01 里程 4byte
    baseInfo = baseInfo .. api.NumToBigBin(0x04, 1) .. api.NumToBigBin(2, 1) .. api.NumToBigBin(charge.isCharge() and 0 or 1, 1) .. api.NumToBigBin(charge.getBatteryPercent(), 1) -- 04 充电状态,电量百分比 2 byte     0 充电，  1 未充电
    baseInfo = baseInfo .. api.NumToBigBin(0x2B, 1) .. api.NumToBigBin(4, 1) .. api.NumToBigBin(charge.getVbat(), 2) .. api.NumToBigBin(0, 2) -- 2B 电池电压 4byte mv
    baseInfo = baseInfo .. api.NumToBigBin(0x30, 1) .. api.NumToBigBin(1, 1) .. api.NumToBigBin(mobile.csq(), 1) -- 30 信号强度 1byte
    baseInfo = baseInfo .. api.NumToBigBin(0x31, 1) .. api.NumToBigBin(1, 1) .. api.NumToBigBin(totalStats, 1) -- 31 卫星个数 1byte
    baseInfo = baseInfo .. api.NumToBigBin(0x5F, 1) .. api.NumToBigBin(8, 1) .. manage.getLastCrashLevel()
    baseInfo = baseInfo .. api.NumToBigBin(0x64, 1) .. api.NumToBigBin(1, 1) .. api.NumToBigBin(getMode(), 1)

    local results = wlan.scanResult()
    logF("wifi.scan", "results", results and #results or 0)
    if results and #results > 3 then
        baseInfo = baseInfo .. api.NumToBigBin(0x54, 1)
        if #results >= 6 then
            baseInfo = baseInfo .. api.NumToBigBin((6 * 7) + 1, 1) .. api.NumToBigBin(6, 1)
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
    local result, lbs = enCellInfo({mobile.scell()})
    if result then
        baseInfo = baseInfo .. api.NumToBigBin(0x5D, 1) .. api.NumToBigBin(#lbs, 1) .. lbs
    end
    
    -- 代码软件版本号
    local bspVer = rtos.version():sub(2)
    local x, y, z = string.match(_G.VERSION, "(%d+).(%d+).(%d+)")
    baseInfo = baseInfo .. api.NumToBigBin(0x66, 1) .. api.NumToBigBin(4, 1) .. api.StrToBin(bspVer, 2) ..api.StrToBin(x, 1)..api.StrToBin(z, 1) 
    
    -- GNSS软件版本号
    baseInfo = baseInfo .. api.NumToBigBin(0x67, 1) .. api.NumToBigBin(2, 1) .. api.NumToBigBin(gnss.getVer(), 2) 

    -- IPV6 地址
    local ip, _, _, ipv6 = socket.localIP()
    if ipv6 then
        if #ipv6 < 40 then
            ipv6 = ipv6.. string.rep("\0", 40 - #ipv6)
        end
        baseInfo = baseInfo .. api.NumToBigBin(0x69, 1) .. api.NumToBigBin(40, 1) .. ipv6
    end
    return baseInfo
end

function common.getNowMode()
    return mode
end

local fastUpload = false

local dataCache = {}

local waitUploadTimes = 0

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

local function exitFastUploadMode()
    fastUpload = false
    log.info("common", "定时器时间到, 退出快速上传模式")
end

function common.setfastUpload(time)
    if mode ~= "TRACKING" then
        log.warn("common", "当前不是跟踪模式,但设置快速上传", mode)
        -- return
    end
    uploadCache()
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
        sys.timerStart(exitFastUploadMode, time * 60 * 1000)
    end
end

sys.taskInit(function()
    local result, firstCapture = nil, true
    while not netWork.timeSync() do
        sys.wait(1000)
    end
    -- gnss.agps() -- 更新星历
    while true do
        uploadCache()
        if mode == "CAPTURE" then
            wlan.scan()
            local times = 0
            gnss.open("app")
            while true do
                srvs.dataSend()
                if gnss.isFix() then
                    mode = "TRACKING"
                    firstCapture = false
                    break
                end
                result = sys.waitUntil("GNSS_STATE_FIX", 30 * 1000)
                if result then
                    mode = "TRACKING"
                    firstCapture = false
                    break
                end
                times = times + 1
                if times >= (firstCapture and 10 or 4) then
                    firstCapture = false
                    if not manage.isRun() then
                        mode = "STATIC_LBS"
                        break
                    end
                    times = 0
                end
            end
        elseif mode == "TRACKING" then
            manage.wake("READ_GNSS_DATA")
            sys.wait(2000)
            srvs.dataSend()
            manage.sleep("READ_GNNS_DATA")
            local staticTrackTime = 0
            while true do
                if not gnss.isFix() then
                    mode = "CAPTURE"
                    break
                end
                manage.wake("READ_GNSS_DATA")
                result = sys.waitUntil("GNSS_STATE_LOSE", 3000) -- 唤醒后等待3秒，确保读到nmea数据，但这期间有可能丢失定位
                if result then
                    manage.sleep("READ_GNSS_DATA")
                    mode = "CAPTURE"
                    break
                end
                if fastUpload then
                    srvs.dataSend()
                else
                    if #dataCache > 60 then
                        local item = table.remove(dataCache, 1)
                        item:free()
                    end
                    local item = zbuff.create(200)
                    item:copy(nil, common.monitorRecord())
                    table.insert(dataCache, item)
                    waitUploadTimes = waitUploadTimes + 1
                    if waitUploadTimes >= 30 then
                        uploadCache()
                    end
                end
                manage.sleep("READ_GNSS_DATA")
                result = sys.waitUntil("GNSS_STATE_LOSE", 7000)
                if result then
                    mode = "CAPTURE"
                    break
                end
                if not manage.isRun() then
                    staticTrackTime = staticTrackTime + 1
                    if staticTrackTime >= 6 then
                        mode = "STATIC_GNSS"
                        break
                    end
                end
            end
        elseif mode == "STATIC_LBS" then
            manage.sleep("READ_GNSS_DATA")
            gnss.close("app")
            lastGPSLocation.lat = 0
            lastGPSLocation.lng = 0
            while not manage.isRun() do
                srvs.dataSend()
                if sys.waitUntil("SYS_STATUS_RUN", 20 * 60 * 1000) then
                    mode = "CAPTURE"
                    break
                end
            end
        elseif mode == "STATIC_GNSS" then
            manage.sleep("READ_GNSS_DATA")
            gnss.close("app")
            while not manage.isRun() do
                srvs.dataSend()
                if sys.waitUntil("SYS_STATUS_RUN", 20 * 60 * 1000) then
                    mode = "CAPTURE"
                    break
                end
            end
        end
        -- 这里应该稍微等一下，防止异常情况
        sys.wait(500)
    end
end)

return common
