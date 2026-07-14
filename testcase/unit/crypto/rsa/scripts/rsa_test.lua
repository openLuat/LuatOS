-- RSA 测试用例集合
-- 说明：
-- - 该文件包含针对 RSA 的核心能力测试：加解密、签名与验签
-- - 测试使用的 PEM 密钥文件会随用例一并打包到设备的 /luadb 目录
-- - 所有测试均依赖已启用的 rsa 库组件
local rsa_test = {}

-- 公钥与私钥文件路径（打包后位于 /luadb）
-- 说明：路径与演示 demo 保持一致，便于复用示例资源或替换为自有密钥
local PUB_KEY_PATH = "/luadb/public.pem"
local PRIV_KEY_PATH = "/luadb/privkey.pem"

-- 预检：确认 rsa 库已启用
-- 失败行为：直接抛错，中止该测试用例
local function require_rsa()
    if not rsa then
        error("本用例需要 rsa 库，请启用 rsa 组件")
    end
end

-- 预检：确认 PEM 密钥文件存在
-- 失败行为：断言失败，提示缺失具体文件路径
local function ensure_keys_exist()
    assert(io.exists(PUB_KEY_PATH), "缺少公钥文件: " .. PUB_KEY_PATH)
    assert(io.exists(PRIV_KEY_PATH), "缺少私钥文件: " .. PRIV_KEY_PATH)
end

-- 获取有效的 PEM 密钥内容
local function get_valid_keys()
    return io.readFile(PUB_KEY_PATH), io.readFile(PRIV_KEY_PATH)
end

-- 测试：RSA 加密→解密一致性
-- 目标：验证使用公钥加密、私钥解密后得到的明文与输入一致
-- 步骤：
--   1) 读取公钥/私钥 PEM
--   2) 用公钥加密固定明文 "abc"
--   3) 用私钥解密密文，应与原明文完全一致
-- 断言：
--   - 加密返回非空密文
--   - 解密结果等于原始明文
function rsa_test.test_encrypt_decrypt()
    require_rsa()
    ensure_keys_exist()

    local pub_pem, pri_pem = get_valid_keys()

    local plaintext = "abc"
    local ciphertext = rsa.encrypt(pub_pem, plaintext)

    assert(ciphertext and #ciphertext > 0, "RSA 加密失败，未得到密文")

    local decrypted = rsa.decrypt(pri_pem, ciphertext, "")
    assert(decrypted == plaintext, string.format("RSA 解密不一致: 预期 %s, 实际 %s", plaintext, tostring(decrypted)))
end

-- 测试：RSA 签名/验签（SHA1）
-- 目标：验证使用私钥对 SHA1 摘要进行签名，公钥验签为真
-- 步骤：
--   1) 计算字符串 "1234567890" 的 SHA1 摘要（十六进制→二进制）
--   2) 私钥对摘要进行签名
--   3) 公钥对签名进行验签
-- 断言：
--   - 生成的签名非空
--   - 验签返回 true
function rsa_test.test_sign_verify_sha1()
    require_rsa()
    ensure_keys_exist()

    local pub_pem, pri_pem = get_valid_keys()

    local hash = crypto.sha1("1234567890"):fromHex()
    local sig = rsa.sign(pri_pem, rsa.MD_SHA1, hash, "")
    assert(sig and #sig > 0, "RSA 签名失败，未得到签名数据")

    local ok = rsa.verify(pub_pem, rsa.MD_SHA1, hash, sig)
    assert(ok == true, "RSA 验签失败，应为 true")
end

-- 测试：验签应失败（摘要不一致）
-- 目标：当验签所用摘要不同于签名时，验签应返回 false
-- 步骤：
--   1) 计算 "1234567890" 的 SHA1 摘要并签名
--   2) 计算不同字符串 "1234567899" 的 SHA1 摘要
--   3) 使用公钥对“不同摘要 + 原签名”进行验签
-- 断言：
--   - 验签返回 false
function rsa_test.test_verify_should_fail_when_hash_differs()
    require_rsa()
    ensure_keys_exist()

    local pub_pem, pri_pem = get_valid_keys()

    local hash_ok = crypto.sha1("1234567890"):fromHex()
    local sig = rsa.sign(pri_pem, rsa.MD_SHA1, hash_ok, "")

    local hash_bad = crypto.sha1("1234567899"):fromHex()
    local ok = rsa.verify(pub_pem, rsa.MD_SHA1, hash_bad, sig)
    assert(ok == false, "RSA 验签应失败，但返回了 true")
