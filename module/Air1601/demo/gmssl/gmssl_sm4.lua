--[[
@module  gmssl_sm4
@summary gmssl_sm4 
@version 1.0
@date    2025.10.29
@author  沈园园
@usage
本文件为gmssl sm4应用功能模块，核心业务逻辑为：
1、演示国密sm4加密和解码的应用；

本文件没有对外接口，直接在main.lua中require "gmssl_sm4"就可以加载运行；
]]


local function gmssl_sm4_task_func()

    if gmssl.sm4encrypt then
        log.info("=== SM4测试")
        local passwd = "1234567890123456"
        local iv = "1234567890666666"
        -- SM4 算法, 对称加密
        originStr = ">>SM4 ECB ZeroPadding test<<"
        --加密模式：ECB；填充方式：ZeroPadding；密钥：1234567890123456；
        encodeStr = gmssl.sm4encrypt("ECB", "ZERO", originStr, passwd)
        log.info("sm4.ecb.zero", "加密后", string.toHex(encodeStr))
        log.info("sm4.ecb.zero", "解密后", gmssl.sm4decrypt("ECB","ZERO",encodeStr,passwd))

        originStr = ">>SM4 ECB Pkcs5Padding test<<"
        --加密模式：ECB；填充方式：Pkcs5Padding；密钥：1234567890123456；
        encodeStr = gmssl.sm4encrypt("ECB", "PKCS5", originStr, passwd)
        log.info("sm4.ecb.pks5", "加密后", string.toHex(encodeStr))
        log.info("sm4.ecb.pks5", "解密后", gmssl.sm4decrypt("ECB","PKCS5",encodeStr,passwd))

        originStr = ">>SM4 CBC Pkcs5Padding test<<"
        --加密模式：CBC；填充方式：Pkcs5Padding；密钥：1234567890123456；偏移量：1234567890666666
        encodeStr = gmssl.sm4encrypt("CBC","PKCS5", originStr, passwd, iv)
        log.info("sm4.cbc.pks5", "加密后", string.toHex(encodeStr))
        log.info("sm4.cbc.pks5", "解密后", gmssl.sm4decrypt("CBC","PKCS5",encodeStr,passwd, iv))

        -- 完全对齐16字节的对比测试
        originStr = "1234567890123456"
        encodeStr = gmssl.sm4encrypt("ECB","PKCS7",originStr,passwd)
        log.info("sm4.ecb.pkcs7", encodeStr:toHex())
        encodeStr = gmssl.sm4encrypt("ECB","PKCS5",originStr,passwd)
        log.info("sm4.ecb.pkcs5", encodeStr:toHex())
        encodeStr = gmssl.sm4encrypt("ECB","ZERO",originStr,passwd)
        log.info("sm4.ecb.zero", encodeStr:toHex())
        encodeStr = gmssl.sm4encrypt("ECB","NONE",originStr,passwd)
        log.info("sm4.ecb.none", encodeStr:toHex())
    end
end

sys.taskInit(gmssl_sm4_task_func)
