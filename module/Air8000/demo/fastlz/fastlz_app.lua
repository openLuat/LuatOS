--[[
@module  fastlz_app
@summary fastlz_app 
@version 1.0
@date    2025.10.28
@author  沈园园
@usage
本文件为fastlz应用功能模块，核心业务逻辑为：
1、演示压缩与解压缩的流程；

本文件没有对外接口，直接在main.lua中require "fastlz_app"就可以加载运行；
]]


function fastlz_compress_uncompress_func(mode)
    -- 原始数据
    local originStr
    if mode == 1 then
        log.info("原始数据文件读取2K数据")
        originStr = io.readFile("/luadb/test.txt")          
    else
        log.info("原始数据108长度字符串")
        originStr = "abcd1234567890efghijklmnopqrstuvwxyzabcd1234567890efghijklmnopqrstuvwxyzabcd1234567890efghijklmnopqrstuvwxyz"            
    end
    
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

function fastlz_task_func()
    -- 原始数据108长度字符串
    fastlz_compress_uncompress_func()
    -- 原始数据文件读取2K数据
    fastlz_compress_uncompress_func(1)   
end


--创建一个task，并且运行task的主函数fastlz_task_func
sys.taskInit(fastlz_task_func)