-- LuaTools需要PROJECT和VERSION这两个信息
PROJECT = "smstest"
VERSION = "1.0.0"

-- 修改者的名称, 方便日后维护
AUTHOR = {"copilot"}

-- sys库是标配
_G.sys = require("sys")

-- 引入测试运行器模块和具体测试集合
local testrunner = require("testrunner")
local sms_test = require("sms_test")

-- 开启一个task,运行测试
sys.taskInit(function()
    -- 第一个参数: 整个测试的名称, 也是上报的用例标识
    -- 第二个参数: 测试列表, testTable中所有以 test_ 开头的函数都会被执行
    testrunner.runBatch("sms", {
        { testTable = sms_test, testcase = "SMS解析能力" }
    })
end)

-- 用户代码已结束---------------------------------------------
-- 结尾总是这一句
sys.run()
-- sys.run()之后后面不要加任何语句!!!!!
