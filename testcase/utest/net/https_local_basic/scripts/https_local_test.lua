local t = {}

local https_local_suite = {}

function https_local_suite.test_https_local_get()
    assert(http and type(http.utest) == "function", "http.utest 不存在")
    assert(http.utest("https_local_get") == true, "https_local_get 失败")
end

function https_local_suite.test_https_local_get_json()
    assert(http.utest("https_local_get_json") == true, "https_local_get_json 失败")
end

function https_local_suite.test_https_local_post_echo()
    assert(http.utest("https_local_post_echo") == true, "https_local_post_echo 失败")
end

function https_local_suite.test_https_local_large_body()
    assert(http.utest("https_local_large_body") == true, "https_local_large_body 失败")
end

function https_local_suite.test_https_local_timeout()
    assert(http.utest("https_local_timeout") == true, "https_local_timeout 失败")
end

function https_local_suite.test_https_local_cert_mismatch()
    assert(http.utest("https_local_cert_mismatch") == true, "https_local_cert_mismatch 失败")
end

function https_local_suite.test_https_local_concurrent()
    assert(http.utest("https_local_concurrent") == true, "https_local_concurrent 失败")
end

function https_local_suite.test_https_local_stress_loop()
    assert(http.utest("https_local_stress_loop") == true, "https_local_stress_loop 失败")
end

t.https_local_suite = https_local_suite

return t
