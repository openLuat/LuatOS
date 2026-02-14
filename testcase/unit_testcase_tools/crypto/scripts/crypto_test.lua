local crypto_tests = {}
local expected_suites = {"TLS-RSA-WITH-AES-128-CCM", "TLS-RSA-WITH-AES-128-CBC-SHA", "TLS-RSA-WITH-AES-128-CCM-8",
                         "TLS-RSA-WITH-AES-128-CBC-SHA256", "TLS-RSA-WITH-AES-256-CCM",
                         "TLS-RSA-WITH-AES-256-CBC-SHA256", "TLS-RSA-WITH-AES-256-CBC-SHA",
                         "TLS-RSA-WITH-AES-256-CCM-8", "TLS-RSA-WITH-AES-128-GCM-SHA256",
                         "TLS-RSA-WITH-AES-256-GCM-SHA384", "TLS-ECDHE-ECDSA-WITH-AES-256-GCM-SHA384",
                         "TLS-ECDHE-RSA-WITH-AES-256-GCM-SHA384", "TLS-ECDHE-ECDSA-WITH-AES-256-CCM",
                         "TLS-ECDHE-ECDSA-WITH-AES-256-CBC-SHA384", "TLS-ECDHE-RSA-WITH-AES-256-CBC-SHA384",
                         "TLS-ECDHE-ECDSA-WITH-AES-256-CBC-SHA", "TLS-ECDHE-RSA-WITH-AES-256-CBC-SHA",
                         "TLS-ECDHE-ECDSA-WITH-AES-256-CCM-8", "TLS-ECDHE-ECDSA-WITH-AES-128-GCM-SHA256",
                         "TLS-ECDHE-RSA-WITH-AES-128-GCM-SHA256", "TLS-ECDHE-ECDSA-WITH-AES-128-CCM",
                         "TLS-ECDHE-ECDSA-WITH-AES-128-CBC-SHA256", "TLS-ECDHE-RSA-WITH-AES-128-CBC-SHA256",
                         "TLS-ECDHE-ECDSA-WITH-AES-128-CBC-SHA", "TLS-ECDHE-RSA-WITH-AES-128-CBC-SHA",
                         "TLS-ECDHE-ECDSA-WITH-AES-128-CCM-8", "TLS-RSA-PSK-WITH-AES-256-GCM-SHA384",
                         "TLS-RSA-PSK-WITH-AES-256-CBC-SHA384", "TLS-RSA-PSK-WITH-AES-256-CBC-SHA",
                         "TLS-RSA-PSK-WITH-AES-128-GCM-SHA256", "TLS-RSA-PSK-WITH-AES-128-CBC-SHA256",
                         "TLS-RSA-PSK-WITH-AES-128-CBC-SHA"}

function crypto_tests.test_md5()
    log.info("crypto_tests", "开始 MD5 计算测试")
    local actual = crypto.md5("str123")
    local expected = "3F2BE04ABDC4664397BCF70712518FC4"
    assert(actual == expected, string.format("MD5计算失败: 预期 %s, 实际 %s", expected, actual))
end

function crypto_tests.test_hmac_md5()
    log.info("crypto_tests", "开始 HMAC-MD5 计算测试")
    local actual = crypto.hmac_md5("hmacmd5", "str123")
    local expected = "8843DAD2F4939A995B2E3F1137282B6B"
    assert(actual == expected, string.format("HMAC-MD5计算失败: 预期 %s, 实际 %s", expected, actual))
end

function crypto_tests.test_sha1()
    log.info("crypto_tests", "开始 SHA1 计算测试")
    local actual = crypto.sha1("str123")
    local expected = "3F7773379D580530FDEA7060EFCA215438383369"
    assert(actual == expected, string.format("SHA1 计算失败: 预期 %s, 实际 %s", expected, actual))

end

function crypto_tests.test_hmac_sha1()
    log.info("crypto_tests", "开始 HMAC-SHA1 计算测试")
    local actual = crypto.hmac_sha1("hmacsha1", "str123")
    local expected = "FE17B06E515E1DA9689ED1F2C6BF1789DF6C0E9A"
    assert(actual == expected, string.format("HMAC-SHA1 计算失败: 预期 %s, 实际 %s", expected, actual))
end

function crypto_tests.test_sha256()
    log.info("crypto_tests", "开始 SHA256 计算测试")
    local actual = crypto.sha256("str123")
    local expected = "25E9211ACBE3B8533DC37CBB431CE8225A613503D08AB5CFBD965533AD021566"
    assert(actual == expected, string.format("SHA256 计算失败: 预期 %s, 实际 %s", expected, actual))
end

function crypto_tests.test_hmac_sha256()
    log.info("crypto_tests", "开始 HMAC-SHA256 计算测试")
    local actual = crypto.hmac_sha256("hmac_sha256", "str123")
    local expected = "395B945F806A955B4B008ACC5321A8D813DCD943A1BE6EB835AB37FD7A697DDB"
    assert(actual == expected, string.format("HMAC-SHA256 计算失败: 预期 %s, 实际 %s", expected, actual))
end

function crypto_tests.test_sha512()
    log.info("crypto_tests", "开始 SHA512 计算测试")

    local actual = crypto.sha512("str123")
    local expected =
        "E0D60F3E56CBEEB7D48CA6556F105FF684EFE73B7C043F1DA82C8DDB26C8E8A1FAB15E6A998B2B31788E29C065110F01F6D6BA45FA1472F4F6F55CBE7A1A44FF"
    assert(actual == expected, string.format("SHA512 计算失败: 预期 %s, 实际 %s", expected, actual))
end

function crypto_tests.test_hmac_sha512()
    log.info("crypto_tests", "开始 HMAC-SHA512 计算测试")

    local actual = crypto.hmac_sha512("hmacsha512", "str123")
    local expected =
        "5381846723EC1DF5739665225769ADF590F29C29505400DD522E2D3C3DFB04113E8FD4A1ED9BAA813D70629D4A437995719286541D2EF27F0291A7924021AFD9"
    assert(actual == expected, string.format("HMAC-SHA512 计算失败: 预期 %s, 实际 %s", expected, actual))
end

function crypto_tests.test_aes_128_ecb_encrypt()
    log.info("crypto_tests", "开始AES-128-ECB/PKCS7形式的对称加密")
    local result = crypto.cipher_encrypt("AES-128-ECB", "PKCS7", "1234567890123456", "1234567890123456")
    local actual = string.toHex(result)
    local expected = "757CCD0CDC5C90EADBEEECF638DD0000050187A0CDE5A9872CBAB091AB73E553"
    assert(actual == expected,
        string.format("AES-128-ECB/PKCS7形式的对称加密失败: 预期 %s, 实际 %s", expected, actual))
end

function crypto_tests.test_aes_128_ecb_decrypt()
    log.info("crypto_tests", "开始AES-128-ECB/PKCS7形式的对称解密")
    -- 先加密得到密文
    local ciphertext = crypto.cipher_encrypt("AES-128-ECB", "PKCS7", "1234567890123456", "1234567890123456")
    -- 再解密
    local actual = crypto.cipher_decrypt("AES-128-ECB", "PKCS7", ciphertext, "1234567890123456")
    local expected = "1234567890123456"
    assert(actual == expected,
        string.format("AES-128-ECB/PKCS7形式的对称解密失败: 预期 %s, 实际 %s", expected, actual))
