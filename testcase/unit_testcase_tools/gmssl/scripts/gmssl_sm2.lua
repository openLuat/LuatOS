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

-- SM2 test:固定秘钥测试
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
    local encry_val = gmssl.sm2encrypt(pkx, pky, encrypt_originStr, true)
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
    encrypt_originStr = "!!from LuatOS!!"
    local encry_val = gmssl.sm2encrypt(pkx, pky, encrypt_originStr, true, true)

    assert(encry_val, "× GMSSL SM2 网站兼容模式(C1C2C3)加密失败")
    if encry_val then
        log.info("√ GMSSL SM2 网站兼容模式(C1C2C3)加密测试成功")
        log.info("GMSSL SM2 网站兼容模式(C1C2C3)解密测试开始")
        local decry_val = gmssl.sm2decrypt(private, encry_val, true, true)
        assert(decry_val == encrypt_originStr, "× GMSSL SM2 网站兼容模式(C1C2C3)解密测试失败")
    end
end

-- SM2动态秘钥测试
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

-- SM2 大数据加密测试 (验证 16KB 上限)
function sm2.test_sm2_large_data_encrypt()
    log.info("GMSSL SM2 大数据加密测试开始 (256/1024 字节)")
    local pkx, pky, private = gmssl.sm2keygen()

    -- 构造 256 字节测试数据
    local data256 = string.rep("A", 256)
    -- 构造 1024 字节测试数据
    local data1024 = string.rep("B", 1024)

    -- 默认 DER 模式 (mode=false)
    for _, testdata in ipairs({data256, data1024}) do
        local label = #testdata .. " 字节"

        -- 默认模式
        local enc = gmssl.sm2encrypt(pkx, pky, testdata)
        assert(enc, "× SM2 大数据(" .. label .. ")默认模式加密失败")
        local dec = gmssl.sm2decrypt(private, enc)
        assert(dec == testdata, "× SM2 大数据(" .. label .. ")默认模式解密失败")

        -- 网站兼容模式 C1C3C2
        local enc2 = gmssl.sm2encrypt(pkx, pky, testdata, true)
        assert(enc2, "× SM2 大数据(" .. label .. ")C1C3C2加密失败")
        local dec2 = gmssl.sm2decrypt(private, enc2, true)
        assert(dec2 == testdata, "× SM2 大数据(" .. label .. ")C1C3C2解密失败")

        -- 网站兼容模式 C1C2C3
        local enc3 = gmssl.sm2encrypt(pkx, pky, testdata, true, true)
        assert(enc3, "× SM2 大数据(" .. label .. ")C1C2C3加密失败")
        local dec3 = gmssl.sm2decrypt(private, enc3, true, true)
        assert(dec3 == testdata, "× SM2 大数据(" .. label .. ")C1C2C3解密失败")
    end

    -- 验证超限数据被正确拒绝 (16385 字节)
    local data_over = string.rep("C", 16385)
    local enc_over = gmssl.sm2encrypt(pkx, pky, data_over)
    assert(enc_over == nil, "× SM2 超限数据应返回 nil")

    log.info("√ GMSSL SM2 大数据加密测试全部通过")
end

