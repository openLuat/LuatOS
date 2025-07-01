--[[
@module  fastlz_test
@summary fastlz压缩与解压缩测试功能模块
@version 1.0
@date    2025.07.01
@author  孟伟
@usage
使用Air780EHM演示压缩与解压缩的流程。
]]

function test_fastlz_func()
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
--创建并且启动一个task
--运行这个task的主函数test_fastlz_func
sys.taskInit(test_fastlz_func)