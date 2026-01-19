local sm4 = {}

local passwd = "1234567890123456"
local iv = "1234567890666666"
local originStr = ""
local ret = 0

--SM4签名和验证测试
function sm4.test_sm4_test_ECB_ZEROPadding_encrypt()
    log.info("GMSSL SM4 ECB_ZEROPadding加密测试开始")
    originStr = ">>SM4 ECB ZeroPadding test<<"
    correct_val = "E8DF19897C0BF1FFA50910C5C548F5A4E9E34BED9F5CEE519CFA24C37A290B25"
    local encry_val = gmssl.sm4encrypt("ECB", "ZERO", originStr, passwd)
    ret = 0
    if string.toHex(encry_val) == correct_val then
        ret = 1
    end
    assert(ret == 1, "× GMSSL SM4 ECB_ZEROPadding加密错误")
    if ret then
        log.info("√ GMSSL SM4 ECB_ZEROPadding加密测试成功")
        log.info("GMSSL SM4 ECB_ZEROPadding解密测试开始")
        local decry_val = gmssl.sm4decrypt("ECB","ZERO",encry_val,passwd)
        assert(decry_val == originStr, "× GMSSL SM4 ECB_ZEROPadding解密测试失败")
    end

end

function sm4.test_sm4_test_ECB_PKCS5Padding_encrypt()
    log.info("GMSSL SM4 ECB_PKCS5Padding加密测试开始")
    originStr = ">>SM4 ECB Pkcs5Padding test<<"
    correct_val = "25B3D6AB8C855115C3A8883FE3ADCC6B9004C83B86CE7A45517CA6736DBA4EFE"
    local encry_val = gmssl.sm4encrypt("ECB", "PKCS5", originStr, passwd)
    ret = 0
    if string.toHex(encry_val) == correct_val then
        ret = 1
    end
    assert(ret == 1, "× GMSSL SM4 ECB_PKCS5Padding加密错误")
    if ret then
        log.info("√ GMSSL SM4 ECB_PKCS5Padding加密测试成功")
        log.info("GMSSL SM4 ECB_PKCS5Padding解密测试开始")
        local decry_val = gmssl.sm4decrypt("ECB","PKCS5",encry_val,passwd)
        assert(decry_val == originStr, "× GMSSL SM4 ECB_PKCS5Padding解密测试失败")
    end

end

function sm4.test_sm4_test_CBC_PKCS5Padding_encrypt()
    log.info("GMSSL SM4 CBC_PKCS5Padding加密测试开始")
    originStr = ">>SM4 CBC Pkcs5Padding test<<"
    correct_val = "A11C24BB018C8124FADAFC9B6BF7932C05BA2F24E9DFB9D79D982A676F9C010C"
    local encry_val = gmssl.sm4encrypt("CBC","PKCS5", originStr, passwd, iv)
    ret = 0
    if string.toHex(encry_val) == correct_val then
        ret = 1
    end
    assert(ret == 1, "× GMSSL SM4 CBC_PKCS5Padding加密错误")
    if ret then
        log.info("√ GMSSL SM4 CBC_PKCS5Padding加密测试成功")
        log.info("GMSSL SM4 CBC_PKCS5Padding解密测试开始")
        local decry_val = gmssl.sm4decrypt("CBC","PKCS5",encry_val,passwd, iv)
        assert(decry_val == originStr, "× GMSSL SM4 CBC_PKCS5Padding解密测试失败")
    end

end

function sm4.test_sm4_test_ECB_PKCS7Padding_encrypt()
    log.info("GMSSL SM4 ECB_PKCS7Padding加密测试开始")
    originStr = "1234567890123456"
    correct_val = "B083DCC0A9F64BD9FAE2FA8C936E3D776C88F739AF2A29A735381F5677BADEF7"
    local encry_val = gmssl.sm4encrypt("ECB","PKCS7",originStr,passwd)
    ret = 0
    if string.toHex(encry_val) == correct_val then
        ret = 1
        log.info("√ GMSSL SM4 ECB_PKCS7Padding加密测试成功")
    end
    assert(ret == 1, "× GMSSL SM4 ECB_PKCS7Padding加密错误")

end

function sm4.test_sm4_test_ECB_PKCS5Padding_encrypt()
    log.info("GMSSL SM4 ECB_PKCS5Padding加密测试开始")
    originStr = "1234567890123456"
    correct_val = "B083DCC0A9F64BD9FAE2FA8C936E3D776C88F739AF2A29A735381F5677BADEF7"
    local encry_val = gmssl.sm4encrypt("ECB", "PKCS5", originStr, passwd)
    ret = 0
    if string.toHex(encry_val) == correct_val then
        ret = 1
        log.info("√ GMSSL SM4 ECB_PKCS5Padding加密测试成功")
    end
    assert(ret == 1, "× GMSSL SM4 ECB_PKCS5Padding加密错误")
    
end

function sm4.test_sm4_test_ECB_ZEROPadding_encrypt()
    log.info("GMSSL SM4 ECB_ZEROPadding加密测试开始")
    originStr = "1234567890123456"
    correct_val = "B083DCC0A9F64BD9FAE2FA8C936E3D77D2D68ED9FE06CB40C9A150AA5917F15F"
    local encry_val = gmssl.sm4encrypt("ECB", "ZERO", originStr, passwd)
    ret = 0
    if string.toHex(encry_val) == correct_val then
        ret = 1
        log.info("√ GMSSL SM4 ECB_ZEROPadding加密测试成功")
    end
    assert(ret == 1, "× GMSSL SM4 ECB_ZEROPadding加密错误")

end

function sm4.test_sm4_test_none_encrypt()
    log.info("GMSSL SM4 none加密测试开始")
    originStr = "1234567890123456"
    correct_val = "B083DCC0A9F64BD9FAE2FA8C936E3D77"
    local encry_val = gmssl.sm4encrypt("ECB","NONE",originStr,passwd)
    ret = 0
    if string.toHex(encry_val) == correct_val then
        ret = 1
        log.info("√ GMSSL SM4 none加密测试成功")
    end
    assert(ret == 1, "× GMSSL SM4 none加密错误")
end



return sm4
