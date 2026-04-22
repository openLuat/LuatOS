local rtc_test = {}
local device_name = rtos.bsp()

local exnetif = require "exnetif"
local original_time
local original_tz

-- rtc.set函数的参数类型和异常值测试
function rtc_test.test_rtc_set_params()
    log.info("开始测试 rtc.set 参数类型和异常值")

    -- 测试table类型参数设置
    local set_table = rtc.set({
        year = 2025,
        mon = 10,
        day = 28,
        hour = 8,
        min = 10,
        sec = 53
    })
    assert(set_table == true, string.format("table类型参数设置失败: 预期true, 实际%s", tostring(set_table)))
    log.info("rtc_test", "table类型参数设置测试通过")

    -- 测试number类型参数设置(时间戳)
    local set_number = rtc.set(1761639053)
    assert(set_number == true,
        string.format("number类型参数设置测试失败: 预期true, 实际%s", tostring(set_number)))
    log.info("rtc_test", "number类型参数设置测试通过")

    -- 测试nil参数
    local set_nil = rtc.set(nil)
    assert(set_nil == nil or set_nil == false,
        string.format("nil参数设置测试失败: 预期nil/false, 实际%s", tostring(set_nil)))
    log.info("rtc_test", "nil参数设置测试通过")

    -- 测试string类型参数
    local set_string = rtc.set("2025-10-28 08:10:53")
    assert(set_string == nil or set_string == false,
        string.format("string参数设置测试失败: 预期nil/false, 实际%s", tostring(set_string)))
    log.info("rtc_test", "string参数设置测试通过")

    -- 测试异常时间戳/
    local set_negative = rtc.set(-1761639053)
    assert(set_negative == false or set_negative == nil,
        string.format("负数时间戳设置测试失败: 预期false/nil, 实际%s", tostring(set_negative)))
    log.info("rtc_test", "负数时间戳参数设置测试通过")

    -- 测试异常时间戳（超大值，超过2038年）
    local set_overflow = rtc.set(5000000000)
    assert(set_overflow == false or set_overflow == nil,
        string.format("超大时间戳设置测试失败: 预期false/nil, 实际%s", tostring(set_overflow)))
    log.info("rtc_test", "超大时间戳参数设置测试通过")

    -- 测试不完整的table参数（缺少必要字段）
    local set_incomplete = rtc.set({
        year = 2025,
        mon = 10,
        day = 28
    })
    assert(set_incomplete == false or set_incomplete == nil,
        string.format("不完整table参数设置测试失败: 预期false/nil, 实际%s", tostring(set_incomplete)))
    log.info("rtc_test", "不完整table参数设置测试通过")

    -- 测试错误负数参数
    local set_invalid_date = rtc.set({
        year = -2025,
        mon = -2,
        day = -31,
        hour = -7,
        min = -10,
        sec = -23
    })
    assert(set_invalid_date == false or set_invalid_date == nil,
        string.format("负数参数设置测试失败: 预期false, 实际%s", tostring(set_invalid_date)))
    log.info("rtc_test", "负数参数设置测试通过")

    -- 测试无效的日期值（如2月31日）
    local set_invalid_date = rtc.set({
        year = 2025,
        mon = 2,
        day = 31,
        hour = 7,
        min = 10,
        sec = 23
    })
    assert(set_invalid_date == false or set_invalid_date == nil,
        string.format("无效日期参数设置测试失败: 预期false, 实际%s", tostring(set_invalid_date)))
    log.info("rtc_test", "无效日期参数设置测试通过")

    -- 测试无效的时间值（小时超出范围）
    local set_invalid_hour = rtc.set({
        year = 2025,
        mon = 10,
        day = 28,
        hour = 25,
        min = 10,
        sec = 53
    })
    assert(set_invalid_hour == false or set_invalid_hour == nil,
        string.format("无效小时参数设置测试失败: 预期false/nil, 实际%s", tostring(set_invalid_hour)))
    log.info("rtc_test", "无效小时参数设置测试通过")

    -- 测试0值时间戳
    local set_zero = rtc.set(0)
    assert(set_zero == false or set_zero == nil,
        string.format("0值时间戳设置测试失败: 预期false/nil, 实际%s", tostring(set_zero)))
    log.info("rtc_test", "0值时间戳参数设置测试通过")

    log.info("rtc_test", "===== rtc.set参数类型和异常值测试全部通过 =====")
