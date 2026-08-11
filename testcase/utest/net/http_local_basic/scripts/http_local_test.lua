local t = {}

local http_local_suite = {}

function http_local_suite.test_http_local_get()
    assert(http and type(http.utest) == "function", "http.utest 不存在")
    assert(http.utest("http_local_get") == true, "http_local_get 失败")
end

function http_local_suite.test_http_local_get_json()
    assert(http.utest("http_local_get_json") == true, "http_local_get_json 失败")
end

function http_local_suite.test_http_local_post_echo()
    assert(http.utest("http_local_post_echo") == true, "http_local_post_echo 失败")
end

function http_local_suite.test_http_local_status_404()
    assert(http.utest("http_local_status_404") == true, "http_local_status_404 失败")
end

function http_local_suite.test_http_local_status_500()
    assert(http.utest("http_local_status_500") == true, "http_local_status_500 失败")
end

function http_local_suite.test_http_local_status_301()
    assert(http.utest("http_local_status_301") == true, "http_local_status_301 失败")
end

function http_local_suite.test_http_local_large_body()
    assert(http.utest("http_local_large_body") == true, "http_local_large_body 失败")
end

function http_local_suite.test_http_local_headers()
    assert(http.utest("http_local_headers") == true, "http_local_headers 失败")
end

function http_local_suite.test_http_local_timeout()
    assert(http.utest("http_local_timeout") == true, "http_local_timeout 失败")
end

function http_local_suite.test_http_local_server_drop()
    assert(http.utest("http_local_server_drop") == true, "http_local_server_drop 失败")
end

function http_local_suite.test_http_local_malformed()
    assert(http.utest("http_local_malformed") == true, "http_local_malformed 失败")
end

function http_local_suite.test_http_local_connect_refused()
    assert(http.utest("http_local_connect_refused") == true, "http_local_connect_refused 失败")
end

function http_local_suite.test_http_local_concurrent()
    assert(http.utest("http_local_concurrent") == true, "http_local_concurrent 失败")
end

function http_local_suite.test_http_local_stress_loop()
    assert(http.utest("http_local_stress_loop") == true, "http_local_stress_loop 失败")
end

t.http_local_suite = http_local_suite

return t
