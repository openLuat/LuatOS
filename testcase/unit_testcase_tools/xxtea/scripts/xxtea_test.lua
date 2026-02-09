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

return xxtea_test
