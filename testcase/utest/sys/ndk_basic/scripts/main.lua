PROJECT = "ndk_basic"
VERSION = "1.0.0"
AUTHOR = {"copilot"}

local testrunner = require("testrunner")
local tests = require("ndk_test")

sys.taskInit(function()
    testrunner.runBatch("ndk_basic", {
        { testTable = tests.ndk_suite, testcase = "C-layer utest-ndk (lifecycle)" },
    })
end)

sys.run()
