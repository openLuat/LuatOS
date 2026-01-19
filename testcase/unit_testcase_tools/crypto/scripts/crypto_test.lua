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
    assert(md5_stream_finish == expected_md5_stream,
        string.format("获取流式SHA1校验值: 预期 %s, 实际 %s", expected_md5_stream, md5_stream_finish))
    local sha256_stream_finish = crypto.hash_finish(sha256_stream)
    local expected_sha256_stream = "B946CCC987465AFCDA7E45B1715219711A13518D1F1663B8C53B848CB0143441"

    assert(md5_stream_finish == expected_md5_stream,
        string.format("获取流式SHA256校验值: 预期 %s, 实际 %s", expected_md5_stream, md5_stream_finish))
    local sha512_stream_finish = crypto.hash_finish(sha512_stream)
    local expected_sha512_stream =
        "D3F2F066F0DA13B4CD51085457A9C50F4DFC3DDC2B790133D49F6A11BD048AB7BF4292ABAAE52D5C2841F7EDA24F51BCE0858EF75DD0EE02283C73783D63C6A4"
    assert(md5_stream_finish == expected_md5_stream,
        string.format("获取流式SHA512校验值: 预期 %s, 实际 %s", expected_md5_stream, md5_stream_finish))

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

return crypto_tests

