local rtc_test = {}
local device_name = rtos.bsp()

local exnetif = require "exnetif"

function rtc_test.test_rtc_task2()
    log.info("开始有网络情况下的rtc时间测试")

    -- rtc.set({ year = 2025, mon = 10, day = 28, hour = 8, min = 10, sec = 53 }) -- 设置日期和时间
    local rtc_set = rtc.set(1761639053) ---- 设置时间戳(与上一行的设置效果相同，二选一即可)
    local rtc_expected_set = {
        year = 2025,
        min = 10,
        hour = 8,
        mon = 10,
        sec = 53,
        day = 28
    }
    local rtc_set_time = rtc.get()
    assert(rtc_set == true,
        string.format("联网下设置 RTC 时钟的时间测试失败: 预期 %s, 实际 %s", true, rtc_set))
    log.info("rtc_test", "联网下设置时间戳后返回值类型测试通过")

    assert(type(rtc_set_time) == type(rtc_expected_set),
        string.format("联网下设置时间戳后返回值类型测试失败: 预期 %s, 实际 %s",
            type(rtc_expected_set), type(rtc_set_time)))
    log.info("rtc_test", "联网下设置时间戳后返回值类型测试通过")

    assert(
        rtc_set_time.year == rtc_expected_set.year and rtc_set_time.mon == rtc_expected_set.mon and rtc_set_time.day ==
            rtc_expected_set.day and rtc_set_time.hour == rtc_expected_set.hour and rtc_set_time.min ==
            rtc_expected_set.min and rtc_set_time.sec == rtc_expected_set.sec,
        string.format("联网下设置时间戳后返回值数据值测试失败: 预期 %s, 实际 %s",
            json.encode(rtc_expected_set), json.encode(rtc_set_time)))
    log.info("rtc_test", "联网下设置时间戳后返回值数据值测试通过")

    local timezome = 32 -- 东八区
    local rtc_timezome_first = rtc.timezone(timezome) -- 设置时区为东八区
    local rtc_timezome_first_time = rtc.get()
    local timezome_expected_first = {
        year = 2025,
        min = 10,
        hour = 8, -- 东八区时间是北京时间
        mon = 10,
        sec = 53,
        day = 28
    }
    assert(rtc_timezome_first == timezome, string.format(
        "联网下设置时区为东8区测试失败：预期%s，实际%s", timezome, rtc_timezome_first))
    log.info("rtc_test", "联网下设置时区为东8区测试通过")

    assert(rtc_timezome_first_time.year == timezome_expected_first.year and rtc_timezome_first_time.mon ==
               timezome_expected_first.mon and rtc_timezome_first_time.day == timezome_expected_first.day and
               rtc_timezome_first_time.hour == timezome_expected_first.hour and rtc_timezome_first_time.min ==
               timezome_expected_first.min and rtc_timezome_first_time.sec == timezome_expected_first.sec,
        string.format("联网下东8区时间数据值测试失败: 预期 %s, 实际 %s",
            json.encode(timezome_expected_first), json.encode(rtc_timezome_first_time)))
    log.info("rtc_test", "联网下东8区时间数据值测试通过")

    if device_name == "Air8000" or device_name == "Air8101" then
        exnetif.set_priority_order({{
            WIFI = {
                ssid = "luatos1234", -- ssid为要连接的WiFi路由器名称，根据实际情况填写；
                password = "12341234" -- password为要连接的WiFi路由器密码，根据实际情况填写；
            }
        }})
        while not socket.adapter(socket.dft()) do
            log.warn("sntp_task_func", "wait IP_READY", socket.dft())
            -- 在此处阻塞等待默认网卡连接成功的消息"IP_READY"
            -- 或者等待1秒超时退出阻塞等待状态;
            -- 注意：此处的1000毫秒超时不要修改的更长；
            -- 因为当使用exnetif.set_priority_order配置多个网卡连接外网的优先级时，会隐式的修改默认使用的网卡
            -- 当exnetif.set_priority_order的调用时序和此处的socket.adapter(socket.dft())判断时序有可能不匹配
            -- 此处的1秒，能够保证，即使时序不匹配，也能1秒钟退出阻塞状态，再去判断socket.adapter(socket.dft())
            sys.waitUntil("IP_READY", 1000)
        end
    end

    socket.sntp()
    sys.waitUntil("NTP_UPDATE", 5000)
    local loop_count = 0
    for i = 1, 5 do
        local difference_time = timezome / 4 -- 时区偏移量，东八区是+8小时，转换为接口需要的
        local os_date = json.encode(os.date("*t"))
        local os_date_table = {
            year = tonumber(string.match(os_date, '"year":(%d+)')),
            month = tonumber(string.match(os_date, '"month":(%d+)')),
            day = tonumber(string.match(os_date, '"day":(%d+)')),
            hour = tonumber(string.match(os_date, '"hour":(%d+)')),
            min = tonumber(string.match(os_date, '"min":(%d+)')),
            sec = tonumber(string.match(os_date, '"sec":(%d+)'))
        }

        local rtc_get_ostime = rtc.get()

        log.info("联网下循环rtc时间", json.encode(rtc_get_ostime))
        assert(rtc_get_ostime.year == os_date_table.year and rtc_get_ostime.mon == os_date_table.month and
                   rtc_get_ostime.day == os_date_table.day and rtc_get_ostime.hour == os_date_table.hour -
                   difference_time and rtc_get_ostime.min == os_date_table.min and rtc_get_ostime.sec ==
                   os_date_table.sec,
            string.format("联网下循环rtc时间数据值测试失败: 预期 %s, 实际 %s",
                json.encode(os_date_table), json.encode(rtc_get_ostime)))
        log.info("rtc_test", "联网下循环rtc时间数据值第" .. i .. "次测试通过")
        sys.wait(1000)
    end
