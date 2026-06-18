local t = {}

local dtls_suite = {}

-- Pre-existing: PSK loopback.
function dtls_suite.test_dtls_utest_loopback_psk()
    assert(socket and type(socket.utest) == "function", "socket.utest 不存在")
    assert(socket.utest("dtls_loopback_psk") == true, "socket.utest(dtls_loopback_psk) 应为 true")
end

-- 1) One-way cert: client uses CA to verify server cert. Handshake + echo.
function dtls_suite.test_dtls_utest_loopback_cert()
    assert(socket and type(socket.utest) == "function", "socket.utest 不存在")
    assert(socket.utest("dtls_loopback_cert") == true,
        "socket.utest(dtls_loopback_cert) 应为 true")
end

-- 2) CA mismatch: server cert is signed by a different CA. Handshake must fail.
function dtls_suite.test_dtls_utest_loopback_cert_mismatch()
    assert(socket and type(socket.utest) == "function", "socket.utest 不存在")
    assert(socket.utest("dtls_loopback_cert_mismatch") == true,
        "socket.utest(dtls_loopback_cert_mismatch) 应为 true")
end

-- 3) mTLS: helper requires client cert + key, client must present them.
function dtls_suite.test_dtls_utest_loopback_mtls()
    assert(socket and type(socket.utest) == "function", "socket.utest 不存在")
    assert(socket.utest("dtls_loopback_mtls") == true,
        "socket.utest(dtls_loopback_mtls) 应为 true")
end

-- 4) Cert parse boundary: bad PEM strings must not be silently accepted.
function dtls_suite.test_dtls_utest_cert_parse_boundary()
    assert(socket and type(socket.utest) == "function", "socket.utest 不存在")
    assert(socket.utest("dtls_cert_parse_boundary") == true,
        "socket.utest(dtls_cert_parse_boundary) 应为 true")
end

t.dtls_suite = dtls_suite

return t
