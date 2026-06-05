PROJECT = "little_flash_basic"
VERSION = "1.0.0"

local testrunner = require("testrunner")
local tests = require("little_flash_test")

sys.taskInit(function()
    testrunner.runBatch("little_flash_basic", {
        { testTable = tests.lf_suite, testcase = "C层utest-little_flash(ftl基础)" }
    })
end)

sys.run()
