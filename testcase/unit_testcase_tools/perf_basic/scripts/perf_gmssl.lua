-- 国密算法性能测试：SM2 / SM3 / SM4
-- 依赖：gmssl 库，无则跳过
-- API 参考：components/gmssl/bind/luat_lib_gmssl.c

local M = {}
local helper = require("perf_helper")

-- SM2 测试向量（与 gmssl demo 保持一致）
-- 私钥/公钥均为 HEX 字符串（64字符 = 32字节）
-- originStr 为原始消息的二进制形式，sm2sign/sm2verify 内部会对其做 SM3 哈希
local SM2_PKX     = "ABE87C924B7ECFDEA1748A06E89003C9F7F4DC5C3563873CE2CAE46F66DE8141"
local SM2_PKY     = "9514733D38CC026F2452A6A3A3A4DA0C28F864AFA5FE2C45E0EB6B761FBB5286"
local SM2_PRIVKEY = "129EDC282CD2E9C1144C2E7315F926D772BC96600D2771E8BE02060313FE00D5"
local SM2_MSG     = string.fromHex("434477813974bf58f94bcf760833c2b40f77a5fc360485b0b9ed1bd9682edb45")

-- SM4 密钥：16字节字符串（sm4encrypt 要求 key 恰好 16 字节）
local SM4_KEY  = "1234567890123456"
local DATA_1KB = string.rep("B", 1024)

local ITERS_SM2 = 10
local ITERS_SM3 = 200
local ITERS_SM4 = 200

local function skip_if_no_gmssl()
    if not gmssl then
        log.warn("perf_gmssl", "gmssl 库不可用，跳过国密性能测试")
        return true
    end
    return false
end

function M.test_perf_sm2_sign()
    if skip_if_no_gmssl() then return end
    if type(gmssl.sm2sign) ~= "function" then
        log.warn("perf_gmssl", "gmssl.sm2sign 不可用，跳过 SM2 签名测试")
        return
    end
    helper.section("SM2 签名性能")
    -- sm2sign(private_hex, msg, id) → sig(64字节二进制)
    local sig = gmssl.sm2sign(SM2_PRIVKEY, SM2_MSG, nil)
    if not sig then
        log.warn("perf_gmssl", "SM2 签名预测试失败，跳过")
        return
    end
    helper.measure("SM2 sign", function()
        local s = gmssl.sm2sign(SM2_PRIVKEY, SM2_MSG, nil)
        assert(s, "SM2 签名失败")
    end, ITERS_SM2)
end

function M.test_perf_sm2_verify()
    if skip_if_no_gmssl() then return end
    if type(gmssl.sm2verify) ~= "function" then
        log.warn("perf_gmssl", "gmssl.sm2verify 不可用，跳过 SM2 验签测试")
        return
    end
    helper.section("SM2 验签性能")
    -- 先生成一个签名供验签复用
    local sig = gmssl.sm2sign(SM2_PRIVKEY, SM2_MSG, nil)
    if not sig then
        log.warn("perf_gmssl", "SM2 签名失败，无法测试验签")
        return
    end
    -- sm2verify(pkx_hex, pky_hex, msg, id, sig) → boolean
    helper.measure("SM2 verify", function()
        local ok = gmssl.sm2verify(SM2_PKX, SM2_PKY, SM2_MSG, nil, sig)
        assert(ok, "SM2 验签失败")
    end, ITERS_SM2)
end

function M.test_perf_sm3_hash()
    if skip_if_no_gmssl() then return end
    if type(gmssl.sm3) ~= "function" then
        log.warn("perf_gmssl", "gmssl.sm3 不可用，跳过 SM3 测试")
        return
    end
    helper.section("SM3 哈希吞吐量（1KB）")
    -- sm3(data) → 32字节二进制摘要
    local ok = pcall(gmssl.sm3, DATA_1KB)
    if not ok then
        log.warn("perf_gmssl", "gmssl.sm3 调用失败，跳过")
        return
    end
    helper.measure("SM3", function() gmssl.sm3(DATA_1KB) end, ITERS_SM3, 1)
end

function M.test_perf_sm4_ecb_encrypt()
    if skip_if_no_gmssl() then return end
    -- 正确 API：gmssl.sm4encrypt(mode, padding, data, key[, iv])
    -- mode: "ECB" 或 "CBC"；padding: "NONE"/"ZERO"/"PKCS5"/"PKCS7"；key: 恰好16字节
    if type(gmssl.sm4encrypt) ~= "function" then
        log.warn("perf_gmssl", "gmssl.sm4encrypt 不可用，跳过 SM4 加密测试")
        return
    end
    helper.section("SM4-ECB 加密吞吐量（1KB）")
    local ok, err = pcall(gmssl.sm4encrypt, "ECB", "PKCS5", DATA_1KB, SM4_KEY)
    if not ok then
        log.warn("perf_gmssl", "gmssl.sm4encrypt 调用失败: " .. tostring(err) .. "，跳过")
        return
    end
    helper.measure("SM4-ECB encrypt", function()
        gmssl.sm4encrypt("ECB", "PKCS5", DATA_1KB, SM4_KEY)
    end, ITERS_SM4, 1)
end

return M
