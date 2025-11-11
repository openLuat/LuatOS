--[[
@module  os_core_demo
@summary LuatOS os核心库功能演示模块，严格按照官方API文档展示所有接口
@version 001.000.000
@date    2025.10.23
@author  王棚嶙
@usage
本模块演示了LuatOS os核心库官方文档中的所有API功能，包括：
1. os.remove - 删除文件
2. os.rename - 文件重命名  
3. os.date - 格式化时间日期
4. os.time - 获取时间戳
5. os.difftime - 计算时间差

]]
local function os_core_demo()
    log.info("os_core", "===== 开始os核心库API演示 =====")
    
    -- 1. 演示os.date接口 - 格式化时间日期功能
    log.info("os.date", "===== 开始os.date接口演示 =====")
    
    -- 获取默认格式的本地时间字符串
    local default_time = os.date()
    log.info("os.date", "默认格式本地时间:", default_time)
    
    -- 获取指定格式的本地时间字符串
    local formatted_time = os.date("%Y-%m-%d %H:%M:%S")
    log.info("os.date", "自定义格式本地时间:", formatted_time)
    
    -- 获取UTC时间字符串（使用!前缀）
    local utc_time = os.date("!%Y-%m-%d %H:%M:%S")
    log.info("os.date", "UTC时间:", utc_time)
    
    -- 获取本地时间table（使用*t）
    local local_table = os.date("*t")
    log.info("os.date", "本地时间table:", "year=" .. local_table.year .. ", month=" .. local_table.month .. ", day=" .. local_table.day)
    
    -- 获取UTC时间table（使用!*t）
    local utc_table = os.date("!*t")
    log.info("os.date", "UTC时间table:", "year=" .. utc_table.year .. ", month=" .. utc_table.month .. ", day=" .. utc_table.day)
    
    -- 格式化指定时间戳
    local specific_timestamp = os.time({year=2024, month=12, day=25, hour=10, min=30, sec=0})
    local specific_time = os.date("%Y年%m月%d日 %H:%M:%S", specific_timestamp)
    log.info("os.date", "指定时间戳格式化:", specific_time)
    
    log.info("os.date", "===== os.date接口演示完成 =====")
    
    -- 2. 演示os.time接口 - 获取时间戳功能
    log.info("os.time", "===== 开始os.time接口演示 =====")
    
    -- 获取当前时间戳
    local current_timestamp = os.time()
    log.info("os.time", "当前时间戳:", current_timestamp, "秒")
    
    -- 从指定时间表获取时间戳
    local specific_time = {
        year = 2024,
        month = 12,
        day = 25,
        hour = 10,
        min = 30,
        sec = 0
    }
    local specific_timestamp = os.time(specific_time)
    log.info("os.time", "指定时间的时间戳:", specific_timestamp, "秒")
    
    -- 获取当前时间的详细时间信息
    local current_time_table = os.date("*t", current_timestamp)
    log.info("os.time", "当前时间详细信息:", "year=" .. current_time_table.year .. ", month=" .. current_time_table.month .. ", day=" .. current_time_table.day)
    
    log.info("os.time", "===== os.time接口演示完成 =====")
    
    -- 3. 演示os.difftime接口 - 计算时间差功能
    log.info("os.difftime", "===== 开始os.difftime接口演示 =====")
    
    -- 获取两个时间点的时间戳
    local time_a = os.time({year=2024, month=1, day=1, hour=0, min=0, sec=0})
    local time_b = os.time({year=2025, month=1, day=1, hour=0, min=0, sec=0})
    
    log.info("os.difftime", "时间点A (2024-01-01):", time_a, "秒")
    log.info("os.difftime", "时间点B (2025-01-01):", time_b, "秒")
    
    -- 计算时间差
    local difference = os.difftime(time_b, time_a)
    log.info("os.difftime", "时间差(B-A):", difference, "秒")
    
    -- 转换为天数显示
    local days = difference / (24 * 60 * 60)
    log.info("os.difftime", "时间差(B-A):", string.format("%.3f", days), "天")
    
    -- 计算负时间差
    local negative_diff = os.difftime(time_a, time_b)
    log.info("os.difftime", "时间差(A-B):", negative_diff, "秒")
    
    log.info("os.difftime", "===== os.difftime接口演示完成 =====")
    
    -- 4. 演示os.remove接口 - 文件删除功能
    log.info("os.remove", "===== 开始os.remove接口演示 =====")
    
    -- 首先创建一个测试文件用于删除
    local test_file = "/os_test_delete.txt"
    local file = io.open(test_file, "w")
    if file then
        file:write("这是用于测试os.remove的示例文件内容\n")
        file:close()
        log.info("os.remove", "创建测试文件成功:", test_file)
    else
        log.error("os.remove", "创建测试文件失败")
        -- 继续演示，尝试删除可能存在的文件
    end
    
    -- 验证文件存在
    if io.exists(test_file) then
        log.info("os.remove", "测试文件存在，准备删除")
    else
        log.warn("os.remove", "测试文件不存在，将尝试删除操作")
    end
    
    -- 使用os.remove删除文件
    local success, errmsg = os.remove(test_file)
    
    if success then
        log.info("os.remove", "文件删除成功")
        
        -- 验证文件已删除
        if not io.exists(test_file) then
            log.info("os.remove", "删除验证通过，文件已不存在")
        end
    else
        log.error("os.remove", "文件删除失败，错误信息:", errmsg or "未知错误")
    end
    
    log.info("os.remove", "===== os.remove接口演示完成 =====")
    
    -- 5. 演示os.rename接口 - 文件重命名功能
    log.info("os.rename", "===== 开始os.rename接口演示 =====")
    
    -- 首先创建源文件
    local old_file = "/os_test_old.txt"
    local new_file = "/os_test_new.txt"
    
    local file = io.open(old_file, "w")
    if file then
        file:write("这是用于测试os.rename的源文件内容\n")
        file:close()
        log.info("os.rename", "创建源文件成功:", old_file)
    else
        log.error("os.rename", "创建源文件失败")
        -- 继续演示，尝试重命名可能存在的文件
    end
    
    -- 验证源文件存在
    if io.exists(old_file) then
        log.info("os.rename", "源文件存在，准备重命名")
    else
        log.warn("os.rename", "源文件不存在，将尝试重命名操作")
    end
    
    -- 清理目标文件（如果存在）
    if io.exists(new_file) then
        os.remove(new_file)
        log.info("os.rename", "清理已存在的目标文件:", new_file)
    end
    
    -- 使用os.rename重命名文件
    local success, errmsg = os.rename(old_file, new_file)
    
    if success then
        log.info("os.rename", "文件重命名成功:", old_file, "->", new_file)
        
        -- 验证原文件不存在
        if not io.exists(old_file) then
            log.info("os.rename", "原文件已不存在，重命名验证通过")
        end
        
        -- 验证新文件存在
        if io.exists(new_file) then
            log.info("os.rename", "新文件存在验证通过:", new_file)
        end
        
        -- 清理测试文件
        os.remove(new_file)
        log.info("os.rename", "测试文件已清理")
    else
        log.error("os.rename", "文件重命名失败，错误信息:", errmsg or "未知错误")
        -- 尝试清理源文件
        if io.exists(old_file) then
            os.remove(old_file)
        end
    end
    
    log.info("os.rename", "===== os.rename接口演示完成 =====")
    
    log.info("os_core", "===== os核心库API演示全部完成 =====")
end

sys.taskInit(os_core_demo)
