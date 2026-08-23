PROJECT = "ndk_basic"
VERSION = "1.0.0"
AUTHOR = {"copilot"}

local testrunner = require("testrunner")
local ndk_lifecycle = require("ndk_lifecycle_test")

sys.taskInit(function()
    testrunner.runBatch("ndk_basic", {
        { testTable = ndk_lifecycle, testcase = "ndk lifecycle tests" },
    })
end)

sys.run()