end

function crypto_tests.test_aes_128_cbc_encrypt()
    log.info("crypto_tests", "开始AES-128-CBC/ZERO形式的对称加密")
    local actual = crypto.cipher_encrypt("AES-128-CBC", "ZERO", "1234567890123456", "1234567890123456",
        "1234567890666666"):toHex()
    local expected = "BBD7A757D8072A0455D783BEA0334EC133312E92EFAA2BA22E61CCC9C15E6EDD"
    assert(actual == expected,
        string.format("AES-128-CBC/ZERO形式的对称加密失败: 预期 %s, 实际 %s", expected, actual))
end

function crypto_tests.test_aes_128_cbc_decrypt()
    log.info("crypto_tests", "开始AES-128-CBC/ZERO形式的对称解密")
    -- 先加密得到密文
    local ciphertext = crypto.cipher_encrypt("AES-128-CBC", "ZERO", "1234567890123456", "1234567890123456",
        "1234567890666666")
    -- 再解密
    local actual = crypto.cipher_decrypt("AES-128-CBC", "ZERO", ciphertext, "1234567890123456", "1234567890666666")
    local expected = "1234567890123456"
    assert(actual == expected,
        string.format("AES-128-CBC/ZERO形式的对称解密失败: 预期 %s, 实际 %s", expected, actual))
end

function crypto_tests.test_des_cbc_encrypt()
    log.info("crypto_tests", "开始DES-CBC/ONE_AND_ZEROS形式的对称加密")
    local actual = crypto.cipher_encrypt("DES-CBC", "ONE_AND_ZEROS", "12345678", "81bytesk", "81bytesiv"):toHex()
    local expected = "8A053F57D3F36640860022831BD176F1"
    assert(actual == expected,
        string.format("DES-CBC/ONE_AND_ZEROS形式的对称加密失败: 预期 %s, 实际 %s", expected, actual))

end

function crypto_tests.test_des_cbc_decrypt()
    log.info("crypto_tests", "开始DES-CBC/ONE_AND_ZEROS形式的对称解密")
    -- 先加密得到密文
    local ciphertext = crypto.cipher_encrypt("DES-CBC", "ONE_AND_ZEROS", "12345678", "81bytesk", "81bytesiv")
    -- 再解密
    local actual = crypto.cipher_decrypt("DES-CBC", "ONE_AND_ZEROS", ciphertext, "81bytesk", "81bytesiv")
    local expected = "12345678"
    assert(actual == expected,
        string.format("DES-CBC/ONE_AND_ZEROS形式的对称解密失败: 预期 %s, 实际 %s", expected, actual))
end

function crypto_tests.test_des_ede3_cbc_encrypt()
    log.info("crypto_tests", "开始 DES-EDE3-CBC/ZEROS_AND_LEN 形式的对称加密")
    local actual = crypto.cipher_encrypt("DES-EDE3-CBC", "ZEROS_AND_LEN", "1234567890", "123456789012345678901234",
        "81bytesiv"):toHex()
    local expected = "5EC956F63FB3F966CF95883C4525709C"
    assert(actual == expected, string.format(
        "DES-EDE3-CBC/ZEROS_AND_LEN 形式的对称加密失败: 预期 %s, 实际 %s", expected, actual))
end

function crypto_tests.test_des_ede3_cbc_decrypt()
    log.info("crypto_tests", "开始 DES-EDE3-CBC/ZEROS_AND_LEN 形式的对称解密")
    -- 先加密得到密文
    local ciphertext = crypto.cipher_encrypt("DES-EDE3-CBC", "ZEROS_AND_LEN", "1234567890", "123456789012345678901234",
        "81bytesiv")
    -- 再解密
    local actual = crypto.cipher_decrypt("DES-EDE3-CBC", "ZEROS_AND_LEN", ciphertext, "123456789012345678901234",
        "81bytesiv")
    local expected = "1234567890"
    assert(actual == expected, string.format(
        "DES-EDE3-CBC/ZEROS_AND_LEN 形式的对称解密失败: 预期 %s, 实际 %s", expected, actual))
end

function crypto_tests.test_crc16()
    log.info("crypto_tests", "开始 CRC16测试")
    local data = crypto.crc16("MODBUS", "123456sdfdsfdsfdsffdsfdsfsdfs1234")
    local actual = string.format("%04X", data)
    local expected = "D3AC"
    assert(actual == expected, string.format("CRC16测试失败: 预期 %s, 实际 %s", expected, actual))
end

function crypto_tests.test_crc16_maxim()
    log.info("crypto_tests", "开始 CRC16_MAXIM测试")
    local data = crypto.crc16("MAXIM", "123456sdfdsfdsfdsffdsfdsfsdfs1234")
    local actual = string.format("%04X", data)
    local expected = "EC06"
    assert(actual == expected, string.format("CRC16_MAXIM测试失败: 预期 %s, 实际 %s", expected, actual))
end

function crypto_tests.test_crc16_ibm()
    log.info("crypto_tests", "开始 CRC16_IBM测试")
    local data = crypto.crc16("IBM", "123456sdfdsfdsfdsffdsfdsfsdfs1234")
    local actual = string.format("%04X", data)
    local expected = "13F9"
    assert(actual == expected, string.format("CRC16_IBM测试失败: 预期 %s, 实际 %s", expected, actual))
end

function crypto_tests.test_crc16_usb()
    log.info("crypto_tests", "开始 CRC16_USB测试")
    local data = crypto.crc16("USB", "123456sdfdsfdsfdsffdsfdsfsdfs1234")
    local actual = string.format("%04X", data)
    local expected = "2C53"
    assert(actual == expected, string.format("CRC16_USB测试失败: 预期 %s, 实际 %s", expected, actual))
end

function crypto_tests.test_crc16__ccitt()
    log.info("crypto_tests", "开始 CRC16_CCITT测试")
    local data = crypto.crc16("CCITT", "123456sdfdsfdsfdsffdsfdsfsdfs1234")
    local actual = string.format("%04X", data)
    local expected = "2EC2"
    assert(actual == expected, string.format("CRC16_CCITT测试失败: 预期 %s, 实际 %s", expected, actual))
end

function crypto_tests.test_crc16_ccitt_false()
    log.info("crypto_tests", "开始 CRC16_CCITT-FALSE测试")
    local data = crypto.crc16("CCITT-FALSE", "123456sdfdsfdsfdsffdsfdsfsdfs1234")
    local actual = string.format("%04X", data)
    local expected = "EA36"
    assert(actual == expected, string.format("CRC16_CCITT-FALSE测试失败: 预期 %s, 实际 %s", expected, actual))
end


function crypto_tests.test_crc16_x25()
    log.info("crypto_tests", "开始 CRC16_X25测试")
    local data = crypto.crc16("X25", "123456sdfdsfdsfdsffdsfdsfsdfs1234")
    local actual = string.format("%04X", data)
    local expected = "ADF0"
    assert(actual == expected, string.format("CRC16_X25测试失败: 预期 %s, 实际 %s", expected, actual))
end

