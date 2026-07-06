PROJECT = "tcp_server_test"
VERSION = "1.0.0"

AUTHOR = {"copilot"}

testrunner = require("testrunner")

local tcp_server_tests = require("tcp_server_test")

sys.taskInit(function()
    testrunner.runBatch("tcp_server_suite", {
        { testTable = tcp_server_tests, testcase = "TCP Server监听测试" }
    })
end)

sys.run()
