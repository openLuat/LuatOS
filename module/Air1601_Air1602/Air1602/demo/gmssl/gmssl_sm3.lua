--[[
@module  gmssl_sm3
@summary gmssl_sm3
@version 1.0
@date    2025.10.29
@author  沈园园
@usage
本文件为gmssl sm3应用功能模块，核心业务逻辑为：
1、演示国密sm3算法；

本文件没有对外接口，直接在main.lua中require "gmssl_sm3"就可以加载运行；
]]


local function gmssl_sm3_task_func()
    -- sm3算法,算HASH值
    local encodeStr = gmssl.sm3("lqlq666lqlq946")
    log.info("gmssl.sm3",string.toHex(encodeStr))
    
    -- sm3算法,算HASH值,但带HMAC
    local encodeStr = gmssl.sm3hmac("lqlq666lqlq946", "123")
    log.info("gmssl.sm3hmac",string.toHex(encodeStr))    

end

sys.taskInit(gmssl_sm3_task_func)
