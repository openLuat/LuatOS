--[[
@module  miniz_app
@summary miniz_app应用功能模块 
@version 1.0
@date    2025.10.28
@author  沈园园
@usage
本文件为miniz应用功能模块，核心业务逻辑为：
1、如何对数据压缩解压；

本文件没有对外接口，直接在main.lua中require "miniz_app"就可以加载运行；
]]


local function miniz_task_func()
    -- 压缩过的字符串, 为了方便演示, 这里用了base64编码
    -- miniz能解压标准zlib数据流
    -- 将字符串进行base64解码
    local b64str = "eAEFQIGNwyAMXOUm+E2+OzjhCCiOjYyhyvbVR7K7IR0l+iau8G82eIW5jXVoPzF5pse/B8FaPXLiWTNxEMsKI+WmIR0l+iayEY2i2V4UbqqPh5bwimyEuY11aD8xeaYHxAquvom6VDFUXqQjG1Fek6efCFfCK0b0LUnQMjiCxhUT05GNL75dFUWCSMcjN3EE5c4Wvq42/36R41fa"
    local str = b64str:fromBase64()
    -- 快速解压
    local dstr = miniz.uncompress(str) 
    -- 压缩过的数据长度 156
    -- 解压后的数据长度,即原始数据的长度 235
    log.info("miniz", "压缩过的数据长度: ", #str, "解压后的数据长度：", #dstr)    
    
    -- 演示压缩解压
    local ostr = "abcd1234567890efghijklmnopqrstuvwxyzabcd1234567890efghijklmnopqrstuvwxyzabcd1234567890efghijklmnopqrstuvwxyz"
    log.info("压缩前的字符串：", #ostr, ostr)
    -- 压缩字符串
    local zstr = miniz.compress(ostr)
    log.info("压缩后的字符串：",#zstr, zstr:toHex())
    -- 解压字符串
    local lstr = miniz.uncompress(zstr)
    log.info("解压后的字符串：", #lstr, lstr)
    
    -- 演示从文件读取2K数据压缩
    local ostr = io.readFile("/luadb/test.txt")
    local zstr = miniz.compress(ostr)
    if zstr then
        log.info("miniz", "压缩前的数据长度: ", #ostr, "压缩后的数据长度: ", #zstr) 
    end  
end


--创建一个task，并且运行task的主函数miniz_task_func
sys.taskInit(miniz_task_func)
