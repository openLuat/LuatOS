
-- LuaTools需要PROJECT和VERSION这两个信息
PROJECT = "lowpower"
VERSION = "1.0.0"

-- sys库是标配
_G.sys = require("sys")

local NETLED = gpio.setup(19, 1) -- 输出模式,休眠后就熄灭了

sys.taskInit(function()
    while 1 do
        if socket.isReady() then
            http.get("http://site0.cn/api/httptest/simple/date", nil, function(code,headers,data)
                log.info("http", code, data)
            end) 
            pm.dtimerStart(0, 300000)
            pm.request(pm.HIB) -- 建议休眠
            --pm.force(pm.HIB) -- 强制休眠,唤醒后需要会走联网流程,不推荐
            --pm.check() -- 检查可休眠状态,用于排查
            sys.wait(300000) -- 5分钟
        else
            sys.wait(1000)
        end
    end
end)

-- 用户代码已结束---------------------------------------------
-- 结尾总是这一句
sys.run()
-- sys.run()之后后面不要加任何语句!!!!!
