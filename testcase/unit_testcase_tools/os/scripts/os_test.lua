local os_tests = {}

function os_tests.test_osDate_default()
    local default_time = os.date()
    assert(type(default_time) == "string", "默认格式应该返回字符串")
    assert(#default_time > 0 and string.match(default_time, "^%a"),
        "日期字符串不应该为空且第一个字符应为英文字母")
end

function os_tests.test_osDate_format()
    local formatted_time = os.date("%Y-%m-%d %H:%M:%S")
    assert(type(formatted_time) == "string", "应该返回字符串")
    -- 验证格式：YYYY-MM-DD HH:MM:SS
    assert(string.match(formatted_time, "^%d%d%d%d%-%d%d%-%d%d %d%d:%d%d:%d%d$"), "格式不正确: " .. formatted_time)
end

function os_tests.test_osDate_formatTimestamp()
    local test_table = {
        year = 2023,
        mon = 1,
        day = 1,
        hour = 8,
        min = 0,
        sec = 0
    }
    local expected_time = "2023-01-01 16:00:00"
    local expected_timestamp = 1672560000
    local specific_timestamp = os.time(test_table)
    assert(type(specific_timestamp) == "number", "应该返回数字")
    assert(specific_timestamp == expected_timestamp,
        string.format("时间戳计算错误: 预期 %s, 实际 %s", expected_timestamp, specific_timestamp))
    local formatted_time = os.date("%Y-%m-%d %H:%M:%S", specific_timestamp)
    assert(formatted_time == expected_time, string.format(
        "将时间转换为指定格式的字符串错误: 预期 %s, 实际 %s", expected_time, formatted_time))
end

function os_tests.test_osDate_formatTable()
    -- 获取当前时间的table格式
    local time_table = os.date("*t")

    -- 1. 验证返回的是table
    assert(type(time_table) == "table", "os.date('*t') 应该返回table")

    -- 2. 验证包含所有9个字段
    local expected_fields = {"year", -- 年份
    "month", -- 月份
    "day", -- 日期
    "hour", -- 小时
    "min", -- 分钟
    "sec", -- 秒钟
    "wday", -- 星期几
    "yday", -- 一年中的第几天
    "isdst" -- 夏令时标志
    }
    -- 检查每个字段是否存在
    for _, field in ipairs(expected_fields) do
        assert(time_table[field] ~= nil, string.format("table缺少字段: %s", field))
    end

    -- 3. 可选：验证字段类型和范围
    assert(type(time_table.year) == "number", "year字段应该是数字")
    assert(time_table.year >= 1900, "年份应该>=1900")

    assert(type(time_table.month) == "number", "mon字段应该是数字")
    assert(time_table.month >= 1 and time_table.month <= 12, "月份应该在1-12之间，实际: " .. time_table.month)

    assert(type(time_table.day) == "number", "day字段应该是数字")
    assert(time_table.day >= 1 and time_table.day <= 31, "日期应该在1-31之间，实际: " .. time_table.day)

    -- 4. 验证正好有9个字段（没有多余字段）
    local field_count = 0
    for _ in pairs(time_table) do
        field_count = field_count + 1
    end

    assert(field_count == 9, string.format("table应该包含9个字段，实际有%d个字段", field_count))

    log.info("测试通过", "os.date('*t') 返回了包含9个字段的有效table")
end
-- 测试用例 : 正差值
function os_tests.test_osDifftime_sec()
    local time1 = os.time({
        year = 2023,
        mon = 1,
        day = 1,
        hour = 0,
        min = 0,
        sec = 0
    })
    local time2 = os.time({
        year = 2023,
        mon = 1,
        day = 2,
        hour = 0,
        min = 0,
        sec = 0
    })
    local diff = os.difftime(time2, time1)
    local expected_diff = 86400
    assert(diff == expected_diff, string.format("时间差计算错误: 预期 %s, 实际 %s", expected_diff, diff))
end

function os_tests.test_osDifftimeReverse()
    -- 测试用例 : 负差值
    local time1 = os.time({
        year = 2023,
        mon = 1,
        day = 1,
        hour = 0,
        min = 0,
        sec = 0
    })
    local time2 = os.time({
        year = 2023,
        mon = 1,
        day = 2,
        hour = 0,
        min = 0,
        sec = 0
    })
    local diff_negative = os.difftime(time1, time2)
    local expected_diff = -86400
    assert(diff_negative == expected_diff,
        string.format("时间差计算错误: 预期 %s, 实际 %s", expected_diff, diff_negative))
end

-- 测试用例 : 天数时间差计算
function os_tests.test_osDifftime_day()
    local time_a = os.time({
        year = 2024,
        month = 1,
        day = 1,
        hour = 0,
        min = 0,
        sec = 0
    })
    local time_b = os.time({
        year = 2025,
        month = 1,
        day = 1,
        hour = 0,
        min = 0,
        sec = 0
    })
    local difference = os.difftime(time_b, time_a)
    local days = difference / (24 * 60 * 60)
    local days_formatted = string.format("%.2f", days)
    local expected_days = "366.00"
    assert(expected_days == days_formatted,
        string.format("天数时间差计算错误: 预期 %s, 实际 %s", expected_days, days_formatted))
