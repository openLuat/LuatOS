-- 哈希算法性能测试：MD5 / SHA1 / SHA256 / SHA512
-- 依赖：crypto（通常始终内置），无则跳过

local M = {}
local helper = require("perf_helper")

local DATA_1KB = string.rep("A", 1024)
local ITERS    = 200  -- 每次 1KB，共 200 次 = 200KB

local function skip_if_no_crypto()
    if not crypto then
        log.warn("perf_hash", "crypto 库不可用，跳过哈希性能测试")
        return true
    end
    return false
end

function M.test_perf_md5()
    if skip_if_no_crypto() then return end
    helper.section("MD5 吞吐量")
    helper.measure("MD5", function() crypto.md5(DATA_1KB) end, ITERS, 1)
end

function M.test_perf_sha1()
    if skip_if_no_crypto() then return end
    helper.section("SHA1 吞吐量")
    helper.measure("SHA1", function() crypto.sha1(DATA_1KB) end, ITERS, 1)
end

function M.test_perf_sha256()
    if skip_if_no_crypto() then return end
    helper.section("SHA256 吞吐量")
    helper.measure("SHA256", function() crypto.sha256(DATA_1KB) end, ITERS, 1)
end

function M.test_perf_sha512()
    if skip_if_no_crypto() then return end
    helper.section("SHA512 吞吐量")
    helper.measure("SHA512", function() crypto.sha512(DATA_1KB) end, ITERS, 1)
end

-- AES-128-ECB 加密吞吐量（顺便测对称密码）
function M.test_perf_aes128_ecb_encrypt()
    if not crypto or not crypto.cipher_encrypt then
        log.warn("perf_hash", "cipher_encrypt 不可用，跳过 AES 测试")
        return
    end
    helper.section("AES-128-ECB 加密吞吐量")
    local key  = "0123456789012345"  -- 16 字节 AES-128 密钥
    helper.measure("AES-128-ECB", function()
        crypto.cipher_encrypt("AES-128-ECB", "PKCS7", DATA_1KB, key)
    end, ITERS, 1)
end

return M