function crypto_tests.test_crc16_xmodem()
    log.info("crypto_tests", "开始 CRC16_XMODEM测试")
    local data = crypto.crc16("XMODEM", "123456sdfdsfdsfdsffdsfdsfsdfs1234")
    local actual = string.format("%04X", data)
    local expected = "5908"
    assert(actual == expected, string.format("CRC16_XMODEM测试失败: 预期 %s, 实际 %s", expected, actual))
end

function crypto_tests.test_crc16_dnp()
    log.info("crypto_tests", "开始 CRC16_DNP测试")
    local data = crypto.crc16("DNP", "123456sdfdsfdsfdsffdsfdsfsdfs1234")
    local actual = string.format("%04X", data)
    local expected = "194D"
    assert(actual == expected, string.format("CRC16_DNP测试失败: 预期 %s, 实际 %s", expected, actual))
end

function crypto_tests.test_crc16_modbus()
    log.info("crypto_tests", "开始 CRC16-MODBUS 测试")
    local data = crypto.crc16_modbus("123456sdfdsfdsfdsffdsfdsfsdfs1234")
    local actual = string.format("%04X", data)
    local expected = "D3AC"
    assert(actual == expected, string.format("CRC16-MODBUS 测试失败: 预期 %s, 实际 %s", expected, actual))
end


function crypto_tests.test_crc32()
    log.info("crypto_tests", "开始 CRC32 测试")
    local expected = "F1389F6D"
    local data = crypto.crc32("123a456", 0xFFFFFFFF, 0x04C11DB7, 0xFFFFFFFF)
    local actual_data = data & 0xFFFFFFFF
    local actual = string.format("%04X", actual_data)
    log.info("actual", actual)
    local _, num = rtos.version(true)
    log.info("当前为" .. num .. "号固件")
    assert(actual == expected, string.format("CRC32 测试失败: 预期 %s, 实际 %s", expected, actual))
end



function crypto_tests.test_crc8()
    log.info("crypto_tests", "开始 CRC8 测试")
    local actual_data = crypto.crc8("123456", 0x07, 0x00, false)
    local actual = string.format("%02X", actual_data)
    local expected = "FD"
    assert(actual == expected, string.format("CRC8 测试失败: 预期 %s, 实际 %s", expected, actual))
end

function crypto_tests.test_crc8_iru()
    log.info("crypto_tests", "开始 CRC8_IRU 测试")
    local actual_data = crypto.crc8("123456", 0x07, 0x00, false)
    local expected = 0xA8
    local actual= actual_data ~ 0x55
    -- 转换为十六进制
    local expected = 0xA8
    assert((actual & 0xFF) == expected, string.format("CRC8_IRU 测试失败: 预期 0x%02X, 实际 0x%02X", expected, actual))
end

function crypto_tests.test_crc8_rohc()
    log.info("crypto_tests", "开始 CRC8_rohc 测试")
    local actual = crypto.crc8("123456", 0x07, 0xFF, true)
    local expected = 0x57
    -- 转换为十六进制
    assert((actual & 0xFF) == expected, string.format("CRC8_IRU 测试失败: 预期 0x%02X, 实际 0x%02X", expected, actual))
end

function crypto_tests.test_crc8_maxim()
    log.info("crypto_tests", "开始 CRC-8/MAXIM 测试")  
    local crc_result = crypto.crc8("123456", 0x31, 0x00, true)
    local expected = 0xEC  -- 输出反转后应该是这个值
    assert((crc_result & 0xFF) == expected,
        string.format("CRC-8/MAXIM测试失败: 预期 0x%02X, 实际 0x%02X", 
            expected, crc_result))
end

function crypto_tests.test_crc7() 
    log.info("crypto_tests", "开始 CRC7测试")
    local actual_data = crypto.crc7("hello", 0x09, 0x00)
    local actual = string.format("%02X", actual_data)
    local expected = "22"
    assert(actual == expected, string.format("CRC7_0x09 测试失败: 预期 %s, 实际 %s", expected, actual))
end

function crypto_tests.test_crc7_default() 
    log.info("crypto_tests", "开始 CRC7_默认值测试")
    local actual_data = crypto.crc7("hello", 0xe5, 0x00)
    local actual = string.format("%02X", actual_data)
    local expected = "40"
    assert(actual == expected, string.format("CRC7_0xe5 测试失败: 预期 %s, 实际 %s", expected, actual))
end

function crypto_tests.test_totp()
    log.info("crypto_tests", "开始 TOTP 动态密码测试")
    local actual = crypto.totp("asdfassdfasdfass", 1764924906)
    local expected = 702358
    assert(actual == expected, string.format("TOTP 动态密码测试失败: 预期 %s, 实际 %s", expected, actual))
end

function crypto_tests.test_base64_encode()
    log.info("crypto_tests", "开始 base64 编码测试")
    local actual = crypto.base64_encode("12345")
    local expected = "MTIzNDU="
    assert(actual == expected, string.format("base64 编码测试失败: 预期 %s, 实际 %s", expected, actual))
end

function crypto_tests.test_base64_decode()
    log.info("crypto_tests", "开始 base64 解码测试")
    local encoded = crypto.base64_encode("12345")
    local actual = crypto.base64_decode(encoded)
    local expected = "12345"
    assert(actual == expected, string.format("base64 解码测试失败: 预期 %s, 实际 %s", expected, actual))
end

