
--- crypto.pk_sign / pk_verify / pk_type 测试
-- 覆盖: RSA-1024 签名/验签, EC-P256 签名/验签, 密钥类型识别, 负面测试(篡改签名)

PROJECT = "pk_sign_test"
VERSION = "1.0.0"

_G.sys = require("sys")

-- ============================================================
-- 嵌入式测试密钥 (仅供测试, 勿用于生产)
-- RSA-1024, PKCS#8 私钥 + SPKI 公钥
-- ============================================================
local RSA_PRIV = [[-----BEGIN PRIVATE KEY-----
MIICdQIBADANBgkqhkiG9w0BAQEFAASCAl8wggJbAgEAAoGBAJ2Qz97nrHElVgee
3A8sLur48j8Xu+3GRGfh2vXxv2l8pHc3jKoBqM1yVzeeoQ0mKBC+ZPJ0whnH5CU2
v3K51Hfj38CoShDtEm6wITc6juKW8SO+mgSZT41xiKIRuAWpp4C5qLYR6/4eJ8lC
YPuol7guaJVeEA0QnQlvGsFzaF0fAgMBAAECgYBmwukvYT0P1d/TvIGcy54V1SJ4
j4wbOPGoJp7dRDsoGwhQUERHJCnpQ6cqOSSkJLyAnwvLLObiVYGv25LkydmNCBFH
puCB8NlxpPj0mXxF4i3Fhz0Wo+R1KKsZS5KdxOe7YRHbg8CYgfzveYXadZ+8t0iI
dC/2RkXwu5bVdrJV4QJBAN6GPJfHbYZ7LekmAlgZNqFU/p97W6bQwE3nuUz23+rb
AfwiCYxzQQ/X0aJO2qdxQjb5AHfYNBXrsBiPVY5sg5cCQQC1ROn3to/Lk4M+03mt
LzpWWms3OsBGszbn2kCRzAc2zlBs4IYVZZhA3c/jgPgl1AtWMWzKL2ZUCq5kBf6m
cYO5AkBQnRTKb4bwFyPUuN5UiB3QaHgt0oSrdCiWkIICrdUEwf6AFtyasw447RiW
0jZIPrGcNKzEveBwqIeM/jAifpFVAkBbCMX7mpqyoV2LYsc7u3kvvu8TaJUBrKVJ
YSmGTxHca1amp0ePXVtOUFdEKRP2Y3xiCCZbj9xzHn4gS4Zs7ps5AkABWeRT6e5X
nhIo22FUxk2kTxnhIlSFj8oABxuxyY1PAGsM/0oo1ycCTo6xLScq3Jm9lRufhDKn
u7mRQVmt1U6h
-----END PRIVATE KEY-----]]

local RSA_PUB = [[-----BEGIN PUBLIC KEY-----
MIGfMA0GCSqGSIb3DQEBAQUAA4GNADCBiQKBgQCdkM/e56xxJVYHntwPLC7q+PI/
F7vtxkRn4dr18b9pfKR3N4yqAajNclc3nqENJigQvmTydMIZx+QlNr9yudR349/A
qEoQ7RJusCE3Oo7ilvEjvpoEmU+NcYiiEbgFqaeAuai2Eev+HifJQmD7qJe4LmiV
XhANEJ0JbxrBc2hdHwIDAQAB
-----END PUBLIC KEY-----]]

-- RSA 原始格式公钥 (BEGIN RSA PUBLIC KEY), mbedtls 同样支持
local RSA_PUB_PKCS1 = [[-----BEGIN RSA PUBLIC KEY-----
MIGJAoGBAJ2Qz97nrHElVgee3A8sLur48j8Xu+3GRGfh2vXxv2l8pHc3jKoBqM1y
VzeeoQ0mKBC+ZPJ0whnH5CU2v3K51Hfj38CoShDtEm6wITc6juKW8SO+mgSZT41x
iKIRuAWpp4C5qLYR6/4eJ8lCYPuol7guaJVeEA0QnQlvGsFzaF0fAgMBAAE=
-----END RSA PUBLIC KEY-----]]

-- EC P-256, PKCS#8 私钥 + SPKI 公钥
local EC_PRIV = [[-----BEGIN PRIVATE KEY-----
MIGHAgEAMBMGByqGSM49AgEGCCqGSM49AwEHBG0wawIBAQQgReDaV/YGOXZQeO1i
OrVh7H7gHgEtw2W5O3frrkXNaZOhRANCAAQYyxqojcnVF/Lk68jV3LxShhaNpnyB
JqnhtCFYYNdtz646Gg3gOctrEYzPJoPT/TuU8VzS5UblEGGHAsw+0ids
-----END PRIVATE KEY-----]]

local EC_PUB = [[-----BEGIN PUBLIC KEY-----
MFkwEwYHKoZIzj0CAQYIKoZIzj0DAQcDQgAEGMsaqI3J1Rfy5OvI1dy8UoYWjaZ8
gSap4bQhWGDXbc+uOhoN4DnLaxGMzyaD0/07lPFc0uVG5RBhhwLMPtInbA==
-----END PUBLIC KEY-----]]

