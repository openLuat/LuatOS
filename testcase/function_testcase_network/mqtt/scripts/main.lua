-- LuaTools需要PROJECT和VERSION这两个信息
PROJECT = "mqtttest"
VERSION = "1.0.0"

-- 修改者的名称, 方便日后维护
AUTHOR = {}

-- sys库是标配
_G.sys = require("sys")
-- 使用mqtt库需要sysplus
_G.sysplus = require("sysplus")

-- 引入测试运行器和测试用例
testrunner = require("testrunner")
mqtt_test = require("mqtt_test")

-- 运行测试
sys.taskInit(function()
    testrunner.runBatch("mqtt", {
        { testTable = mqtt_test, testcase = "MQTT功能测试" }
    })
end)

-- 用户代码已结束---------------------------------------------
-- 结尾总是这一句
sys.run()
-- sys.run()之后后面不要加任何语句!!!!!
