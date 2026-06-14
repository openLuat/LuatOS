PROJECT = "mobile_rfcal_basic"
VERSION = "1.0.0"
local testrunner = require("testrunner")
local tests = require("mobile_rfcal_test")
sys.taskInit(function()
    testrunner.runBatch("mobile_rfcal_basic", {
        { testTable = tests.c_suite,    testcase = "C层utest-mobile.rfcal" },
        { testTable = tests.lua_suite,  testcase = "Lua层-mobile.rfcal绑定" },
        { testTable = tests.at_suite,   testcase = "AT server派发" },
    })
end)
sys.run()
