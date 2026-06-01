local t = {}

local http_suite = {}

function http_suite.test_http_utest_external_qq()
    assert(http and type(http.utest) == "function", "http.utest 不存在")
    assert(http.utest("http_external_qq") == true, "http.utest(http_external_qq) 应为 true")
end

t.http_suite = http_suite

return t
