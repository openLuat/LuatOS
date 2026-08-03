-- iotauth 测试
-- 校验手段:
--   a) 基线固定向量: 改造前用老版本捕获的三元组输出, 逐字节比对, 确保新老版本一致
--   b) Lua层独立重算: 用 crypto 库按各云平台官方签名算法重算 password, 与 C 实现互相印证
--   c) qcloud 的 conn_id 由 TRNG 随机生成, 用格式断言 + 独立重算校验
local iotauth_tests = {}

-- 公共输入夹具
local ALIYUN_PK = "123456789"
local ALIYUN_DN = "abcdefg"
local ALIYUN_DS = "Y877Bgo8X5owd3lcB5wWDjryNPoB"
local ONENET_PID_NEW = "Ck2AF9QD2K"
local ONENET_KEY_NEW = "KuF3NT/jUBJ62LNBB/A8XZA9CqS3Cu79B/ABmfA1UCw="
local ONENET_PID_OLD = "12342334"
local ONENET_KEY_OLD = "adfasdfadsfadsf="
local ONENET_RES_OLD = "products/12342334/devices/test"
local IOTDA_ID = "6203cc94c7fb24029b110408_88888888"
local IOTDA_SECRET = "123456789"
local QCLOUD_PID = "LD8S5J1L07"
local QCLOUD_DN = "test"
local QCLOUD_PSK = "acyv3QDJrRa0fW5UE58KnQ=="
local TUYA_ID = "6c95875d0f5ba69607nzfl"
local TUYA_SECRET = "fb803786602df760"
local BAIDU_CORE = "abcd123"
local BAIDU_KEY = "mydevice"
local BAIDU_SECRET = "ImSeCrEt0I1M2jkl"

-- 注: 部分 LuatOS 构建中 number 为浮点类型, 大时间戳不能用 %d 格式化, 统一用字符串常量
local TS_DEFAULT_ALIYUN = "32472115200" -- 2999-01-01 0:0:0
local TS_DEFAULT_TUYA = "7258089600"    -- 2200-01-01 0:0:0
local TS_EXPLICIT = "1700000000"

local function assertTriple(tag, cid, un, pw, exp_cid, exp_un, exp_pw)
    assert(cid == exp_cid, string.format("%s client_id 不一致: 预期 [%s], 实际 [%s]", tag, exp_cid, tostring(cid)))
    assert(un == exp_un, string.format("%s user_name 不一致: 预期 [%s], 实际 [%s]", tag, exp_un, tostring(un)))
    assert(pw == exp_pw, string.format("%s password 不一致: 预期 [%s], 实际 [%s]", tag, exp_pw, tostring(pw)))
end

local function aliyun_cid(method, ts, securemode)
    return string.format("%s.%s|securemode=%d,signmethod=%s,timestamp=%s|", ALIYUN_PK, ALIYUN_DN, securemode, method, ts)
end

-- ===================== a) 阿里云 基线向量 =====================

function iotauth_tests.test_aliyun_hmacmd5()
    log.info("iotauth_tests", "test_aliyun_hmacmd5")
    local cid, un, pw = iotauth.aliyun(ALIYUN_PK, ALIYUN_DN, ALIYUN_DS)
    assertTriple("aliyun_hmacmd5", cid, un, pw,
        aliyun_cid("hmacmd5", TS_DEFAULT_ALIYUN, 3),
        ALIYUN_DN .. "&" .. ALIYUN_PK,
        "16CB9B20009795D576E9172CDC820646")
end

function iotauth_tests.test_aliyun_hmacsha1()
    log.info("iotauth_tests", "test_aliyun_hmacsha1")
    local cid, un, pw = iotauth.aliyun(ALIYUN_PK, ALIYUN_DN, ALIYUN_DS, "hmacsha1")
    assertTriple("aliyun_hmacsha1", cid, un, pw,
        aliyun_cid("hmacsha1", TS_DEFAULT_ALIYUN, 3),
        ALIYUN_DN .. "&" .. ALIYUN_PK,
        "4E5358D2C33CA163BDA58EC994B9E312712230C7")
