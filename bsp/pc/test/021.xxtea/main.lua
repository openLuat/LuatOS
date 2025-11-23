
-- LuaTools需要PROJECT和VERSION这两个信息
PROJECT = "httpdemo"
VERSION = "1.0.0"

--[[
本demo需要http库, 大部分能联网的设备都具有这个库
http也是内置库, 无需require
]]

-- sys库是标配
_G.sys = require("sys")
--[[特别注意, 使用http库需要下列语句]]
_G.sysplus = require("sysplus")


sys.taskInit(function()
    local text = "Hello World!"
    local key = "07946"
    local encrypt_data = xxtea.encrypt(text, key)
    log.info("testCrypto.xxteaTest","xxtea_encrypt:", encrypt_data:toHex())

    print("========================================================")

    local decrypt_data = xxtea.decrypt(encrypt_data, key)
    log.info("testCrypto.xxteaTest","decrypt_data:", decrypt_data:toHex())
end)

-- 用户代码已结束---------------------------------------------
-- 结尾总是这一句
sys.run()
-- sys.run()之后后面不要加任何语句!!!!!
