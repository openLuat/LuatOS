-- sms 模块 C 层 utest 的 Lua 入口
-- 真实用例在 components/utest/sms/luat_sms_utest.c, 需以 LUAT_USE_UTEST=y 构建 PC 模拟器
local sms_test = {}

local sms_suite = {}

local all_cases = {
    "ucs2_encode_basic",    -- ASCII / 3字节中文基线
    "ucs2_encode_2byte",    -- 2字节 UTF-8(C2B7/C3A9/西里尔/希腊), 历史 bug 所在
    "ucs2_encode_dots",     -- 。U+3002 / ．U+FF0E / · U+00B7
    "ucs2_encode_mixed",    -- 1/2/3 字节混排不错位
    "ucs2_encode_invalid",  -- 截断/非法/4字节/缓冲区不足必须失败
    "ucs2_encode_empty",    -- 空串合法
    "ucs2_roundtrip",       -- 编码后解码必须还原原文
}

for _, case_name in ipairs(all_cases) do
    sms_suite["test_sms_utest_" .. case_name] = (function(cn)
        return function()
            assert(sms and type(sms.utest) == "function", "sms.utest 不存在(需 LUAT_USE_UTEST=y 构建)")
            local ok = sms.utest(cn)
            assert(ok == true, string.format("sms.utest(%s) 应返回 true, 实际返回 %s", cn, tostring(ok)))
        end
    end)(case_name)
end

sms_test.sms_suite = sms_suite

return sms_test
