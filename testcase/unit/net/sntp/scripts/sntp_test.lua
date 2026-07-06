local sntp_test = {}

-- 自定义NTP服务器列表，可选配置，默认使用内置的ntp服务器地址ntp.aliyun.com
local ntp_servers = {"ntp.aliyun.com", "ntp.air32.cn", "time1.cloud.tencent.com"}

-- 全局变量记录上次同步成功的时间戳
local last_high_precision_time = nil
local sync_count = 0

-- 时间规范化函数
function normalize_time_struct(time_struct)
    local normalized = {}
    for k, v in pairs(time_struct) do
        normalized[k] = v
    end

    if normalized.hour >= 24 then
        -- 计算进位天数
        local extra_days = math.floor(normalized.hour / 24)
        -- 计算剩余小时
        normalized.hour = normalized.hour % 24

        -- 增加天数
        normalized.day = normalized.day + extra_days

        -- 需要处理月份和年份的进位
        -- 获取每个月的天数（考虑闰年）
        local function days_in_month(year, month)
            local month_days = {31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31}
            -- 闰年判断（能被4整除但不能被100整除，或者能被400整除）
            if month == 2 then
                if (year % 4 == 0 and year % 100 ~= 0) or (year % 400 == 0) then
                    return 29
                end
            end
            return month_days[month]
        end

        -- 处理天数超过当月天数的情况
        while normalized.day > days_in_month(normalized.year, normalized.month) do
            normalized.day = normalized.day - days_in_month(normalized.year, normalized.month)
            normalized.month = normalized.month + 1

            if normalized.month > 12 then
                normalized.month = 1
                normalized.year = normalized.year + 1
            end
        end

        -- 更新yday（一年中的第几天）
        local function calculate_yday(year, month, day)
            local month_days = {31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31}
            if (year % 4 == 0 and year % 100 ~= 0) or (year % 400 == 0) then
                month_days[2] = 29
            end

            local yday = day
            for i = 1, month - 1 do
                yday = yday + month_days[i]
            end
            return yday
        end

        normalized.yday = calculate_yday(normalized.year, normalized.month, normalized.day)

        -- 更新wday（星期几，1=星期日，7=星期六）
        -- 使用Zeller公式计算星期
        local function calculate_wday(year, month, day)
            if month < 3 then
                month = month + 12
                year = year - 1
            end
            local k = year % 100
            local j = math.floor(year / 100)
            local h = (day + math.floor(13 * (month + 1) / 5) + k + math.floor(k / 4) + math.floor(j / 4) + 5 * j) % 7
            -- 转换：0=星期六，1=星期日，2=星期一，...，6=星期五
            -- 转换为Lua标准：1=星期日，2=星期一，...，7=星期六
            return (h + 5) % 7 + 1
        end

        normalized.wday = calculate_wday(normalized.year, normalized.month, normalized.day)
    end

    return normalized
end

