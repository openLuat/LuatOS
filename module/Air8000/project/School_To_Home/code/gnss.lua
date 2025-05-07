local gnss = {}
local tList = {}
local moduleName = "gnss"
local uartId = 2
local isOpen = false
local isFix = false
local logSwitch = true
local gnssVersion = 0

local function logF(...)
    if logSwitch then
        log.info(moduleName, ...)
    end
end

local function catchGnssVer()
    libgnss.on("raw", function(data)
        local tmpData = data:split("\r\n")
        for k, v in pairs(tmpData) do
            if v and v:find("FWVer") then
                local version = v:match("FWVer .+Build(%d+)")
                if version then
                    gnssVersion = tonumber(version)
                    log.info("当前版本号GNSS固件版本号", version, type(version))
                end
                libgnss.on("raw")
            end
        end
    end)
end

function gnss.getVer()
    return gnssVersion
end

-- 打开、初始化gnss和串口
function gnss.open(tag)
    logF("打开状态", tag, isOpen)
    if not tList[tag] then
        tList[tag] = true
    end
    if isOpen then
        return
    end
    isFix = false
    if gnssVersion == 0 then
        catchGnssVer()
    end
    -- manage.wake("gnss")
    libgnss.clear() -- 清空数据,兼初始化
    uart.setup(uartId, 115200)
    -- libgnss.bind(uartId, uart.VUART_0)
    libgnss.bind(uartId)
    pcb.gnssPower(true)
    -- libgnss.debug(true)
    sys.wait(400)
    isOpen = true
    uart.write(2, "$CFGTP,1000000,500000,7,0,800,0*7D\r\n")
    gnss.agps()
end

-- 关闭、去初始化gnss和串口
function gnss.close(tag)
    log.info("gnss.close", tag, "关闭GNSS")
    if not isOpen then
        return
    end
    tList[tag] = nil
    for k, v in pairs(tList) do
        logF("close flag", k, v)
        if v then
            logF("有应用在占用，无法关闭", k, v)
            return
        end
    end
    isFix = false
    isOpen = false
    gpio.close(42)
    log.info("gnss.close", "关闭GNSS完成")
    pcb.gnssPower(false)
    uart.close(uartId)
    libgnss.clear() -- 清空数据,兼初始化
    -- manage.sleep("gnss")
end

-- gnss是否定位
function gnss.isFix()
    return isFix
end

-- gnss是否打开
function gnss.isOpen()
    return isOpen
end

-- 订阅GNSS状态编码
sys.subscribe("GNSS_STATE", function(event, ticks)
    -- event取值有 
    -- FIXED 定位成功
    -- LOSE  定位丢失
    -- ticks是事件发生的时间,一般可以忽略
    logF("gnss", "state", event, ticks)
    -- 定位成功，控制1pps 常亮
    -- 定位失败，控制1pps 500ms闪烁
    if event == "FIXED" then
        sys.timerStart(uart.write, 100, 2, "$CFGTP,1000000,1000,7,0,800,0*79\r\n")  -- 定位成功，给CC0257B发指令，改变1pps输出频率为常高
        isFix = true
    elseif event == "LOSE" then
        sys.timerStart(uart.write, 100, 2, "$CFGTP,1000000,500000,7,0,800,0*7D\r\n")    -- 定位失败，给CC0257B发指令，改变1pps输出频率为500ms高低
        isFix = false
    end
end)

