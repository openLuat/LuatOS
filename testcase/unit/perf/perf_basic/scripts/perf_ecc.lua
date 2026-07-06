-- ECDSA P-256 签名/验签性能测试（代替 ed25519，因固件通用 ECC 接口为 ECDSA）
-- 依赖：crypto.pk_generate / crypto.pk_sign / crypto.pk_verify
-- 无相关接口则跳过

local M = {}
local helper = require("perf_helper")

local ITERS_SIGN   = 10
local ITERS_VERIFY = 10

local _priv_pem = nil
local _pub_pem  = nil
local _sig_cache = nil
local _hash_cache = nil

-- 检查 pk 系列 API 是否可用
local function check_pk_available()
    if not crypto then
        log.warn("perf_ecc", "crypto 库不可用，跳过 ECC 性能测试")
        return false
    end
    if type(crypto.pk_generate) ~= "function" then
        log.warn("perf_ecc", "crypto.pk_generate 不可用（可能为精简固件），跳过 ECC 性能测试")
        return false
    end
    return true
end

-- 生成 P-256 密钥对（只在首次调用时生成）
local function ensure_keypair()
    if _priv_pem and _pub_pem then return true end
    local t0 = mcu.ticks()
    _priv_pem, _pub_pem = crypto.pk_generate("ec", "P-256")
    local elapsed = mcu.ticks() - t0
    if not _priv_pem or not _pub_pem then
        log.warn("perf_ecc", "P-256 密钥生成失败，跳过 ECC 性能测试")
        return false
    end
    log.info("perf", string.format("[ECC P-256 keygen] 生成耗时 %dms", elapsed))
    return true
end

function M.test_perf_ecc_sign()
    if not check_pk_available() then return end
    if not ensure_keypair() then return end
    helper.section("ECDSA P-256 SHA256 签名")
    _hash_cache = crypto.sha256("LuatOS ECC perf benchmark"):fromHex()
    assert(_hash_cache and #_hash_cache == 32, "SHA256 应为 32 字节")
    helper.measure("ECDSA P-256 sign", function()
        local sig = crypto.pk_sign(crypto.MD_SHA256, _hash_cache, _priv_pem)
        assert(sig and #sig > 0, "ECDSA 签名失败")
        _sig_cache = sig
    end, ITERS_SIGN)
end

function M.test_perf_ecc_verify()
    if not check_pk_available() then return end
    if not ensure_keypair() then return end
    if not _sig_cache then
        -- 如果签名测试没有先跑，先生成一次签名
        _hash_cache = crypto.sha256("LuatOS ECC perf benchmark"):fromHex()
        _sig_cache = crypto.pk_sign(crypto.MD_SHA256, _hash_cache, _priv_pem)
        assert(_sig_cache and #_sig_cache > 0, "初始签名失败，无法进行验签测试")
    end
    helper.section("ECDSA P-256 SHA256 验签")
    helper.measure("ECDSA P-256 verify", function()
        local ok = crypto.pk_verify(crypto.MD_SHA256, _hash_cache, _pub_pem, _sig_cache)
        assert(ok == true, "ECDSA 验签失败")
    end, ITERS_VERIFY)
end

return M
