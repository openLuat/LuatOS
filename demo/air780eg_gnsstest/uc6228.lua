--[[

]]

local uc6228 = {
    version = "1.0.1"
}

local sys = require("sys")

function uc6228.setup(opts)
    uc6228.opts = opts
    if not uc6228.opts.uart_id then
        uc6228.opts.uart_id = 2
    end
end

function uc6228.start()
    -- 初始化串口
    local gps_uart_id = uc6228.opts.uart_id
    local opts = uc6228.opts
    local write = uc6228.writeCmd
    uart.setup(gps_uart_id, 115200)
    -- 是否为调试模式
    if opts.debug then
        libgnss.debug(true)
    end
    libgnss.bind(gps_uart_id)

    -- 是否需要切换定位系统呢?
    if opts.sys then
        if type(opts.sys) == "number" then
            if opts.sys == 1 then
                uart.write(gps_uart_id, "$CFGSYS,H01\r\n")
            elseif opts.sys == 2 then
                uart.write(gps_uart_id, "$CFGSYS,H10\r\n")
            elseif opts.sys == 5 then
                uart.write(gps_uart_id, "$CFGSYS,H101\r\n")
            else
                uart.write(gps_uart_id, "$CFGSYS,H11\r\n")
            end
        end
    end

    if not opts.nmea_ver or opts.nmea_ver == 41 then
        uart.write(gps_uart_id, "$CFGNMEA,h51\r\n") -- 切换到NMEA 4.1
    end

    -- 打开全部NMEA语句
    if opts.rmc_only then
        uart.write(gps_uart_id, "$CFGMSG,0,0,0\r\n")
        sys.wait(20)
        uart.write(gps_uart_id, "$CFGMSG,0,1,0\r\n")
        sys.wait(20)
        uart.write(gps_uart_id, "$CFGMSG,0,2,0\r\n")
        sys.wait(20)
        uart.write(gps_uart_id, "$CFGMSG,0,3,0\r\n")
        sys.wait(20)
        uart.write(gps_uart_id, "$CFGMSG,0,4,1\r\n")
        sys.wait(20)
        uart.write(gps_uart_id, "$CFGMSG,0,5,0\r\n")
        sys.wait(20)
        uart.write(gps_uart_id, "$CFGMSG,0,6,0\r\n")
        sys.wait(20)
        uart.write(gps_uart_id, "$CFGMSG,0,7,0\r\n")
        sys.wait(20)
    elseif uc6228.opts.no_nmea then
        uart.write(gps_uart_id, "$CFGMSG,0,0,0\r\n")
        sys.wait(20)
        uart.write(gps_uart_id, "$CFGMSG,0,1,0\r\n")
        sys.wait(20)
        uart.write(gps_uart_id, "$CFGMSG,0,2,0\r\n")
        sys.wait(20)
        uart.write(gps_uart_id, "$CFGMSG,0,3,0\r\n")
        sys.wait(20)
        uart.write(gps_uart_id, "$CFGMSG,0,4,0\r\n")
        sys.wait(20)
        uart.write(gps_uart_id, "$CFGMSG,0,5,0\r\n")
        sys.wait(20)
        uart.write(gps_uart_id, "$CFGMSG,0,6,0\r\n")
        sys.wait(20)
        uart.write(gps_uart_id, "$CFGMSG,0,7,0\r\n")
        sys.wait(20)
    else
        uart.write(gps_uart_id, "$CFGMSG,0,0,1\r\n") -- GGA
        sys.wait(10)
        uart.write(gps_uart_id, "$CFGMSG,0,1,1\r\n") -- GLL
        sys.wait(10)
        uart.write(gps_uart_id, "$CFGMSG,0,2,1\r\n") -- GSA
        sys.wait(10)
        uart.write(gps_uart_id, "$CFGMSG,0,3,1\r\n") -- GSV
        sys.wait(10)
        uart.write(gps_uart_id, "$CFGMSG,0,4,1\r\n") -- RMC
        sys.wait(10)
        uart.write(gps_uart_id, "$CFGMSG,0,5,1\r\n") -- VTG
        sys.wait(10)
        uart.write(gps_uart_id, "$CFGMSG,0,6,1\r\n") -- ZDA
        sys.wait(10)
        -- uart.write(gps_uart_id, "$CFGMSG,0,7,1\r\n") -- GST
        -- sys.wait(10)
    end
end

function uc6228.writeCmd(cmd)
    log.info("uc6228", "写入指令", cmd:trim())
    uart.write(uc6228.opts.uart_id, cmd)
end

function uc6228.reboot(mode)
    local cmd = "$RESET,0,"
    if not mode then
        mode = 0
    end
    if mode == 2 then
        cmd = cmd .. "hff\r\n"
    elseif mode == 1 then
        cmd = cmd .. "h01\r\n"
    else
        cmd = cmd .. "h00\r\n"
    end
    uart.write(uc6228.opts.uart_id, cmd)
    if mode == 2 then
        uc6228.agps_tm = nil
    end
    libgnss.clear()