end

function rtc_test.test_rtc_task1()
    local rtc_expected_default
    if device_name == "Air8101" then
        wlan.disconnect()
        rtc_expected_default = {
            year = 1970,
            min = 0,
            hour = 0,
            mon = 1,
            day = 1
        }
    else
        mobile.flymode(0, true)
        sys.waitUntil("IP_LOSE")
        rtc_expected_default = {
            year = 2000,
            min = 0,
            hour = 0,
            mon = 1,
            day = 1
        }
    end

    log.info("开始无网络情况下的rtc时间测试")

    local rtc_default_time = rtc.get()

    assert(type(rtc_default_time) == type(rtc_expected_default),
        string.format("无网络获取默认时间数据类型测试失败: 预期 %s, 实际 %s",
            type(rtc_expected_default), type(rtc_default_time)))
    log.info("rtc_test", "无网络获取默认时间数据类型测试通过")

    assert(rtc_default_time.year == rtc_expected_default.year and rtc_default_time.mon == rtc_expected_default.mon and
               rtc_default_time.day == rtc_expected_default.day and rtc_default_time.hour == rtc_expected_default.hour and
               rtc_default_time.min == rtc_expected_default.min,
        string.format("无网络获取默认时间数据值测试失败: 预期 %s, 实际 %s",
            json.encode(rtc_expected_default), json.encode(rtc_default_time)))
    log.info("rtc_test", "无网络获取默认时间数据值测试通过")

    local rtc_expected_set = {
        year = 2025,
        min = 10,
        hour = 8,
        mon = 10,
        sec = 53,
        day = 28
    }
    -- rtc.set({ year = 2025, mon = 10, day = 28, hour = 8, min = 10, sec = 53 }) -- 设置日期和时间
    local rtc_set = rtc.set(1761639053) ---- 设置时间戳(与上一行的设置效果相同，二选一即可)
    local rtc_set_time = rtc.get()

    assert(rtc_set == true,
        string.format("无网络设置 RTC 时钟的时间测试失败: 预期 %s, 实际 %s", true, rtc_set))
    log.info("rtc_test", "无网络设置时间戳后返回值类型测试通过")

    assert(type(rtc_set_time) == type(rtc_expected_set),
        string.format("无网络设置时间戳后返回值类型测试失败: 预期 %s, 实际 %s",
            type(rtc_expected_set), type(rtc_set_time)))
    log.info("rtc_test", "无网络设置时间戳后返回值类型测试通过")

    assert(
        rtc_set_time.year == rtc_expected_set.year and rtc_set_time.mon == rtc_expected_set.mon and rtc_set_time.day ==
            rtc_expected_set.day and rtc_set_time.hour == rtc_expected_set.hour and rtc_set_time.min ==
            rtc_expected_set.min and rtc_set_time.sec == rtc_expected_set.sec,
        string.format("无网络设置时间戳后返回值数据值测试失败: 预期 %s, 实际 %s",
            json.encode(rtc_expected_set), json.encode(rtc_set_time)))
    log.info("rtc_test", "无网络设置时间戳后返回值数据值测试通过")

    local timezome1 = -32 -- 西八区
    local rtc_timezome_second = rtc.timezone(timezome1) -- 设置时区为西八区
    local rtc_timezome_second_time = rtc.get()
    assert(rtc_timezome_second == timezome1, string.format(
        "无网络设置时区为西8区测试失败：预期%s，实际%s", timezome1, rtc_timezome_second))
    log.info("rtc_test", "设置时区为西8区测试通过")

    local timezome2 = 32 -- 东八区
    local rtc_timezome_first = rtc.timezone(timezome2) -- 设置时区为东八区
    local rtc_timezome_first_time = rtc.get()
    local timezome_expected_first = {
        year = 2025,
        min = 10,
        hour = 8, -- 东八区时间是北京时间
        mon = 10,
        sec = 53,
        day = 28
    }
    assert(rtc_timezome_first == timezome2, string.format(
        "无网络设置时区为东8区测试失败：预期%s，实际%s", timezome2, rtc_timezome_first))
    log.info("rtc_test", "无网络设置时区为东8区测试通过")

    assert(rtc_timezome_first_time.year == timezome_expected_first.year and rtc_timezome_first_time.mon ==
               timezome_expected_first.mon and rtc_timezome_first_time.day == timezome_expected_first.day and
               rtc_timezome_first_time.hour == timezome_expected_first.hour and rtc_timezome_first_time.min ==
               timezome_expected_first.min and rtc_timezome_first_time.sec == timezome_expected_first.sec,
        string.format("无网络东8区时间数据值测试失败: 预期 %s, 实际 %s",
            json.encode(timezome_expected_first), json.encode(rtc_timezome_first_time)))
    log.info("rtc_test", "无网络东8区时间数据值测试通过")

    local loop_count = 0
    for i = 1, 5 do
        local difference_time = timezome2 / 4 -- 时区偏移量，东八区是+8小时，转换为接口需要的
        local os_date = json.encode(os.date("*t"))
        local os_date_table = {
            year = tonumber(string.match(os_date, '"year":(%d+)')),
            month = tonumber(string.match(os_date, '"month":(%d+)')),
            day = tonumber(string.match(os_date, '"day":(%d+)')),
            hour = tonumber(string.match(os_date, '"hour":(%d+)')),
            min = tonumber(string.match(os_date, '"min":(%d+)')),
            sec = tonumber(string.match(os_date, '"sec":(%d+)'))
        }

        local rtc_get_ostime = rtc.get()

        log.info("无网络循环rtc时间", json.encode(rtc_get_ostime))
        assert(rtc_get_ostime.year == os_date_table.year and rtc_get_ostime.mon == os_date_table.month and
                   rtc_get_ostime.day == os_date_table.day and rtc_get_ostime.hour == os_date_table.hour -
                   difference_time and rtc_get_ostime.min == os_date_table.min and rtc_get_ostime.sec ==
                   os_date_table.sec,
            string.format("无网络循环rtc时间数据值测试失败: 预期 %s, 实际 %s",
                json.encode(os_date_table), json.encode(rtc_get_ostime)))
        log.info("rtc_test", "无网络循环rtc时间数据值第" .. i .. "次测试通过")

        loop_count = loop_count + 1
        if loop_count >= 5 then
            if device_name == "Air8101" then
                wlan.connect("luatos1234", "12341234")
            else
                mobile.flymode(0, false)
                sys.waitUntil("NET_READY", 10000)
            end
            log.info("rtc_test", "无网络测试结束，网络已就绪")
            return
        end
        sys.wait(1000)
    end
end

return rtc_test
