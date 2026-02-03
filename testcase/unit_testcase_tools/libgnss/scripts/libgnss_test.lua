local libgnss_test = {}

local lbsLoc2 = require("lbsLoc2")

local gps_uart_id = 2 -- GNSS模块使用的UART端口号
local gnssmode = 1 -- 设置gnss的模式为1,1为全卫星开启，2为单北斗开启

local is_test_running = false
local gnss_power_on = false -- 记录GNSS电源状态

-- 测试结果存储
local test_results = {}

-- 测试libgnss.getIntLocation接口
function test_getIntLocation()
    log.info("测试", "调用libgnss.getIntLocation()")

    local lat, lng, speed = libgnss.getIntLocation(0)

    log.info("getIntLocation结果", "纬度:", lat or "nil", "经度:", lng or "nil", "速度:", speed or "nil")

    -- 判断测试是否通过：函数能正常调用，不崩溃即为通过
    assert(lat ~= nil and lng ~= nil, string.format(
        "获取number类型的位置和速度信息返回值异常: 预期纬度和经度不为nil, 实际纬度=%s, 经度=%s",
        lat or "nil", lng or "nil"))
    log.info("获取number类型的位置和速度信息测试通过")

    local passed = (lat ~= nil and lng ~= nil)
    test_results["getIntLocation"] = passed

    return passed
end

-- 测试libgnss.getRmc接口
function test_getRmc()
    log.info("测试", "调用libgnss.getRmc(0)")

    local rmc = libgnss.getRmc(0)

    assert(rmc ~= nil, string.format("获取RMC的信息返回值异常: 预期RMC不为nil,实际RMC=%s",
        tostring(rmc)))
    log.info("获取RMC的信息测试通过")

    if rmc then
        local passed = true
        test_results["getRmc"] = passed
        return passed
    else
        log.warn("getRmc结果", "返回nil")
        test_results["getRmc"] = false
        return false
    end
end

-- 测试libgnss.getGsv接口
function test_getGsv()
    log.info("测试", "调用libgnss.getGsv()")

    local gsv = libgnss.getGsv()

    assert(gsv ~= nil, string.format("获取原始GSV信息返回值异常: 预期GSV不为nil,实际GSV=%s",
        tostring(gsv)))
    log.info("获取原始GSV信息测试通过")

    if gsv then
        log.info("getGsv结果", "类型:", type(gsv), "卫星总数:", gsv.total_sats or "nil")
        local passed = true
        test_results["getGsv"] = passed
        return passed
    else
        log.warn("getGsv结果", "返回nil")
        test_results["getGsv"] = false
        return false
    end
end

-- 测试libgnss.getGsa接口
function test_getGsa()
    log.info("测试", "调用libgnss.getGsa(0)")

    local gsa = libgnss.getGsa(0)

    assert(gsa ~= nil, string.format("获取原始GSA信息返回值异常: 预期GSA不为nil,实际GSA=%s",
        tostring(gsa)))
    log.info("获取原始GSA信息测试通过")

    if gsa then
        log.info("getGsa结果", "类型:", type(gsa), "PDOP:", gsa.pdop or "nil")
        local passed = true
        test_results["getGsa"] = passed
        return passed
    else
        log.warn("getGsa结果", "返回nil")
        test_results["getGsa"] = false
        return false
    end
end


-- 清理GNSS状态
function cleanup_gnss()
    log.info("清理", "关闭GNSS调试输出和电源")

    -- 关闭调试输出
    libgnss.debug(false)

    -- 清除数据
    libgnss.clear()

    -- 关闭GNSS电源（可选，根据需求）
    if gnss_power_on then
        pm.power(pm.GPS, false)
        gnss_power_on = false
        log.info("清理", "GNSS电源已关闭")
    end

    -- 重置状态
    is_test_running = false

    log.info("清理", "GNSS清理完成")
end

-- 执行所有libgnss接口测试
function run_libgnss_interface_tests()
    log.info("========= libgnss接口功能测试 =========")

    local test_functions = {{
        name = "isFix",
        func = test_isFix
    }, {
        name = "getIntLocation",
        func = test_getIntLocation
    }, {
        name = "getRmc",
        func = test_getRmc
    }, {
        name = "getGsv",
        func = test_getGsv
    }, {
        name = "getGsa",
        func = test_getGsa
    }
    -- , {
    --     name = "getVtg",
    --     func = test_getVtg
    -- }, {
    --     name = "getZda",
    --     func = test_getZda
    -- }, {
    --     name = "getGga",
    --     func = test_getGga
    -- }, {
    --     name = "getGll",
    --     func = test_getGll
    -- }
}

    local total_tests = 0
    local passed_tests = 0

    for _, test in ipairs(test_functions) do
        total_tests = total_tests + 1

        log.info("执行测试", test.name)

        local success, result = pcall(test.func)

        if success then
            if result then
                passed_tests = passed_tests + 1
                log.info("✓", test.name, "通过")
            else
                log.warn("!", test.name, "返回false")
            end
        else
            log.error("✗", test.name, "调用失败:", result)
        end

        sys.wait(300) -- 测试间隔
    end

    -- 判断是否所有测试都通过
    local all_passed = true
    for test_name, result in pairs(test_results) do
        if not result then
            all_passed = false
            break
        end
    end

    return all_passed, passed_tests, total_tests
