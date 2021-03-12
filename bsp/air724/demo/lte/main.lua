

-- LuaTools需要PROJECT和VERSION这两个信息
PROJECT = "ltedemo"
VERSION = "1.0.0"

-- sys库是标配
local sys = require "sys"

-- 启动个task, 定时查询iccid/imei/imsi, 并在1分钟后切换SIM卡并重启
sys.taskInit(function()
    local simid = 0
    local count = 0
    while true do
        sys.wait(5000)
        log.info("lte", "imsi", lte.imsi())
        log.info("lte", "imei", lte.imei())
        log.info("lte", "iccid", lte.iccid())
        log.info("lte", "sn", lte.sn(0))
        log.info("socket", "ip", socket.ip())

        count = count + 1
        if count > 12 then
            local re,simid = lte.switchSimGet()
            if re then
                lte.switchSimSet(simid == 0 and 1 or 0) -- 切换到另外一张卡
                rtos.reboot()
            end
        end
    end
end)

-- 用户代码已结束---------------------------------------------
-- 结尾总是这一句
sys.run()
-- sys.run()之后后面不要加任何语句!!!!!
