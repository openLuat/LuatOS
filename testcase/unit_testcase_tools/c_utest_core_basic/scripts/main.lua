PROJECT = "c_utest_core_basic"
VERSION = "1.0.0"

AUTHOR = {"copilot"}

local testrunner = require("testrunner")
local tests = require("c_utest_core_test")

sys.taskInit(function()
    testrunner.runBatch("c_utest_core_basic", {
        { testTable = tests.pack_suite, testcase = "C层utest-pack(简单)" },
        { testTable = tests.crypto_suite, testcase = "C层utest-crypto(中等)" },
        { testTable = tests.zbuff_suite, testcase = "C层utest-zbuff(复杂)" }
    })
end)

sys.run()