end

function iotauth_tests.test_aliyun_hmacsha256()
    log.info("iotauth_tests", "test_aliyun_hmacsha256")
    local cid, un, pw = iotauth.aliyun(ALIYUN_PK, ALIYUN_DN, ALIYUN_DS, "hmacsha256")
    assertTriple("aliyun_hmacsha256", cid, un, pw,
        aliyun_cid("hmacsha256", TS_DEFAULT_ALIYUN, 3),
        ALIYUN_DN .. "&" .. ALIYUN_PK,
        "2842DC9F2FBA19C671DD3F4D24590D41F91C25FD9BC4E5101951BEA88B7DEACD")
end

function iotauth_tests.test_aliyun_explicit_timestamp()
    log.info("iotauth_tests", "test_aliyun_explicit_timestamp")
    local cid, un, pw = iotauth.aliyun(ALIYUN_PK, ALIYUN_DN, ALIYUN_DS, "hmacmd5", tonumber(TS_EXPLICIT))
    assertTriple("aliyun_ts_md5", cid, un, pw,
        aliyun_cid("hmacmd5", TS_EXPLICIT, 3),
        ALIYUN_DN .. "&" .. ALIYUN_PK,
        "21FAD88809E6E674A0BC8D43D6FD1889")
    cid, un, pw = iotauth.aliyun(ALIYUN_PK, ALIYUN_DN, ALIYUN_DS, "hmacsha1", tonumber(TS_EXPLICIT), true)
    assertTriple("aliyun_ts_sha1_tls", cid, un, pw,
        aliyun_cid("hmacsha1", TS_EXPLICIT, 2),
        ALIYUN_DN .. "&" .. ALIYUN_PK,
        "501B3E054A929A0158D8E34826A224C1B9E967E3")
end

function iotauth_tests.test_aliyun_uppercase_method()
    log.info("iotauth_tests", "test_aliyun_uppercase_method")
    -- 大写 method 与小写输出必须完全一致
    local pairs = {
        {"HMACMD5", "hmacmd5", "16CB9B20009795D576E9172CDC820646"},
        {"HMACSHA1", "hmacsha1", "4E5358D2C33CA163BDA58EC994B9E312712230C7"},
        {"HMACSHA256", "hmacsha256", "2842DC9F2FBA19C671DD3F4D24590D41F91C25FD9BC4E5101951BEA88B7DEACD"},
    }
    for _, item in ipairs(pairs) do
        local upper_m, lower_m, exp_pw = item[1], item[2], item[3]
        local cid1, un1, pw1 = iotauth.aliyun(ALIYUN_PK, ALIYUN_DN, ALIYUN_DS, upper_m)
        local cid2, un2, pw2 = iotauth.aliyun(ALIYUN_PK, ALIYUN_DN, ALIYUN_DS, lower_m)
        assert(cid1 == cid2, string.format("aliyun %s/%s client_id 大小写不一致", upper_m, lower_m))
        assert(un1 == un2, string.format("aliyun %s/%s user_name 大小写不一致", upper_m, lower_m))
        assert(pw1 == pw2, string.format("aliyun %s/%s password 大小写不一致", upper_m, lower_m))
        assert(pw1 == exp_pw, string.format("aliyun %s password 与基线不一致: 实际 [%s]", upper_m, tostring(pw1)))
        -- client_id 中 signmethod 始终为小写
        assert(cid1:find("signmethod=" .. lower_m .. ",", 1, true), "aliyun client_id signmethod 应为小写")
    end
end

