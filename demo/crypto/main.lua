
-- LuaTools需要PROJECT和VERSION这两个信息
PROJECT = "cryptodemo"
VERSION = "1.0.0"

log.info("main", PROJECT, VERSION)

-- sys库是标配
_G.sys = require("sys")

if wdt then
    --添加硬狗防止程序卡死，在支持的设备上启用这个功能
    wdt.init(9000)--初始化watchdog设置为9s
    sys.timerLoopStart(wdt.feed, 3000)--3s喂一次狗
end

sys.taskInit(function()

    sys.wait(3000)

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

    -- DES-ECB 加解密
    local data1 = crypto.cipher_encrypt("DES-ECB", "PKCS7", "abcdefg", "12345678")
    if data1 then -- DES-ECB 在某些平台不支持的
        print(data1:toHex())
        local data2 = crypto.cipher_decrypt("DES-ECB", "PKCS7", data1, "12345678")
        print(data2)
    end

    -- 打印所有支持的cipher
    if crypto.cipher_list then
        log.info("cipher", "list", json.encode(crypto.cipher_list()))
    end
    -- 打印所有支持的cipher suites
    if crypto.cipher_suites then
        log.info("cipher", "suites", json.encode(crypto.cipher_suites()))
    end

    for i=1, 10 do
        sys.wait(100)
        log.info("crypto", "真随机数",string.unpack("I",crypto.trng(4)))
        -- log.info("crypto", "伪随机数",math.random()) -- 输出的是浮点数,不建议使用
    end

    -- totp的密钥
    local secret = "VK54ZXPO74ISEM2E"
    --写死时间戳用来测试
    local ts = 1646796576
    --生成十分钟的动态码验证下
    for i=1,600,30 do
        local r = crypto.totp(secret,ts+i)
        local time = os.date("*t",ts+i + 8*3600)--东八区
        log.info("totp", string.format("%06d" ,r),time.hour,time.min,time.sec)
    end

    if crypto.md_file then
        log.info("md5", crypto.md_file("MD5", "/luadb/logo.jpg"))
        log.info("sha1", crypto.md_file("SHA1", "/luadb/logo.jpg"))
        log.info("sha256", crypto.md_file("SHA256", "/luadb/logo.jpg"))
        
        log.info("hmac_md5", crypto.md_file("MD5", "/luadb/logo.jpg", "123456"))
        log.info("hmac_sha1", crypto.md_file("SHA1", "/luadb/logo.jpg", "123456"))
        log.info("hmac_sha256", crypto.md_file("SHA256", "/luadb/logo.jpg", "123456"))
    end

    if crypto.checksum then
        log.info("checksum", "OK", string.char(crypto.checksum("OK")):toHex())
        log.info("checksum", "357E", string.char(crypto.checksum("357E", 1)):toHex())
    end

    log.info("crypto", "ALL Done")
    sys.wait(100000)
end)

-- 用户代码已结束---------------------------------------------
-- 结尾总是这一句
sys.run()
-- sys.run()之后后面不要加任何语句!!!!!
