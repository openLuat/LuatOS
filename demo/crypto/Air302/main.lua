
-- LuaTools需要PROJECT和VERSION这两个信息
PROJECT = "cryptodemo"
VERSION = "1.0.0"

-- sys库是标配
_G.sys = require("sys")

-- 日志TAG, 非必须
local NETLED = gpio.setup(19, 0)

sys.taskInit(function()
    while 1 do
        if socket.isReady() then
            NETLED(1)
            sys.wait(100)
            NETLED(0)
            sys.wait(1900)
        else
            NETLED(1)
            sys.wait(500)
            NETLED(0)
            sys.wait(500)
        end
    end
end)

sys.timerLoopStart(function()
    --sys.wait(3000) -- 开机后展示crypto功能

    -- MD5,输出结果已经hex编码
    log.info("md5", crypto.md5("abc"))
    log.info("hmac_md5", crypto.hmac_md5("abc", "1234567890"))

    -- SHA1,输出结果已经hex编码
    log.info("sha1", crypto.sha1("abc"))
    log.info("hmac_sha1", crypto.hmac_sha1("abc", "1234567890"))

    -- AES加密, 未经Hex编码. AES-128-ECB 算法,待加密字符串如果超过32字节会报错,待查. by wendal 20200812
    local data_encrypt = crypto.cipher_encrypt("AES-128-ECB", "PKCS7", "12345678901234 > " .. nbiot.imei(), "1234567890123456")
    local data2_encrypt = crypto.cipher_encrypt("AES-128-CBC", "PKCS7", "12345678901234 > ".. nbiot.imei(), "1234567890123456", "1234567890666666")
    log.info("AES", data_encrypt:toHex())
    log.info("AES", data2_encrypt:toHex())

    -- AES解密, 未经Hex编码
    local data_decrypt = crypto.cipher_decrypt("AES-128-ECB", "PKCS7", data_encrypt, "1234567890123456")
    local data2_decrypt = crypto.cipher_decrypt("AES-128-CBC", "PKCS7", data2_encrypt, "1234567890123456", "1234567890666666")
    log.info("AES", data_decrypt)
    log.info("AES", data2_decrypt)
    log.info("mem", rtos.meminfo("sys"))
end, 2000)

-- 用户代码已结束---------------------------------------------
-- 结尾总是这一句
sys.run()
-- sys.run()之后后面不要加任何语句!!!!!