function iotauth_tests.test_aliyun_tls_flag()
    log.info("iotauth_tests", "test_aliyun_tls_flag")
    local cid, un, pw = iotauth.aliyun(ALIYUN_PK, ALIYUN_DN, ALIYUN_DS, "hmacmd5", nil, true)
    assertTriple("aliyun_tls_md5", cid, un, pw,
        aliyun_cid("hmacmd5", TS_DEFAULT_ALIYUN, 2),
        ALIYUN_DN .. "&" .. ALIYUN_PK,
        "16CB9B20009795D576E9172CDC820646")
    cid, un, pw = iotauth.aliyun(ALIYUN_PK, ALIYUN_DN, ALIYUN_DS, "hmacsha256", nil, true)
    assertTriple("aliyun_tls_sha256", cid, un, pw,
        aliyun_cid("hmacsha256", TS_DEFAULT_ALIYUN, 2),
        ALIYUN_DN .. "&" .. ALIYUN_PK,
        "2842DC9F2FBA19C671DD3F4D24590D41F91C25FD9BC4E5101951BEA88B7DEACD")
end

-- ===================== a) onenet 基线向量 =====================

function iotauth_tests.test_onenet_md5()
    log.info("iotauth_tests", "test_onenet_md5")
    local cid, un, pw = iotauth.onenet(ONENET_PID_NEW, "test", ONENET_KEY_NEW)
    assertTriple("onenet_md5", cid, un, pw,
        "test", ONENET_PID_NEW,
        "version=2018-10-31&res=products%2FCk2AF9QD2K%2Fdevices%2Ftest&et=32472115200&method=md5&sign=htDD26UhXtXayMFAWRmNiA%3D%3D")
end

function iotauth_tests.test_onenet_sha1()
    log.info("iotauth_tests", "test_onenet_sha1")
    local cid, un, pw = iotauth.onenet(ONENET_PID_NEW, "test", ONENET_KEY_NEW, "sha1")
    assertTriple("onenet_sha1", cid, un, pw,
        "test", ONENET_PID_NEW,
        "version=2018-10-31&res=products%2FCk2AF9QD2K%2Fdevices%2Ftest&et=32472115200&method=sha1&sign=onzQlILHFFNqIY%2BdOXYM3lthLT8%3D")
end

function iotauth_tests.test_onenet_sha256()
    log.info("iotauth_tests", "test_onenet_sha256")
    local cid, un, pw = iotauth.onenet(ONENET_PID_NEW, "test", ONENET_KEY_NEW, "sha256")
    assertTriple("onenet_sha256", cid, un, pw,
        "test", ONENET_PID_NEW,
        "version=2018-10-31&res=products%2FCk2AF9QD2K%2Fdevices%2Ftest&et=32472115200&method=sha256&sign=6Y4zbk3Sa89tRf9lMxCCE0jG74uEcEuu%2Fnly1pU9ADM%3D")
end

function iotauth_tests.test_onenet_uppercase_method()
    log.info("iotauth_tests", "test_onenet_uppercase_method")
    -- 大写 method 时 token 中 method= 保留原样(MD5), 基线已捕获
    local cid, un, pw = iotauth.onenet(ONENET_PID_NEW, "test", ONENET_KEY_NEW, "MD5")
    assertTriple("onenet_upper_MD5", cid, un, pw,
        "test", ONENET_PID_NEW,
        "version=2018-10-31&res=products%2FCk2AF9QD2K%2Fdevices%2Ftest&et=32472115200&method=MD5&sign=y215sMm9evP3NThz5QRsiA%3D%3D")
end

function iotauth_tests.test_onenet_old_platform()
    log.info("iotauth_tests", "test_onenet_old_platform")
    -- 旧版平台, 显式 res, 覆盖 URL 编码 '/' -> '%2F' 路径
    local cid, un, pw = iotauth.onenet(ONENET_PID_OLD, "test", ONENET_KEY_OLD, "md5", nil, nil, ONENET_RES_OLD)
    assertTriple("onenet_old_res_md5", cid, un, pw,
        "test", ONENET_PID_OLD,
        "version=2018-10-31&res=products%2F12342334%2Fdevices%2Ftest&et=32472115200&method=md5&sign=wZWDnoyHugla0wMlcl75xg%3D%3D")
    cid, un, pw = iotauth.onenet(ONENET_PID_OLD, "test", ONENET_KEY_OLD, "sha1", nil, nil, ONENET_RES_OLD)
    assertTriple("onenet_old_res_sha1", cid, un, pw,
        "test", ONENET_PID_OLD,
        "version=2018-10-31&res=products%2F12342334%2Fdevices%2Ftest&et=32472115200&method=sha1&sign=FHt8BqSNGv0VEJKbHN4zod6a69Q%3D")