-- SM2 nil参数测试
function sm2.test_sm2_nil_params()
    log.info("GMSSL SM2 nil参数测试开始")

    local pkx = "ABE87C924B7ECFDEA1748A06E89003C9F7F4DC5C3563873CE2CAE46F66DE8141"
    local pky = "9514733D38CC026F2452A6A3A3A4DA0C28F864AFA5FE2C45E0EB6B761FBB5286"
    local private = "129EDC282CD2E9C1144C2E7315F926D772BC96600D2771E8BE02060313FE00D5"
    local testStr = "test string"

    -- 测试encrypt各参数为nil的情况
    local sm2encrypt_first = gmssl.sm2encrypt(nil, pky, testStr)
    assert(sm2encrypt_first == nil, "× sm2encrypt pkx为nil应该返回nil或抛出错误")
    log.info("sm2", "sm2encrypt pkx为nil测试通过")

    local sm2encrypt_second = gmssl.sm2encrypt(pkx, nil, testStr)
    assert(sm2encrypt_second == nil, "× sm2encrypt pky为nil应该返回nil或抛出错误")
    log.info("sm2", "sm2encrypt pky为nil测试通过")

    local sm2encrypt_third = gmssl.sm2encrypt(pkx, pky, nil)
    assert(sm2encrypt_third == nil, "× sm2encrypt data为nil应该返回nil或抛出错误")
    log.info("sm2", "sm2encrypt data为nil测试通过")

    -- 测试encrypt的mode参数为nil的情况
    local sm2encrypt_fourth = gmssl.sm2encrypt(pkx, pky, testStr, nil)
    assert(sm2encrypt_fourth ~= nil, "× sm2encrypt mode为nil应该使用默认值false，不应返回nil")
    log.info("sm2", "sm2encrypt mode为nil测试通过")

    -- 测试encrypt的mode2参数为nil的情况
    local sm2encrypt_fifth = gmssl.sm2encrypt(pkx, pky, testStr, true, nil)
    assert(sm2encrypt_fifth ~= nil, "× sm2encrypt mode2为nil应该使用默认值false，不应返回nil")
    log.info("sm2", "sm2encrypt mode2为nil测试通过")

    -- 测试decrypt各参数为nil的情况
    local sm2encrypt_valid = gmssl.sm2encrypt(pkx, pky, testStr)
    assert(sm2encrypt_valid, "× 创建有效加密数据失败")
    log.info("sm2", "创建有效加密数据成功")

    local sm2decrypt_first = gmssl.sm2decrypt(nil, sm2encrypt_valid)
    assert(sm2decrypt_first == nil, "× sm2decrypt private为nil应返回nil")
    log.info("sm2", "sm2decrypt private为nil测试通过")

    local sm2decrypt_second = gmssl.sm2decrypt(private, nil)
    assert(sm2decrypt_second == nil, "× sm2decrypt data为nil应返回nil")
    log.info("sm2", "sm2decrypt data为nil测试通过")

    local sm2decrypt_third = gmssl.sm2decrypt(private, sm2encrypt_valid, nil)
    assert(sm2decrypt_third ~= nil, "× sm2decrypt mode为nil应该使用默认值false，不应返回nil")
    log.info("sm2", "sm2decrypt mode为nil测试通过")

    local sm2encrypt_valid_nil = gmssl.sm2encrypt(pkx, pky, testStr, true, nil)
    local sm2decrypt_fourth = gmssl.sm2decrypt(private, sm2encrypt_valid_nil, true, nil)
    assert(sm2decrypt_fourth ~= nil,
        "× sm2decrypt mode1为true,mode2为nil应该使用默认值false，不应返回nil")
    log.info("sm2", "sm2decrypt mode1为true,mode2为nil测试通过")

    local sm2decrypt_fifth = gmssl.sm2decrypt(private, sm2encrypt_valid, false, nil)
    assert(sm2decrypt_fifth ~= nil,
        "× sm2decrypt mode1为false,mode2为nil应该使用默认值false，不应返回nil")
    log.info("sm2", "sm2decrypt mode1为false,mode2为nil测试通过")

    -- 测试sign各参数为nil的情况
    private = "129EDC282CD2E9C1144C2E7315F926D772BC96600D2771E8BE02060313FE00D5"
    local originStr = string.fromHex("434477813974bf58f94bcf760833c2b40f77a5fc360485b0b9ed1bd9682edb45")

    local sm2sign_first = gmssl.sm2sign(private, originStr, nil)
    assert(sm2sign_first ~= nil, "× sm2sign id为nil应该使用默认值false，不应返回nil")
    log.info("sm2", "sm2sign id为nil测试通过")

    -- 测试verify各参数为nil的情况
    local valid_sign = gmssl.sm2sign(private, originStr, nil)
    assert(valid_sign, "× 创建有效签名失败")

    local sm2verify_first = gmssl.sm2verify(pkx, pky, originStr, nil, valid_sign)
    assert(sm2verify_first ~= nil, "× sm2verify id为nil应该使用默认值false，不应返回nil")
    log.info("sm2", "sm2verify id为nil测试通过")

    log.info("√ GMSSL SM2 nil参数测试全部通过")
end

return sm2
