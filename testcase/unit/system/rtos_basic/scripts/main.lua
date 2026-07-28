PROJECT = "rtos_basic"
VERSION = "1.0.0"

AUTHOR = {"luatos"}

local testrunner = require("testrunner")
local tests = require("rtos_test")

sys.taskInit(function()
    testrunner.runBatch("rtos_basic", {
        { testTable = tests.info_suite, testcase = "RTOS信息API" },
        { testTable = tests.timer_suite, testcase = "RTOS软件定时器" },
        { testTable = tests.msg_suite, testcase = "RTOS消息收发" },
    })
end)

sys.run()