end

function iotauth_tests.test_onenet_custom_version()
    log.info("iotauth_tests", "test_onenet_custom_version")
    local cid, un, pw = iotauth.onenet(ONENET_PID_NEW, "test", ONENET_KEY_NEW, "sha256", nil, "2022-05-01")
    assertTriple("onenet_custom_version", cid, un, pw,
        "test", ONENET_PID_NEW,
        "version=2022-05-01&res=products%2FCk2AF9QD2K%2Fdevices%2Ftest&et=32472115200&method=sha256&sign=N41Pmx3YpLyOoc9jtyCFPJX1etO8MxfcCr7xHYw40ws%3D")
end

-- ===================== a) iotda 基线向量 =====================
-- 注意: client_id 中的日期段来自 localtime, 与运行环境时区相关, 基线在 UTC+8 环境捕获

function iotauth_tests.test_iotda_default()
    log.info("iotauth_tests", "test_iotda_default")
    local cid, un, pw = iotauth.iotda(IOTDA_ID, IOTDA_SECRET)
    assertTriple("iotda_default", cid, un, pw,
        IOTDA_ID .. "_0_0_2999010100",
        IOTDA_ID,
        "5888ea6f4631ce76d621f452e8823507c36dd68a61f6e08518c8935e280c3c72")
end

function iotauth_tests.test_iotda_with_timestamp()
    log.info("iotauth_tests", "test_iotda_with_timestamp")
    local cid, un, pw = iotauth.iotda(IOTDA_ID, IOTDA_SECRET, tonumber(TS_EXPLICIT))
    assertTriple("iotda_ts", cid, un, pw,
        IOTDA_ID .. "_0_1_2023111506",
        IOTDA_ID,
        "1c05cd54cb1b9585d40f10581aa2c84bf8c93c418eceff2f55f55dbc396c5b32")
end

-- ===================== a) tuya 基线向量 =====================

function iotauth_tests.test_tuya_default()
    log.info("iotauth_tests", "test_tuya_default")
    local cid, un, pw = iotauth.tuya(TUYA_ID, TUYA_SECRET)
    assertTriple("tuya_default", cid, un, pw,
        "tuyalink_" .. TUYA_ID,
        TUYA_ID .. "|signMethod=hmacSha256,timestamp=" .. TS_DEFAULT_TUYA .. ",secureMode=1,accessType=1",
        "d4e2d498e4195db3ed213b33d662e3b7bf434dc3d5a1f2e63b602ac9248ba72c")
end

function iotauth_tests.test_tuya_with_timestamp()
    log.info("iotauth_tests", "test_tuya_with_timestamp")
    local cid, un, pw = iotauth.tuya(TUYA_ID, TUYA_SECRET, tonumber(TS_EXPLICIT))
    assertTriple("tuya_ts", cid, un, pw,
        "tuyalink_" .. TUYA_ID,
        TUYA_ID .. "|signMethod=hmacSha256,timestamp=" .. TS_EXPLICIT .. ",secureMode=1,accessType=1",
        "1560ae9a5d22067b47f6e98347c6e408fd9e9b63cd6c1f354fedbe452b0375db")
end

-- ===================== a) baidu 基线向量 =====================

function iotauth_tests.test_baidu_md5()
    log.info("iotauth_tests", "test_baidu_md5")
    local cid, un, pw = iotauth.baidu(BAIDU_CORE, BAIDU_KEY, BAIDU_SECRET)
    assertTriple("baidu_md5_notime", cid, un, pw,
        BAIDU_CORE,
        "thingidp@" .. BAIDU_CORE .. "|" .. BAIDU_KEY .. "|MD5",
        "22bc75231495220c7a2202fe15f7d286")
    cid, un, pw = iotauth.baidu(BAIDU_CORE, BAIDU_KEY, BAIDU_SECRET, "MD5", tonumber(TS_EXPLICIT))
    assertTriple("baidu_md5_ts", cid, un, pw,
        BAIDU_CORE,
        "thingidp@" .. BAIDU_CORE .. "|" .. BAIDU_KEY .. "|" .. TS_EXPLICIT .. "|MD5",
        "c7aa0f9bd88fb5ba4857abc4868921e0")
