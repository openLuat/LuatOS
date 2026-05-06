-- AirLink raw ping/pong loopback 基础测试
PROJECT = "airlink_ping_basic"
VERSION = "1.0.0"

local testsuite = require("testsuite")
local ping_tests = require("airlink_ping_test")

sys.taskInit(function()
    local ok = testsuite.runTestSuite({}, ping_tests)
    if rtos.bsp() == "PC" then
        os.exit(ok and 0 or 1)
    end
end)

sys.run()
