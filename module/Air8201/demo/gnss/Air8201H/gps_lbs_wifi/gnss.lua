local gnss = {}

local sys = require "sys"

local isFix = false

-- *****************gps定位************************

-- gnss的供电
-- local gnssEnvPower = gpio.setup(26, 1)
-- local gpsPower = gpio.setup(2, 1)
-- gnss的复位
-- local gpsRst = gpio.setup(27, 1)

local function gnssPower(onoff)
    gpio.setup(26, onoff and 1 or 0)
    gpio.setup(25, onoff and 1 or 0) 
end

local isOn = true

local function power(on)
    if on ~= isOn then
        if on then--开机后要清空一下
            libgnss.clear()
        end
        gnssPower(on)
        -- gnssEnvPower(on and 1 or 0)
        -- gpsPower(on and 1 or 0)
        if on then--开机后要清空一下
            -- gpsRst(0)
            -- sys.timerStart(gpsRst, 500, 1)
            libgnss.clear()
        end
        isOn = on
    end
end

sys.taskInit(function()
    log.info("GPS", "start")
    -- 开启gps的供电引脚
    gnssPower(isOn);

    local uartId = 2
    libgnss.clear() -- 清空数据,兼初始化
    uart.setup(uartId, 115200)

    sys.wait(200) -- GPNSS芯片启动需要时间
    gnss.agps() -- 更新星历
    -- 调试日志,可选
    libgnss.debug(true)
    -- 绑定读取gnss数据的端口
    libgnss.bind(2)
end)


-- 订阅GNSS状态编码
sys.subscribe("GNSS_STATE", function(event, ticks)
    -- event取值有 
    -- FIXED 定位成功
    -- LOSE  定位丢失
    -- ticks是事件发生的时间,一般可以忽略
    log.info("gnss", "state", event, ticks)
    if event == "FIXED" then
        local locStr = libgnss.locStr()
        log.info("gnss", "locStr", locStr)
        isFix = true
    elseif event == "LOSE" then
        log.info("gnss", "no fix")
    end
end)

local function doAgps()
    -- 首先, 发起位置查询
    local lat, lng
    if mobile then
        -- 查询基站信息
        mobile.reqCellInfo(6)
        -- 等待基站数据已更新的消息，超时时间6秒
        sys.waitUntil("CELL_INFO_UPDATE", 6000)
        -- 包含一下lbsLoc2库
        local lbsLoc2 = require("lbsLoc2")
        -- 执行定位请求，返回坐标的纬度和精度
        lat, lng = lbsLoc2.request(5000)
        log.info("lbsLoc2", lat, lng)
        if lat and lng then
            -- 确保lat和lng是数字
            lat = tonumber(lat)
            lng = tonumber(lng)
            log.info("lbsLoc2", lat, lng)
        end
    end
    if not lat then
        log.info("not lat")
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
    log.info("now-->",now,"---agps_time-->",agps_time)
    if now - agps_time > 3600 then
        -- local url = "http://download.openluat.com/9501-xingli/HXXT_GPS_BDS_AGNSS_DATA.dat" -- GPS和北斗
        local url = "http://download.openluat.com/9501-xingli/HXXT_ALL_AGNSS_DATA.dat"        -- 全星历

        local code = http.request("GET", url, nil, nil, {
            dst = "/hxxt.dat"
        }).wait()
        if code and code == 200 then
            log.info("下载星历成功", url)
            io.writeFile("/hxxt_tm", tostring(now))
        else
            log.info("下载星历失败", code)
        end
    else
        log.info("星历不需要更新", now - agps_time)
    end
    -- 写入星历
    local agps_data = io.readFile("/hxxt.dat")
    if agps_data and #agps_data > 1024 then
        log.info("写入星历数据", "长度", #agps_data)
        for offset = 1, #agps_data, 512 do
            log.info("gnss", "AGNSS", "write >>>", #agps_data:sub(offset, offset + 511))
            sys.wait(100) -- 等100ms反而更成功
        end
    else
        log.info("没有星历数据")
        isFix = false
        return
    end

    -- 写入参考位置
    -- "lat":23.4068813,"min":27,"valid":true,"day":27,"lng":113.2317505
    if not lat or not lng then
        -- lat, lng = 23.4068813, 113.2317505
        log.info("没有GPS坐标", lat, lng)
        isFix = false
        return -- TODO 暂时不写入参考位置
    end
    if socket.sntp then
        --时间同步
        socket.sntp()
        --等待时间同步成功消息
        sys.waitUntil("NTP_UPDATE", 1000)
    end
    --获取日期函数，参数1是格式化字符串
    local date = os.date("!*t")
    if date.year >= 2024 then
        local str = string.format("$AIDTIME,%d,%d,%d,%d,%d,%d,000", date["year"], date["month"], date["day"], date["hour"], date["min"], date["sec"])
        log.info("参考时间", str)
        sys.wait(20)
    end

    local str = string.format("$AIDPOS,%.7f,%s,%.7f,%s,1.0\r\n", lat > 0 and lat or (0 - lat), lat > 0 and 'N' or 'S', lng > 0 and lng or (0 - lng), lng > 0 and 'E' or 'W')
    log.info("写入AGPS参考位置", str)
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
    isFix = false
    -- 两小时更新一次星历吧
    sys.timerStart(gnss.agps, 2 * 60 * 60 * 1000)
end

local agpsTaskHandle

-- 下载并写入星历
function gnss.agps()
    if not agpsTaskHandle or coroutine.status(agpsTaskHandle) == "dead" then
        agpsTaskHandle = sys.taskInit(doAgps)
    end
end

return gnss