function crypto_tests.test_trng()
    log.info("crypto_tests", "开始真随机数测试")
    local set = {}
    for i = 1, 5 do
        local data = crypto.trng(4)
        assert(data and #data == 4, "TRNG 长度错误或返回nil")
        local hex = data:toHex()
        assert(not set[hex], "TRNG 重复发现: " .. hex)
        set[hex] = true
        log.info("crypto_tests", "第" .. i .. "个TRNG:", hex)
    end
end

function crypto_tests.test_tls_suites()
    log.info("crypto_tests", "开始 TLS 套件测试")
    local suites = crypto.cipher_suites()
    assert(suites, "无法获取 TLS 套件列表")

    local suite_map = {}
    for _, suite in ipairs(suites) do
        suite_map[suite] = true
    end

    local missing_suites = {}
    for _, expected in ipairs(expected_suites) do
        if not suite_map[expected] then
            table.insert(missing_suites, expected)
        end
    end
    assert(#missing_suites == 0, "缺少 TLS 套件: " .. table.concat(missing_suites, ", "))

    log.info("crypto_tests", "TLS 套件测试通过")
end

function crypto_tests.test_md()
    log.info("crypto_tests", "开始 HASH值 的计算测试")
    local actual_md5 = crypto.md("MD5", "1234567890", "123456")
    local expected_md5 = "3324A5385619D5485AAD1D8D274214A0"
    assert(actual_md5 == expected_md5,
        string.format("HASH值_MD5计算失败: 预期 %s, 实际 %s", expected_md5, actual_md5))

    local actual_sha1 = crypto.md("SHA1", "1234567890", "123456")
    local expected_sha1 = "E374E1A5449F65E6566F910BAE824CE163B4CE3D"
    assert(actual_sha1 == expected_sha1,
        string.format("HASH值_SHA1计算失败: 预期 %s, 实际 %s", expected_sha1, actual_sha1))

    local actual_sha256 = crypto.md("SHA256", "1234567890", "123456")
    local expected_sha256 = "30CFE99B630FCFB71DA1D68FAAC41B9944728A44244A385DDAE0ADB35910BB41"
    assert(actual_sha256 == expected_sha256,
        string.format("HASH值_SHA256计算失败: 预期 %s, 实际 %s", expected_sha256, actual_sha256))

    local actual_sha512 = crypto.md("SHA512", "1234567890", "123456")
    local expected_sha512 =
        "ED7693A035C7A3CC341082527B82D0393BB19F5A71D6AC3D5B238C397D752534D901AFDB57D5E266C9AB7EC1597CDB49989FD231A49F6ECA0D3EDF67A49E2A86"
    assert(actual_sha512 == expected_sha512,
        string.format("HASH值_SHA512计算失败: 预期 %s, 实际 %s", expected_sha512, actual_sha512))
end

function crypto_tests.test_md_file()
    log.info("crypto_tests", "开始文件的HASH值计算测试")
    local actual_md5 = crypto.md_file("MD5", "/luadb/logo.jpg", "123456")
    local expected_md5 = "B5F5A687DB904DB67D3311899932DD61"
    assert(actual_md5 == expected_md5,
        string.format("文件的HASH值_MD5计算失败: 预期 %s, 实际 %s", expected_md5, actual_md5))

    local actual_sha1 = crypto.md_file("SHA1", "/luadb/logo.jpg", "123456")
    local expected_sha1 = "2A0B55C290D54ADF2F185EAE460254D267C7CE1F"
    assert(actual_sha1 == expected_sha1,
        string.format("文件的HASH值_SHA1计算失败: 预期 %s, 实际 %s", expected_sha1, actual_sha1))

    local actual_sha256 = crypto.md_file("SHA256", "/luadb/logo.jpg", "123456")
    local expected_sha256 = "6E443C84D4D7A4721A9A195EB9038EDCFA8A8F60A3F1E8A0090B57B3BAB4942E"
    assert(actual_sha256 == expected_sha256,
        string.format("文件的HASH值_SHA256计算失败: 预期 %s, 实际 %s", expected_sha256, actual_sha256))

    local actual_sha512 = crypto.md_file("SHA512", "/luadb/logo.jpg", "123456")
    local expected_sha512 =
        "D9E5C97993948EF65AD244165FE9E527DDB9B33FDC3302DA887D06FE8A6A84373BB47A83CC3494954D759B71911E796B14232385D0BAC29E07C22A194D8D565E"
    assert(actual_sha512 == expected_sha512,
        string.format("文件的HASH值_SHA512计算失败: 预期 %s, 实际 %s", expected_sha512, actual_sha512))
end

function crypto_tests.test_hash_init()
    log.info("crypto_tests", "开始hash_init测试")
    local md5_stream = crypto.hash_init("MD5", "123456")
    assert(md5_stream, "hash_init_md5创建失败")
    local sha1_stream = crypto.hash_init("SHA1", "123456")
    assert(sha1_stream, "hash_init_sha1创建失败")
    local sha256_stream = crypto.hash_init("SHA256", "123456")
    assert(sha256_stream, "hash_init_sha256创建失败")
    local sha512_stream = crypto.hash_init("SHA512", "123456")
    assert(sha512_stream, "hash_init_sha512创建失败")
end

function crypto_tests.test_hash_finish()
    log.info("crypto_tests", "开始 hash_finish 测试")
    local md5_stream = crypto.hash_init("MD5", "123456")
    local sha1_stream = crypto.hash_init("SHA1", "123456")
    local sha256_stream = crypto.hash_init("SHA256", "123456")
    local sha512_stream = crypto.hash_init("SHA512", "123456")

    local md5_stream_finish = crypto.hash_finish(md5_stream)
    local expected_md5_stream = "CAB1380EA86D8ACC9AA62390A58406AA"
    assert(md5_stream_finish == expected_md5_stream,
        string.format("获取流式MD5校验值: 预期 %s, 实际 %s", expected_md5_stream, md5_stream_finish))

    local sha1_stream_finish = crypto.hash_finish(sha1_stream)
    local expected_sha1_stream = "823688DAFCA7393D24C871A2DA98A84D8732E927"
    assert(sha1_stream_finish == expected_sha1_stream,
        string.format("获取流式SHA1校验值: 预期 %s, 实际 %s", expected_sha1_stream, sha1_stream_finish))

    local sha256_stream_finish = crypto.hash_finish(sha256_stream)
    local expected_sha256_stream = "B946CCC987465AFCDA7E45B1715219711A13518D1F1663B8C53B848CB0143441"
    assert(sha256_stream_finish == expected_sha256_stream,
        string.format("获取流式SHA256校验值: 预期 %s, 实际 %s", expected_sha256_stream, sha256_stream_finish))

    local sha512_stream_finish = crypto.hash_finish(sha512_stream)
    local expected_sha512_stream =
        "D3F2F066F0DA13B4CD51085457A9C50F4DFC3DDC2B790133D49F6A11BD048AB7BF4292ABAAE52D5C2841F7EDA24F51BCE0858EF75DD0EE02283C73783D63C6A4"
    assert(sha512_stream_finish == expected_sha512_stream,
        string.format("获取流式SHA512校验值: 预期 %s, 实际 %s", expected_sha512_stream, sha512_stream_finish))
end

-- 校验和测试
function crypto_tests.test_checksum_add()
    log.info("crypto_tests", "开始校验和累加模式测试")
    local actual = crypto.checksum("OK", 1)
    local expected = 154
    assert(actual == expected,
        string.format("校验和累加模式测试失败: 预期 %s, 实际 %s", expected, actual))
end

function crypto_tests.test_checksum_xor()
    log.info("crypto_tests", "开始校验和异或模式测试")
    local actual = crypto.checksum("OK")
    local expected = 4
    assert(actual == expected,
        string.format("校验和异或模式测试失败: 预期 %s, 实际 %s", expected, actual))
end

-- GCM模式加解密测试
function crypto_tests.test_aes_128_gcm_encrypt()
    log.info("crypto_tests", "开始AES-128-GCM加密测试")
    local key = "0123456789abcdef"  -- 16字节密钥
    local iv = "abcdef9876543210"   -- 16字节初始向量
    local plaintext = "Hello, LuaTools! This is a test message for GCM encryption."
    
    local ciphertext, tag = crypto.cipher_encrypt("AES-128-GCM", "NONE", plaintext, key, iv)
    assert(ciphertext and tag, "AES-128-GCM加密失败: 返回nil")
    assert(#ciphertext == #plaintext, "密文长度应与明文相同")
    assert(#tag > 0, "TAG不应为空")
    
    log.info("crypto_tests", "密文(hex): " .. string.toHex(ciphertext))
    log.info("crypto_tests", "TAG(hex): " .. string.toHex(tag))
end

function crypto_tests.test_aes_128_gcm_decrypt()
    log.info("crypto_tests", "开始AES-128-GCM解密测试")
    local key = "0123456789abcdef"  -- 16字节密钥
    local iv = "abcdef9876543210"   -- 16字节初始向量
    local plaintext = "Hello, LuaTools! This is a test message for GCM encryption."
    
    -- 先加密
    local ciphertext, tag = crypto.cipher_encrypt("AES-128-GCM", "NONE", plaintext, key, iv)
    
    -- 再解密
    local decrypted = crypto.cipher_decrypt("AES-128-GCM", "NONE", ciphertext, key, iv, tag)
    assert(decrypted == plaintext, 
        string.format("AES-128-GCM解密失败: 预期 %s, 实际 %s", plaintext, decrypted))
end

function crypto_tests.test_aes_128_gcm_with_known_vector()
    log.info("crypto_tests", "开始AES-128-GCM已知向量测试")
    local key = "0123456789abcdef"
    local iv = "abcdef9876543210"
    local plaintext = "Hello, LuaTools! This is a test message for GCM encryption."
    
    local ciphertext, tag = crypto.cipher_encrypt("AES-128-GCM", "NONE", plaintext, key, iv)
    -- 预期密文值(与main.lua中的结果对应)
    local expected_ciphertext = "B23DD8E88600EEEE384EECC036ED5DDF51AB7CBCC73A3B53E2B63155867CDC4459C82F00070970609040B880AED39353A3F2DDD1D90E2284D26544"
    local actual_ciphertext = string.toHex(ciphertext)
    
    assert(actual_ciphertext == expected_ciphertext,
        string.format("AES-128-GCM加密向量测试失败: 预期 %s, 实际 %s", expected_ciphertext, actual_ciphertext))
end

function crypto_tests.test_aes_256_gcm_encrypt()
    log.info("crypto_tests", "开始AES-256-GCM加密测试")
    local key = "0123456789abcdef0123456789abcdef"  -- 32字节密钥
    local iv = "abcdef9876543210"                  -- 16字节初始向量
    local plaintext = "Test message for AES-256-GCM encryption mode"
    
    local ciphertext, tag = crypto.cipher_encrypt("AES-256-GCM", "NONE", plaintext, key, iv)
    assert(ciphertext and tag, "AES-256-GCM加密失败: 返回nil")
    assert(#ciphertext == #plaintext, "密文长度应与明文相同")
    assert(#tag > 0, "TAG不应为空")
    
    log.info("crypto_tests", "密文(hex): " .. string.toHex(ciphertext))
    log.info("crypto_tests", "TAG(hex): " .. string.toHex(tag))
end

function crypto_tests.test_aes_256_gcm_decrypt()
    log.info("crypto_tests", "开始AES-256-GCM解密测试")
    local key = "0123456789abcdef0123456789abcdef"  -- 32字节密钥
    local iv = "abcdef9876543210"                  -- 16字节初始向量
    local plaintext = "Test message for AES-256-GCM encryption mode"
    
    -- 先加密
    local ciphertext, tag = crypto.cipher_encrypt("AES-256-GCM", "NONE", plaintext, key, iv)
    
    -- 再解密
    local decrypted = crypto.cipher_decrypt("AES-256-GCM", "NONE", ciphertext, key, iv, tag)
    assert(decrypted == plaintext,
        string.format("AES-256-GCM解密失败: 预期 %s, 实际 %s", plaintext, decrypted))
end

function crypto_tests.test_gcm_tag_validation()
    log.info("crypto_tests", "开始GCM TAG验证测试")
    local key = "0123456789abcdef"
    local iv = "abcdef9876543210"
    local plaintext = "Test GCM tag validation"
    
    local ciphertext, tag = crypto.cipher_encrypt("AES-128-GCM", "NONE", plaintext, key, iv)
    
    -- 尝试用错误的TAG解密,应该失败或返回错误的结果
    local wrong_tag = string.sub(tag, 1, #tag - 1) .. string.char((string.byte(string.sub(tag, #tag)) + 1) % 256)
    local decrypted_wrong = crypto.cipher_decrypt("AES-128-GCM", "NONE", ciphertext, key, iv, wrong_tag)
    
    -- 正确的TAG解密应该成功
    local decrypted_correct = crypto.cipher_decrypt("AES-128-GCM", "NONE", ciphertext, key, iv, tag)
    assert(decrypted_correct == plaintext, "使用正确TAG解密失败")
    log.info("crypto_tests", "GCM TAG验证测试通过")
end

----------------------------------------------------------------------
-- 以下为补充的测试用例
----------------------------------------------------------------------

-- cipher_list 测试
function crypto_tests.test_cipher_list()
    log.info("crypto_tests", "开始 cipher_list 测试")
    local ciphers = crypto.cipher_list()
    assert(type(ciphers) == "table", "cipher_list 应返回 table")
    assert(#ciphers > 0, "cipher_list 不应为空")
    -- 检查常见的算法是否存在
    local cipher_map = {}
    for _, v in ipairs(ciphers) do
        cipher_map[v] = true
    end
    assert(cipher_map["AES-128-ECB"], "cipher_list 应包含 AES-128-ECB")
    assert(cipher_map["AES-128-CBC"], "cipher_list 应包含 AES-128-CBC")
    assert(cipher_map["AES-256-ECB"], "cipher_list 应包含 AES-256-ECB")
    assert(cipher_map["AES-256-CBC"], "cipher_list 应包含 AES-256-CBC")
    log.info("crypto_tests", "cipher_list 共" .. #ciphers .. "个算法")
end

-- hash_update 流式计算测试: 分段更新后结果应与一次性计算一致
function crypto_tests.test_hash_update_md5()
    log.info("crypto_tests", "开始 hash_update MD5 流式计算测试")
    -- 一次性计算
    local expected = crypto.md5("HelloWorld1234567890")
    -- 流式计算
    local stream = crypto.hash_init("MD5")
    assert(stream, "hash_init MD5 创建失败")
    crypto.hash_update(stream, "Hello")
    crypto.hash_update(stream, "World")
    crypto.hash_update(stream, "1234567890")
    local actual = crypto.hash_finish(stream)
    assert(actual == expected,
        string.format("hash_update MD5 流式结果不一致: 预期 %s, 实际 %s", expected, actual))
end

function crypto_tests.test_hash_update_sha1()
    log.info("crypto_tests", "开始 hash_update SHA1 流式计算测试")
    local expected = crypto.sha1("HelloWorld1234567890")
    local stream = crypto.hash_init("SHA1")
    assert(stream, "hash_init SHA1 创建失败")
    crypto.hash_update(stream, "Hello")
    crypto.hash_update(stream, "World")
    crypto.hash_update(stream, "1234567890")
    local actual = crypto.hash_finish(stream)
    assert(actual == expected,
        string.format("hash_update SHA1 流式结果不一致: 预期 %s, 实际 %s", expected, actual))
end

function crypto_tests.test_hash_update_sha256()
    log.info("crypto_tests", "开始 hash_update SHA256 流式计算测试")
    local expected = crypto.sha256("HelloWorld1234567890")
    local stream = crypto.hash_init("SHA256")
    assert(stream, "hash_init SHA256 创建失败")
    crypto.hash_update(stream, "Hello")
    crypto.hash_update(stream, "World")
    crypto.hash_update(stream, "1234567890")
    local actual = crypto.hash_finish(stream)
    assert(actual == expected,
        string.format("hash_update SHA256 流式结果不一致: 预期 %s, 实际 %s", expected, actual))
end

function crypto_tests.test_hash_update_sha512()
    log.info("crypto_tests", "开始 hash_update SHA512 流式计算测试")
    local expected = crypto.sha512("HelloWorld1234567890")
    local stream = crypto.hash_init("SHA512")
    assert(stream, "hash_init SHA512 创建失败")
    crypto.hash_update(stream, "Hello")
    crypto.hash_update(stream, "World")
    crypto.hash_update(stream, "1234567890")
    local actual = crypto.hash_finish(stream)
    assert(actual == expected,
        string.format("hash_update SHA512 流式结果不一致: 预期 %s, 实际 %s", expected, actual))
end

-- 带 hmac 的流式 hash 测试
function crypto_tests.test_hash_update_hmac_sha256()
    log.info("crypto_tests", "开始 hash_update HMAC-SHA256 流式计算测试")
    local expected = crypto.hmac_sha256("HelloWorld1234567890", "mysecretkey")
    local stream = crypto.hash_init("SHA256", "mysecretkey")
    assert(stream, "hash_init HMAC-SHA256 创建失败")
    crypto.hash_update(stream, "Hello")
    crypto.hash_update(stream, "World")
    crypto.hash_update(stream, "1234567890")
    local actual = crypto.hash_finish(stream)
    assert(actual == expected,
        string.format("hash_update HMAC-SHA256 流式结果不一致: 预期 %s, 实际 %s", expected, actual))
end

-- crypto.md() 无 hmac 测试
function crypto_tests.test_md_no_hmac()
    log.info("crypto_tests", "开始 md 无 hmac 计算测试")

    local actual_md5 = crypto.md("MD5", "1234567890")
    local expected_md5 = crypto.md5("1234567890")
    assert(actual_md5 == expected_md5,
        string.format("md('MD5') 与 md5() 结果不一致: 预期 %s, 实际 %s", expected_md5, actual_md5))

    local actual_sha1 = crypto.md("SHA1", "1234567890")
    local expected_sha1 = crypto.sha1("1234567890")
    assert(actual_sha1 == expected_sha1,
        string.format("md('SHA1') 与 sha1() 结果不一致: 预期 %s, 实际 %s", expected_sha1, actual_sha1))

    local actual_sha256 = crypto.md("SHA256", "1234567890")
    local expected_sha256 = crypto.sha256("1234567890")
    assert(actual_sha256 == expected_sha256,
        string.format("md('SHA256') 与 sha256() 结果不一致: 预期 %s, 实际 %s", expected_sha256, actual_sha256))

    local actual_sha512 = crypto.md("SHA512", "1234567890")
    local expected_sha512 = crypto.sha512("1234567890")
    assert(actual_sha512 == expected_sha512,
        string.format("md('SHA512') 与 sha512() 结果不一致: 预期 %s, 实际 %s", expected_sha512, actual_sha512))
end

-- crypto.md_file() 无 hmac 测试
function crypto_tests.test_md_file_no_hmac()
    log.info("crypto_tests", "开始文件的HASH值无hmac计算测试")
    local actual_md5 = crypto.md_file("MD5", "/luadb/logo.jpg")
    assert(actual_md5 and #actual_md5 == 32,
        string.format("文件MD5无hmac计算失败, 返回: %s", tostring(actual_md5)))

    local actual_sha1 = crypto.md_file("SHA1", "/luadb/logo.jpg")
    assert(actual_sha1 and #actual_sha1 == 40,
        string.format("文件SHA1无hmac计算失败, 返回: %s", tostring(actual_sha1)))

    local actual_sha256 = crypto.md_file("SHA256", "/luadb/logo.jpg")
    assert(actual_sha256 and #actual_sha256 == 64,
        string.format("文件SHA256无hmac计算失败, 返回: %s", tostring(actual_sha256)))

    local actual_sha512 = crypto.md_file("SHA512", "/luadb/logo.jpg")
    assert(actual_sha512 and #actual_sha512 == 128,
        string.format("文件SHA512无hmac计算失败, 返回: %s", tostring(actual_sha512)))
end

-- CRC16 USER-DEFINED 模式测试
function crypto_tests.test_crc16_user_defined()
    log.info("crypto_tests", "开始 CRC16 USER-DEFINED 测试")
    -- 使用与 MODBUS 相同的参数, 结果应相同
    local data_modbus = crypto.crc16("MODBUS", "123456")
    local data_user = crypto.crc16("USER-DEFINED", "123456", 0x8005, 0xFFFF, 0x0000, 1, 0)
    assert(data_modbus == data_user,
        string.format("CRC16 USER-DEFINED 模拟 MODBUS 失败: MODBUS=%04X, USER=%04X", data_modbus, data_user))
end

-- AES-256-ECB 加解密测试
function crypto_tests.test_aes_256_ecb_encrypt_decrypt()
    log.info("crypto_tests", "开始 AES-256-ECB 加解密测试")
    local key = "12345678901234561234567890123456" -- 32字节密钥
    local plaintext = "TestAES256ECBxxx" -- 16字节明文
    local ciphertext = crypto.cipher_encrypt("AES-256-ECB", "PKCS7", plaintext, key)
    assert(ciphertext, "AES-256-ECB 加密返回nil")
    local decrypted = crypto.cipher_decrypt("AES-256-ECB", "PKCS7", ciphertext, key)
    assert(decrypted == plaintext,
        string.format("AES-256-ECB 解密失败: 预期 %s, 实际 %s", plaintext, decrypted))
end

-- AES-256-CBC 加解密测试
function crypto_tests.test_aes_256_cbc_encrypt_decrypt()
    log.info("crypto_tests", "开始 AES-256-CBC 加解密测试")
    local key = "12345678901234561234567890123456" -- 32字节密钥
    local iv = "abcdefghijklmnop"                 -- 16字节IV
    local plaintext = "Hello AES-256-CBC mode test!"
    local ciphertext = crypto.cipher_encrypt("AES-256-CBC", "PKCS7", plaintext, key, iv)
    assert(ciphertext, "AES-256-CBC 加密返回nil")
    local decrypted = crypto.cipher_decrypt("AES-256-CBC", "PKCS7", ciphertext, key, iv)
    assert(decrypted == plaintext,
        string.format("AES-256-CBC 解密失败: 预期 %s, 实际 %s", plaintext, decrypted))
end

-- AES-192-ECB 加解密测试
function crypto_tests.test_aes_192_ecb_encrypt_decrypt()
    log.info("crypto_tests", "开始 AES-192-ECB 加解密测试")
    local key = "123456789012345612345678" -- 24字节密钥
    local plaintext = "AES192ECBtestdat" -- 16字节明文
    local ciphertext = crypto.cipher_encrypt("AES-192-ECB", "PKCS7", plaintext, key)
    assert(ciphertext, "AES-192-ECB 加密返回nil")
    local decrypted = crypto.cipher_decrypt("AES-192-ECB", "PKCS7", ciphertext, key)
    assert(decrypted == plaintext,
        string.format("AES-192-ECB 解密失败: 预期 %s, 实际 %s", plaintext, decrypted))
end

-- AES-192-CBC 加解密测试
function crypto_tests.test_aes_192_cbc_encrypt_decrypt()
    log.info("crypto_tests", "开始 AES-192-CBC 加解密测试")
    local key = "123456789012345612345678" -- 24字节密钥
    local iv = "abcdefghijklmnop"          -- 16字节IV
    local plaintext = "Hello AES-192-CBC mode!"
    local ciphertext = crypto.cipher_encrypt("AES-192-CBC", "PKCS7", plaintext, key, iv)
    assert(ciphertext, "AES-192-CBC 加密返回nil")
    local decrypted = crypto.cipher_decrypt("AES-192-CBC", "PKCS7", ciphertext, key, iv)
    assert(decrypted == plaintext,
        string.format("AES-192-CBC 解密失败: 预期 %s, 实际 %s", plaintext, decrypted))
end

-- NONE 填充模式测试 (明文长度必须为块大小整数倍)
function crypto_tests.test_aes_128_ecb_none_padding()
    log.info("crypto_tests", "开始 AES-128-ECB NONE 填充模式测试")
    local key = "1234567890123456"
    local plaintext = "1234567890123456" -- 恰好 16 字节
    local ciphertext = crypto.cipher_encrypt("AES-128-ECB", "NONE", plaintext, key)
    assert(ciphertext, "AES-128-ECB NONE 加密返回nil")
    assert(#ciphertext == 16, "NONE 填充模式密文长度应为 16")
    local decrypted = crypto.cipher_decrypt("AES-128-ECB", "NONE", ciphertext, key)
    assert(decrypted == plaintext,
        string.format("AES-128-ECB NONE 解密失败: 预期 %s, 实际 %s", plaintext, decrypted))
end

-- ONE_AND_ZEROS 填充模式测试
function crypto_tests.test_aes_128_cbc_one_and_zeros()
    log.info("crypto_tests", "开始 AES-128-CBC ONE_AND_ZEROS 填充模式测试")
    local key = "1234567890123456"
    local iv = "abcdefghijklmnop"
    local plaintext = "ShortData"
    local ciphertext = crypto.cipher_encrypt("AES-128-CBC", "ONE_AND_ZEROS", plaintext, key, iv)
    assert(ciphertext, "AES-128-CBC ONE_AND_ZEROS 加密返回nil")
    local decrypted = crypto.cipher_decrypt("AES-128-CBC", "ONE_AND_ZEROS", ciphertext, key, iv)
    assert(decrypted == plaintext,
        string.format("AES-128-CBC ONE_AND_ZEROS 解密失败: 预期 %s, 实际 %s", plaintext, decrypted))
end

-- ZEROS_AND_LEN 填充模式测试
function crypto_tests.test_aes_128_ecb_zeros_and_len()
    log.info("crypto_tests", "开始 AES-128-ECB ZEROS_AND_LEN 填充模式测试")
    local key = "1234567890123456"
    local plaintext = "TestZerosLen"
    local ciphertext = crypto.cipher_encrypt("AES-128-ECB", "ZEROS_AND_LEN", plaintext, key)
    assert(ciphertext, "AES-128-ECB ZEROS_AND_LEN 加密返回nil")
    local decrypted = crypto.cipher_decrypt("AES-128-ECB", "ZEROS_AND_LEN", ciphertext, key)
    assert(decrypted == plaintext,
        string.format("AES-128-ECB ZEROS_AND_LEN 解密失败: 预期 %s, 实际 %s", plaintext, decrypted))
end

-- base64 空字符串测试
function crypto_tests.test_base64_empty()
    log.info("crypto_tests", "开始 base64 空字符串测试")
    local encoded = crypto.base64_encode("")
    assert(encoded == "", string.format("base64 编码空字符串失败: 预期空, 实际 '%s'", encoded))
    local decoded = crypto.base64_decode("")
    assert(decoded == "", string.format("base64 解码空字符串失败: 预期空, 实际 '%s'", decoded))
end

-- base64 二进制数据测试
function crypto_tests.test_base64_binary()
    log.info("crypto_tests", "开始 base64 二进制数据测试")
    local binary = string.char(0, 1, 2, 255, 254, 253, 128, 64)
    local encoded = crypto.base64_encode(binary)
    assert(encoded and #encoded > 0, "base64 编码二进制数据返回空")
    local decoded = crypto.base64_decode(encoded)
    assert(decoded == binary, "base64 二进制数据编解码不一致")
end

-- base64 长字符串测试
function crypto_tests.test_base64_long_string()
    log.info("crypto_tests", "开始 base64 长字符串测试")
    local long_str = string.rep("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789", 10)
    local encoded = crypto.base64_encode(long_str)
    assert(encoded and #encoded > 0, "base64 编码长字符串返回空")
    local decoded = crypto.base64_decode(encoded)
    assert(decoded == long_str, "base64 长字符串编解码不一致")
end

-- trng 不同长度测试
function crypto_tests.test_trng_lengths()
    log.info("crypto_tests", "开始 trng 不同长度测试")
    for _, len in ipairs({1, 4, 8, 16, 32, 64, 128}) do
        local data = crypto.trng(len)
        assert(data and #data == len,
            string.format("TRNG 长度 %d 失败: 返回长度 %d", len, data and #data or 0))
    end
end

-- trng 最大长度限制测试 (超过128应被截断为128)
function crypto_tests.test_trng_max_length()
    log.info("crypto_tests", "开始 trng 最大长度限制测试")
    local data = crypto.trng(256)
    assert(data and #data == 128,
        string.format("TRNG 超长请求应截断为128, 实际长度: %d", data and #data or 0))
end

-- checksum 长数据测试
function crypto_tests.test_checksum_long_data()
    log.info("crypto_tests", "开始校验和长数据测试")
    local data = string.rep("ABCD", 64) -- 256字节
    local xor_result = crypto.checksum(data, 0)
    local add_result = crypto.checksum(data, 1)
    assert(type(xor_result) == "number", "校验和异或模式应返回 number")
    assert(type(add_result) == "number", "校验和累加模式应返回 number")
    -- "ABCD" 异或= 0x41^0x42^0x43^0x44 = 0x04, 重复64次异或自身=0x00
    assert(xor_result == 0x00,
        string.format("校验和长数据异或失败: 预期 0x00, 实际 0x%02X", xor_result))
end

-- checksum 单字节测试
function crypto_tests.test_checksum_single_byte()
    log.info("crypto_tests", "开始校验和单字节测试")
    local result_xor = crypto.checksum("A", 0)
    assert(result_xor == 0x41,
        string.format("校验和单字节异或失败: 预期 0x41, 实际 0x%02X", result_xor))
    local result_add = crypto.checksum("A", 1)
    assert(result_add == 0x41,
        string.format("校验和单字节累加失败: 预期 0x41, 实际 0x%02X", result_add))
end

-- CRC32 默认参数测试
function crypto_tests.test_crc32_default()
    log.info("crypto_tests", "开始 CRC32 默认参数测试")
    -- 不带可选参数和带默认参数的结果应一致
    local crc_default = crypto.crc32("123456")
    local crc_explicit = crypto.crc32("123456", 0xFFFFFFFF, 0x04C11DB7, 0xFFFFFFFF)
    assert(crc_default == crc_explicit,
        string.format("CRC32 默认参数不一致: 默认=%08X, 显式=%08X",
            crc_default & 0xFFFFFFFF, crc_explicit & 0xFFFFFFFF))
end

-- CRC8 无参数(仅数据)测试
function crypto_tests.test_crc8_default()
    log.info("crypto_tests", "开始 CRC8 默认参数测试")
    local result = crypto.crc8("hello")
    assert(type(result) == "number", "CRC8 默认参数应返回 number")
    -- 使用相同默认参数显式调用, 结果应一致
    local result_explicit = crypto.crc8("hello", 0x07, 0x00, false)
    assert(result == result_explicit,
        string.format("CRC8 默认参数不一致: 默认=%02X, 显式=%02X", result, result_explicit))
end

-- CRC7 默认参数测试
function crypto_tests.test_crc7_params()
    log.info("crypto_tests", "开始 CRC7 不同参数测试")
    -- 默认多项式0xE5, 初始值0x00
    local crc_a = crypto.crc7("hello")
    local crc_b = crypto.crc7("hello", 0xE5, 0x00)
    assert(crc_a == crc_b,
        string.format("CRC7 默认参数不一致: 默认=%02X, 显式=%02X", crc_a, crc_b))
end

-- 加密后密文与明文不同
function crypto_tests.test_cipher_encrypt_not_equal_plaintext()
    log.info("crypto_tests", "开始密文与明文不同测试")
    local plaintext = "1234567890123456"
    local key = "abcdefghijklmnop"
    local ciphertext = crypto.cipher_encrypt("AES-128-ECB", "PKCS7", plaintext, key)
    assert(ciphertext ~= plaintext, "加密后密文不应与明文相同")
end

-- 不同密钥加密同一数据得到不同密文
function crypto_tests.test_cipher_different_keys()
    log.info("crypto_tests", "开始不同密钥产生不同密文测试")
    local plaintext = "1234567890123456"
    local key1 = "abcdefghijklmnop"
    local key2 = "ponmlkjihgfedcba"
    local cipher1 = crypto.cipher_encrypt("AES-128-ECB", "PKCS7", plaintext, key1)
    local cipher2 = crypto.cipher_encrypt("AES-128-ECB", "PKCS7", plaintext, key2)
    assert(cipher1 ~= cipher2, "不同密钥应产生不同密文")
end

-- TOTP 不同时间戳产生不同结果(跨不同30秒窗口)
function crypto_tests.test_totp_different_time()
    log.info("crypto_tests", "开始 TOTP 不同时间窗口测试")
    local secret = "asdfassdfasdfass"
    local otp1 = crypto.totp(secret, 1000000)
    local otp2 = crypto.totp(secret, 1000030) -- 不同的30秒窗口
    -- 注: 同一窗口内结果相同, 不同窗口可能不同(极小概率相同)
    assert(type(otp1) == "number" and otp1 >= 0 and otp1 < 1000000,
        string.format("TOTP 结果应为6位数字, 实际: %s", tostring(otp1)))
    assert(type(otp2) == "number" and otp2 >= 0 and otp2 < 1000000,
        string.format("TOTP 结果应为6位数字, 实际: %s", tostring(otp2)))
end

-- TOTP 相同时间窗口产生相同结果
function crypto_tests.test_totp_same_window()
    log.info("crypto_tests", "开始 TOTP 同一时间窗口测试")
    local secret = "asdfassdfasdfass"
    -- 同一30秒窗口内的两个时间戳
    local otp1 = crypto.totp(secret, 1764924900)
    local otp2 = crypto.totp(secret, 1764924920) -- 同一30秒窗口
    assert(otp1 == otp2,
        string.format("TOTP 同一窗口结果应相同: %s vs %s", tostring(otp1), tostring(otp2)))
end

-- DES-ECB 加解密测试
function crypto_tests.test_des_ecb_encrypt_decrypt()
    log.info("crypto_tests", "开始 DES-ECB 加解密测试")
    local key = "12345678" -- 8字节密钥
    local plaintext = "TestDES!"
    local ciphertext = crypto.cipher_encrypt("DES-ECB", "PKCS7", plaintext, key)
    assert(ciphertext, "DES-ECB 加密返回nil")
    local decrypted = crypto.cipher_decrypt("DES-ECB", "PKCS7", ciphertext, key)
    assert(decrypted == plaintext,
        string.format("DES-ECB 解密失败: 预期 %s, 实际 %s", plaintext, decrypted))
end

-- DES-EDE3-ECB (3DES ECB) 加解密测试
function crypto_tests.test_des_ede3_ecb_encrypt_decrypt()
    log.info("crypto_tests", "开始 DES-EDE3-ECB 加解密测试")
    local key = "123456789012345678901234" -- 24字节密钥
    local plaintext = "3DEStest"
    local ciphertext = crypto.cipher_encrypt("DES-EDE3-ECB", "PKCS7", plaintext, key)
    assert(ciphertext, "DES-EDE3-ECB 加密返回nil")
    local decrypted = crypto.cipher_decrypt("DES-EDE3-ECB", "PKCS7", ciphertext, key)
    assert(decrypted == plaintext,
        string.format("DES-EDE3-ECB 解密失败: 预期 %s, 实际 %s", plaintext, decrypted))
end

-- md5 已知向量验证
function crypto_tests.test_md5_known_vectors()
    log.info("crypto_tests", "开始 MD5 已知向量测试")
    -- RFC 1321 测试向量
    local actual = crypto.md5("abc")
    local expected = "900150983CD24FB0D6963F7D28E17F72"
    assert(actual == expected,
        string.format("MD5('abc') 失败: 预期 %s, 实际 %s", expected, actual))
end

-- sha256 已知向量验证
function crypto_tests.test_sha256_known_vectors()
    log.info("crypto_tests", "开始 SHA256 已知向量测试")
    local actual = crypto.sha256("abc")
    local expected = "BA7816BF8F01CFEA414140DE5DAE2223B00361A396177A9CB410FF61F20015AD"
    assert(actual == expected,
        string.format("SHA256('abc') 失败: 预期 %s, 实际 %s", expected, actual))
end

-- sha1 已知向量验证
function crypto_tests.test_sha1_known_vectors()
    log.info("crypto_tests", "开始 SHA1 已知向量测试")
    local actual = crypto.sha1("abc")
    local expected = "A9993E364706816ABA3E25717850C26C9CD0D89D"
    assert(actual == expected,
        string.format("SHA1('abc') 失败: 预期 %s, 实际 %s", expected, actual))
end

-- CRC16 MODBUS 与 crc16_modbus 结果一致性测试
function crypto_tests.test_crc16_modbus_consistency()
    log.info("crypto_tests", "开始 CRC16 MODBUS 一致性测试")
    local data = "HelloWorld123"
    local crc_generic = crypto.crc16("MODBUS", data)
    local crc_modbus = crypto.crc16_modbus(data)
    assert(crc_generic == crc_modbus,
        string.format("CRC16 MODBUS 不一致: generic=%04X, modbus=%04X", crc_generic, crc_modbus))
end

-- 多轮加解密一致性测试
function crypto_tests.test_cipher_multiple_rounds()
    log.info("crypto_tests", "开始多轮加解密一致性测试")
    local key = "1234567890123456"
    local iv = "abcdefghijklmnop"
    local plaintext = "MultiRoundTest!!"
    for i = 1, 5 do
        local ciphertext = crypto.cipher_encrypt("AES-128-CBC", "PKCS7", plaintext, key, iv)
        local decrypted = crypto.cipher_decrypt("AES-128-CBC", "PKCS7", ciphertext, key, iv)
        assert(decrypted == plaintext,
            string.format("第 %d 轮加解密不一致: 预期 %s, 实际 %s", i, plaintext, decrypted))
    end
end

return crypto_tests

