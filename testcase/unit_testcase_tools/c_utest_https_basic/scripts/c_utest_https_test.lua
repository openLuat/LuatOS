local t = {}

local https_suite = {}

function https_suite.test_https_utest_external_qq()
    assert(http and type(http.utest) == "function", "http.utest 不存在")
    assert(http.utest("https_external_qq") == true, "http.utest(https_external_qq) 应为 true")
end

t.https_suite = https_suite

return t
