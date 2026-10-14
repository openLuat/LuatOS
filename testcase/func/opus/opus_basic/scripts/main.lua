-- LuaTools需要PROJECT和VERSION这两个信息
PROJECT = "opus_test"
VERSION = "1.0.0"

AUTHOR = {"luatos"}

-- 引入测试套件和测试运行器模块
testrunner = require("testrunner")

-- 载入需要测试的模块
opus_test = require("opus_test")

-- 开启一个task,运行测试
sys.taskInit(function()
    -- opus 是可选外部组件：只有编入 luatos-ext-components/opus 的构建才有 codec.OPUS。
    -- 源码缺失（无 ext 仓库检出）或 LUAT_OPUS_MODE=off 时整体跳过，避免报假失败。
    if codec.OPUS == nil then
        log.warn("opus_test", "本构建未编入 opus (codec.OPUS 为 nil)，跳过 opus 编解码用例")
        log.info("testrunner", "### OVERALL_PASS ### opus skipped: codec.OPUS unavailable")
        if rtos.bsp() == "PC" then
            os.exit(0)
        end
        return
    end
    testrunner.runBatch("opus", {
        {testTable = opus_test, testcase = "opus编解码测试"}
    })
end)

-- 用户代码已结束---------------------------------------------
-- 结尾总是这一句
sys.run()
-- sys.run()之后后面不要加任何语句!!!!!
