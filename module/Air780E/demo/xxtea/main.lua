
-- LuaTools需要PROJECT和VERSION这两个信息
PROJECT = "xxtea"
VERSION = "1.0.0"

-- sys库是标配
_G.sys = require("sys")


sys.taskInit(function()
    if not xxtea then
        while true do
            sys.wait(1000)
            -- 每隔1秒打印一条信息
            log.info("testCrypto.xxteaTest","xxtea库不存在,请云编译一份最新版固件,并选上xxtea库")
        end
    end
    while true do
        sys.wait(1000)
        local text = "Hello World!"
        local key = "07946"
        local encrypt_data = xxtea.encrypt(text, key)
        log.info("testCrypto.xxteaTest","xxtea_encrypt:", encrypt_data:toHex())
        local decrypt_data = xxtea.decrypt(encrypt_data, key)
        log.info("testCrypto.xxteaTest","decrypt_data:", decrypt_data:toHex())
    end
end)

-- 用户代码已结束---------------------------------------------
-- 结尾总是这一句
sys.run()
-- sys.run()之后后面不要加任何语句!!!!!