end

function iotauth_tests.test_baidu_sha256()
    log.info("iotauth_tests", "test_baidu_sha256")
    local cid, un, pw = iotauth.baidu(BAIDU_CORE, BAIDU_KEY, BAIDU_SECRET, "SHA256")
    assertTriple("baidu_sha256_notime", cid, un, pw,
        BAIDU_CORE,
        "thingidp@" .. BAIDU_CORE .. "|" .. BAIDU_KEY .. "|SHA256",
        "8b84e00accf874b07c1ac586830d211386294df1d2303d40d19c007c0e937af5")
    cid, un, pw = iotauth.baidu(BAIDU_CORE, BAIDU_KEY, BAIDU_SECRET, "SHA256", tonumber(TS_EXPLICIT))
    assertTriple("baidu_sha256_ts", cid, un, pw,
        BAIDU_CORE,
        "thingidp@" .. BAIDU_CORE .. "|" .. BAIDU_KEY .. "|" .. TS_EXPLICIT .. "|SHA256",
        "4b4923db7522a0fe7a50a26003ba4a7647f627921828127e169073b9eafe5a2e")
end

function iotauth_tests.test_baidu_lowercase_method()
    log.info("iotauth_tests", "test_baidu_lowercase_method")
    local cid1, un1, pw1 = iotauth.baidu(BAIDU_CORE, BAIDU_KEY, BAIDU_SECRET, "md5")
    local cid2, un2, pw2 = iotauth.baidu(BAIDU_CORE, BAIDU_KEY, BAIDU_SECRET, "MD5")
    assert(cid1 == cid2 and un1 == un2 and pw1 == pw2, "baidu md5/MD5 大小写输出不一致")
    assert(pw1 == "22bc75231495220c7a2202fe15f7d286", "baidu md5 password 与基线不一致")
end

-- ===================== a) 不支持的 method (保留老版本行为) =====================

function iotauth_tests.test_unsupported_method()
    log.info("iotauth_tests", "test_unsupported_method")
    -- aliyun: 失败时 client_id/user_name/password 均未写入
    local cid, un, pw = iotauth.aliyun(ALIYUN_PK, ALIYUN_DN, ALIYUN_DS, "crc32")
    assertTriple("aliyun_badmethod", cid, un, pw, "", "", "")
    -- onenet: 同上
    cid, un, pw = iotauth.onenet(ONENET_PID_NEW, "test", ONENET_KEY_NEW, "crc32")
    assertTriple("onenet_badmethod", cid, un, pw, "", "", "")
    -- qcloud: 老版本行为为 client_id/user_name 已写入, password 为空
    cid, un, pw = iotauth.qcloud(QCLOUD_PID, QCLOUD_DN, QCLOUD_PSK, "crc32")
    assert(cid == QCLOUD_PID .. QCLOUD_DN, "qcloud badmethod client_id 与老版本行为不一致")
    assert(un ~= nil and un ~= "" and pw == "", "qcloud badmethod 应保持 user_name 非空且 password 为空的老版本行为")
    -- baidu: 老版本行为为 client_id 已写入, user_name/password 为空
    cid, un, pw = iotauth.baidu(BAIDU_CORE, BAIDU_KEY, BAIDU_SECRET, "crc32")
    assertTriple("baidu_badmethod", cid, un, pw, BAIDU_CORE, "", "")
end

-- ===================== c) qcloud 随机 conn_id 校验 =====================