end

-- ============================================================
-- 错误参数测试用例
-- 说明：测试当传入不符合要求的参数时函数的行为
--       只测试那些能安全返回 nil/false 的场景
-- ============================================================

-- 测试：rsa.encrypt 使用无效 PEM 字符串
-- 目标：传入无效的 PEM 字符串时，应返回 nil
function rsa_test.test_encrypt_invalid_pem()
    require_rsa()
    local plaintext = "abc"

    -- 测试 key 参数为无效 PEM 字符串
    local ret = rsa.encrypt("invalid pem key", plaintext)
    assert(ret == nil, "rsa.encrypt(无效PEM, data) 应返回 nil")

    -- 测试 key 参数为空字符串
    ret = rsa.encrypt("", plaintext)
    assert(ret == nil, "rsa.encrypt('', data) 应返回 nil")
end

-- 测试：rsa.encrypt 使用过长的数据
-- 目标：当待加密数据超过 RSA 密钥最大加密长度时，应返回 nil
-- 说明：对于 2048 位密钥，PKCS#1 v1.5 填充最大加密长度为 245 字节
function rsa_test.test_encrypt_data_too_long()
    require_rsa()
    ensure_keys_exist()
    local pub_pem = io.readFile(PUB_KEY_PATH)

    -- 获取密钥长度（通过尝试加密确定最大长度）
    -- 2048位密钥最大加密长度 = 256 - 11 = 245 字节
    -- 测试超过 245 字节的数据，例如 300 字节
    local long_data = string.rep("a", 300)
    local ret = rsa.encrypt(pub_pem, long_data)
    assert(ret == nil, "rsa.encrypt 超长数据应返回 nil")
end

