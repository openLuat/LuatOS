local miniz_test = {}

local miniz_suite = {}

-- 逐一调用所有 C 层测试用例
local all_cases = {
    "compress_decompress_basic",
    "compress_decompress_empty",
    "compress_decompress_single_byte",
    "compress_decompress_binary",
    "compress_decompress_repeated",
    "compress_decompress_raw",
    "compress_adler32",
    "compress_raw_blocks",
    "compress_static_blocks",
    "compress_greedy",
    "compress_nondeterministic",
    "compress_rle",
    "compress_filter_matches",
    "compress_combined_flags",
    "decompress_invalid_data",
    "compress_1byte",
    "compress_2bytes",
    "compress_8k",
    "compress_32k",
    "compress_ratio_greedy",
    "compress_tiny_raw",
    "compress_lorem",
}

-- 每个 C 用例生成一个 Lua 测试函数
for _, case_name in ipairs(all_cases) do
    local test_fn_name = "test_miniz_utest_" .. case_name
    miniz_suite[test_fn_name] = (function(cn)
        return function()
            assert(miniz and type(miniz.utest) == "function", "miniz.utest 不存在")
            local ok = miniz.utest(cn)
            assert(ok == true, string.format("miniz.utest(%s) 应返回 true, 实际返回 %s", cn, tostring(ok)))
        end
    end)(case_name)
end

miniz_test.miniz_suite = miniz_suite

return miniz_test
