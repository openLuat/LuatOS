--[[
必须定义PROJECT和VERSION变量，Luatools工具会用到这两个变量，远程升级功能也会用到这两个变量
PROJECT：项目名，ascii string类型
        可以随便定义，只要不使用,就行
VERSION：项目版本号，ascii string类型
        如果使用合宙iot.openluat.com进行远程升级，必须按照"XXX.YYY.ZZZ"三段格式定义：
            X、Y、Z各表示1位数字，三个X表示的数字可以相同，也可以不同，同理三个Y和三个Z表示的数字也是可以相同，可以不同
            因为历史原因，YYY这三位数字必须存在，但是没有任何用处，可以一直写为000
        如果不使用合宙iot.openluat.com进行远程升级，根据自己项目的需求，自定义格式即可

本demo演示的功能为：
实现使用Air780EHM来对文本/段落序列、原始像素数据序列或具有大量重复的任何其他数据块的快速压缩与解压缩。
]]
-- LuaTools需要PROJECT和VERSION这两个信息
PROJECT = "FastLZ"
VERSION = "1.0.0"

--添加硬狗防止程序卡死
if wdt then
    wdt.init(9000)--初始化watchdog设置为9s
    sys.timerLoopStart(wdt.feed, 3000)--3s喂一次狗
end

function test_fastlz()
    sys.wait(1000)
    -- 原始数据
    local originStr = io.readFile("/luadb/test.txt") or "q309pura;dsnf;asdouyf89q03fonaewofhaeop;fhiqp02398ryhai;ofinap983fyua0weo;ifhj3p908fhaes;iofaw789prhfaeiwop;fhaesp98fadsjklfhasklfsjask;flhadsfk"
    local maxOut = #originStr
    log.info("原始数据长度", #originStr)

    -- 以压缩等级1 进行压缩
    local L1 = fastlz.compress(originStr,1)
    log.info("压缩等级1：压缩后的数据长度", #L1)

    -- 解压
    local dstr1 = fastlz.uncompress(L1,maxOut)
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
    local dstr2 = fastlz.uncompress(L2,maxOut)
    log.info("压缩等级2：解压后的数据长度", #dstr2)

    -- 判断解压后的数据是否与原始数据相同
    if originStr == dstr2 then
        log.info("压缩等级2：解压后的数据与原始数据相同")
    else
        log.info("压缩等级2：解压后的数据与原始数据不同")
    end
end

sys.taskInit(test_fastlz)


-- 用户代码已结束---------------------------------------------
-- 结尾总是这一句
sys.run()
-- sys.run()之后后面不要加任何语句!!!!!
