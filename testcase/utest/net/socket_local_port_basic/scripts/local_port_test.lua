-- socket.localPort 的行为契约：传 0 由底层挑端口时，挑中的那个必须能读回来。
-- 不需要外网（UDP connect 只做本地绑定）。runner 用 pairs 遍历，每个用例自建自销。

local t = {}

local local_port_suite = {}

local function new_sock()
    local c = socket.create(nil, function() end)
    assert(c ~= nil, "socket.create 失败")
    return c
end

-- 未绑定返回 nil（不是 0 —— 0 会被当成端口号用掉）
function local_port_suite.test_unbound_returns_nil()
    local c = new_sock()
    local p = socket.localPort(c)
    assert(p == nil, "未绑定时应返回 nil，实际 " .. tostring(p))
    socket.close(c)
end

-- 传 0 → 底层挑；connect 后要能读到
function local_port_suite.test_zero_port_is_readable_after_connect()
    local c = new_sock()
    assert(socket.config(c, 0, true), "socket.config(0) 失败")
    assert(socket.localPort(c) == nil, "还没 connect 就不该有端口")

    assert(socket.connect(c, "127.0.0.1", 9), "socket.connect 失败")
    local picked = socket.localPort(c)
    assert(type(picked) == "number" and picked > 0,
           "connect 后应能读到系统挑的端口，实际 " .. tostring(picked))
    socket.close(c)
end

-- 显式给的端口原样读回
function local_port_suite.test_explicit_port_is_kept()
    local c = new_sock()
    assert(socket.config(c, 52345, true), "socket.config(52345) 失败")
    assert(socket.connect(c, "127.0.0.1", 9), "socket.connect 失败")
    assert(socket.localPort(c) == 52345,
           "显式端口应原样读回，实际 " .. tostring(socket.localPort(c)))
    socket.close(c)
end

-- 两个 socket 读到不同端口
function local_port_suite.test_two_sockets_differ()
    local a, b = new_sock(), new_sock()
    assert(socket.config(a, 0, true) and socket.config(b, 0, true), "config 失败")
    assert(socket.connect(a, "127.0.0.1", 9) and socket.connect(b, "127.0.0.1", 9),
           "connect 失败")
    assert(socket.localPort(a) ~= socket.localPort(b),
           "两个 socket 不该读到同一个端口")
    socket.close(a)
    socket.close(b)
end

t.local_port_suite = local_port_suite

return t
