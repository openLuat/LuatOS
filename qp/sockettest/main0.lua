
-- LuaTools需要PROJECT和VERSION这两个信息
PROJECT = "testsocket"
VERSION = "1.0.0"

log.info("main", PROJECT, VERSION)

-- 添加硬狗防止程序卡死
if wdt then
    wdt.init(9000) -- 初始化watchdog设置为9s
    sys.timerLoopStart(wdt.feed, 3000) -- 3s喂一次狗
end

local function testsocket()
    local isReady,index
    local r1,r2,r3
    while true do
        sys.wait(2000)
        isReady,index = socket.adapter()
        log.info("test socket:", isReady, index)

        r1,r2,r3 = socket.localIP()
        log.info("test ip:", r1, r2,r3)
    end
end

sys.taskInit(testsocket)


-- 用户代码已结束---------------------------------------------
-- 结尾总是这一句
sys.run()
-- sys.run()之后后面不要加任何语句!!!!!
