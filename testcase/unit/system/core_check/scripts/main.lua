PROJECT = "mouble_check"
VERSION = "1.0.0"
AUTHOR = {"xu"}

-- sys库是标配
_G.sys = require("sys")
--[[特别注意, 使用http库需要下列语句]]
_G.sysplus = require("sysplus")


mcu.hardfault(0)
testrunner = require("testrunner")
check_core= require ("check_function")

sys.taskInit(function()
    -- 第一个参数, 是整个测试的名称
    -- 第二个参数, 是一个表数组, 每个表包含 testTable 和 testcase 字段
    --   testTable - 包含测试函数的表, 也就是模块, 其中的所有 test_ 开头的函数都会被执行
    --   testcase - 测试用例的名称, 用于上报
    testrunner.runBatch("check_core", {
        {testTable = check_core, testcase = "固件检查"}
    })
end)
sys.run()