local function check_qcloud(method, exp_suffix, exp_hex_len)
    local cid, un, pw = iotauth.qcloud(QCLOUD_PID, QCLOUD_DN, QCLOUD_PSK, method)
    assert(cid == QCLOUD_PID .. QCLOUD_DN, "qcloud client_id 错误: " .. tostring(cid))
    -- user_name 格式: <pid><dn>;<appid>;<5位随机字母conn_id>;<ts>
    local prefix = "^" .. QCLOUD_PID .. QCLOUD_DN .. ";12010126;(%a+);" .. TS_DEFAULT_ALIYUN .. "$"
    local conn_id = un:match(prefix)
    assert(conn_id ~= nil, string.format("qcloud user_name 格式错误: [%s]", tostring(un)))
    assert(#conn_id == 5, string.format("qcloud conn_id 长度应为5: [%s]", conn_id))
    -- password 格式: <hex>;<suffix>
    local hex = pw:match("^([%x]+);" .. exp_suffix .. "$")
    assert(hex ~= nil, string.format("qcloud password 格式错误: [%s]", tostring(pw)))
    assert(#hex == exp_hex_len, string.format("qcloud password hex 长度应为 %d: [%s]", exp_hex_len, hex))
    -- 独立重算: hmac(user_name, base64decode(psk))
    local psk_raw = QCLOUD_PSK:fromBase64()
    local exp_hex
    if exp_suffix == "hmacsha1" then
        exp_hex = crypto.hmac_sha1(un, psk_raw):lower()
    else
        exp_hex = crypto.hmac_sha256(un, psk_raw):lower()
    end
    assert(hex == exp_hex, string.format("qcloud %s password 独立重算不一致: 预期 [%s], 实际 [%s]", method, exp_hex, hex))
end

function iotauth_tests.test_qcloud_sha256()
    log.info("iotauth_tests", "test_qcloud_sha256")
    check_qcloud("sha256", "hmacsha256", 64)
end

function iotauth_tests.test_qcloud_sha1()
    log.info("iotauth_tests", "test_qcloud_sha1")
    check_qcloud("sha1", "hmacsha1", 40)
end

function iotauth_tests.test_qcloud_uppercase_method()
    log.info("iotauth_tests", "test_qcloud_uppercase_method")
    check_qcloud("SHA256", "hmacsha256", 64)
end

-- ===================== b) Lua 层独立重算 =====================

function iotauth_tests.test_cross_check_aliyun()
    log.info("iotauth_tests", "test_cross_check_aliyun")
    local src = "clientId" .. ALIYUN_PK .. "." .. ALIYUN_DN
        .. "deviceName" .. ALIYUN_DN
        .. "productKey" .. ALIYUN_PK
        .. "timestamp" .. TS_EXPLICIT
    local _, _, pw = iotauth.aliyun(ALIYUN_PK, ALIYUN_DN, ALIYUN_DS, "hmacmd5", tonumber(TS_EXPLICIT))
    assert(pw == crypto.hmac_md5(src, ALIYUN_DS), "aliyun hmacmd5 独立重算不一致")
    _, _, pw = iotauth.aliyun(ALIYUN_PK, ALIYUN_DN, ALIYUN_DS, "hmacsha1", tonumber(TS_EXPLICIT))
    assert(pw == crypto.hmac_sha1(src, ALIYUN_DS), "aliyun hmacsha1 独立重算不一致")
    _, _, pw = iotauth.aliyun(ALIYUN_PK, ALIYUN_DN, ALIYUN_DS, "hmacsha256", tonumber(TS_EXPLICIT))
    assert(pw == crypto.hmac_sha256(src, ALIYUN_DS), "aliyun hmacsha256 独立重算不一致")
end

-- onenet token 的 url 编码: 仅 '+' '/' '=' 会出现在 base64 sign 中
local function onenet_urlenc(s)
    return (s:gsub("+", "%%2B"):gsub("/", "%%2F"):gsub("=", "%%3D"))
end

local function check_onenet(method, version, res)
    local _, _, pw = iotauth.onenet(ONENET_PID_NEW, "test", ONENET_KEY_NEW, method, nil, version, res)
    local et = tostring(TS_DEFAULT_ALIYUN)
    local res_val = res or ("products/" .. ONENET_PID_NEW .. "/devices/test")
    local sig_src = et .. "\n" .. method .. "\n" .. res_val .. "\n" .. version
    local key_raw = ONENET_KEY_NEW:fromBase64()
    local sign_b64
    if method == "md5" then
        sign_b64 = crypto.hmac_md5(sig_src, key_raw):fromHex():toBase64()
    elseif method == "sha1" then
        sign_b64 = crypto.hmac_sha1(sig_src, key_raw):fromHex():toBase64()
    else
        sign_b64 = crypto.hmac_sha256(sig_src, key_raw):fromHex():toBase64()
    end
    local exp_pw = string.format("version=%s&res=%s&et=%s&method=%s&sign=%s",
        version, onenet_urlenc(res_val), et, method, onenet_urlenc(sign_b64))
    assert(pw == exp_pw, string.format("onenet %s 独立重算不一致: 预期 [%s], 实际 [%s]", method, exp_pw, tostring(pw)))
end

function iotauth_tests.test_cross_check_onenet()
    log.info("iotauth_tests", "test_cross_check_onenet")
    check_onenet("md5", "2018-10-31")
    check_onenet("sha1", "2018-10-31")
    check_onenet("sha256", "2018-10-31")
    check_onenet("sha256", "2022-05-01")
end

function iotauth_tests.test_cross_check_iotda()
    log.info("iotauth_tests", "test_cross_check_iotda")
    -- password = hmac_sha256(msg=device_secret, key="YYYYMMDDHH"), 小写hex
    local _, _, pw = iotauth.iotda(IOTDA_ID, IOTDA_SECRET, tonumber(TS_EXPLICIT))
    assert(pw == crypto.hmac_sha256(IOTDA_SECRET, "2023111506"):lower(),
        "iotda 独立重算不一致(注意依赖时区, 基线环境为 UTC+8)")
end

function iotauth_tests.test_cross_check_tuya()
    log.info("iotauth_tests", "test_cross_check_tuya")
    local _, _, pw = iotauth.tuya(TUYA_ID, TUYA_SECRET, tonumber(TS_EXPLICIT))
    local src = "deviceId=" .. TUYA_ID .. ",timestamp=" .. TS_EXPLICIT .. ",secureMode=1,accessType=1"
    assert(pw == crypto.hmac_sha256(src, TUYA_SECRET):lower(), "tuya 独立重算不一致")
end

function iotauth_tests.test_cross_check_baidu()
    log.info("iotauth_tests", "test_cross_check_baidu")
    -- password = md5/sha256("<key>&<ts>&<METHOD><secret>"), 小写hex
    local _, _, pw = iotauth.baidu(BAIDU_CORE, BAIDU_KEY, BAIDU_SECRET, "MD5")
    assert(pw == crypto.md5(BAIDU_KEY .. "&0&MD5" .. BAIDU_SECRET):lower(), "baidu md5 独立重算不一致")
    _, _, pw = iotauth.baidu(BAIDU_CORE, BAIDU_KEY, BAIDU_SECRET, "MD5", tonumber(TS_EXPLICIT))
    assert(pw == crypto.md5(BAIDU_KEY .. "&" .. TS_EXPLICIT .. "&MD5" .. BAIDU_SECRET):lower(), "baidu md5 ts 独立重算不一致")
    _, _, pw = iotauth.baidu(BAIDU_CORE, BAIDU_KEY, BAIDU_SECRET, "SHA256")
    assert(pw == crypto.sha256(BAIDU_KEY .. "&0&SHA256" .. BAIDU_SECRET):lower(), "baidu sha256 独立重算不一致")
    _, _, pw = iotauth.baidu(BAIDU_CORE, BAIDU_KEY, BAIDU_SECRET, "SHA256", tonumber(TS_EXPLICIT))
    assert(pw == crypto.sha256(BAIDU_KEY .. "&" .. TS_EXPLICIT .. "&SHA256" .. BAIDU_SECRET):lower(), "baidu sha256 ts 独立重算不一致")
end

return iotauth_tests
