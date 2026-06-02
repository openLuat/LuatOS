PROJECT = "uart_zbuff_basic"
VERSION = "1.0.0"

local testrunner = require("testrunner")
local uart_zbuff_tests = require("uart_zbuff_test")

sys.taskInit(function()
    testrunner.runBatch("uart_zbuff", {
        {testTable = uart_zbuff_tests, testcase = "uart zbuff mode tests"}
    })
end)

sys.run()