-- 验证时间一致性
local function verify_time_consistency()
    -- 获取RTC时钟原始数据（UTC时间）
    local rtc_time = rtc.get()

    -- 获取本地时间结构
    local local_struct_time = os.date("*t")

    -- 获取UTC时间结构
    local utc_struct_time = os.date("!*t")

    -- 检查本地时间与RTC时间的差值是否为8小时（东八区）
    -- 将RTC时间（UTC）转换为本地时间结构
    local rtc_as_local = {
        year = rtc_time.year,
        month = rtc_time.mon,
        day = rtc_time.day,
        hour = rtc_time.hour + 8, -- UTC+8
        min = rtc_time.min,
        sec = rtc_time.sec
    }

    -- 规范化时间
    rtc_as_local = normalize_time_struct(rtc_as_local)

    -- 检查年份
    assert(local_struct_time.year == rtc_as_local.year,
        string.format("比较本地时间和UTC年份测试失败: 本地=%d, RTC=%d", local_struct_time.year,
            rtc_as_local.year))
    log.info("比较本地时间和UTC年份测试通过")

    -- 检查月份
    assert(local_struct_time.month == rtc_as_local.month,
        string.format("比较本地时间和UTC月份测试失败: 本地=%d, RTC=%d", local_struct_time.month,
            rtc_as_local.month))
    log.info("比较本地时间和UTC月份测试通过")

    -- 检查日期
    assert(local_struct_time.day == rtc_as_local.day, string.format(
        "比较本地时间和UTC日期测试失败: 本地=%d, RTC=%d", local_struct_time.day, rtc_as_local.day))
    log.info("比较本地时间和UTC日期测试通过")

    -- 检查小时
    local hour_diff = math.abs(local_struct_time.hour - rtc_as_local.hour)
    assert(hour_diff <= 1,
        string.format("比较本地时间和UTC小时测试失败: 本地=%d, RTC=%d, 差值=%d",
            local_struct_time.hour, rtc_as_local.hour, hour_diff))
    log.info("比较本地时间和UTC小时测试通过")

    -- 检查分钟
    local min_diff = math.abs(local_struct_time.min - rtc_as_local.min)
    assert(min_diff <= 1,
        string.format("比较本地时间和UTC分钟测试失败: 本地=%d, RTC=%d, 差值=%d", local_struct_time.min,
            rtc_as_local.min, min_diff))
    log.info("比较本地时间和UTC分钟测试通过")

    -- 检查秒钟
    local sec_diff = math.abs(local_struct_time.sec - rtc_as_local.sec)
    assert(sec_diff <= 1,
        string.format("比较本地时间和UTC秒钟测试失败: 本地=%d, RTC=%d, 差值=%d", local_struct_time.sec,
            rtc_as_local.sec, sec_diff))
    log.info("比较本地时间和UTC秒钟测试通过")

    -- 验证本地时间与UTC时间的差值是否为8小时
    local local_timestamp = os.time(local_struct_time)
    local utc_timestamp = os.time(utc_struct_time)
    local time_diff = local_timestamp - utc_timestamp

    assert(time_diff == 28800,
        string.format("比较本地时间和UTC小时差测试失败: 实际=%d秒, 预期=28800秒", time_diff))
    log.info("比较本地时间和UTC小时差测试通过")
end

-- 判断是否为有效的高精度时间（不是系统启动时间）
local function is_valid_high_precision_time(ntp_time)
    if not ntp_time or not ntp_time.tsec then
        return false
    end

    -- 如果tsec小于100000（约1天），很可能是系统启动时间
    -- 实际的时间戳应该在1609459200（2021年之后）
    return ntp_time.tsec > 1000000
end

-- 验证高精度时间连续性
local function verify_high_precision_time_continuity(current_high_precision_time)
    -- 增加同步计数
    sync_count = sync_count + 1

    log.info("sntp", string.format("第%d次同步的高精度时间检查", sync_count))

    -- 判断当前时间是否有效
    local is_current_valid = is_valid_high_precision_time(current_high_precision_time)

    if not is_current_valid then
        log.info("sntp", "当前高精度时间为系统启动时间，跳过连续性验证")
        last_high_precision_time = current_high_precision_time
        return
    end

    -- 检查是否有上次的有效高精度时间记录
    if last_high_precision_time and is_valid_high_precision_time(last_high_precision_time) then
        -- 考虑毫秒部分
        local current_total_ms = current_high_precision_time.tsec * 1000 + current_high_precision_time.tms
        local last_total_ms = last_high_precision_time.tsec * 1000 + last_high_precision_time.tms
        local ms_passed = current_total_ms - last_total_ms

        -- 预期的等待时间（毫秒），每次测试等待2秒
        local expected_wait_ms = 2000

        -- 放宽误差范围：预期等待时间 ± 1000ms（1秒）
        -- 考虑到网络延迟、系统调度等因素
        local min_expected_ms = expected_wait_ms - 1000 -- 1秒
        local max_expected_ms = expected_wait_ms + 1000 -- 3秒

        log.info("sntp", "高精度时间连续性检查:")
        log.info("sntp", string.format("  上次时间: %d.%03d秒", last_high_precision_time.tsec,
            last_high_precision_time.tms))
        log.info("sntp", string.format("  本次时间: %d.%03d秒", current_high_precision_time.tsec,
            current_high_precision_time.tms))
        log.info("sntp", string.format("  时间增量: %.3f秒", ms_passed / 1000))
        log.info("sntp", string.format("  预期增量: %.3f秒 (±1.0秒)", expected_wait_ms / 1000))

        -- 验证时间连续性
        assert(ms_passed >= min_expected_ms,
            string.format("高精度时间连续性测试失败: 增量太小, 实际=%.3f秒, 最小预期=%.3f秒",
                ms_passed / 1000, min_expected_ms / 1000))

        assert(ms_passed <= max_expected_ms,
            string.format("高精度时间连续性测试失败: 增量太大, 实际=%.3f秒, 最大预期=%.3f秒",
                ms_passed / 1000, max_expected_ms / 1000))

        -- 检查时间回退
        assert(ms_passed >= 0, string.format("检测到时间回退: 增量=%.3f秒", ms_passed / 1000))

        log.info("sntp", "高精度时间连续性验证通过")
    else
        log.info("sntp", "无有效的上一次高精度时间记录，跳过连续性验证")
    end

    -- 更新记录
    last_high_precision_time = current_high_precision_time
