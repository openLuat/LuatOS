local c_utest_crypto_test = {}

local cjson_suite = {}
function cjson_suite.test_cjson_utest_encode_decode_basic()
    assert(json and type(json.utest) == "function", "json.utest 不存在")
    local ok = json.utest("encode_decode_basic")
    assert(ok == true, "json.utest(encode_decode_basic) 应返回 true")
end

local rsa_suite = {}
function rsa_suite.test_rsa_utest_invalid_pem_encrypt()
    assert(rsa and type(rsa.utest) == "function", "rsa.utest 不存在")
    local ok = rsa.utest("invalid_pem_encrypt")
    assert(ok == true, "rsa.utest(invalid_pem_encrypt) 应返回 true")
end

local gmssl_suite = {}
function gmssl_suite.test_gmssl_utest_sm3_known_vector()
    assert(gmssl and type(gmssl.utest) == "function", "gmssl.utest 不存在")
    local ok = gmssl.utest("sm3_known_vector")
    assert(ok == true, "gmssl.utest(sm3_known_vector) 应返回 true")
end

c_utest_crypto_test.cjson_suite = cjson_suite
c_utest_crypto_test.rsa_suite = rsa_suite
c_utest_crypto_test.gmssl_suite = gmssl_suite

return c_utest_crypto_test