end

-- os.rename()接口测试
-- 测试1：修改源文件存在且非只读的文件名字
function os_tests.test_osRenameExist_wr()
    local old_file = "/os_test_old.txt"
    local file = io.open(old_file, "w")
    if file then
        file:write("这是用于测试os.rename的源文件内容\n")
        file:close()
        log.info("os.rename", "创建源文件成功:", old_file)
    end
    local success, errmsg = os.rename("/os_test_old.txt", "/os_test_new.txt")
    assert(success == true and errmsg == nil, string.format(
        "修改源文件存在且非只读的文件名字失败: 结果 %s, 错误信息 %s", success, errmsg))
    log.info("测试通过√：修改源文件存在且非只读的文件名字成功")
end

-- 测试2：修改源文件存在且只读的文件名字
function os_tests.test_osRenameExist_r()
    local old_file = "/luadb/os_test_old.txt"
    local file = io.open(old_file)
    if file then
        log.info("os.rename1", "创建源文件成功:", old_file)
    end
    local success, errmsg = os.rename("/os_test_old.txt", "/os_test_new.txt")
    assert(success ~= true and errmsg ~= nil, string.format(
        "源文件存在且只读的文件名字不能被修改: 结果 %s, 错误信息 %s", success, errmsg))
    log.info("测试通过√：不能修改源文件存在且只读的文件名字")
end

-- -- 测试3：目标文件存在目录也存在
function os_tests.test_osRenameTargetFileExist()
    local testDir = "/test_dir"
    log.info("io_test", "创建目录:", io.mkdir(testDir))
    local ret, data = io.lsdir(testDir)
    -- 在目录中创建几个测试文件
    io.writeFile(testDir .. "/file1.txt", "测试文件1")
    io.writeFile(testDir .. "/file2.txt", "测试文件2")
    io.writeFile(testDir .. "/file3.txt", "测试文件3")
    local _, files_before = io.lsdir(testDir)
    local success, errmsg = os.rename("/test_dir/file1.txt", "/test_dir/file2.txt")
    local _, files_after = io.lsdir(testDir)
    assert(success == true and errmsg == nil,
        string.format("目标文件存在的文件名字能被修改: 结果 %s, 错误信息 %s", success, errmsg))

    assert(#files_after < #files_before,
        string.format(
            "目标文件存在的文件名字能被修改但会覆盖,文件数会减少：实际有%d个文件",
            #files_after))
    log.info("测试通过√：目标文件存在的文件名字能被修改，但会覆盖")

    io.rmdir(testDir) -- 清理
end

-- 测试4：目标文件目录不存在
function os_tests.test_osRenameTargetDirectory_notExist()
    local testDir = "/test_dir1"
    log.info("io_test1", "创建目录:", io.mkdir(testDir))
    -- 在目录中创建几个测试文件
    io.writeFile(testDir .. "/file1.txt", "测试文件1")
    local success, errmsg = os.rename("/test_dir1/file1.txt", "/test_dir2/file2.txt")
    assert(success ~= true and errmsg ~= nil, string.format(
        "目标文件存在的文件名字不能被修改: 结果 %s, 错误信息 %s", success, errmsg))
    log.info("测试通过√：目标文件目录不存在的文件名字不能被修改")
    io.rmdir("testDir") -- 清理
end

--测试5：修改源文件不存在的文件名字
function os_tests.test_osRenameFileIsNotExist()
    local old_file = "os_test_old.txt"
     local success, errmsg = os.rename("os_test_old.txt", "/file2.txt")
     assert(success ~= true and errmsg ~= nil,
        string.format("源文件不存在的文件名字不能被修改: 结果 %s, 错误信息 %s", success, errmsg))
       log.info("测试通过√：源文件不存在的文件名字不能被修改，请检查文件是否创建失败") 


end

-- os.remove()接口：
--测试1：删除非只读的文件
function os_tests.test_osRemoveFileIsExist()
    local testDir = "/test"
    log.info("io_test", "创建目录:", io.mkdir(testDir))
    -- 在目录中创建几个测试文件
    io.writeFile(testDir .. "/file1.txt", "测试文件1")
    io.writeFile(testDir .. "/file2.txt", "测试文件2")
    io.writeFile(testDir .. "/file3.txt", "测试文件3")
    local success, errmsg = os.remove("/test/file1.txt")
    assert(success == true and errmsg == nil,
        string.format("非只读文件删除成功: 结果 %s, 错误信息 %s", success, errmsg))
    log.info("测试通过√：非只读文件删除成功")
    io.rmdir(testDir) -- 清理
end


return os_tests