-- ============================================================
local PASS = 0
local FAIL = 0

local function check(name, cond)
    if cond then
        PASS = PASS + 1
        log.info("PASS", name)
    else
        FAIL = FAIL + 1
        log.error("FAIL", name)
    end
end

sys.taskInit(function()

    -- --------------------------------------------------------
    -- 基础检查: crypto.pk_sign / pk_verify / pk_type 是否存在
    -- --------------------------------------------------------
    check("api_pk_sign_exists",   type(crypto.pk_sign)   == "function")
    check("api_pk_verify_exists", type(crypto.pk_verify) == "function")
    check("api_pk_type_exists",   type(crypto.pk_type)   == "function")

    -- --------------------------------------------------------
    -- 1. pk_type: RSA 密钥类型识别
    -- --------------------------------------------------------
    local rsa_pub_type  = crypto.pk_type(RSA_PUB)
    local rsa_priv_type = crypto.pk_type(RSA_PRIV, true)
    check("pk_type_rsa_pub",  rsa_pub_type  == "rsa")
    check("pk_type_rsa_priv", rsa_priv_type == "rsa")

    -- --------------------------------------------------------
    -- 2. pk_type: EC 密钥类型识别
    -- --------------------------------------------------------
    local ec_pub_type  = crypto.pk_type(EC_PUB)
    local ec_priv_type = crypto.pk_type(EC_PRIV, true)
    check("pk_type_ec_pub",  ec_pub_type  == "ec")
    check("pk_type_ec_priv", ec_priv_type == "ec")

    -- --------------------------------------------------------
    -- 3. RSA-SHA256 签名 + 验签 (SPKI 公钥)
    -- --------------------------------------------------------
    local data = "hello luatos pk_sign test"
    local hash = crypto.sha256(data):fromHex()
    check("rsa_hash_len", #hash == 32)

    local rsa_sig = crypto.pk_sign(crypto.MD_SHA256, hash, RSA_PRIV)
    check("rsa_sign_ok",    rsa_sig ~= nil)
    check("rsa_sig_len_ok", rsa_sig ~= nil and #rsa_sig > 0)

    if rsa_sig then
        local ok = crypto.pk_verify(crypto.MD_SHA256, hash, RSA_PUB, rsa_sig)
        check("rsa_verify_spki_ok", ok == true)

        -- 3b. 用 PKCS#1 公钥格式验签 (BEGIN RSA PUBLIC KEY)
        local ok2 = crypto.pk_verify(crypto.MD_SHA256, hash, RSA_PUB_PKCS1, rsa_sig)
        check("rsa_verify_pkcs1_ok", ok2 == true)
    end

    -- --------------------------------------------------------
    -- 4. RSA 篡改签名应验签失败
    -- --------------------------------------------------------
    if rsa_sig then
        local bad_sig = rsa_sig:sub(1, #rsa_sig - 1) .. string.char((rsa_sig:byte(#rsa_sig) ~ 0xFF))
        local bad_ok = crypto.pk_verify(crypto.MD_SHA256, hash, RSA_PUB, bad_sig)
        check("rsa_verify_tampered_fail", bad_ok == false)
    end

    -- --------------------------------------------------------
    -- 5. RSA: 不同数据的签名不能验证另一份数据
    -- --------------------------------------------------------
    local hash2 = crypto.sha256("different data"):fromHex()
    if rsa_sig then
        local mismatch_ok = crypto.pk_verify(crypto.MD_SHA256, hash2, RSA_PUB, rsa_sig)
        check("rsa_verify_wrong_data_fail", mismatch_ok == false)
    end

    -- --------------------------------------------------------
    -- 6. EC-SHA256 签名 + 验签
    -- --------------------------------------------------------
    local ec_hash = crypto.sha256(data):fromHex()
    local ec_sig  = crypto.pk_sign(crypto.MD_SHA256, ec_hash, EC_PRIV)
    check("ec_sign_ok",    ec_sig ~= nil)
    check("ec_sig_len_ok", ec_sig ~= nil and #ec_sig > 0)

    if ec_sig then
        local ok = crypto.pk_verify(crypto.MD_SHA256, ec_hash, EC_PUB, ec_sig)
        check("ec_verify_ok", ok == true)
    end

    -- --------------------------------------------------------
    -- 7. EC 篡改签名应验签失败
    -- --------------------------------------------------------
    if ec_sig then
        local bad_ec = ec_sig:sub(1, #ec_sig - 1) .. string.char((ec_sig:byte(#ec_sig) ~ 0xFF))
        local bad_ok = crypto.pk_verify(crypto.MD_SHA256, ec_hash, EC_PUB, bad_ec)
        check("ec_verify_tampered_fail", bad_ok == false)
    end

    -- --------------------------------------------------------
    -- 8. 错误密钥类型 (用 EC 公钥验证 RSA 签名) 应失败
    -- --------------------------------------------------------
    if rsa_sig then
        local cross_ok = crypto.pk_verify(crypto.MD_SHA256, hash, EC_PUB, rsa_sig)
        check("cross_key_verify_fail", cross_ok == false)
    end

    -- --------------------------------------------------------
    -- 9. 无效密钥数据应返回 nil / false
    -- --------------------------------------------------------
    local bad_sig2 = crypto.pk_sign(crypto.MD_SHA256, hash, "invalid key data")
    check("invalid_privkey_sign_nil", bad_sig2 == nil)

    local bad_vok = crypto.pk_verify(crypto.MD_SHA256, hash, "invalid key data", "sig")
    check("invalid_pubkey_verify_false", bad_vok == false)

    -- --------------------------------------------------------
    -- 10. pk_generate: API 存在性
    -- --------------------------------------------------------
    check("api_pk_generate_exists", type(crypto.pk_generate) == "function")

    -- --------------------------------------------------------
    -- 11. pk_generate: RSA-2048 密钥对生成
    -- --------------------------------------------------------
    local gen_rsa_priv, gen_rsa_pub = crypto.pk_generate("rsa", "2048")
    check("gen_rsa_priv_not_nil", gen_rsa_priv ~= nil)
    check("gen_rsa_pub_not_nil",  gen_rsa_pub  ~= nil)
    if gen_rsa_priv and gen_rsa_pub then
        check("gen_rsa_priv_pem",  gen_rsa_priv:find("PRIVATE KEY") ~= nil)
        check("gen_rsa_pub_pem",   gen_rsa_pub:find("PUBLIC KEY")   ~= nil)
        -- 验证生成的密钥可以正常签名/验签
        local gen_rsa_sig = crypto.pk_sign(crypto.MD_SHA256, hash, gen_rsa_priv)
        check("gen_rsa_sign_ok", gen_rsa_sig ~= nil)
        if gen_rsa_sig then
            local gen_rsa_ok = crypto.pk_verify(crypto.MD_SHA256, hash, gen_rsa_pub, gen_rsa_sig)
            check("gen_rsa_verify_ok", gen_rsa_ok == true)
        end
        -- 验证密钥类型
        local gen_rsa_type = crypto.pk_type(gen_rsa_pub)
        check("gen_rsa_pub_type_rsa", gen_rsa_type == "rsa")
    end

    -- --------------------------------------------------------
    -- 12. pk_generate: EC P-256 密钥对生成
    -- --------------------------------------------------------
    local gen_ec_priv, gen_ec_pub = crypto.pk_generate("ec", "P-256")
    check("gen_ec_priv_not_nil", gen_ec_priv ~= nil)
    check("gen_ec_pub_not_nil",  gen_ec_pub  ~= nil)
    if gen_ec_priv and gen_ec_pub then
        check("gen_ec_priv_pem", gen_ec_priv:find("PRIVATE KEY") ~= nil)
        check("gen_ec_pub_pem",  gen_ec_pub:find("PUBLIC KEY")   ~= nil)
        -- 验证生成的密钥可以正常签名/验签
        local gen_ec_sig = crypto.pk_sign(crypto.MD_SHA256, ec_hash, gen_ec_priv)
        check("gen_ec_sign_ok", gen_ec_sig ~= nil)
        if gen_ec_sig then
            local gen_ec_ok = crypto.pk_verify(crypto.MD_SHA256, ec_hash, gen_ec_pub, gen_ec_sig)
            check("gen_ec_verify_ok", gen_ec_ok == true)
        end
        -- 验证密钥类型
        local gen_ec_type = crypto.pk_type(gen_ec_pub)
        check("gen_ec_pub_type_ec", gen_ec_type == "ec")
    end

    -- --------------------------------------------------------
    -- 13. pk_generate: 默认参数 (ec 不指定曲线)
    -- --------------------------------------------------------
    local gen_ec2_priv, gen_ec2_pub = crypto.pk_generate("ec")
    check("gen_ec_default_priv", gen_ec2_priv ~= nil)
    check("gen_ec_default_pub",  gen_ec2_pub  ~= nil)

    -- --------------------------------------------------------
    -- 14. pk_generate: 无效密钥类型返回 nil
    -- --------------------------------------------------------
    local bad_priv, bad_pub = crypto.pk_generate("dsa")
    check("gen_invalid_type_nil", bad_priv == nil and bad_pub == nil)

    -- --------------------------------------------------------
    -- 汇总
    -- --------------------------------------------------------
    log.info("============================")
    log.info("pk_sign test", string.format("PASS=%d  FAIL=%d", PASS, FAIL))
    if FAIL == 0 then
        log.info("Result", "ALL PASS")
    else
        log.error("Result", "SOME TESTS FAILED")
    end

end)

sys.run()
