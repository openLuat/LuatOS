
-- LuaTools需要PROJECT和VERSION这两个信息
PROJECT = "pmdemo"
VERSION = "1.0.0"

log.info("main", PROJECT, VERSION)

-- sys库是标配
_G.sys = require("sys")

-- 注意:本demo使用luatools下载!!!
-- 注意:本demo使用luatools下载!!!
-- 注意:本demo使用luatools下载!!!

sys.taskInit(function()
    while 1 do
        sys.wait(3000)
        log.info("pm", "休眠60秒", "GPIO下降沿唤醒，键盘唤醒和RTC闹钟唤醒")
        -- air105仅支持id=0实际精度为秒, 但参数要求是毫秒
        -- 所以下面的调用id=0, timeout=60*1000
        pm.dtimerStart(0, 60000)
        -- air105air105仅支持pm.DEEP, 为暂停模式, 唤醒后不复位, 代码继续运行，可以被下降沿中断，RTC中断，硬件键盘中断唤醒
        pm.request(pm.DEEP)
        sys.wait(100)
        pm.request(pm.IDLE)
        -- air105唤醒后不复位, 代码继续运行, 下面的代码在唤醒后执行
        log.info("pm", "系统被唤醒", "代码继续执行")
        sys.publish("SYS_WAKEUP")
    end

end)

-- 用户代码已结束---------------------------------------------
-- 结尾总是这一句
sys.run()
-- sys.run()之后后面不要加任何语句!!!!!