end

function uc6228.stop()
    uart.close(uc6228.opts.uart_id)
end

local function do_agps()
    -- 首先, 发起位置查询
    local lat, lng
    if mobile then
        mobile.reqCellInfo(6)
        sys.waitUntil("CELL_INFO_UPDATE", 6000)
        local lbsLoc2 = require("lbsLoc2")
        lat, lng = lbsLoc2.request(5000)
        -- local lat, lng, t = lbsLoc2.request(5000, "bs.openluat.com")
        log.info("lbsLoc2", lat, lng)
        if lat and lng then
            lat = tonumber(lat)
            lng = tonumber(lng)
            log.info("lbsLoc2", lat, lng)
        end
    elseif wlan then
        -- wlan.scan()
        -- sys.waitUntil("WLAN_SCAN_DONE", 5000)
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
        local url = uc6228.opts.url
        if not uc6228.opts.url then
            if uc6228.opts.sys and 2 == uc6228.opts.sys then
                -- 单北斗
                url = "http://download.openluat.com/9501-xingli/HXXT_BDS_AGNSS_DATA.dat"
            else
                url = "http://download.openluat.com/9501-xingli/HXXT_GPS_BDS_AGNSS_DATA.dat"
            end
        end
        local code = http.request("GET", url, nil, nil, {dst="/hxxt.dat"}).wait()
        if code and code == 200 then
            log.info("uc6228", "下载星历成功", url)
            io.writeFile("/hxxt_tm", tostring(now))
        else
            log.info("uc6228", "下载星历失败", code)
        end
    else
        log.info("uc6228", "星历不需要更新", now - agps_time)
    end

    local gps_uart_id = uc6228.opts.uart_id or 2

    -- 写入星历
    local agps_data = io.readFile("/hxxt.dat")
    if agps_data and #agps_data > 1024 then
        log.info("uc6228", "写入星历数据", "长度", #agps_data)
        for offset=1,#agps_data,512 do
            log.info("gnss", "AGNSS", "write >>>", #agps_data:sub(offset, offset + 511))
            uart.write(gps_uart_id, agps_data:sub(offset, offset + 511))
            sys.wait(100) -- 等100ms反而更成功
        end
        -- uart.write(gps_uart_id, agps_data)
    else
        log.info("uc6228", "没有星历数据")
        return
    end

    -- 写入参考位置
    -- "lat":23.4068813,"min":27,"valid":true,"day":27,"lng":113.2317505
    if not lat or not lng then
        -- lat, lng = 23.4068813, 113.2317505
        log.info("uc6228", "没有GPS坐标", lat, lng)
        return -- TODO 暂时不写入参考位置
    end
    if socket.sntp then
        socket.sntp()
        sys.waitUntil("NTP_UPDATE", 1000)
    end
    local date = os.date("!*t")
    if date.year > 2023 then
        local str = string.format("$AIDTIME,%d,%d,%d,%d,%d,%d,000", date["year"], date["month"], date["day"],
            date["hour"], date["min"], date["sec"])
        log.info("uc6228", "参考时间", str)
        uart.write(gps_uart_id, str .. "\r\n")
        sys.wait(20)
    end

    local str = string.format("$AIDPOS,%.7f,%s,%.7f,%s,1.0\r\n",
    lat > 0 and lat or (0 - lat), lat > 0 and 'N' or 'S',
    lng > 0 and lng or (0 - lng), lng > 0 and 'E' or 'W')
    log.info("uc6228", "写入AGPS参考位置", str)
    uart.write(gps_uart_id, str)

    -- 结束
    uc6228.agps_tm = now
end

function uc6228.agps(force)
    -- 如果不是强制写入AGPS信息, 而且是已经定位成功的状态,那就没必要了
    if not force and libgnss.isFix() then return end
    -- 先判断一下时间
    local now = os.time()
    if force or not uc6228.agps_tm or now - uc6228.agps_tm > 3600 then
        -- 执行AGPS
        log.info("uc6228", "开始执行AGPS")
        do_agps()
    else
        log.info("uc6228", "暂不需要写入AGPS")
    end
end

function uc6228.saveloc(lat, lng)
    if not lat or not lng then
        if libgnss.isFix() then
            local rmc = libgnss.getRmc(3)
            if rmc then
                lat, lng = rmc.lat, rmc.lng
            end
        end
    end
    if lat and lng then
        log.info("待保存的GPS位置", lat, lng)
        local locStr = string.format('{"lat":%7f,"lng":%7f}', lat, lng)
        log.info("uc6228", "保存GPS位置", locStr)
        io.writeFile("/hxxtloc", locStr)
    end
end

sys.subscribe("GNSS_STATE", function(event)
    if event == "FIXED" then
        uc6228.saveloc()
    end
end)


return uc6228
