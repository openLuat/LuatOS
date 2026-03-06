
-- LuaTools需要PROJECT和VERSION这两个信息
PROJECT = "fastlzdemo"
VERSION = "1.0.0"

sys = require("sys")

--添加硬狗防止程序卡死
if wdt then
    wdt.init(9000)--初始化watchdog设置为9s
    sys.timerLoopStart(wdt.feed, 3000)--3s喂一次狗
end

sys.taskInit(function()
    sys.wait(1000)
    -- 压缩过的字符串
    local tmp = io.readFile("/luadb/fastlz.h") or "q309pura;dsnf;asdouyf89q03fonaewofhaeop;fhiqp02398ryhai;ofinap983fyua0weo;ifhj3p908fhaes;iofaw789prhfaeiwop;fhaesp98fadsjklfhasklfsjask;flhadsfk"
    local L1 = fastlz.compress(tmp)
    local dstr = fastlz.uncompress(L1)
    log.info("fastlz", "压缩等级1", #tmp, #L1, #dstr)
    L1 = nil
    dstr = nil
    local L2 = fastlz.compress(tmp, 2)
    local dstr = fastlz.uncompress(L2)
    log.info("fastlz", "压缩等级2", #tmp, #L2, #dstr)
    L1 = nil
    dstr = nil
end)


-- 用户代码已结束---------------------------------------------
-- 结尾总是这一句
sys.run()
-- sys.run()之后后面不要加任何语句!!!!!