end

-- 打印时间信息的工具函数
local function print_time_details()
    -- 执行时间一致性验证
    verify_time_consistency()
end

-- 打印高精度时间戳并进行验证
local function print_and_verify_high_precision_time()
    local ntp_time = socket.ntptm()

    assert(ntp_time ~= nil and ntp_time.tsec ~= nil, "高精度时间戳获取失败")

    log.info("sntp", "高精度时间戳", string.format("%u.%03d", ntp_time.tsec, ntp_time.tms))

    -- 验证高精度时间连续性
    verify_high_precision_time_continuity(ntp_time)

    return ntp_time
end

function sntp_test.test_custom_servers()
    -- 重置计数器
    sync_count = 0
    last_high_precision_time = nil

    -- 等待网络就绪
    while not socket.adapter(socket.dft()) do
        log.warn("sntp", "wait IP_READY", socket.dft())
        sys.waitUntil("IP_READY", 1000)
    end

    log.info("sntp", "recv IP_READY", socket.dft())

    for i = 1, 5 do
        log.info("sntp", string.format("开始第%d次时间同步测试", i))

        -- 方式1：使用自定义服务器列表
        log.info("sntp", "开始同步，服务器列表：", json.encode(ntp_servers))
        -- 选择自己要用的的服务器
        socket.sntp(ntp_servers[2])

        -- 等待同步结果
        local sync_success = sys.waitUntil("NTP_UPDATE", 5000)

        assert(sync_success == true, string.format(
            "使用自定义服务器地址等待同步测试失败：预期true，实际%s", sync_success))
        log.info("使用自定义服务器地址等待同步测试通过")

        log.info("sntp", string.format("第%d次同步成功", i))

        -- 打印时间详情
        print_time_details()

        -- 打印并验证高精度时间
        print_and_verify_high_precision_time()

        -- 等待2秒进行下一次测试
        sys.wait(2000)
    end

    log.info("sntp", "所有时间同步测试完成")
    log.info("sntp", string.format("总计同步次数: %d", sync_count))
end

function sntp_test.test_default_servers()
    -- 重置计数器
    sync_count = 0
    last_high_precision_time = nil

    -- 等待网络就绪
    while not socket.adapter(socket.dft()) do
        log.warn("sntp", "wait IP_READY", socket.dft())
        sys.waitUntil("IP_READY", 1000)
    end

    log.info("sntp", "recv IP_READY", socket.dft())

    for i = 1, 10 do
        log.info("sntp", string.format("开始第%d次时间同步测试", i))

        -- 使用默认的ntp服务器地址：ntp.aliyun.com
        socket.sntp()

        -- 等待同步结果
        local sync_success = sys.waitUntil("NTP_UPDATE", 5000)

        assert(sync_success == true, string.format(
            "使用默认的ntp服务器地址等待同步测试失败：预期true，实际%s", sync_success))
        log.info("使用默认的ntp服务器地址等待同步测试通过")

        log.info("sntp", string.format("第%d次同步成功", i))

        -- 打印时间详情
        print_time_details()

        -- 打印并验证高精度时间
        print_and_verify_high_precision_time()

        -- 等待2秒进行下一次测试
        sys.wait(2000)
    end

    log.info("sntp", "所有时间同步测试完成")
    log.info("sntp", string.format("总计同步次数: %d", sync_count))
end

-- 订阅NTP错误消息
sys.subscribe("NTP_ERROR", function(err_info)
    log.error("sntp", "同步过程发生错误", err_info or "未知错误")
end)

return sntp_test
