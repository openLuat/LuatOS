local sm2 = {}

local originStr = ""
local encrypt_originStr = ""
local pkx = ""
local pky = ""
local private = ""
local dynamicStr = ""
local sign_val = ""

-- SM2签名和验证测试
function sm2.test_sm2_sign_verify()
    log.info("GMSSL SM2 签名和验证测试开始")
    pkx = "ABE87C924B7ECFDEA1748A06E89003C9F7F4DC5C3563873CE2CAE46F66DE8141"
    pky = "9514733D38CC026F2452A6A3A3A4DA0C28F864AFA5FE2C45E0EB6B761FBB5286"
    private = "129EDC282CD2E9C1144C2E7315F926D772BC96600D2771E8BE02060313FE00D5"
    originStr = string.fromHex("434477813974bf58f94bcf760833c2b40f77a5fc360485b0b9ed1bd9682edb45")
    sign_val = gmssl.sm2sign(private, originStr, nil)
        -- log.info("sm2sign", sign_val and sign_val:toHex())
        assert(sign_val, "× SM2 签名失败")
        if sign_val then
            local actual_val = gmssl.sm2verify(pkx, pky, originStr, nil, sign_val)
            assert(actual_val == true, "× SM2 验证测试失败")
        end
    -- 假设这里有 SM2 签名和验证的测试代码
    -- 这里只是一个示例，实际测试代码应调用 GMSSL 的 SM2 接口
end

function sm2.test_sm2_sign_IDverify()
    log.info("GMSSL SM2 带ID的签名和验证测试开始")
    local id = "1234"
    pkx = "ABE87C924B7ECFDEA1748A06E89003C9F7F4DC5C3563873CE2CAE46F66DE8141"
    pky = "9514733D38CC026F2452A6A3A3A4DA0C28F864AFA5FE2C45E0EB6B761FBB5286"
    private = "129EDC282CD2E9C1144C2E7315F926D772BC96600D2771E8BE02060313FE00D5"
    originStr = string.fromHex("434477813974bf58f94bcf760833c2b40f77a5fc360485b0b9ed1bd9682edb45")
    sign_val = gmssl.sm2sign(private, originStr, id)
        -- log.info("sm2sign", sign_val and sign_val:toHex())
        assert(sign_val, "× SM2 带ID签名失败")
        if sign_val then
            local actual_val = gmssl.sm2verify(pkx, pky, originStr, id, sign_val)
            assert(actual_val == true, "× SM2 带ID验证测试失败")
        end
end

-- --SM2 test:固定秘钥测试
function sm2.test_sm2_test_encrypt()
    log.info("GMSSL SM2 默认模式加密测试开始")
    pkx = "ABE87C924B7ECFDEA1748A06E89003C9F7F4DC5C3563873CE2CAE46F66DE8141"
    pky = "9514733D38CC026F2452A6A3A3A4DA0C28F864AFA5FE2C45E0EB6B761FBB5286"
    private = "129EDC282CD2E9C1144C2E7315F926D772BC96600D2771E8BE02060313FE00D5"
    encrypt_originStr = "!!from LuatOS!!"
    local encry_val = gmssl.sm2encrypt(pkx, pky, encrypt_originStr)
    assert(encry_val, "× GMSSL SM2 默认模式加密失败")
    if encry_val then
        log.info("√ GMSSL SM2 默认模式加密测试成功")
        log.info("GMSSL SM2 默认模式解密测试开始")
        local decry_val = gmssl.sm2decrypt(private, encry_val)
        assert(decry_val == encrypt_originStr, "× GMSSL SM2 默认模式解密测试失败")
    end

end

function sm2.test_sm2_test_C1C3C2_encrypt()
    log.info("GMSSL SM2 网站兼容模式(C1C3C2)加密测试开始")
    pkx = "ABE87C924B7ECFDEA1748A06E89003C9F7F4DC5C3563873CE2CAE46F66DE8141"
    pky = "9514733D38CC026F2452A6A3A3A4DA0C28F864AFA5FE2C45E0EB6B761FBB5286"
    private = "129EDC282CD2E9C1144C2E7315F926D772BC96600D2771E8BE02060313FE00D5"
    encrypt_originStr = "!!from LuatOS!!"
    local encry_val = gmssl.sm2encrypt(pkx, pky, encrypt_originStr,true)
    assert(encry_val, "× GMSSL SM2 网站兼容模式(C1C3C2)加密失败")
    if encry_val then
        log.info("√ GMSSL SM2 网站兼容模式(C1C3C2)加密测试成功")
        log.info("GMSSL SM2 网站兼容模式(C1C3C2)解密测试开始")
        local decry_val = gmssl.sm2decrypt(private, encry_val, true)
        assert(decry_val == encrypt_originStr, "× GMSSL SM2 网站兼容模式(C1C3C2)解密测试失败")
    end

