
-- LuaTools需要PROJECT和VERSION这两个信息
PROJECT = "FastLZ"
VERSION = "1.0.0"

--添加硬狗防止程序卡死
if wdt then
    wdt.init(9000)--初始化watchdog设置为9s
    sys.timerLoopStart(wdt.feed, 3000)--3s喂一次狗
end

sys.taskInit(function()
    sys.wait(1000)

    -- 原始数据
    local originStr = io.readFile("/luadb/fastlz.h") or "q309pura;dsnf;asdouyf89q03fonaewofhaeop;fhiqp02398ryhai;ofinap983fyua0weo;ifhj3p908fhaes;iofaw789prhfaeiwop;fhaesp98fadsjklfhasklfsjask;flhadsfk"
    log.info("原始数据长度", #originStr)

    -- 以压缩等级1 进行压缩
    local L1 = fastlz.compress(originStr)
    log.info("压缩等级1：压缩后的数据长度", #L1)

    -- 解压
    local dstr1 = fastlz.uncompress(L1)
    log.info("压缩等级1：解压后的的数据长度", #dstr1)

    -- 判断解压后的数据是否与原始数据相同
    if originStr == dstr1 then
        log.info("压缩等级1：解压后的数据与原始数据相同")
    else
        log.info("压缩等级1：解压后的数据与原始数据不同")
    end

    sys.wait(1000)

    -- 以压缩等级2 进行压缩
    local L2 = fastlz.compress(originStr, 2)
    log.info("压缩等级2：压缩后的数据长度", #L2)

    -- 解压
    local dstr2 = fastlz.uncompress(L2)
    log.info("压缩等级2：解压后的数据长度", #dstr2)

    -- 判断解压后的数据是否与原始数据相同
    if originStr == dstr2 then
        log.info("压缩等级2：解压后的数据与原始数据相同")
    else
        log.info("压缩等级2：解压后的数据与原始数据不同")
    end
end)


-- 用户代码已结束---------------------------------------------
-- 结尾总是这一句
sys.run()
-- sys.run()之后后面不要加任何语句!!!!!
