--[[

]]

local air530z = {}

local sys = require("sys")

function air530z.setup(opts)
    air530z.opts = opts
end

function air530z.start()
    -- 初始化串口
    local gps_uart_id = air530z.opts.uart_id or 2
    local opts = air530z.opts
    local write = air530z.writeCmd
    -- 切换波特率
    uart.setup(gps_uart_id, 9600)
    uart.write(gps_uart_id,"$PCAS01,5*19\r\n")
    sys.wait(100)
    uart.close(gps_uart_id)
    sys.wait(100)
    uart.setup(gps_uart_id, 115200)
    -- 是否为调试模式
    if opts.debug then
        libgnss.debug(true)
    end
    libgnss.bind(gps_uart_id)
    libgnss.on("txt", function(txt)
        -- log.info("air530z", "收到TXT数据", txt)
        if txt:startsWith("$GPTXT,01,01,02,MS=") then
            local tmp = txt:split(",")
            log.info("air530z", "GPS有效星历", tmp[8], "BDS有效星历", tmp[11])
            air530z.xl_gps = tonumber(tmp[8])
            air530z.xl_bds = tonumber(tmp[11])
            air530z.xl_tm = os.time()
        elseif txt:startsWith("$GPTXT,01,01,01,ANTENNA") then
            -- 天线状态
            air530z.antenna = txt:split(" ")[2]
            if air530z.antenna then
                air530z.antenna = air530z.antenna:split("*")[1]
            end
            -- log.info("air530z", "天线状态", air530z.antenna)
        end
    end)

    -- 配置NMEA版本, 4.1的GSA有额外的标识
    if not opts.nmea_ver or opts.nmea_ver >= 41 then
        write("PCAS05,2")
    else
        write("PCAS05,5")
    end
    -- 打开全部NMEA语句
    if opts.rmc_only then
        write("PCAS03,0,0,0,0,1,0,0,0,0,0,,,0,0,,,,0")
        write("PCAS03,,,,,,,,,,,0")
    elseif air530z.opts.no_nmea then
        write("PCAS03,0,0,0,0,0,0,0,0,0,0,,,0,0,,,,0")
        write("PCAS03,,,,,,,,,,,0")
    else
        write("PCAS03,1,1,1,1,1,1,1,0,0,0,,,0,0,,,,0")
        write("PCAS03,,,,,,,,,,,1")
    end
    -- 是否需要切换定位系统呢?
    if opts.sys then
        if type(opts.sys) == "number" then
            air530z.writeCmd("PCAS04," .. tostring(opts.sys))
            -- 若开启了GPS, 那么把SBAS和QZSS也打开
            if (opts.sys & 1) == 1 then
                -- 额外打开SBAS和QZSS
                write("PCAS15,4,FFFF")
                write("PCAS15,5,1F")
            end
        end
    end
end

function air530z.writeCmd(cmd, full)
    if not full then
        local ck = crypto.checksum(cmd)
        cmd = string.format("$%s*%02X\r\n", cmd, ck)
    end
    log.info("air530z", "写入指令", cmd:trim())
    uart.write(air530z.opts.uart_id, cmd)
end

function air530z.reboot(mode)
    local cmd = string.format("PCAS10,%d", mode or 0)
    air530z.writeCmd(cmd)
    if mode and mode == 2 then
        air530z.agps_tm = nil
    end
    libgnss.clear()
end

function air530z.stop()
    uart.close(air530z.opts.uart_id)
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
    elseif wlan then
        -- wlan.scan()
        -- sys.waitUntil("WLAN_SCAN_DONE", 5000)
    end
    if not lat then
        -- 获取最后的本地位置
        local locStr = io.readFile("/zkwloc")
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
    local agps_time = tonumber(io.readFile("/zkw_tm") or "0") or 0
    if now - agps_time > 3600 then
        local url = air530z.opts.url
        if not air530z.opts.url then
            if air530z.opts.sys and 2 == air530z.opts.sys then
                url = "http://download.openluat.com/9501-xingli/CASIC_data_bds.dat"
            else
                url = "http://download.openluat.com/9501-xingli/CASIC_data.dat"
            end
        end
        local code = http.request("GET", url, nil, nil, {dst="/ZKW.dat"}).wait()
        if code and code == 200 then
            log.info("air530z", "下载星历成功", url)
            io.writeFile("/zkw_tm", tostring(now))
        else
            log.info("air530z", "下载星历失败", code)
        end
    else
        log.info("air530z", "星历不需要更新", now - agps_time)
    end

    local gps_uart_id = air530z.opts.uart_id or 2

    -- 写入星历
    local agps_data = io.readFile("/ZKW.dat")
    if agps_data and #agps_data > 1024 then
        log.info("air530z", "写入星历数据", "长度", #agps_data)
        for offset=1,#agps_data,512 do
            -- log.info("gnss", "AGNSS", "write >>>", #agps_data:sub(offset, offset + 511))
            uart.write(gps_uart_id, agps_data:sub(offset, offset + 511))
            sys.wait(100) -- 等100ms反而更成功
        end
    else
        log.info("air530z", "没有星历数据")
        return
    end

    -- 写入参考位置
    -- "lat":23.4068813,"min":27,"valid":true,"day":27,"lng":113.2317505
    if not lat or not lng then
        -- lat, lng = 23.4068813, 113.2317505
        return -- TODO 暂时不写入参考位置
    end
    socket.sntp()
    sys.waitUntil("NTP_UPDATE", 1000)
    local dt = os.date("!*t")
    local lla = {lat=lat, lng=lng}
    local aid = libgnss.casic_aid(dt, lla)
    uart.write(gps_uart_id, aid.."\r\n")

    -- 结束
    air530z.agps_tm = now
end

function air530z.agps(force)
    -- 如果不是强制写入AGPS信息, 而且是已经定位成功的状态,那就没必要了
    if not force and libgnss.isFix() then return end
    -- 先判断一下时间
    local now = os.time()
    if force or not air530z.agps_tm or now - air530z.agps_tm > 3600 then
        -- 执行AGPS
        log.info("air530z", "开始执行AGPS")
        do_agps()
    else
        log.info("air530z", "暂不需要写入AGPS")
    end
end

function air530z.saveloc(lat, lng)
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
        log.info("air530z", "保存GPS位置", locStr)
        io.writeFile("/zkwloc", locStr)
    end
end

sys.subscribe("GNSS_STATE", function(event)
    if event == "FIXED" then
        air530z.saveloc()
    end
end)


return air530z
