local xxtea_test = {}

function xxtea_test.test_conventional_string()
    local text = "Hello World!"
    local key = "07946"
    local encrypt_data = xxtea.encrypt(text, key)
    assert(encrypt_data ~= nil, string.format(
        "xxtea常规字符串加密测试失败：预计加密后返回值不为nil,实际返回值为nil"))
    log.info("xxtea_test", "常规字符串加密测试通过")

    if encrypt_data then
        local decrypt_data = xxtea.decrypt(encrypt_data, key)
        assert(#decrypt_data == #text,
            string.format(
                "xxtea常规字符串解密测试失败：预计解密后数据长度为%d,实际返回值为%d", #text,
                #decrypt_data))
        log.info("xxtea_test", "常规字符串解密数据长度测试通过")

        assert(decrypt_data == text,
            string.format(
                "xxtea常规字符串解密测试失败：预计解密后数据内容为%s,实际返回值为%s", text,
                decrypt_data))
        log.info("xxtea_test", "常规字符串解密内容测试通过")
    end

end

function xxtea_test.test_chinese_string()
    local chinese_text = "你好，世界！Hello World! 测试123"
    local chinese_key = "test_key_1234567"
    local encrypt_data = xxtea.encrypt(chinese_text, chinese_key)
    assert(encrypt_data ~= nil,
        string.format("xxtea中文加密测试失败：预计加密后返回值不为nil,实际返回值为nil"))
    log.info("xxtea_test", "中文加密测试通过")

    if encrypt_data then
        local decrypt_data = xxtea.decrypt(encrypt_data, chinese_key)
        assert(#decrypt_data == #chinese_text,
            string.format("xxtea中文解密测试失败：预计解密后数据长度为%d,实际返回值为%d",
                #chinese_text, #decrypt_data))
        log.info("xxtea_test", "中文解密数据长度测试通过")

        assert(decrypt_data == chinese_text,
            string.format("xxtea中文解密测试失败：预计解密后数据内容为%s,实际返回值为%s",
                chinese_text, decrypt_data))
        log.info("xxtea_test", "中文解密内容测试通过")
    end
end

function xxtea_test.test_character_null()
    local empty_text = ""
    local empty_key = ""
    local empty_encrypt = xxtea.encrypt(empty_text, empty_key)
    assert(empty_encrypt == nil, string.format(
        "xxtea空字符串加密测试失败：预计返回值为nil,实际返回值为%s", empty_encrypt))
    log.info("xxtea_test", "空字符串加密测试通过")
end

function xxtea_test.test_short_text()
    local short_text = "ABC"
    local short_key = "123"
    local empty_encrypt = xxtea.encrypt(short_text, short_key)
    assert(empty_encrypt ~= nil, string.format(
        "xxtea短文本加密测试失败：预计返回值不为nil,实际返回值为%s", empty_encrypt))
    log.info("xxtea_test", "短文本加密测试通过")

    if empty_encrypt then
        local decrypt_data = xxtea.decrypt(empty_encrypt, short_key)
        assert(#decrypt_data == #short_text,
            string.format("xxtea短文本解密测试失败：预计解密后数据长度为%d,实际返回值为%d",
                #short_text, #decrypt_data))
        log.info("xxtea_test", "短文本解密数据长度测试通过")

        assert(decrypt_data == short_text,
            string.format("xxtea短文本解密测试失败：预计解密后数据内容为%s,实际返回值为%s",
                short_text, decrypt_data))
        log.info("xxtea_test", "短文本解密内容测试通过")
    end
end

function xxtea_test.test_long_text()
    local long_text = string.rep("X", 1024)
    local long_key = "123"
    local empty_encrypt = xxtea.encrypt(long_text, long_key)
    assert(empty_encrypt ~= nil, string.format(
        "xxtea长文本加密测试失败：预计返回值不为nil,实际返回值为%s", empty_encrypt))
    log.info("xxtea_test", "长文本加密测试通过")

    if empty_encrypt then
        local decrypt_data = xxtea.decrypt(empty_encrypt, long_key)
        assert(#decrypt_data == #long_text,
            string.format("xxtea长文本解密测试失败：预计解密后数据长度为%d,实际返回值为%d",
                #long_text, #decrypt_data))
        log.info("xxtea_test", "长文本解密数据长度测试通过")

        assert(decrypt_data == long_text,
            string.format("xxtea长文本解密测试失败：预计解密后数据内容为%s,实际返回值为%s",
                long_text, decrypt_data))
        log.info("xxtea_test", "长文本解密内容测试通过")
    end
end

function xxtea_test.test_key_text()
    local key_text = "TestKey"
    local test_keys = {{
        key = "a",
        desc = "1字节密钥"
    }, {
        key = "1234567890",
        desc = "10字节密钥"
    }, {
        key = "1234567890123456",
        desc = "16字节密钥"
    }, {
        key = "12345678901234567890123456789012",
        desc = "32字节密钥"
    }}

    for _, key_info in ipairs(test_keys) do
        log.info("test_xxtea", "测试密钥:", key_info.desc)
        local test_encrypt = xxtea.encrypt(key_text, key_info.key)
        assert(test_encrypt ~= nil,
            string.format(
                "长度为" .. key_info.desc .. "测试失败：预计返回值不为nil,实际返回值为%s",
                test_encrypt))
        log.info("xxtea_test", "长度为" .. key_info.desc .. "测试通过")

        if test_encrypt then
            local test_decrypt = xxtea.decrypt(test_encrypt, key_info.key)
            assert(#test_decrypt == #key_text,
                string.format(
                    "长度为" .. key_info.desc ..
                        "测试失败：预计解密后数据长度为%d,实际返回值为%d", #key_text, #test_decrypt))
            log.info("xxtea_test", "长度为" .. key_info.desc .. "测试通过")

            assert(test_decrypt == key_text,
                string.format(
                    "长度为" .. key_info.desc ..
                        "测试失败：预计解密后数据内容为%s,实际返回值为%s", key_text, test_decrypt))
            log.info("xxtea_test", "长度为" .. key_info.desc .. "测试通过")
        end
    end
end

function xxtea_test.test_warn_key()
    local correct_text = "Hello World!"
    local correct_key = "correct_key12345"
    local wrong_key = "wrong_key_67890"
    local test_encrypt_wrong = xxtea.encrypt(correct_text, correct_key)
    local date_tohex, date_tohex_len = test_encrypt_wrong:toHex()

    if test_encrypt_wrong then
        local wrong_decrypt = xxtea.decrypt(test_encrypt_wrong, wrong_key)
        assert(wrong_decrypt == nil,
            string.format(
                "使用错误密钥解密测试失败：预计解密后数据内容为错误内容,实际返回值为%s",
                wrong_decrypt))
        log.info("xxtea_test", "使用错误密钥解密测试通过")
    end
end

function xxtea_test.test_multiple_test()
    local iterations = 10
    local multiple_text = "multipletext123456"
    local multiple_key = "multiplekey"
    for i = 1, iterations do
        local multiple_encrypt = xxtea.encrypt(multiple_text, multiple_key)
        assert(multiple_encrypt ~= nil,
            string.format("多次加密第" .. i .. "测试失败：预计返回值不为nil,实际返回值为%s",
                multiple_encrypt))
        log.info("xxtea_test", "多次加密第" .. i .. "测试通过")
        if multiple_encrypt then
            local multiple_decrypt = xxtea.decrypt(multiple_encrypt, multiple_key)
            assert(#multiple_decrypt == #multiple_text,
                string.format(
                    "多次解密第" .. i .. "测试失败：预计解密后数据长度为%d,实际返回值为%d",
                    #multiple_text, #multiple_decrypt))
            log.info("xxtea_test", "多次解密第" .. i .. "测试通过")

            assert(multiple_decrypt == multiple_text,
                string.format(
                    "多次解密第" .. i .. "测试失败：预计解密后数据内容为%s,实际返回值为%s",
                    multiple_text, multiple_decrypt))
            log.info("xxtea_test", "多次解密第" .. i .. "测试通过")
        end
    end
end

function xxtea_test.test_multiple_key()
    local same_text = "Same text"
    local same_key = "consistency_key"
    local same_encrypt_first = xxtea.encrypt(same_text, same_key)
    local same_encrypt_second = xxtea.encrypt(same_text, same_key)
    assert(same_encrypt_first == same_encrypt_second, string.format("相同数据和密钥多次加密测试失败"))
    log.info("相同数据和密钥多次加密测试通过")
end

function xxtea_test.test_binary()
    local binary_data = ""
    for i = 0, 255 do
        binary_data = binary_data .. string.char(i % 256)
        if #binary_data >= 64 then
            break
        end -- 限制长度为64字节
    end
    local binary_key = "binary_key_123456"
    local binary_encrypt = xxtea.encrypt(binary_data, binary_key)
    assert(binary_encrypt ~= nil,
        string.format("二进制数据加密测试失败：预期不为nil，实际%s", binary_encrypt))
    log.info("二进制数据加密测试通过")
    if binary_encrypt then
        local binary_decrypt = xxtea.decrypt(binary_encrypt, binary_key)
        assert(#binary_decrypt == #binary_data, string.format(
            "二进制数据解密数据长度测试失败：预期为%s，实际%s", #binary_data, #binary_decrypt))
        log.info("二进制数据解密数据长度测试通过")

        assert(binary_decrypt == binary_data, string.format(
            "二进制数据解密数据内容测试失败：预期为%s，实际%s", binary_data, binary_decrypt))
        log.info("二进制数据解密数据内容测试通过")

    end
end




function xxtea_test.test_number_param_encrypt_data()
    -- 测试加密函数传入数字类型的data参数
    local num_data = 12345
    local key = "test_key"
    
    -- 使用pcall捕获可能发生的错误
    local success, encrypt_result = pcall(xxtea.encrypt, num_data, key)
    
    -- 如果pcall执行失败（抛出错误），说明函数不支持数字类型参数
    if not success then
        log.info("xxtea_test", "数字类型data参数加密测试：函数抛出错误，符合预期")
        return
    end
    
    -- 如果pcall成功执行，验证返回值
    assert(encrypt_result ~= nil, 
        string.format("xxtea数字类型data参数加密测试失败：加密函数返回nil"))
    
    log.info("xxtea_test", "数字类型data参数加密测试通过，加密结果不为nil")
    
    -- 验证解密后是否能得到原始数字的字符串形式
    local success_decrypt, decrypt_result = pcall(xxtea.decrypt, encrypt_result, key)
    
    assert(success_decrypt, "xxtea数字类型data参数解密测试失败：解密函数执行出错")
    assert(decrypt_result ~= nil, 
        string.format("xxtea数字类型data参数解密测试失败：解密返回nil"))
    
    -- 预期数字参数会被转换为字符串
    assert(tostring(num_data) == decrypt_result, 
        string.format("xxtea数字类型data参数加密解密测试失败：预期解密结果为'%s'，实际为'%s'", 
            tostring(num_data), tostring(decrypt_result)))
    
    log.info("xxtea_test", "数字类型data参数加密解密测试通过")
end

function xxtea_test.test_number_param_encrypt_key()
    -- 测试加密函数传入数字类型的key参数
    local data = "Hello World!"
    local num_key = 123456
    
    -- 使用pcall捕获可能发生的错误
    local success, encrypt_result = pcall(xxtea.encrypt, data, num_key)
    
    -- 如果pcall执行失败（抛出错误），说明函数不支持数字类型参数
    if not success then
        log.info("xxtea_test", "数字类型key参数加密测试：函数抛出错误，符合预期")
        return
    end
    
    -- 如果pcall成功执行，验证返回值
    assert(encrypt_result ~= nil, 
        string.format("xxtea数字类型key参数加密测试失败：加密函数返回nil"))
    
    log.info("xxtea_test", "数字类型key参数加密测试通过，加密结果不为nil")
    
    -- 验证解密时使用相同的数字key是否能成功解密
    local success_decrypt, decrypt_result = pcall(xxtea.decrypt, encrypt_result, num_key)
    
    assert(success_decrypt, "xxtea数字类型key参数解密测试失败：解密函数执行出错")
    assert(decrypt_result ~= nil, 
        string.format("xxtea数字类型key参数解密测试失败：解密返回nil"))
    assert(data == decrypt_result, 
        string.format("xxtea数字类型key参数加密解密测试失败：预期解密结果为'%s'，实际为'%s'", 
            data, tostring(decrypt_result)))
    
    log.info("xxtea_test", "数字类型key参数加密解密测试通过")
end

function xxtea_test.test_number_param_both()
    -- 测试加密函数同时传入数字类型的data和key参数
    local num_data = 98765
    local num_key = 54321
    
    -- 使用pcall捕获可能发生的错误
    local success, encrypt_result = pcall(xxtea.encrypt, num_data, num_key)
    
    -- 如果pcall执行失败（抛出错误），说明函数不支持数字类型参数
    if not success then
        log.info("xxtea_test", "数字类型双参数加密测试：函数抛出错误，符合预期")
        return
    end
    
    -- 如果pcall成功执行，验证返回值
    assert(encrypt_result ~= nil, 
        string.format("xxtea数字类型双参数加密测试失败：加密函数返回nil"))
    
    log.info("xxtea_test", "数字类型双参数加密测试通过，加密结果不为nil")
    
    -- 验证解密
    local success_decrypt, decrypt_result = pcall(xxtea.decrypt, encrypt_result, num_key)
    
    assert(success_decrypt, "xxtea数字类型双参数解密测试失败：解密函数执行出错")
    assert(decrypt_result ~= nil, 
        string.format("xxtea数字类型双参数解密测试失败：解密返回nil"))
    
    -- 预期数字data参数会被转换为字符串
    assert(tostring(num_data) == decrypt_result, 
        string.format("xxtea数字类型双参数加密解密测试失败：预期解密结果为'%s'，实际为'%s'", 
            tostring(num_data), tostring(decrypt_result)))
    
    log.info("xxtea_test", "数字类型双参数加密解密测试通过")
end

function xxtea_test.test_number_param_edge_cases()
    -- 测试边界情况的数字参数
    
    -- 测试用例：各种数字类型
    local test_cases = {
        {data = 0, key = "test_key", desc = "data为0"},
        {data = -123, key = "test_key", desc = "data为负数"},
        {data = 9999999999, key = "test_key", desc = "data为大整数"},
        {data = 3.14159, key = "test_key", desc = "data为浮点数"},
        {data = "Hello", key = 0, desc = "key为0"},
        {data = "Hello", key = -456, desc = "key为负数"},
        {data = "Hello", key = 1.2345, desc = "key为浮点数"},
    }
    
    for _, tc in ipairs(test_cases) do
        log.info("xxtea_test", string.format("测试边界情况：%s", tc.desc))
        
        local success, encrypt_result = pcall(xxtea.encrypt, tc.data, tc.key)
        
        -- 如果抛出错误，记录并继续下一个测试
        if not success then
            log.info("xxtea_test", string.format("边界情况'%s'：函数抛出错误", tc.desc))
            goto continue
        end
        
        -- 验证加密结果
        assert(encrypt_result ~= nil, 
            string.format("边界情况'%s'加密测试失败：返回nil", tc.desc))
        
        -- 验证解密
        local success_decrypt, decrypt_result = pcall(xxtea.decrypt, encrypt_result, tc.key)
        
        assert(success_decrypt, string.format("边界情况'%s'解密执行失败", tc.desc))
        assert(decrypt_result ~= nil, 
            string.format("边界情况'%s'解密测试失败：返回nil", tc.desc))
        
        -- 验证解密结果与原始数据的字符串形式一致
        local expected = type(tc.data) == "string" and tc.data or tostring(tc.data)
        assert(expected == decrypt_result, 
            string.format("边界情况'%s'加密解密验证失败：预期'%s'，实际'%s'", 
                tc.desc, expected, tostring(decrypt_result)))
        
        log.info("xxtea_test", string.format("边界情况'%s'测试通过", tc.desc))
        
        ::continue::
    end
end

function xxtea_test.test_number_param_nil_handling()
    -- 测试nil值处理（虽然这不是数字类型，但作为边界情况测试）
    local data = "test data"
    local key = "test key"
    
    -- 测试data为nil
    local success1, result1 = pcall(xxtea.encrypt, nil, key)
    if success1 then
        assert(result1 == nil, "传入nil data时预期返回nil")
        log.info("xxtea_test", "nil data参数测试通过")
    else
        log.info("xxtea_test", "nil data参数导致函数抛出错误")
    end
    
    -- 测试key为nil
    local success2, result2 = pcall(xxtea.encrypt, data, nil)
    if success2 then
        assert(result2 == nil, "传入nil key时预期返回nil")
        log.info("xxtea_test", "nil key参数测试通过")
    else
        log.info("xxtea_test", "nil key参数导致函数抛出错误")
    end
end

return xxtea_test
