local t = {}

local pack_suite = {}
function pack_suite.test_pack_utest_basic()
    assert(pack and type(pack.utest) == "function", "pack.utest 不存在")
    assert(pack.utest("pack_unpack_basic") == true, "pack.utest(pack_unpack_basic) 应为 true")
end

local crypto_suite = {}
function crypto_suite.test_crypto_utest_sha1()
    assert(crypto and type(crypto.utest) == "function", "crypto.utest 不存在")
    assert(crypto.utest("sha1_known_vector") == true, "crypto.utest(sha1_known_vector) 应为 true")
end

local zbuff_suite = {}
function zbuff_suite.test_zbuff_utest_rw_u8()
    assert(zbuff and type(zbuff.utest) == "function", "zbuff.utest 不存在")
    assert(zbuff.utest("rw_u8_basic") == true, "zbuff.utest(rw_u8_basic) 应为 true")
end

t.pack_suite = pack_suite
t.crypto_suite = crypto_suite
t.zbuff_suite = zbuff_suite

return t
