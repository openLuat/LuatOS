
-- LuaTools需要PROJECT和VERSION这两个信息
PROJECT = "i2sdemo"
VERSION = "1.0.0"

-- sys库是标配
sys = require("sys")

if wdt then
    --添加硬狗防止程序卡死，在支持的设备上启用这个功能
    wdt.init(9000)--初始化watchdog设置为9s
    sys.timerLoopStart(wdt.feed, 3000)--3s喂一次狗
end

sys.taskInit(function()
    audio.config(0, 20, 1, 0, 20)
    audio.setBus(0, audio.BUS_I2S)
    audio.start(0, audio.PCM, 1, 16000, 16)
    audio.vol(0, 10)

    local file_size = fs.fsize("/luadb/test.pcm")
    print("/luadb/test.pcm size",file_size)   
    local f = io.open("/luadb/test.pcm", "rb")
    if f then 
        while 1 do
            local data = f:read(4096)
            print("-------------")
            if not data or #data == 0 then
                break
            end
            audio.write(0, data)
            sys.wait(50)
        end
        f:close()
    end
end)

sys.taskInit(function()
    while 1 do
        sys.wait(1000)
        log.info("sys", rtos.meminfo("sys"))
    end
end)

-- 用户代码已结束---------------------------------------------
-- 结尾总是这一句
sys.run()
-- sys.run()之后后面不要加任何语句!!!!!
