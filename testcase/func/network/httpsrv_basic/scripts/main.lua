PROJECT = "httpsrv_test"
VERSION = "1.0.0"

testrunner = require("testrunner")

local httpsrv_tests = require("httpsrv_test")

sys.taskInit(function()
    testrunner.runBatch("httpsrv_suite", {
        { testTable = httpsrv_tests, testcase = "httpsrv全网卡绑定测试" }
    })
end)

sys.run()
