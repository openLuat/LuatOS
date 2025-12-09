--[[
@module  gnss
@summary gnss应用测试功能模块
@version 1.0
@date    2025.07.27
@author  李源龙
@usage
主要功能：
1、开启gnss定位，使用agps辅助定位
2、定位成功获取经纬度

]]
local lbsLoc2 = require("lbsLoc2")
local gps_uart_id = 2

local gnssmode=1


local function agps()
    if libgnss.isFix() then return end
    local lat, lng
    
    -- 判断星历时间和下载星历   
    while not socket.adapter(socket.dft()) do
        log.warn("airlbs_multi_cells_wifi_func", "wait IP_READY", socket.dft())
        -- 在此处阻塞等待默认网卡连接成功的消息"IP_READY"
        -- 或者等待1秒超时退出阻塞等待状态;
        -- 注意：此处的1000毫秒超时不要修改的更长；
        -- 因为当使用exnetif.set_priority_order配置多个网卡连接外网的优先级时，会隐式的修改默认使用的网卡
        -- 当exnetif.set_priority_order的调用时序和此处的socket.adapter(socket.dft())判断时序有可能不匹配
        -- 此处的1秒，能够保证，即使时序不匹配，也能1秒钟退出阻塞状态，再去判断socket.adapter(socket.dft())
        local result=sys.waitUntil("IP_READY", 30000)
        if result == false then
            log.warn("gnss_agps", "wait IP_READY timeout")
            return
        end
    end
    socket.sntp()
    sys.waitUntil("NTP_UPDATE", 5000)
    local now = os.time()
    local agps_time = tonumber(io.readFile("/hxxt_tm") or "0") or 0
    log.info("os.time",now)
    log.info("agps_time",agps_time)
    if now - agps_time > 3600 or io.fileSize("/hxxt.dat") < 1024 then
        local url 

        if gnssmode and 2 == gnssmode then
            -- 单北斗
            url = "http://download.openluat.com/9501-xingli/HXXT_BDS_AGNSS_DATA.dat"
        else
            url = "http://download.openluat.com/9501-xingli/HXXT_GPS_BDS_AGNSS_DATA.dat"
        end
        local code = http.request("GET", url, nil, nil, {dst="/hxxt.dat"}).wait()
        if code and code == 200 then
            log.info("exgnss.opts", "下载星历成功", url)
            io.writeFile("/hxxt_tm", tostring(now))
        else
            log.info("exgnss.opts", "下载星历失败", code)
        end
    else
        log.info("exgnss.opts", "星历不需要更新", now - agps_time)
    end
    --进行基站定位，给到gnss芯片一个大概的位置
    if mobile then
        lat, lng = lbsLoc2.request(5000)
        -- local lat, lng, t = lbsLoc2.request(5000, "bs.openluat.com")
        -- log.info("lbsLoc2", lat, lng)
        if lat and lng then
            lat = tonumber(lat)
            lng = tonumber(lng)
            log.info("lbsLoc2", lat, lng)
            -- 转换单位
            local lat_dd,lat_mm = math.modf(lat)
            local lng_dd,lng_mm = math.modf(lng)
            lat = lat_dd * 100 + lat_mm * 60
            lng = lng_dd * 100 + lng_mm * 60
        end
    elseif wlan then
        -- wlan.scan()
        -- sys.waitUntil("WLAN_SCAN_DONE", 5000)
    end
    --获取基站定位失败则使用本地之前保存的位置
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

    -- 写入星历
    local agps_data = io.readFile("/hxxt.dat")
    if agps_data and #agps_data > 1024 then
        log.info("exgnss.opts", "写入星历数据", "长度", #agps_data)
        for offset=1,#agps_data,512 do
            log.info("exgnss", "AGNSS", "write >>>", #agps_data:sub(offset, offset + 511))
            uart.write(gps_uart_id, agps_data:sub(offset, offset + 511))
            sys.wait(100) -- 等100ms反而更成功
        end
        -- uart.write(gps_uart_id, agps_data)
    else
        log.info("exgnss.opts", "没有星历数据")
        return
    end
    -- "lat":23.4068813,"min":27,"valid":true,"day":27,"lng":113.2317505
    --如果没有经纬度的话，定位时间会变长，大概10-20s左右
    if not lat or not lng then
        -- lat, lng = 23.4068813, 113.2317505
        log.info("exgnss.opts", "没有GPS坐标", lat, lng)
        return --暂时不写入参考位置
    else
        log.info("exgnss.opts", "写入GPS坐标", lat, lng)
    end
    --写入时间
    local date = os.date("!*t")
    if date.year > 2023 then
        local str = string.format("$AIDTIME,%d,%d,%d,%d,%d,%d,000", date["year"], date["month"], date["day"],
            date["hour"], date["min"], date["sec"])
        log.info("exgnss.opts", "参考时间", str)
        uart.write(gps_uart_id, str .. "\r\n")
        sys.wait(20)
    end
    -- 写入参考位置
    local str = string.format("$AIDPOS,%.7f,%s,%.7f,%s,1.0\r\n",
    lat > 0 and lat or (0 - lat), lat > 0 and 'N' or 'S',
    lng > 0 and lng or (0 - lng), lng > 0 and 'E' or 'W')
    log.info("exgnss.opts", "写入AGPS参考位置", str)
    uart.write(gps_uart_id, str)

end


local function gnss_open()
    log.info("GPS", "start")
    libgnss.clear() -- 清空数据,兼初始化
    --设置串口波特率
    uart.setup(gps_uart_id, 115200)
    -- 打开GPS
    pm.power(pm.GPS, true)
    -- 绑定uart,底层自动处理GNSS数据
    -- 第二个参数是转发到虚拟UART, 方便上位机分析
    libgnss.bind(gps_uart_id, uart.VUART_0)
    sys.wait(200) -- GPNSS芯片启动需要时间
    -- 调试日志,可选
    libgnss.debug(true)

    -- 增加显示的语句
    uart.write(gps_uart_id, "$CFGMSG,0,1,1\r\n") -- GLL
    sys.wait(20)
    uart.write(gps_uart_id, "$CFGMSG,0,5,1\r\n") -- VTG
    sys.wait(20)
    uart.write(gps_uart_id, "$CFGMSG,0,6,1\r\n") -- ZDA
    sys.wait(20)
    sys.taskInit(agps)

end

sys.taskInit(gnss_open)


--GNSS定位状态的消息处理函数：
local function gnss_state(event, ticks)
    -- event取值有
    -- "FIXED"：string类型 定位成功
    -- "LOSE"： string类型 定位丢失

    -- ticks number类型 是事件发生的时间,一般可以忽略
    log.info("exgnss", "state", event)
    if event=="FIXED" then
        --获取rmc数据
        --json.encode默认输出"7f"格式保留7位小数，可以根据自己需要的格式调整小数位，本示例保留5位小数
        log.info("nmea", "rmc0", json.encode(libgnss.getRmc(0),"5f"))
    end
end

sys.subscribe("GNSS_STATE",gnss_state)