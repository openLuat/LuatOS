PROJECT = "webp_basic"
VERSION = "1.0.0"

AUTHOR = {"copilot"}

testrunner = require("testrunner")

local webp_tests = require("webp_test")

sys.taskInit(function()
    testrunner.runBatch("webp_basic", {
        { testTable = webp_tests, testcase = "libwebp解码器测试" }
    })
end)

sys.run()