end

-- rtc.setBaseYear函数测试
function rtc_test.test_rtc_baseyear()
    log.info("开始测试 rtc.setBaseYear 函数")

    -- 保存当前时间用于恢复
    original_time = rtc.get()

    -- 测试设置基准年为1900
    rtc.setBaseYear(1900)
    local set_time = {
        year = 2025,
        mon = 10,
        day = 28,
        hour = 8,
        min = 10,
        sec = 53
    }
    rtc.set(set_time)
    local get_time = rtc.get()
    assert(get_time.year == set_time.year and get_time.mon == set_time.mon and get_time.day == set_time.day,
        "基准年1900设置后时间读写失败")
    log.info("rtc_test", "基准年1900测试通过")

    -- 测试设置基准年为2000
    rtc.setBaseYear(2000)
    rtc.set(set_time)
    get_time = rtc.get()
    log.info("rtc_test", "基准年2000设置后时间: " .. json.encode(get_time))
    assert(get_time.year == set_time.year and get_time.mon == set_time.mon and get_time.day == set_time.day,
        "基准年2000设置后时间读写失败")
    log.info("rtc_test", "基准年2000测试通过，当前时间: " .. json.encode(get_time))

    -- 测试设置负值基准年
    local result = pcall(rtc.setBaseYear, -100)
    assert(result ~= true, "rtc.setBaseYear设置负值基准年测试失败")
    log.info("rtc_test", "rtc.setBaseYear设置负值基准年测试成功")

    -- 测试nil参数
    local result = pcall(rtc.setBaseYear, nil)
    assert(result ~= true, "rtc.setBaseYear设置nil基准年设置测试失败")
    log.info("rtc_test", "rtc.setBaseYear设置nil基准年设置测试成功")

    log.info("rtc_test", "===== rtc.setBaseYear函数测试完成 =====")
end

