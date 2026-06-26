PROJECT = "miniz_basic"
VERSION = "1.0.0"

local testrunner = require("testrunner")
local miniz_test = require("miniz_test")

sys.taskInit(function()
    testrunner.runBatch("miniz_basic", {
        { testTable = miniz_test.miniz_suite, testcase = "C层utest-miniz(压缩/解压核心逻辑)" },
    })
end)

sys.run()
