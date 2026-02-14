-- 测试运行器模块
-- 整合联网、测试执行、结果上报的完整流程
local testrunner = {}

-- 导入依赖模块
local netready = require("netready")
local testreport = require("testreport")
local testsuite = require("testsuite")

-- 全局上下文对象，包含配置和运行时信息
local ctx = {
    timeout = 30000,  -- 等待网络连接的超时时间（毫秒）
    retry_count = 3,   -- 重试次数
    wifi_ssid = "观看15秒广告解锁WiFi",
    wifi_password = "qwertYUIOP",
    -- status_url = "http://httpbin.air32.cn/post",  -- 状态上报服务器 URL
}

-- 上报测试的当前状态
-- 参数:
--   testcase - 字符串，测试用例名称
--   status - 字符串，测试状态（"running"、"passed"、"failed" 等）
--   msg - 字符串，状态描述或错误信息
local function reportStatus(testcase, status, msg)
    log.info("testrunner", string.format("上报状态: %s - %s", testcase, status))
    
    local code = testreport.reportStatus(ctx, testcase, status, msg)
    
    if code == 200 then
        log.info("testrunner", "状态上报成功")
    elseif code == nil then
        -- log.info("testrunner", "状态 URL 未配置，跳过上报")
    else
        log.warn("testrunner", string.format("状态上报失败，状态码: %d", code))
    end
    
    return code
end

-- 上报测试结果
-- 参数: 
--   result - 布尔值，测试结果（true 为成功，false 为失败）
--   testcase - 字符串，测试用例名称
--   msg - 字符串，测试描述信息
-- 返回: HTTP 状态码
local function reportResult(result, testcase, msg)
    log.info("testrunner", "开始上报测试结果...")
    
    local code, headers, body = testreport.send(ctx, result, testcase, msg)
    
    if code == 200 then
        log.info("testrunner", "结果上报成功")
    elseif code == nil then
        -- log.info("testrunner", "报告 URL 未配置，跳过上报")
    else
        log.warn("testrunner", string.format("结果上报失败，状态码: %d", code))
    end
    
    return code
end

-- 加载配置信息
local function loadConfig()
    local ctx_path = "/luadb/ctx.json"
    -- 判断是否存在, 不存在就跳过
    if not io.exists(ctx_path) then
        log.warn("testrunner", "上下文文件不存在，使用默认配置")
        return
    end
    local data = io.readFile(ctx_path)
    local t_data = json.decode(data)
    -- 合并文件中的配置到 ctx
    for k, v in pairs(t_data) do
        ctx[k] = v
    end
end



-- 执行测试套件
-- 参数: testTable - 包含测试函数的表、testcase - 测试用例名称
-- 返回: 布尔值，所有测试通过时返回 true
local function runTests(testTable, testcase, only)
    log.info("testrunner", "开始执行测试用例...")
    
    -- 上报测试开始状态
    reportStatus(testcase, "running", "测试执行中")
    
    local success = testsuite.runTestSuite(ctx, testTable, only)
    
    if success then
        log.info("testrunner", "所有测试用例通过")
        -- 上报测试成功状态
        reportStatus(testcase, "passed", "测试执行成功")
    else
        log.warn("testrunner", "部分测试用例失败")
        -- 上报测试失败状态
        reportStatus(testcase, "failed", "测试执行失败")
    end
    
    return success
end


-- 去激活网络
local function deInitNetwork()
    log.info("testrunner", "断开网络连接...")
    netready.deinit()
end

-- 初始化网络连接
-- 返回: 布尔值，网络连接成功时返回 true
local function initNetwork()
    log.info("testrunner", "开始初始化网络连接...")

    netready.exec(ctx, ctx.timeout)
    
    -- 等待 IP_READY 事件，表示网络已就绪, 这里默认就等半分钟吧，半分钟且三次重试
    local result
    local retry_count = 3
    while 1 do
        result = sys.waitUntil("IP_READY", 30000)
        if result or retry_count <= 0 then
            break
        end
        retry_count = retry_count - 1
        log.warn("testrunner", "网络未就绪，正在重试，剩余次数: " .. retry_count)
        if mobile then
            mobile.flymode(0, true)
            sys.wait(2000)
            mobile.flymode(0, false)
        end
    end
    
    
    -- 设置默认网卡的dns为腾讯云dns
    socket.setDNS(nil, 1, "119.29.29.29")
    socket.setDNS(nil, 2, "223.5.5.5")

    if result then
        log.info("testrunner", "网络连接成功")
        return true
    else
        deInitNetwork()
        log.warn("testrunner", "网络连接失败，超时")
        return false
    end
end




-- 主流程：运行完整的测试
-- 参数:
--   testTable - 包含测试函数的表
--   testcase - 字符串，测试用例名称（用于上报）
--   msg - 字符串，测试描述（用于上报）
-- 返回: 布尔值，整个流程成功时返回 true
function testrunner.run(testTable, testcase, msg)
    log.info("testrunner", "===== 开始测试运行流程 =====")
    
    loadConfig()
    -- 打印配置信息
    log.info("testrunner", "当前配置:", json.encode(ctx))
    
    -- 步骤 1: 初始化网络连接
    if not initNetwork() then
        log.error("testrunner", "网络初始化失败，中止测试")
        reportResult(false, testcase, msg .. " - 网络连接失败")
        return false
    end
    
    -- 步骤 2: 执行测试用例
    local test_result = runTests(testTable, testcase)
    
    -- 步骤 3: 上报测试结果
    reportResult(test_result, testcase, msg)
    deInitNetwork()
    log.info("testrunner", "===== 测试运行流程结束 =====")
    
    return test_result
end

-- 运行多个测试套件
-- 参数:
--   testcases - 表，包含多个测试信息，格式为:
--     {
--       {testTable = {...}, testcase = "name1", msg = "desc1"},
--       {testTable = {...}, testcase = "name2", msg = "desc2"},
--       ...
--     }
-- 返回: 布尔值，所有测试都通过时返回 true
function testrunner.runBatch(name, testcases)
    log.info("testrunner", "===== 开始批量测试 =====")
    
    loadConfig()
    local all_passed = true
    
    -- 初始化一次网络连接
    if not initNetwork() then
        log.error("testrunner", "网络初始化失败，中止所有测试")
        return false
    end
    
    -- 依次执行每个测试
    for idx, testcase_info in ipairs(testcases) do
        log.info("testrunner", string.format("执行第 %d 个测试: %s", idx, testcase_info.testcase))
        
        local result = runTests(testcase_info.testTable, testcase_info.testcase, testcase_info.only)
        --reportResult(result, testcase_info.testcase, testcase_info.msg)
        
        if not result then
            all_passed = false
        end
    end
    
    log.info("testrunner", "===== 批量测试结束 =====")
    -- 应该在这里才上报整体结果
    if all_passed then
        log.info("testrunner", "所有测试均通过")
    else
        log.warn("testrunner", "部分测试未通过")
    end
    reportResult(all_passed, name, (all_passed and "所有测试均通过" or "部分测试失败"))
    
    deInitNetwork()
    return all_passed
end

return testrunner
