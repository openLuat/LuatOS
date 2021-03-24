

PROJECT = "camerademo"
VERSION = "1.0.0"

local sys = require "sys"

pmd.ldoset(3000, pmd.LDO_VLCD)
pmd.ldoset(3000, pmd.LDO_VCAM)
pmd.ldoset(3300, pmd.LDO_VIBR)

sys.taskInit(function()
    local netled = gpio.setup(1, 0)
    local netmode = gpio.setup(4, 0)
    while 1 do
        netled(1)
        netmode(0)
        sys.wait(500)
        netled(0)
        netmode(1)
        sys.wait(500)
        log.info("luatos", "hi", os.date())
    end
end)

sys.taskInit(function()
    sys.wait(10000)
    camera.init(function(ret,name,w,h)
        log.info("camera", ret,name,w,h)
        if ret then
            sys.taskInit(function ()
                while true do
                    sys.wait(1000)
                    camera.previewStart()
                    sys.wait(5000)
                    --camera.previewStop()
                    sys.wait(100)
                    local ret, size, data = camera.capture("mem", "jpg"--[[, 0, 0, 80]])
                    if ret then
                        log.info("camera", ret, size) -- data很大,就不要打印了吧
                    else
                        log.info("camera", ret)
                    end
                end
            end)
        end
    end)
end)


-- 用户代码已结束---------------------------------------------
-- 结尾总是这一句
sys.run()
-- sys.run()之后后面不要加任何语句!!!!!