-- timezone函数完整测试
function rtc_test.test_rtc_timezone_comprehensive()
    log.info("开始测试 rtc.timezone 函数完整功能")

    -- 先设置一个基准时间
    local base_time = {
        year = 2025,
        mon = 10,
        day = 28,
        hour = 12,
        min = 0,
        sec = 0
    }
    rtc.set(base_time)

    -- 保存原始时区
    original_tz = rtc.timezone()

    -- 测试不传参数
    local current_tz = rtc.timezone()
    assert(type(current_tz) == "number" and current_tz == 32,
        string.format("rtc.timezone不传参数读取时区失败，返回值类型错误: 预期number, 实际%s",
            type(current_tz)))
    log.info("rtc_test", string.format("rtc.timezone不传参数读取测试通过: %d (1/4小时单位)", current_tz))

    -- 测试所有标准时区
    local timezones_to_test = {
        [-48] = "西12区",
        [-44] = "西11区",
        [-40] = "西10区",
        [-36] = "西9区",
        [-32] = "西8区",
        [-28] = "西7区",
        [-24] = "西6区",
        [-20] = "西5区",
        [-16] = "西4区",
        [-12] = "西3区",
        [-8] = "西2区",
        [-4] = "西1区",
        [0] = "零时区",
        [4] = "东1区",
        [8] = "东2区",
        [12] = "东3区",
        [16] = "东4区",
        [20] = "东5区",
        [24] = "东6区",
        [28] = "东7区",
        [32] = "东8区",
        [36] = "东9区",
        [40] = "东10区",
        [44] = "东11区",
        [48] = "东12区"
    }

    for tz_value, tz_name in pairs(timezones_to_test) do
        local set_result = rtc.timezone(tz_value)
        assert(set_result == tz_value, string.format("%s(%d)设置失败: 预期返回值%d, 实际%d", tz_name,
            tz_value, tz_value, set_result))

        local utc_time = rtc.get()
        local local_time = os.date("*t")

        local hour_diff = (local_time.hour - utc_time.hour + 24) % 24
        local expected_diff = tz_value / 4
        assert(hour_diff == expected_diff or hour_diff == expected_diff + 24 or hour_diff == expected_diff - 24,
            string.format(
                "%s(%d)时间偏移验证失败: UTC小时%d, 本地小时%d, 预期偏移%d小时, 实际偏移%d小时",
                tz_name, tz_value, utc_time.hour, local_time.hour, expected_diff, hour_diff))

        log.info("rtc_test", string.format("%s(%d)测试通过", tz_name, tz_value))
    end

    -- 测试异常传参
    log.info("rtc_test", "开始测试timezone异常传参")

    -- 测试超出范围的时区值（>48）
    local invalid_tz = 52
    local set_result = rtc.timezone(invalid_tz)
    assert(set_result == false,
        string.format("测试超范围时区设置测试失败: 预期false, 实际%s", tostring(set_result)))
    log.info("rtc_test", string.format("超范围时区%d被拒绝测试成功", invalid_tz))

    -- 测试超出范围的时区值（<-48）
    local invalid_tz = -52
    local set_result = rtc.timezone(invalid_tz)
    assert(set_result == false,
        string.format("超范围时区设置测试失败: 预期false, 实际%s", tostring(set_result)))
    log.info("rtc_test", string.format("超范围时区%d被拒绝测试成功", invalid_tz))

    -- 测试非4的倍数的时区值
    local invalid_tz = 30
    local set_result = rtc.timezone(invalid_tz)
    assert(set_result == false,
        string.format("非4倍数时区设置测试失败: 预期false, 实际%s", tostring(set_result)))
    log.info("rtc_test", string.format("非4倍数时区%d被拒绝测试成功", invalid_tz))

    -- 测试string类型参数
    local result = rtc.timezone("32")
    assert(result == false, "rtc.timezone传入string类型时区参数测试失败")
    log.info("rtc_test", "rtc.timezone传入string类型时区参数测试成功")

    -- 测试nil参数
    local result = rtc.timezone(nil)
    assert(result == false, "rtc.timezone传入nil参数测试失败")
    log.info("rtc_test", "rtc.timezone传入nil参数测试成功")

    -- 测试boolean类型参数
    local result = rtc.timezone(true)
    assert(result == false, "rtc.timezone传入boolean类型时区参数测试失败")
    log.info("rtc_test", "rtc.timezone传入boolean类型时区参数测试成功")

    log.info("rtc_test", "===== rtc.timezone函数完整测试完成 =====")
end

-- 有网络情况下的测试
function rtc_test.test_rtc_task2()
    log.info("开始有网络情况下的rtc时间测试")

    rtc.setBaseYear(1900)
    rtc.set(original_time)
    rtc.timezone(original_tz)

    local rtc_set = rtc.set(1761639053)
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
    local rtc_timezome_first = rtc.timezone(timezome)
    local rtc_timezome_first_time = rtc.get()
    local timezome_expected_first = {
        year = 2025,
        min = 10,
        hour = 8,
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

    socket.sntp()
    sys.waitUntil("NTP_UPDATE", 5000)

    for i = 1, 5 do
        local difference_time = timezome / 4
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

-- 无网络情况下的测试
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

    rtc.setBaseYear(1900)
    rtc.set(original_time)
    rtc.timezone(original_tz)


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
    local rtc_set = rtc.set(1761639053)
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
    local rtc_timezome_second = rtc.timezone(timezome1)
    local rtc_timezome_second_time = rtc.get()
    assert(rtc_timezome_second == timezome1, string.format(
        "无网络设置时区为西8区测试失败：预期%s，实际%s", timezome1, rtc_timezome_second))
    log.info("rtc_test", "设置时区为西8区测试通过")

    local timezome2 = 32 -- 东八区
    local rtc_timezome_first = rtc.timezone(timezome2)
    local rtc_timezome_first_time = rtc.get()
    local timezome_expected_first = {
        year = 2025,
        min = 10,
        hour = 8,
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

    for i = 1, 5 do
        local difference_time = timezome2 / 4
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
        sys.wait(1000)
    end

    if device_name == "Air8101" then
        wlan.connect("luatos1234", "12341234")
    else
        mobile.flymode(0, false)
        sys.waitUntil("NET_READY", 10000)
    end
    log.info("rtc_test", "无网络测试结束，网络已就绪")
end

return rtc_test
