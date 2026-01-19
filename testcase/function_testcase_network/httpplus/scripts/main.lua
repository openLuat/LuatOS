-- LuaTools需要PROJECT和VERSION这两个信息
PROJECT = "httpplusdemo"
VERSION = "1.0.0"

-- 修改者的名称, 方便日后维护
AUTHOR = {}

-- httpplus 扩展库用例，覆盖大文件、长 header、multipart 等能力

-- sys库是标配
_G.sys = require("sys")
-- httpplus 依赖网络调度能力，保持与 http 用例一致
_G.sysplus = require("sysplus")

-- 载入测试套件和运行器
local testrunner = require("testrunner")
local httpplus_test = require("httpplus_test")

-- 开启一个task,运行测试
sys.taskInit(function()
    testrunner.runBatch("httpplus", {
        {testTable = httpplus_test, testcase = "httpplus测试"}
    })
end)

-- 用户代码已结束---------------------------------------------
sys.run()
-- sys.run()之后后面不要加任何语句!!!!!
