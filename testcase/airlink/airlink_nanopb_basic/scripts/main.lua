-- AirLink nanopb RPC loopback 基础测试
PROJECT = "airlink_nanopb_basic"
VERSION = "1.0.0"

local testsuite = require("testsuite")
local nanopb_tests = require("airlink_nanopb_test")

sys.taskInit(function()
    local ok = testsuite.runTestSuite({}, nanopb_tests)
    if rtos.bsp() == "PC" then
        os.exit(ok and 0 or 1)
    end
end)

sys.run()
