
-- LuaTools需要PROJECT和VERSION这两个信息
PROJECT = "gmssldemo"
VERSION = "1.0.0"

log.info("main", PROJECT, VERSION)

-- sys库是标配
_G.sys = require("sys")

if wdt then
    --添加硬狗防止程序卡死，在支持的设备上启用这个功能
    wdt.init(9000)--初始化watchdog设置为9s
    sys.timerLoopStart(wdt.feed, 3000)--3s喂一次狗
end

sys.taskInit(function()

    sys.wait(3000)
    log.info("gmssl", "start")

    -- SM2 , 非对称加密, 类似于RSA,但属于椭圆算法
    -- 就当前实现还是比较慢的
    if gmssl.sm2encrypt then -- 部分BSP不支持
        local originStr = "encryption standard"
        local pkx = "191BFF8148006EEA72D857CB974DB9F4903B3CA3655D8D597AD4663F5044DCB1"
        local pky = "E2F7888AF1FCD8C653A8059CD2F379855389F71A7709E2C1EE1E914C855EF119"
        local private = "1649AB77A00637BD5E2EFE283FBF353534AA7F7CB89463F208DDBC2920BB0DA0"
        local rand = "4C62EEFD6ECFC2B95B92FD6C3D9575148AFA17425546D49018E5388D49DD7B4F"
        local encodeStr = gmssl.sm2encrypt(pkx,pky,rand,originStr,private)
        print(originStr,"encrypt",string.toHex(encodeStr))
        log.info("testsm.sm2decrypt",gmssl.sm2decrypt(private,encodeStr,pkx,pky))
    end

    -- SM3 算法, hash类
    encodeStr = gmssl.sm3update("lqlq666lqlq946")
    log.info("testsm.sm3update",string.toHex(encodeStr))

    -- SM4 算法, 对称加密
    originStr = "SM4 ECB ZeroPadding test"
    --加密模式：ECB；填充方式：ZeroPadding；密钥：1234567890123456；密钥长度：128 bit
    encodeStr = gmssl.sm4encrypt("ECB","ZERO",originStr,"1234567890123456")
    print(originStr,"encrypt",string.toHex(encodeStr))
    log.info("testsm.sm4decrypt",gmssl.sm4decrypt("ECB","ZERO",encodeStr,"1234567890123456"))

    originStr = "AES128 ECB Pkcs5Padding test"
    --加密模式：ECB；填充方式：Pkcs5Padding；密钥：1234567890123456；密钥长度：128 bit
    encodeStr = gmssl.sm4encrypt("ECB","PKCS5",originStr,"1234567890123456")
    print(originStr,"encrypt",string.toHex(encodeStr))
    log.info("testsm.sm4decrypt",gmssl.sm4decrypt("ECB","PKCS5",encodeStr,"1234567890123456"))

    originStr = "AES256 CBC Pkcs5Padding test"
    --加密模式：CBC；填充方式：Pkcs5Padding；密钥：1234567890123456；密钥长度：256 bit；偏移量：1234567890666666
    encodeStr = gmssl.sm4encrypt("CBC","PKCS5",originStr,"1234567890123456","1234567890666666")
    print(originStr,"encrypt",string.toHex(encodeStr))
    log.info("testsm.sm4decrypt",gmssl.sm4decrypt("CBC","PKCS5",encodeStr,"1234567890123456","1234567890666666"))

    log.info("sm", "ALL Done")
end)

-- 用户代码已结束---------------------------------------------
-- 结尾总是这一句
sys.run()
-- sys.run()之后后面不要加任何语句!!!!!
