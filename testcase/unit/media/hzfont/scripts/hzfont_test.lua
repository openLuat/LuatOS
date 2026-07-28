local hzfont_tests = {}

function hzfont_tests.test_hzfontinit_default()
    local result = hzfont.init(nil, hzfont.HZFONT_CACHE_256, true)
    assert(type(result) == "boolean", "返回值类型错误应为boolean型")
    assert(result == true, "合宙字库首次初始化失败")

    -- hzfont.init 设计为幂等: 已初始化时直接复用并返回 true,
    -- 避免重复初始化导致缓存/堆损坏
    local second_result = hzfont.init(nil, hzfont.HZFONT_CACHE_512, true)
    assert(type(second_result) == "boolean", "返回值类型错误应为boolean型")
    assert(second_result == true, "合宙字库二次初始化应幂等返回true")
end


return hzfont_tests
