--[[
AirLink raw ping/pong loopback 测试

测试条件: PC 模拟器, LUAT_USE_AIRLINK_LOOPBACK 已启用
测试内容:
  1. airlink.ping API 存在
  2. loopback 下 ping "hello" 能收到正确的回显和 RTT
  3. 空 payload ping 正常回显
  4. 极短 timeout 导致超时, 结果携带 ok=false
--]]

local ping_tests = {}

local TAG = "ping_test"

-- LuatOS 的 C 内置模块通过全局变量访问，不能用 require()
local airlink = _G.airlink

-- 由于 pairs() 不保证顺序, 使用 setUp 在每次测试前确保 loopback 已启动 (幂等)
local _loopback_started = false
function ping_tests.setUp()
    if airlink and not _loopback_started then
        airlink.start(airlink.MODE_LOOPBACK)
        sys.wait(300)
        _loopback_started = true
    end
end

-- 测试: airlink.ping 函数存在
function ping_tests.test_01_module_has_ping_api()
    assert(airlink ~= nil, "airlink 全局变量不存在 (C 模块未编译?)")
    assert(type(airlink.ping) == "function", "airlink.ping 不存在")
    assert(type(airlink.MODE_LOOPBACK) == "number", "airlink.MODE_LOOPBACK 不存在")
    log.info(TAG, "模块 API 检查通过")
end

-- 测试: loopback ping "hello" 能正确回显
function ping_tests.test_02_loopback_ping_roundtrip()
    if airlink == nil then
        assert(true)
        return
    end

    local got = nil
    local h = sys.subscribe("AIRLINK_PING_RESULT", function(id, ok, v1, v2)
        got = {id = id, ok = ok, v1 = v1, v2 = v2}
        sys.publish("PING_TEST_02_DONE")
    end)

    local reqid = airlink.ping("hello", 3000)
    assert(type(reqid) == "number", "request_id 非数字: " .. type(reqid))

    assert(sys.waitUntil("PING_TEST_02_DONE", 3500), "超时未收到 AIRLINK_PING_RESULT")
    sys.unsubscribe(h)

    assert(got ~= nil, "got 为 nil")
    assert(got.id == reqid, string.format("request_id 不匹配 got=%s want=%s", tostring(got.id), tostring(reqid)))
    assert(got.ok == true, "ping 应成功, ok=" .. tostring(got.ok) .. " v1=" .. tostring(got.v1))
    assert(type(got.v1) == "number" and got.v1 >= 0, "RTT 非法: " .. tostring(got.v1))
    assert(got.v2 == "hello", "回显不匹配: " .. tostring(got.v2))

    log.info(TAG, string.format("ping 成功 rtt=%dms echo=%s", got.v1, got.v2))
end

-- 测试: 空 payload ping 正常回显
function ping_tests.test_03_empty_payload_roundtrip()
    if airlink == nil then
        assert(true)
        return
    end

    local got = nil
    local h = sys.subscribe("AIRLINK_PING_RESULT", function(id, ok, v1, v2)
        got = {ok = ok, v1 = v1, v2 = v2}
        sys.publish("PING_TEST_03_DONE")
    end)

    airlink.ping("", 3000)
    assert(sys.waitUntil("PING_TEST_03_DONE", 3500), "超时未收到空 payload 结果")
    sys.unsubscribe(h)

    assert(got ~= nil, "got 为 nil")
    assert(got.ok == true, "空 payload ping 应成功")
    assert(got.v2 == "", "空 payload 回显不匹配: " .. tostring(got.v2))

    log.info(TAG, "空 payload ping 通过")
end

-- 测试: 极短超时应触发超时失败
function ping_tests.test_04_timeout()
    if airlink == nil then
        assert(true)
        return
    end

    local got = nil
    local h = sys.subscribe("AIRLINK_PING_RESULT", function(id, ok, v1, v2)
        got = {ok = ok, v1 = v1}
        sys.publish("PING_TEST_04_DONE")
    end)

    -- 1ms timeout: loopback 来不及回复
    airlink.ping("timeout_test", 1)
    assert(sys.waitUntil("PING_TEST_04_DONE", 2000), "超时测试未收到结果事件")
    sys.unsubscribe(h)

    assert(got ~= nil, "got 为 nil")
    assert(got.ok == false, "期望 ping 超时失败, ok=" .. tostring(got.ok))
    assert(got.v1 == "timeout", "期望 v1='timeout', got=" .. tostring(got.v1))

    log.info(TAG, "超时失败路径测试通过")
end

return ping_tests