local function doAgps()
    -- 首先, 发起位置查询
    gnss.open("tag_agps")
    local lat, lng
    if mobile then
        --mobile.reqCellInfo(6)
        --sys.waitUntil("CELL_INFO_UPDATE", 6000)
        local lbsLoc2 = require("lbsLoc2")
        lat, lng = lbsLoc2.request(5000)
        logF("lbsLoc2", lat, lng)
        if lat and lng then
            lat = tonumber(lat)
            lng = tonumber(lng)
            logF("lbsLoc2", lat, lng)
            -- 转换坐标单位
            local lat_dd,lat_mm = math.modf(lat)
            local lng_dd,lng_mm = math.modf(lng)
            lat = lat_dd * 100 + lat_mm * 60
            lng = lng_dd * 100 + lng_mm * 60
        end
    end
    if not lat then
        -- 获取最后的本地位置
        local locStr = io.readFile("/hxxtloc")
        if locStr then
            local jdata = json.decode(locStr)
            if jdata and jdata.lat then
                lat = jdata.lat
                lng = jdata.lng
            end
        end
    end
    -- 然后, 判断星历时间和下载星历
    local now = os.time()
    local agps_time = tonumber(io.readFile("/hxxt_tm") or "0") or 0
    if now - agps_time > 3600 then
        -- local url = "http://download.openluat.com/9501-xingli/HXXT_GPS_BDS_AGNSS_DATA.dat" -- GPS和北斗
        local url = "http://download.openluat.com/9501-xingli/HXXT_ALL_AGNSS_DATA.dat" -- 全星历

        local code = http.request("GET", url, nil, nil, {
            dst = "/hxxt.dat"
        }).wait()
        if code and code == 200 then
            logF("下载星历成功", url)
            io.writeFile("/hxxt_tm", tostring(now))
        else
            logF("下载星历失败", code)
        end
    else
        logF("星历不需要更新", now - agps_time)
    end
    -- 写入星历
    collectgarbage("collect")
    collectgarbage("collect")

    local agps_data = io.readFile("/hxxt.dat")
    if agps_data and #agps_data > 1024 then
        logF("写入星历数据", "长度", #agps_data)
        -- for offset = 1, #agps_data, 512 do
        --     logF("gnss", "AGNSS", "write >>>", #agps_data:sub(offset, offset + 511))
        --     uart.write(uartId, agps_data:sub(offset, offset + 511))
        --     sys.wait(100) -- 等100ms反而更成功
        -- end
        uart.write(uartId, agps_data)
        sys.wait(20)
    else
        logF("没有星历数据")
        gnss.close("tag_agps")
        return
    end

    -- 写入参考位置
    -- "lat":23.4068813,"min":27,"valid":true,"day":27,"lng":113.2317505
    if not lat or not lng then
        -- lat, lng = 23.4068813, 113.2317505
        logF("没有GPS坐标", lat, lng)
        gnss.close("tag_agps")
        return -- TODO 暂时不写入参考位置
    end
    if socket.sntp then
        socket.sntp()
        sys.waitUntil("NTP_UPDATE", 1000)
    end
    local date = os.date("!*t")
    if date.year >= 2024 then
        local str = string.format("$AIDTIME,%d,%d,%d,%d,%d,%d,000", date["year"], date["month"], date["day"], date["hour"], date["min"], date["sec"])
        logF("参考时间", str)
        uart.write(uartId, str .. "\r\n")
        sys.wait(20)
    end

    local str = string.format("$AIDPOS,%.7f,%s,%.7f,%s,1.0\r\n", lat > 0 and lat or (0 - lat), lat > 0 and 'N' or 'S', lng > 0 and lng or (0 - lng), lng > 0 and 'E' or 'W')
    logF("写入AGPS参考位置", str)
    uart.write(uartId, str)
    sys.wait(200)
    local times = 0
    while times < 120 do
        if isFix then
            break
        end
        times = times + 1
        sys.wait(1000)
    end
    sys.wait(6000)
    gnss.close("tag_agps")
    -- 两小时更新一次星历吧
    -- sys.timerStart(gnss.agps, 2 * 60 * 60 * 1000)
end

local agpsTaskHandle

-- 下载并写入星历
function gnss.agps()
    if not agpsTaskHandle or coroutine.status(agpsTaskHandle) == "dead" then
        agpsTaskHandle = sys.taskInit(doAgps)
    end
end

return gnss
