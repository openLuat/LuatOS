-- LuaTools需要PROJECT和VERSION这两个信息
PROJECT = "httpdnstest"
VERSION = "1.0.0"

-- 修改者的名称, 方便日后维护
AUTHOR = "copilot"

-- sys库是标配
_G.sys = require("sys")
-- 使用http库需要sysplus
_G.sysplus = require("sysplus")

-- 引入测试运行器和测试模块
testrunner = require("testrunner")
httpdns_test = require("httpdns_test")

-- 开启一个task,运行测试
sys.taskInit(function()
    testrunner.runBatch("httpdns", {
        { testTable = httpdns_test, testcase = "HTTPDNS解析" }
    })
end)

-- 用户代码已结束---------------------------------------------
-- 结尾总是这一句
sys.run()
-- sys.run()之后后面不要加任何语句!!!!!
