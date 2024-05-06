
-- LuaTools需要PROJECT和VERSION这两个信息
PROJECT = "cryptodemo"
VERSION = "1.0.0"

log.info("main", PROJECT, VERSION)

-- sys库是标配
_G.sys = require("sys")

-- Air780E的AT固件默认会为开机键防抖, 导致部分用户刷机很麻烦
if rtos.bsp() == "EC618" and pm and pm.PWK_MODE then
    pm.power(pm.PWK_MODE, false)
end


if wdt then
    --添加硬狗防止程序卡死，在支持的设备上启用这个功能
    wdt.init(9000)--初始化watchdog设置为9s
    sys.timerLoopStart(wdt.feed, 3000)--3s喂一次狗
end

sys.taskInit(function()

    sys.wait(1000)

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

	local data_encrypt = crypto.cipher_encrypt("AES-128-ECB", "ZERO", "023001", "HZBIT@WLW/YSBKEY")
	log.info("AES", "aes-128-ecb", data_encrypt:toHex())
	local data_decrypt = crypto.cipher_decrypt("AES-128-ECB", "ZERO", data_encrypt, "HZBIT@WLW/YSBKEY")
	log.info("AES", "aes-128-ecb", data_decrypt)

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

    -- DES-ECB 加解密
    local data1 = crypto.cipher_encrypt("DES-ECB", "PKCS7", "abcdefg", "12345678")
    if data1 then -- DES-ECB 在某些平台不支持的
        log.info("des", data1:toHex())
        local data2 = crypto.cipher_decrypt("DES-ECB", "PKCS7", data1, "12345678")
        log.info("des", data2)
    else
        log.info("des", "当前固件不支持DES/3DES")
    end

    -- 3DES-ECB 加解密
    local data1 = crypto.cipher_encrypt("DES-EDE3-ECB", "PKCS7", "abcdefg!!--ZZSS", "123456781234567812345678")
    if data1 then -- DES-ECB 在某些平台不支持的
        log.info("3des", data1:toHex())
        local data2 = crypto.cipher_decrypt("DES-EDE3-ECB", "PKCS7", data1, "123456781234567812345678")
        log.info("3des", data2)
    else
        log.info("3des", "当前固件不支持DES/3DES")
    end


    -- 打印所有支持的cipher
    if crypto.cipher_list then
        log.info("cipher", "list", json.encode(crypto.cipher_list()))
    else
        log.info("cipher", "当前固件不支持crypto.cipher_list")
    end
    -- 打印所有支持的cipher suites
    if crypto.cipher_suites then
        log.info("cipher", "suites", json.encode(crypto.cipher_suites()))
    else
        log.info("cipher", "当前固件不支持crypto.cipher_suites")
    end

    ---------------------------------------
    log.info("随机数测试")
    for i=1, 10 do
        sys.wait(100)
        log.info("crypto", "真随机数",string.unpack("I",crypto.trng(4)))
        -- log.info("crypto", "伪随机数",math.random()) -- 输出的是浮点数,不推荐
        -- log.info("crypto", "伪随机数",math.random(1, 65525)) -- 不推荐
    end

    -- totp的密钥
    log.info("totp的密钥")
    local secret = "VK54ZXPO74ISEM2E"
    --写死时间戳用来测试
    local ts = 1646796576
    --生成十分钟的动态码验证下
    for i=1,600,30 do
        local r = crypto.totp(secret,ts+i)
        local time = os.date("*t",ts+i + 8*3600)--东八区
        log.info("totp", string.format("%06d" ,r),time.hour,time.min,time.sec)
    end

    -- 文件测试
    log.info("文件hash值测试")
    if crypto.md_file then
        log.info("md5", crypto.md_file("MD5", "/luadb/logo.jpg"))
        log.info("sha1", crypto.md_file("SHA1", "/luadb/logo.jpg"))
        log.info("sha256", crypto.md_file("SHA256", "/luadb/logo.jpg"))
        
        log.info("hmac_md5", crypto.md_file("MD5", "/luadb/logo.jpg", "123456"))
        log.info("hmac_sha1", crypto.md_file("SHA1", "/luadb/logo.jpg", "123456"))
        log.info("hmac_sha256", crypto.md_file("SHA256", "/luadb/logo.jpg", "123456"))
    else
        log.info("文件hash值测试", "当前固件不支持crypto.md_file")
    end

    if crypto.checksum then
        log.info("checksum", "OK", string.char(crypto.checksum("OK")):toHex())
        log.info("checksum", "357E", string.char(crypto.checksum("357E", 1)):toHex())
    else
        log.info("checksum", "当前固件不支持crypto.checksum")
    end

    -- 流式hash测试
    log.info("流式hash测试")
    if crypto.hash_init then
        -- MD5
        local md5_obj = crypto.hash_init("MD5")
        crypto.hash_update(md5_obj, "1234567890")
        crypto.hash_update(md5_obj, "1234567890")
        crypto.hash_update(md5_obj, "1234567890")
        crypto.hash_update(md5_obj, "1234567890")
        local md5_result = crypto.hash_finish(md5_obj)
        log.info("md5_stream", md5_result)
        log.info("md5", crypto.md5("1234567890123456789012345678901234567890"))

        -- HMAC_MD5
        local hmac_md5_obj = crypto.hash_init("MD5", "1234567890")
        crypto.hash_update(hmac_md5_obj, "1234567890")
        crypto.hash_update(hmac_md5_obj, "1234567890")
        crypto.hash_update(hmac_md5_obj, "1234567890")
        crypto.hash_update(hmac_md5_obj, "1234567890")
        local hmac_md5_result = crypto.hash_finish(hmac_md5_obj)
        log.info("hmac_md5_stream", hmac_md5_result)
        log.info("hmac_md5", crypto.hmac_md5("1234567890123456789012345678901234567890", "1234567890"))

        -- SHA1
        local sha1_obj = crypto.hash_init("SHA1")
        crypto.hash_update(sha1_obj, "1234567890")
        crypto.hash_update(sha1_obj, "1234567890")
        crypto.hash_update(sha1_obj, "1234567890")
        crypto.hash_update(sha1_obj, "1234567890")
        local sha1_result = crypto.hash_finish(sha1_obj)
        log.info("sha1_stream", sha1_result)
        log.info("sha1", crypto.sha1("1234567890123456789012345678901234567890"))

        -- HMAC_SHA1
        local hmac_sha1_obj = crypto.hash_init("SHA1", "1234567890")
        crypto.hash_update(hmac_sha1_obj, "1234567890")
        crypto.hash_update(hmac_sha1_obj, "1234567890")
        crypto.hash_update(hmac_sha1_obj, "1234567890")
        crypto.hash_update(hmac_sha1_obj, "1234567890")
        local hmac_sha1_result = crypto.hash_finish(hmac_sha1_obj)
        log.info("hmac_sha1_stream", hmac_sha1_result)
        log.info("hmac_sha1", crypto.hmac_sha1("1234567890123456789012345678901234567890", "1234567890"))

        -- SHA256
        local sha256_obj = crypto.hash_init("SHA256")
        crypto.hash_update(sha256_obj, "1234567890")
        crypto.hash_update(sha256_obj, "1234567890")
        crypto.hash_update(sha256_obj, "1234567890")
        crypto.hash_update(sha256_obj, "1234567890")
        local sha256_result = crypto.hash_finish(sha256_obj)
        log.info("sha256_stream", sha256_result)
        log.info("sha256", crypto.sha256("1234567890123456789012345678901234567890"))

        -- HMAC_SHA256
        local hmac_sha256_obj = crypto.hash_init("SHA256", "1234567890")
        crypto.hash_update(hmac_sha256_obj, "1234567890")
        crypto.hash_update(hmac_sha256_obj, "1234567890")
        crypto.hash_update(hmac_sha256_obj, "1234567890")
        crypto.hash_update(hmac_sha256_obj, "1234567890")
        local hmac_sha256_result = crypto.hash_finish(hmac_sha256_obj)
        log.info("hmac_sha256_stream", hmac_sha256_result)
        log.info("hmac_sha256", crypto.hmac_sha256("1234567890123456789012345678901234567890", "1234567890"))

        -- SHA512
        local sha512_obj = crypto.hash_init("SHA512")
        if sha512_obj then
            crypto.hash_update(sha512_obj, "1234567890")
            crypto.hash_update(sha512_obj, "1234567890")
            crypto.hash_update(sha512_obj, "1234567890")
            crypto.hash_update(sha512_obj, "1234567890")
            local sha512_result = crypto.hash_finish(sha512_obj)
            log.info("sha512_stream", sha512_result)
            log.info("sha512", crypto.sha512("1234567890123456789012345678901234567890"))
        end

        -- HMAC_SHA512
        local hmac_sha512_obj = crypto.hash_init("SHA512", "1234567890")
        if hmac_sha512_obj then
            crypto.hash_update(hmac_sha512_obj, "1234567890")
            crypto.hash_update(hmac_sha512_obj, "1234567890")
            crypto.hash_update(hmac_sha512_obj, "1234567890")
            crypto.hash_update(hmac_sha512_obj, "1234567890")
            local hmac_sha512_result = crypto.hash_finish(hmac_sha512_obj)
            log.info("hmac_sha512_stream", hmac_sha512_result)
            log.info("hmac_sha512", crypto.hmac_sha512("1234567890123456789012345678901234567890", "1234567890"))
        end
    else
        log.info("crypto", "当前固件不支持crypto.hash_init")
    end

    log.info("crc7测试")
    if crypto.crc7 then
        local result = crypto.crc7(string.char(0xAA), 0xE5, 0x00)
        log.info("crc7测试", result, string.format("%02X", result))
    else
        log.info("crypto", "当前固件不支持crypto.crc7")
    end

    log.info("crypto", "ALL Done")
    sys.wait(100000)
end)

-- 用户代码已结束---------------------------------------------
-- 结尾总是这一句
sys.run()
-- sys.run()之后后面不要加任何语句!!!!!