-- 测试：rsa.decrypt 使用无效参数
-- 目标：传入无效 PEM、空数据、无效密文时，应返回 nil
function rsa_test.test_decrypt_invalid_params()
    require_rsa()
    ensure_keys_exist()
    local _, pri_pem = get_valid_keys()
    local plaintext = "abc"
    local ciphertext = rsa.encrypt(get_valid_keys(), plaintext)

    -- 确保密文有效，否则后续测试无意义
    assert(ciphertext and #ciphertext > 0, "加密失败，无法继续解密错误参数测试")

    -- 测试 key 参数为无效 PEM 字符串
    local ret = rsa.decrypt("invalid pem key", ciphertext, "")
    assert(ret == nil, "rsa.decrypt(无效PEM, data) 应返回 nil")

    -- 测试 key 参数为空字符串
    ret = rsa.decrypt("", ciphertext, "")
    assert(ret == nil, "rsa.decrypt('', data) 应返回 nil")

    -- 测试 data 参数为空字符串
    ret = rsa.decrypt(pri_pem, "", "")
    assert(ret == nil, "rsa.decrypt(key, '') 应返回 nil")

    -- 测试 data 参数为无效数据（随机字符串）
    ret = rsa.decrypt(pri_pem, "invalid ciphertext", "")
    assert(ret == nil, "rsa.decrypt(key, 无效密文) 应返回 nil")
end

-- 测试：rsa.sign 使用无效参数
-- 目标：传入无效 PEM、无效 md 模式、错误长度的 hash 时，应返回 nil
function rsa_test.test_sign_invalid_params()
    require_rsa()
    ensure_keys_exist()
    local _, pri_pem = get_valid_keys()
    
    -- 正确的 hash：20 字节的 SHA1 值
    local valid_hash = crypto.sha1("1234567890"):fromHex()
    assert(#valid_hash == 20, "SHA1 哈希应为 20 字节")

    -- 测试 key 参数为无效 PEM 字符串
    local ret = rsa.sign("invalid pem key", rsa.MD_SHA1, valid_hash, "")
    assert(ret == nil, "rsa.sign(无效PEM, md, hash) 应返回 nil")

    -- 测试 key 参数为空字符串
    ret = rsa.sign("", rsa.MD_SHA1, valid_hash, "")
    assert(ret == nil, "rsa.sign('', md, hash) 应返回 nil")

    -- 测试 md 参数为无效的签名模式（超出范围）
    ret = rsa.sign(pri_pem, 999, valid_hash, "")
    assert(ret == nil, "rsa.sign(key, 无效md, hash) 应返回 nil")

    -- 测试 hash 参数长度错误（太短，10 字节）
    local short_hash = string.rep("a", 10)
    ret = rsa.sign(pri_pem, rsa.MD_SHA1, short_hash, "")
    assert(ret == nil, "rsa.sign(key, md, 长度错误的hash) 应返回 nil")

    -- 测试 hash 参数长度错误（太长，30 字节）
    local long_hash = string.rep("a", 30)
    ret = rsa.sign(pri_pem, rsa.MD_SHA1, long_hash, "")
    assert(ret == nil, "rsa.sign(key, md, 长度错误的hash) 应返回 nil")

    -- 测试 hash 参数为无效数据（随机字符串，长度正确但内容无效）
    local invalid_hash = string.rep("x", 20)
    ret = rsa.sign(pri_pem, rsa.MD_SHA1, invalid_hash, "")
    -- 对于无效的哈希内容，签名可能会成功（只是对随机数据签名），也可能失败
    -- 这里不强制断言，因为 mbedtls 可能会成功签名随机数据
    if ret ~= nil then
        -- 如果签名成功，至少应该是非空字符串
        assert(#ret > 0, "签名结果不应为空")
    end
end

-- 测试：rsa.verify 使用无效参数
-- 目标：传入无效 PEM、无效 md 模式、错误长度的 hash、无效签名时，应返回 nil 或 false
function rsa_test.test_verify_invalid_params()
    require_rsa()
    ensure_keys_exist()
    local pub_pem, pri_pem = get_valid_keys()
    local valid_hash = crypto.sha1("1234567890"):fromHex()
    local sig = rsa.sign(pri_pem, rsa.MD_SHA1, valid_hash, "")
    assert(sig and #sig > 0, "签名失败，无法继续验签错误参数测试")

    -- 测试 key 参数为无效 PEM 字符串
    local ret = rsa.verify("invalid pem key", rsa.MD_SHA1, valid_hash, sig)
    assert(ret == nil, "rsa.verify(无效PEM, md, hash, sig) 应返回 nil")

    -- 测试 key 参数为空字符串
    ret = rsa.verify("", rsa.MD_SHA1, valid_hash, sig)
    assert(ret == nil, "rsa.verify('', md, hash, sig) 应返回 nil")

    -- 测试 md 参数为无效的签名模式（超出范围）
    ret = rsa.verify(pub_pem, 999, valid_hash, sig)
    assert(ret == false, "rsa.verify(key, 无效md, hash, sig) 应返回 false")

    -- 测试 hash 参数长度错误（太短）
    local short_hash = string.rep("a", 10)
    ret = rsa.verify(pub_pem, rsa.MD_SHA1, short_hash, sig)
    assert(ret == false, "rsa.verify(key, md, 长度错误hash, sig) 应返回 false")

    -- 测试 hash 参数长度错误（太长）
    local long_hash = string.rep("a", 30)
    ret = rsa.verify(pub_pem, rsa.MD_SHA1, long_hash, sig)
    assert(ret == false, "rsa.verify(key, md, 长度错误hash, sig) 应返回 false")

    -- 测试 hash 参数为无效数据（随机字符串）
    local invalid_hash = string.rep("x", 20)
    ret = rsa.verify(pub_pem, rsa.MD_SHA1, invalid_hash, sig)
    assert(ret == false, "rsa.verify(key, md, 无效hash, sig) 应返回 false")

    -- 测试 sig 参数为空字符串
    ret = rsa.verify(pub_pem, rsa.MD_SHA1, valid_hash, "")
    assert(ret == false, "rsa.verify(key, md, hash, '') 应返回 false")

    -- 测试 sig 参数为无效签名数据
    ret = rsa.verify(pub_pem, rsa.MD_SHA1, valid_hash, "invalid signature")
    assert(ret == false, "rsa.verify(key, md, hash, 无效签名) 应返回 false")
end

return rsa_test