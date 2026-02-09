local hzfont_tests = {}

function hzfont_tests.test_hzfontinit_default()
    local result = hzfont.init(nil, hzfont.HZFONT_CACHE_256, true)
    assert(type(result) == "boolean", "返回值类型错误应为bplean型")
    assert(result == true, "合宙字库首次初始化失败")
end


function hzfont_tests.test_hzfontinit_second()
    local result = hzfont.init(nil, hzfont.HZFONT_CACHE_512, true)
    assert(type(result) == "boolean", "返回值类型错误应为bplean型")
    assert(result == false, "合宙字库已初始化不可进行二次初始化")
end
return hzfont_tests
