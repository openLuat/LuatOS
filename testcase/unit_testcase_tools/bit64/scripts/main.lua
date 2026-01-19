-- LuaTools需要PROJECT和VERSION这两个信息
PROJECT = "bit64test"
VERSION = "1.0.0"

-- 修改者的名称, 方便日后维护
AUTHOR = {"chao"}

-- 引入测试套件和测试运行器模块
testrunner = require("testrunner")

-- 载入需要测试的模块
bit64_test = require("bit64_test")

-- 开启一个task,运行测试
sys.taskInit(function()
    -- 第一个参数, 是整个测试的名称
    -- 第二个参数, 是一个表数组, 每个表包含 testTable 和 testcase 字段
    --   testTable - 包含测试函数的表, 也就是模块, 其中的所有 test_ 开头的函数都会被执行
    --   testcase - 测试用例的名称, 用于上报
    testrunner.runBatch("bit64", {
        {testTable = bit64_test, testcase = "bit64测试"}
    })

end)

-- 用户代码已结束---------------------------------------------
-- 结尾总是这一句
sys.run()
-- sys.run()之后后面不要加任何语句!!!!!