end

local function agps()
    if libgnss.isFix() then
        log.info("AGPS", "已定位，跳过AGPS")
        return
    end

    local lat, lng
    -- 判断星历时间和下载星历   
    while not socket.adapter(socket.dft()) do
        log.warn("airlbs_multi_cells_wifi_func", "wait IP_READY", socket.dft())
        local result = sys.waitUntil("IP_READY", 1000)
        if result == false then
            log.warn("gnss_agps", "wait IP_READY timeout")
            return
        end
    end

    socket.sntp()
    sys.waitUntil("NTP_UPDATE", 5000)

    local now = os.time()
    local agps_time = tonumber(io.readFile("/hxxt_tm") or "0") or 0
    log.info("os.time", now)
    log.info("agps_time", agps_time)

    if now - agps_time > 3600 or io.fileSize("/hxxt.dat") < 1024 then
        local url

        if gnssmode and 2 == gnssmode then
            -- 单北斗
            url = "http://download.openluat.com/9501-xingli/HXXT_BDS_AGNSS_DATA.dat"
        else
            url = "http://download.openluat.com/9501-xingli/HXXT_GPS_BDS_AGNSS_DATA.dat"
        end

        local code = http.request("GET", url, nil, nil, {
            dst = "/hxxt.dat"
        }).wait()

        if code and code == 200 then
            log.info("exgnss.opts", "下载星历成功", url)
            io.writeFile("/hxxt_tm", tostring(now))
        else
            log.info("exgnss.opts", "下载星历失败", code)
        end
    else
        log.info("exgnss.opts", "星历不需要更新", now - agps_time)
    end

    -- 进行基站定位，给到gnss芯片一个大概的位置
    lat, lng = lbsLoc2.request(5000)

    if lat and lng then
        lat = tonumber(lat)
        lng = tonumber(lng)
        log.info("lbsLoc2", lat, lng)
        -- 转换单位
        local lat_dd, lat_mm = math.modf(lat)
        local lng_dd, lng_mm = math.modf(lng)
        lat = lat_dd * 100 + lat_mm * 60
        lng = lng_dd * 100 + lng_mm * 60
    end

    -- 获取基站定位失败则使用本地之前保存的位置
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
        for offset = 1, #agps_data, 512 do
            log.info("exgnss", "AGNSS", "write >>>", #agps_data:sub(offset, offset + 511))
            uart.write(gps_uart_id, agps_data:sub(offset, offset + 511))
            sys.wait(100) -- 等100ms反而更成功
        end
    else
        log.info("exgnss.opts", "没有星历数据")
        return
    end

    if not lat or not lng then
        log.info("exgnss.opts", "没有GPS坐标", lat, lng)
        return -- 暂时不写入参考位置
    else
        log.info("exgnss.opts", "写入GPS坐标", lat, lng)
    end

    -- 写入时间
    local date = os.date("!*t")
    if date.year > 2023 then
        local str = string.format("$AIDTIME,%d,%d,%d,%d,%d,%d,000", date["year"], date["month"], date["day"],
            date["hour"], date["min"], date["sec"])
        log.info("exgnss.opts", "参考时间", str)
        uart.write(gps_uart_id, str .. "\r\n")
        sys.wait(20)
    end

    -- 写入参考位置
    local str = string.format("$AIDPOS,%.7f,%s,%.7f,%s,1.0\r\n", lat > 0 and lat or (0 - lat), lat > 0 and 'N' or 'S',
        lng > 0 and lng or (0 - lng), lng > 0 and 'E' or 'W')
    log.info("exgnss.opts", "写入AGPS参考位置", str)
    uart.write(gps_uart_id, str)
end

function libgnss_test.test_gnss_open()
    log.info("libgnss测试", "开始")

    -- 重置测试状态
    is_test_running = true
    test_results = {}

    -- 清除历史定位数据
    log.info("开始清除历史定位数据")
    libgnss.clear()

    -- 设置串口波特率
    uart.setup(gps_uart_id, 115200)

    -- 打开GPS电源
    local gps_power_open_result = pm.power(pm.GPS, true)
    assert(gps_power_open_result == true,
        string.format("GPS电源打开失败: 预期 %s, 实际 %s", true, gps_power_open_result))
    log.info("GPS电源打开测试通过")
    gnss_power_on = true

    -- 绑定uart
    libgnss.bind(gps_uart_id)

    -- 开启调试日志
    libgnss.debug(true)

    -- 开启自动设置RTC
    libgnss.rtcAuto(true)
    log.info("RTC自动设置: 开启")

    -- 等待GNSS模块初始化（重要！）
    log.info("等待GNSS模块初始化...")
    sys.wait(3000) -- 等待3秒让GNSS模块启动

    -- 启动AGPS（在后台）
    sys.taskInit(agps)

    -- 等待AGPS完成
    log.info("等待AGPS处理...")
    sys.wait(3000) -- 增加等待时间

    -- 执行libgnss接口功能测试
    log.info("开始执行libgnss接口功能测试...")
    local all_passed, passed_tests, total_tests = run_libgnss_interface_tests()

    -- 清理GNSS状态
    cleanup_gnss()
end

-- 添加一个清理函数，确保在测试结束或出错时清理资源
function libgnss_test.cleanup()
    if is_test_running then
        cleanup_gnss()
    end
end

return libgnss_test
