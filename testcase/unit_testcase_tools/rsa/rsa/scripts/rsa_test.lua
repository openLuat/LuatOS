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

    local pub_pem = io.readFile(PUB_KEY_PATH)
    local pri_pem = io.readFile(PRIV_KEY_PATH)

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

    local pub_pem = io.readFile(PUB_KEY_PATH)
    local pri_pem = io.readFile(PRIV_KEY_PATH)

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

    local pub_pem = io.readFile(PUB_KEY_PATH)
    local pri_pem = io.readFile(PRIV_KEY_PATH)

    local hash_ok = crypto.sha1("1234567890"):fromHex()
    local sig = rsa.sign(pri_pem, rsa.MD_SHA1, hash_ok, "")

    local hash_bad = crypto.sha1("1234567899"):fromHex()
    local ok = rsa.verify(pub_pem, rsa.MD_SHA1, hash_bad, sig)
    assert(ok == false, "RSA 验签应失败，但返回了 true")
end

return rsa_test
