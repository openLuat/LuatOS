PROJECT = "mobile_rfa_basic"
VERSION = "1.0.0"
local testrunner = require("testrunner")
local tests = require("mobile_rfa_test")
sys.taskInit(function()
    testrunner.runBatch("mobile_rfa_basic", {
        { testTable = tests.c_suite,    testcase = "C层桩 (mobile.rfTest*)" },
        { testTable = tests.lua_suite,  testcase = "Lua端 mobile.rfTest* 绑定" },
        { testTable = tests.at_suite,   testcase = "rfa AT 派发表" },
        { testTable = tests.rfa_suite,  testcase = "rfa.lua 模块" },
    })
end)
sys.run()
