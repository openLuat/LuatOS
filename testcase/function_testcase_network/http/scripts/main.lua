-- LuaTools需要PROJECT和VERSION这两个信息
PROJECT = "httpdemo"
VERSION = "1.0.0"

-- 修改者的名称, 方便日后维护
AUTHOR = {}

--[[
本demo需要http库, 大部分能联网的设备都具有这个库
http也是内置库, 无需require

1. 如需上传大文件,请使用 httpplus 库, 对应demo/httpplus
2. 
]]

-- sys库是标配
_G.sys = require("sys")
--[[特别注意, 使用http库需要下列语句]]
_G.sysplus = require("sysplus")

-- Air780E的AT固件默认会为开机键防抖, 导致部分用户刷机很麻烦
if rtos.bsp() == "EC618" and pm and pm.PWK_MODE then
    pm.power(pm.PWK_MODE, false)
end

-- -- 引入测试套件和测试运行器模块
testrunner = require("testrunner")

-- -- 载入需要测试的模块
http_test = require("http_test")

-- 开启一个task,运行测试
sys.taskInit(function()
    -- 第一个参数, 是整个测试的名称
    -- 第二个参数, 是一个表数组, 每个表包含 testTable 和 testcase 字段
    --   testTable - 包含测试函数的表, 也就是模块, 其中的所有 test_ 开头的函数都会被执行
    --   testcase - 测试用例的名称, 用于上报
    testrunner.runBatch("http", {
        {testTable = http_test, testcase = "http测试"}
    })
end)

-- 用户代码已结束---------------------------------------------
-- 结尾总是这一句
sys.run()
-- sys.run()之后后面不要加任何语句!!!!!
