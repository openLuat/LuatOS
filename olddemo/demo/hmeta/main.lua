
-- LuaTools需要PROJECT和VERSION这两个信息
PROJECT = "hmetademo"
VERSION = "1.0.0"

-- sys库是标配
_G.sys = require("sys")


-- Air780E的AT固件默认会为开机键防抖, 导致部分用户刷机很麻烦
if rtos.bsp() == "EC618" and pm and pm.PWK_MODE then
    pm.power(pm.PWK_MODE, false)
end


sys.taskInit(function()
    while hmeta do
        -- hmeta识别底层模组类型的
        -- 不同的模组可以使用相同的bsp,但根据封装的不同,根据内部数据仍可识别出具体模块
        log.info("hmeta", hmeta.model(), hmeta.hwver and hmeta.hwver())
        log.info("bsp",   rtos.bsp())
        sys.wait(3000)
    end
    log.info("这个bsp不支持hmeta库哦")
end)

-- 用户代码已结束---------------------------------------------
-- 结尾总是这一句
sys.run()
-- sys.run()之后后面不要加任何语句!!!!!
