local t = {}

local tcp_suite = {}

function tcp_suite.test_tcp_utest_external_qq()
    assert(socket and type(socket.utest) == "function", "socket.utest 不存在")
    assert(socket.utest("tcp_external_qq") == true, "socket.utest(tcp_external_qq) 应为 true")
end

t.tcp_suite = tcp_suite

return t
