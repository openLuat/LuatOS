-- AirLink RPC 增强功能测试
-- 测试: 新 handler 签名 / AIRLINK_RPC_DEFER 常量 / async API / notify API

PROJECT = "rpc_enhance_basic"
VERSION = "1.0.0"

-- 直接使用 testsuite 跳过网络初始化 (本测试为纯本地逻辑验证)
local testsuite = require("testsuite")
local rpc_tests = require("rpc_api_test")

sys.taskInit(function()
    local ok = testsuite.runTestSuite({}, rpc_tests)
    if rtos.bsp() == "PC" then
        os.exit(ok and 0 or 1)
    end
end)

sys.run()
