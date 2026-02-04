local rtc_test = {}

function rtc_test.test_rtc_task1()
    log.info("开始无网络情况下的rtc时间测试")
    local rtc_expected_default = {
        year = 2000,
        min = 0,
        hour = 0,
        mon = 1,
        sec = 5,
        day = 1
    }
    local rtc_default_time = rtc.get()
    log.info("默认时间：", json.encode(rtc_default_time)) -- 打印当前日期和时间

    assert(type(rtc_default_time) == type(rtc_expected_default),
        string.format("无网络获取默认时间数据类型测试失败: 预期 %s, 实际 %s",
            type(rtc_expected_default), type(rtc_default_time)))
    log.info("rtc_test", "无网络获取默认时间数据类型测试通过")

    assert(rtc_default_time.year == rtc_expected_default.year and rtc_default_time.mon == rtc_expected_default.mon and
               rtc_default_time.day == rtc_expected_default.day and rtc_default_time.hour == rtc_expected_default.hour and
               rtc_default_time.min == rtc_expected_default.min and rtc_default_time.sec == rtc_expected_default.sec,
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

    assert(rtc_set == true, string.format("设置 RTC 时钟的时间测试失败: 预期 %s, 实际 %s", true, rtc_set))
    log.info("rtc_test", "设置时间戳后返回值类型测试通过")

    assert(type(rtc_set_time) == type(rtc_expected_set),
        string.format("设置时间戳后返回值类型测试失败: 预期 %s, 实际 %s", type(rtc_expected_set),
            type(rtc_set_time)))
    log.info("rtc_test", "设置时间戳后返回值类型测试通过")

    assert(
        rtc_set_time.year == rtc_expected_set.year and rtc_set_time.mon == rtc_expected_set.mon and rtc_set_time.day ==
            rtc_expected_set.day and rtc_set_time.hour == rtc_expected_set.hour and rtc_set_time.min ==
            rtc_expected_set.min and rtc_set_time.sec == rtc_expected_set.sec,
        string.format("设置时间戳后返回值数据值测试失败: 预期 %s, 实际 %s",
            json.encode(rtc_expected_set), json.encode(rtc_set_time)))
    log.info("rtc_test", "设置时间戳后返回值数据值测试通过")


end

return rtc_test
