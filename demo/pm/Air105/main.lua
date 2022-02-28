
-- LuaTools需要PROJECT和VERSION这两个信息
PROJECT = "pmdemo"
VERSION = "1.0.0"

log.info("main", PROJECT, VERSION)

-- sys库是标配
_G.sys = require("sys")

sys.taskInit(function()
    while 1 do
        sys.wait(3000)
        log.info("pm", "休眠60秒", "GPIO下降沿唤醒，键盘唤醒和RTC闹钟唤醒")
        -- air105仅支持id=0, 实际精度为秒, 但参数要求是毫秒
        -- 所以下面的调用id=0, timeout=60*1000
        pm.dtimerStart(0, 60000)
        -- air105 支持2个休眠状态, 均为暂停模式, 唤醒后不复位, 代码继续运行
        -- LIGHT , GPIO状态不变, 功耗较高
        -- DEEP  , GPIO全部变成内部下拉, 功耗在1ma左右, 注意: GPIO下拉状态在唤醒后不会变化
        -- pm.request(pm.LIGHT)
        pm.request(pm.DEEP)
        -- air105唤醒后不复位, 代,码继续运行, 下面的代码在唤醒后执行
        log.info("pm", "系统被唤醒", "代码继续执行")
        sys.publish("SYS_WAKEUP")
    end

end)

-- 用户代码已结束---------------------------------------------
-- 结尾总是这一句
sys.run()
-- sys.run()之后后面不要加任何语句!!!!!