end

function sm2.test_sm2_test_C1C2C3_encrypt()
    log.info("GMSSL SM2 网站兼容模式(C1C2C3)加密测试开始")
    pkx = "ABE87C924B7ECFDEA1748A06E89003C9F7F4DC5C3563873CE2CAE46F66DE8141"
    pky = "9514733D38CC026F2452A6A3A3A4DA0C28F864AFA5FE2C45E0EB6B761FBB5286"
    private = "129EDC282CD2E9C1144C2E7315F926D772BC96600D2771E8BE02060313FE00D5"
    local encry_val = gmssl.sm2encrypt(pkx, pky, encrypt_originStr,true, true)
    
    assert(encry_val, "× GMSSL SM2 网站兼容模式(C1C2C3)加密失败")
    if encry_val then
        log.info("√ GMSSL SM2 网站兼容模式(C1C2C3)加密测试成功")
        log.info("GMSSL SM2 网站兼容模式(C1C2C3)解密测试开始")
        local decry_val = gmssl.sm2decrypt(private, encry_val, true, true)
        assert(decry_val == encrypt_originStr, "× GMSSL SM2 网站兼容模式(C1C2C3)解密测试失败")
    end

end

--SM2动态秘钥测试
function sm2.test_sm2_dynamic_encrypt()
    log.info("GMSSL SM2 动态秘钥默认加密测试开始")
    local pkx, pky, private = gmssl.sm2keygen()
    dynamicStr = "32wrniosadnfvnadsio;fasiow"
    local encry_val = gmssl.sm2encrypt(pkx, pky, dynamicStr)
    
    assert(encry_val, "× GMSSL SM2 动态秘钥默认加密失败")
    if encry_val then
        log.info("√ GMSSL SM2 动态秘钥默认模式加密测试成功")
        log.info("GMSSL SM2 动态秘钥默认模式解密测试开始")
        local decry_val = gmssl.sm2decrypt(private, encry_val)
        assert(decry_val == dynamicStr, "× GMSSL SM2 动态秘钥默认模式解密测试失败")
    end
end

function sm2.test_sm2_dynamic_C1C3C2_encrypt()
    log.info("GMSSL SM2 动态秘钥网站兼容模式(C1C3C2)加密测试开始")
    local pkx, pky, private = gmssl.sm2keygen()
    dynamicStr = "32wrniosadnfvnadsio;fasiow"
    local encry_val = gmssl.sm2encrypt(pkx, pky, dynamicStr, true)
    
    assert(encry_val, "× GMSSL SM2 动态秘钥网站兼容模式(C1C3C2)加密失败")
    if encry_val then
        log.info("√ GMSSL SM2 动态秘钥网站兼容模式(C1C3C2)加密测试成功")
        log.info("GMSSL SM2 动态秘钥网站兼容模式(C1C3C2)解密测试开始")
        local decry_val = gmssl.sm2decrypt(private, encry_val, true)
        assert(decry_val == dynamicStr, "× GMSSL SM2 动态秘钥网站兼容模式(C1C3C2)解密测试失败")
    end
end

function sm2.test_sm2_dynamic_C1C2C3_encrypt()
    log.info("GMSSL SM2 动态秘钥网站兼容模式(C1C2C3)加密测试开始")
    local pkx, pky, private = gmssl.sm2keygen()
    dynamicStr = "32wrniosadnfvnadsio;fasiow"
    local encry_val = gmssl.sm2encrypt(pkx, pky, dynamicStr, true, true)
    
    assert(encry_val, "× GMSSL SM2 动态秘钥网站兼容模式(C1C2C3)加密失败")
    if encry_val then
        log.info("√ GMSSL SM2 动态秘钥网站兼容模式(C1C2C3)加密测试成功")
        log.info("GMSSL SM2 动态秘钥网站兼容模式(C1C2C3)解密测试开始")
        local decry_val = gmssl.sm2decrypt(private, encry_val, true, true)
        assert(decry_val == dynamicStr, "× GMSSL SM2 动态秘钥网站兼容模式(C1C2C3)解密测试失败")
    end
end


return sm2
