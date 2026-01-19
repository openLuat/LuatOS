-- 测试套件模块
local suite = {}
local testreport = require("testreport")

-- 运行单个测试套件
-- 参数: testTable - 包含多个测试函数的表，函数名必须以 "test_" 开头
-- 返回: 布尔值，当所有测试通过时返回 true
function suite.runTestSuite(ctx, testTable, only)
    local passCount = 0  -- 通过的测试数
    local failCount = 0  -- 失败的测试数
    local failedTests = {} -- 失败的测试函数名列表
    
    -- 遍历测试表中的所有项
    for key, value in pairs(testTable) do
        -- 检查键是否为字符串且以 "test_" 开头
        if type(key) == "string" and string.sub(key, 1, 5) == "test_" then
            if only and key ~= only then
                -- 如果指定了only参数且当前测试函数名不匹配，则跳过
                goto next
            end
            -- 检查值是否为函数
            if type(value) == "function" then
                log.info("suite", "Running test: " .. key)
                collectgarbage("collect")
                collectgarbage("collect")
                testreport.reportStatus(ctx, key, "running", "started")
                -- 使用 pcall 安全执行测试函数，防止错误中断运行
                if testTable.setUp then
                    -- 如果存在 setUp 函数，先执行它
                    local success, err = pcall(testTable.setUp)
                    if not success then
                        log.info("suite", string.format("✗ %s setUp failed: %s", key, err))
                        failCount = failCount + 1
                        table.insert(failedTests, key .. " (setUp failed)")
                        testreport.reportStatus(ctx, key, "failed", "setUp failed: " .. err)
                        goto next
                    end
                end
                local success, err = pcall(value)
                if testTable.tearDown then
                    -- 如果存在 tearDown 函数，执行它
                    local tdSuccess, tdErr = pcall(testTable.tearDown)
                    if not tdSuccess then
                        log.info("suite", string.format("✗ %s tearDown failed: %s", key, tdErr))
                        -- 即使 tearDown 失败，也继续处理测试结果
                    end
                end
                if success then
                    -- 测试通过，打印成功信息
                    log.info("suite", string.format("✓ %s passed", key))
                    passCount = passCount + 1
                    testreport.reportStatus(ctx, key, "passed", "passed")
                else
                    -- 测试失败，打印失败信息和错误信息
                    log.info("suite", string.format("✗ %s failed: %s", key, err))
                    failCount = failCount + 1
                    table.insert(failedTests, key)
                    testreport.reportStatus(ctx, key, "failed", err)
                end
                sys.wait(10)  -- 测试间隔，防止过快执行, 然后wdt死机
            end
            ::next::
        end
    end
    
    -- 打印测试套件总结
    log.info("suite", string.format("Total: %d passed, %d failed", passCount, failCount))
    if failCount > 0 then
        log.info("suite", "Failed testcases: " .. table.concat(failedTests, ", "))
        testreport.reportStatus(ctx, "suite", "failed", table.concat(failedTests, ", "))
    end
    return failCount == 0
end

-- 运行多个测试套件
-- 参数: ... - 可变数量的测试表
-- 返回: 布尔值，当所有测试套件都通过时返回 true
function suite.runMultipleTestSuites(...)
    local totalPass = 0   -- 通过的测试套件数
    local totalFail = 0   -- 失败的测试套件数
    local testTables = {...}  -- 收集所有传入的测试表
    
    -- 遍历每个测试表
    for _, testTable in ipairs(testTables) do
        -- 运行单个测试套件
        local result = suite.runTestSuite(testTable)
        if not result then
            -- 如果有测试失败，增加失败计数
            totalFail = totalFail + 1
        else
            -- 如果所有测试通过，增加通过计数
            totalPass = totalPass + 1
        end
    end
    
    -- 打印总体测试结果
    log.info('suite', "===== Overall Test Results =====")
    log.info("suite", string.format("Total: %d passed, %d failed", totalPass, totalFail))
    return totalFail == 0
end



return suite