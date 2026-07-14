local sm3 = {}

-- SM3测试
function sm3.test_sm3_update()
    log.info("GMSSL SM3 测试开始")
    local correct_val = "E64FD76F4078E51DCA428323D3FADBD5D52723BBF1379184650DA5CE6002B2BF"
    local update_val = gmssl.sm3update("lqlq666lqlq946")
    log.info("gmssl.sm3update", string.toHex(update_val))
    assert(string.toHex(update_val) == correct_val, "× SM3 测试失败")
end

-- SM3测试
function sm3.test_sm3_normal()
    log.info("GMSSL SM3 正常功能测试开始")
    
    local test_data = "lqlq666lqlq946"
    local correct_val = "E64FD76F4078E51DCA428323D3FADBD5D52723BBF1379184650DA5CE6002B2BF"
    
    local hash_val = gmssl.sm3(test_data)
    assert(hash_val, "× GMSSL SM3 计算失败")
    
    local hash_hex = string.toHex(hash_val)
    assert(hash_hex == correct_val, "× GMSSL SM3 计算结果错误，期望: " .. correct_val .. ", 实际: " .. hash_hex)
    log.info("√ GMSSL SM3 正常功能测试成功，hash值: " .. hash_hex)
end

-- SM3 HMAC测试
function sm3.test_sm3hmac_normal()
    log.info("GMSSL SM3 HMAC 正常功能测试开始")
    
    local test_data = "lqlq666lqlq946"
    local test_key = "123"
    local correct_val = "FBB67FC936777011AA70336F0F0B6305D529A97A87D8ECA8880472CD2C30A721"
    
    local hmac_val = gmssl.sm3hmac(test_data, test_key)
    assert(hmac_val, "× GMSSL SM3 HMAC 计算失败")
    
    local hmac_hex = string.toHex(hmac_val)
    assert(hmac_hex == correct_val, "× GMSSL SM3 HMAC 计算结果错误，期望: " .. correct_val .. ", 实际: " .. hmac_hex)
    log.info("√ GMSSL SM3 HMAC 正常功能测试成功，hmac值: " .. hmac_hex)
end


-- SM3 nil参数测试
function sm3.test_sm3_nil_params()
    log.info("GMSSL SM3 nil参数测试开始")

    local sm3_first = gmssl.sm3(nil)
    assert(sm3_first == nil, "× sm3传入nil应该返回nil")
    log.info("sm3", "sm3传入nil测试通过")

    local sm3hmac_first = gmssl.sm3hmac(nil, "key")
    assert(sm3hmac_first == nil, "× sm3hmac data为nil应该返回nil")
    log.info("sm3", "sm3hmac data为nil测试通过")

    local sm3hmac_second = gmssl.sm3hmac("data", nil)
    assert(sm3hmac_second == nil, "× sm3hmac key为nil应该返回nil")
    log.info("sm3", "sm3hmac key为nil测试通过")

    local sm3hmac_third = gmssl.sm3hmac(nil, nil)
    assert(sm3hmac_third == nil, "× sm3hmac两个参数都为nil应该返回nil")
    log.info("sm3", "sm3hmac两个参数都为nil测试通过")

    -- SM3UPDATE函数
    if gmssl.sm3update then
        local sm3update_first = gmssl.sm3update(nil)
        assert(sm3update_first == nil, "× sm3update传入nil应该返回nil")
        log.info("sm3", "sm3update传入nil测试通过")
    end

    log.info("√ GMSSL SM3 nil参数测试全部通过")
end

return sm3
