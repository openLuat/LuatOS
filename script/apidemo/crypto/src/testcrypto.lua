local testcrypto = {}

local sys = require "sys"

local function crypto_test()
    -- MD5,输出结果已经hex编码
    log.info("md5", crypto.md5("abc"))
    log.info("hmac_md5", crypto.hmac_md5("abc", "1234567890"))

    -- SHA1,输出结果已经hex编码
    log.info("sha1", crypto.sha1("abc"))
    log.info("hmac_sha1", crypto.hmac_sha1("abc", "1234567890"))

    -- SHA256,输出结果已经hex编码
    log.info("sha256", crypto.sha256("abc"))
    log.info("hmac_sha256", crypto.hmac_sha256("abc", "1234567890"))

    -- SHA512,输出结果已经hex编码
    log.info("sha512", crypto.sha512("abc"))
    log.info("hmac_sha512", crypto.hmac_sha512("abc", "1234567890"))

    -- AES加密, 未经Hex编码. AES-128-ECB 算法,待加密字符串如果超过32字节会报错,待查. by wendal 20200812
    local data_encrypt = crypto.cipher_encrypt("AES-128-ECB", "PKCS7", "12345678901234 > 123456", "1234567890123456")
    local data2_encrypt = crypto.cipher_encrypt("AES-128-CBC", "PKCS7", "12345678901234 > 123456", "1234567890123456", "1234567890666666")
    log.info("AES", "aes-128-ecb", data_encrypt:toHex())
    log.info("AES", "aes-128-cbc", data2_encrypt:toHex())

    -- AES解密, 未经Hex编码
    local data_decrypt = crypto.cipher_decrypt("AES-128-ECB", "PKCS7", data_encrypt, "1234567890123456")
    local data2_decrypt = crypto.cipher_decrypt("AES-128-CBC", "PKCS7", data2_encrypt, "1234567890123456", "1234567890666666")
    log.info("AES", "aes-128-ecb", data_decrypt)
    log.info("AES", "aes-128-cbc", data2_decrypt)
    log.info("mem", rtos.meminfo("sys"))


    --totp的密钥
    local secret = "VK54ZXPO74ISEM2E"
    --写死时间戳用来测试
    local ts = 1646796576
    --生成十分钟的动态码验证下
    for i=1,600,30 do
        local r = crypto.totp(secret,ts+i)
        local time = os.date("*t",ts+i + 8*3600)--东八区
        log.info("totp",r,time.hour,time.min,time.sec)
    end
end

sys.taskInit(function()
    crypto_test()
    while 1 do
        sys.wait(100)
    end
end)

return testcrypto