--[[
@module  log_test
@summary log功能测试模块
@version 1.0
@date    2025.11.19
@author  王世豪
@usage
本demo演示的核心功能为：
1. log.debug 日志等级测试
2. log.info 日志等级测试
3. log.warn 日志等级测试
4. log.error 日志等级测试

]]

local function test_log_output(level_name)
    print(string.format("测试日志级别: %s", level_name))

    log.debug(PROJECT, "debug message") 
    log.info(PROJECT, "info message")
    log.warn(PROJECT, "warn message")
    log.error(PROJECT, "error message")
end

local function logtest_task()
    -- 打印当前默认日志输出等级
    local default_level = log.getLevel()
    print("日志功能测试开始")
    print(string.format("默认日志级别: %s", default_level))
    
    -- 实验1：使用默认日志输出等级测试
    test_log_output(default_level)
    
    -- 实验2：设置为INFO级别，只输出info及以上级别的日志
    log.setLevel("INFO")
    test_log_output("INFO")
    
    -- 实验3：设置为WARN级别，只输出warn及以上级别的日志
    log.setLevel("WARN")
    test_log_output("WARN")
    
    -- 实验4：设置为ERROR级别，只输出error级别的日志
    log.setLevel("ERROR")
    test_log_output("ERROR")
    
    -- 实验5：设置为SILENT级别，完全关闭日志输出
    log.setLevel("SILENT")
    test_log_output("SILENT")
    
    -- 实验6：恢复默认日志输出等级，验证日志输出恢复
    log.setLevel(default_level)
    print("恢复默认日志输出等级: " .. log.getLevel())
    
    -- 测试不同参数类型的日志输出
    log.info(PROJECT, "数值:", 123, "布尔值:", true, "表:", {name="test", value=456})
end

-- 启动测试任务
sys.taskInit(logtest_task)