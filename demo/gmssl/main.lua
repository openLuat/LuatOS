
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

-- Air101/Air103默认80M主频, 跑国密算法会很慢的,调整到240M
if mcu and (rtos.bsp() == "AIR101" or rtos.bsp() == "AIR103" or rtos.bsp() == "AIR601" ) then
    mcu.setClk(240)
end

sys.taskInit(function()

    sys.wait(3000)
    log.info("gmssl", "start")

    -- SM2 , 非对称加密, 类似于RSA,但属于椭圆算法
    -- 就当前实现还是比较慢的
    if gmssl.sm2encrypt then -- 部分BSP不支持
        local originStr = "!!from LuatOS!!"
        local pkx = "ABE87C924B7ECFDEA1748A06E89003C9F7F4DC5C3563873CE2CAE46F66DE8141"
        local pky = "9514733D38CC026F2452A6A3A3A4DA0C28F864AFA5FE2C45E0EB6B761FBB5286"
        local private = "129EDC282CD2E9C1144C2E7315F926D772BC96600D2771E8BE02060313FE00D5"

        -- GMSSL默认格式
        log.info("==== SM2 默认GMSSL模式")
        local encodeStr = gmssl.sm2encrypt(pkx,pky,originStr)
        log.info("对比", originStr,"encrypt",string.toHex(encodeStr))
        log.info("gmssl.sm2decrypt",gmssl.sm2decrypt(private,encodeStr))

        -- 网站兼容模式 https://i.goto327.top/CryptTools/SM2.aspx
        -- 密钥格式 C1C3C2
        log.info("==== SM2 网站兼容模式")
        local encodeStr = gmssl.sm2encrypt(pkx,pky,originStr, true)
        log.info("sm2", originStr,"encrypt",string.toHex(encodeStr))
        log.info("gmssl.sm2decrypt",gmssl.sm2decrypt(private,encodeStr,true))
    end

    -- SM3 算法, hash类
    if gmssl.sm3update then
        log.info("=== SM3测试")
        encodeStr = gmssl.sm3update("lqlq666lqlq946")
        log.info("gmssl.sm3update",string.toHex(encodeStr))
    end

    if gmssl.sm4encrypt then
        log.info("=== SM4测试")
        local passwd = "1234567890123456"
        local iv = "1234567890666666"
        -- SM4 算法, 对称加密
        originStr = ">>SM4 ECB ZeroPadding test<<"
        --加密模式：ECB；填充方式：ZeroPadding；密钥：1234567890123456；密钥长度：128 bit
        encodeStr = gmssl.sm4encrypt("ECB","ZERO",originStr,passwd)
        log.info("加密对比", originStr,"encrypt",string.toHex(encodeStr))
        log.info("gmssl.sm4decrypt",gmssl.sm4decrypt("ECB","ZERO",encodeStr,passwd))

        originStr = ">>SM4 ECB Pkcs5Padding test<<"
        --加密模式：ECB；填充方式：Pkcs5Padding；密钥：1234567890123456；密钥长度：128 bit
        encodeStr = gmssl.sm4encrypt("ECB","PKCS5",originStr,passwd)
        log.info("加密对比", originStr,"encrypt",string.toHex(encodeStr))
        log.info("gmssl.sm4decrypt",gmssl.sm4decrypt("ECB","PKCS5",encodeStr,passwd))

        originStr = ">>SM4 CBC Pkcs5Padding test<<"
        --加密模式：CBC；填充方式：Pkcs5Padding；密钥：1234567890123456；密钥长度：128 bit；偏移量：1234567890666666
        encodeStr = gmssl.sm4encrypt("CBC","PKCS5",originStr,passwd,iv)
        log.info("加密对比", originStr,"encrypt",string.toHex(encodeStr))
        log.info("gmssl.sm4decrypt",gmssl.sm4decrypt("CBC","PKCS5",encodeStr,passwd, iv))
    end

    log.info("gmssl", "ALL Done")
end)

-- 用户代码已结束---------------------------------------------
-- 结尾总是这一句
sys.run()
-- sys.run()之后后面不要加任何语句!!!!!
