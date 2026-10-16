PROJECT = "sms_basic"
VERSION = "1.0.0"

local testrunner = require("testrunner")
local sms_test = require("sms_test")

sys.taskInit(function()
    testrunner.runBatch("sms_basic", {
        { testTable = sms_test.sms_suite, testcase = "C层utest-sms(UTF-8/UCS2编解码)" },
    })
end)

sys.run()
