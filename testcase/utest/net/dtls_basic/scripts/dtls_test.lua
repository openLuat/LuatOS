local t = {}

local dtls_suite = {}

function dtls_suite.test_dtls_utest_loopback_psk()
    assert(socket and type(socket.utest) == "function", "socket.utest 不存在")
    assert(socket.utest("dtls_loopback_psk") == true, "socket.utest(dtls_loopback_psk) 应为 true")
end

t.dtls_suite = dtls_suite

return t
