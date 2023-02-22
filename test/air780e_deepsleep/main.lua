--[[
    对应的issue https://gitee.com/openLuat/LuatOS/issues/I6GZGQ
]]

PROJECT = "gnss"
VERSION = "1.0.0"

-- sys库是标配
local sys = require("sys")

uart.setup(2, 115200)
uart.on(2, "recv", function()
    while 1 do
        local data = uart.read(2, 1024)
        if not data or #data == 0 then
            return
        end
        log.info("uart2", data)
    end
end)
function gpsinit()
    log.info("GPS", "开始启动")
    pm.power(pm.GPS, true)
    log.info("GPS", "启动完成")
end

mobile.flymode(0, false)

-- 休眠进程
sys.taskInit(function()
    gpsinit()
    sys.wait(20 * 1000)
    log.info("开始休眠")
    mobile.flymode(0, true)
    pm.dtimerStart(0, 15 * 1000)
    pm.power(pm.GPS, false)
    pm.power(pm.USB, false) -- 如果是插着USB测试，需要关闭USB
    pm.force(pm.DEEP) -- 也可以pm.HIB模式
    sys.wait(1000)
    log.info("休眠失败")
end)

sys.run()
