
PROJECT = "os_test"
VERSION = "1.0.0"
local function test_os_remove()
    log.info("os.remove", "测试开始")
    -- 先创建一个测试文件
    local testFile = "/test_remove.txt"
    local f = io.open(testFile, "w")
    if f then
        f:write("test content")
        f:close()
        log.info("os.remove", "测试文件创建成功")
    else
        log.error("os.remove", "无法创建测试文件")
        return
    end

    -- 测试删除文件
    local result, err = os.remove(testFile)
    if result then
        log.info("os.remove", "文件删除成功")
    else
        log.error("os.remove", "文件删除失败", err)
    end

    -- 测试删除不存在的文件
    result, err = os.remove("/nonexistent.txt")
    if not result then
        log.info("os.remove", "删除不存在文件返回预期结果", err)
    end
end

-- 测试 os.rename() 文件重命名功能
local function test_os_rename()
    log.info("os.rename", "测试开始")
    -- 创建源文件
    local srcFile = "/test_rename_src.txt"
    local f = io.open(srcFile, "w")
    if f then
        f:write("test content")
        f:close()
        log.info("os.rename", "源文件创建成功")
    else
        log.error("os.rename", "无法创建源文件")
        return
    end

    -- 目标文件路径
    local dstFile = "/test_rename_dst.txt"

    -- 测试重命名
    local result, err = os.rename(srcFile, dstFile)
    if result then
        log.info("os.rename", "文件重命名成功")

        -- 验证新文件是否存在
        if io.open(dstFile, "r") then
            log.info("os.rename", "验证新文件存在")
            os.remove(dstFile)
        end
    else
        log.error("os.rename", "文件重命名失败", err)
        os.remove(srcFile)
    end

    -- 测试重命名不存在的文件
    result, err = os.rename("/nonexistent_src.txt", "/nonexistent_dst.txt")
    if not result then
        log.info("os.rename", "重命名不存在文件返回预期结果", err)
    end
end

-- 测试 os.date() 和 os.time() 功能
local function test_os_date_time()
    log.info("os.date/time", "测试开始")

    -- 获取当前时间戳
    local currentTimestamp = os.time()
    log.info("os.time", "当前时间戳", currentTimestamp)

    -- 测试 os.date() 各种格式
    log.info("os.date", "默认格式本地时间", os.date())
    log.info("os.date", "默认格式UTC时间", os.date("!%c"))
    log.info("os.date", "自定义格式本地时间", os.date("%Y-%m-%d %H:%M:%S"))
    log.info("os.date", "自定义格式UTC时间", os.date("!%Y-%m-%d %H:%M:%S"))

    -- 测试特定时间
    local testTime = {year=2000, mon=1, day=1, hour=0, min=0, sec=0}
    local testTimestamp = os.time(testTime)
    log.info("os.time", "2000-01-01 00:00:00 时间戳", testTimestamp)
    log.info("os.date", "格式化特定时间", os.date("!%Y-%m-%d %H:%M:%S", testTimestamp))

    -- 测试获取时间表
    local localTimeTable = os.date("*t")
    log.info("os.date", "本地时间表", json.encode(localTimeTable))
    local utcTimeTable = os.date("!*t")
    log.info("os.date", "UTC时间表", json.encode(utcTimeTable))

    -- 测试 os.difftime()
    local time1 = os.time()
    sys.wait(1000) -- 等待1秒
    local time2 = os.time()
    local diff = os.difftime(time2, time1)
    log.info("os.difftime", "时间差(应该约等于1)", diff)
end

-- 主测试函数
local function test_all()
    log.info("OS接口测试", "===== 开始测试 =====")
    test_os_remove()
    test_os_rename()
    test_os_date_time()
    log.info("OS接口测试", "===== 测试完成 =====")
end

-- 启动测试
sys.taskInit(function()
    sys.wait(1000) -- 等待系统初始化
    test_all()
end)
-- 用户代码已结束---------------------------------------------
-- 结尾总是这一句
sys.run()
-- sys.run()之后后面不要加任何语句!!!!!