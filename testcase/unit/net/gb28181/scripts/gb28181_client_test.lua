--[[
exgb28181client.lua 的单元测试（里程碑 2.7）。

本文件只测**不依赖真实平台**的部分：
  - start() 的参数校验(纯逻辑，失败时不会真的发起网络)
  - start/stop/is_registered/on 的接口契约
  - 状态机的初始状态与幂等性

完整注册流程(REGISTER → 401 → 摘要 → 200 OK → 心跳)需要真实平台，
属联调而非单测，见 tests/tools/gb_platform_probe.py 与 C 层的
test_platform_vectors.c。

注意：client 是模块级单例，用例间会互相影响。因此每个用例开头先
stop() 归零状态，保证与执行顺序无关（testrunner 用 pairs 遍历）。
]]

local client = require("exgb28181client")

local t = {}

-- 哨兵：用于把基准配置里的某字段显式删除。
-- 不能直接写 { server_addr = nil } —— 在 Lua 中给表键赋 nil 等于删除该键，
-- pairs() 不会遍历到它，覆盖也就不会发生，用例会静默地用到基准值。
local REMOVE = {}

-- 一份合法的基准配置；服务器地址指向一个不会有人应答的端口，
-- 这样 start() 能成功建立 UDP socket 但不会真的完成注册
local function base_opts(overrides)
    local o = {
        server_addr = "127.0.0.1",
        server_port = 1,             -- 无人监听
        domain      = "3502000000",
        device_id   = "35020000001320000001",
        password    = "test_password",
        transport   = "udp",
        local_port  = 5099,
        keepalive   = 0,             -- 测试中关掉心跳
        expires     = 300,
    }
    if overrides then
        for k, v in pairs(overrides) do
            if v == REMOVE then o[k] = nil else o[k] = v end
        end
    end
    return o
end

-- 每个用例开头归零，避免单例状态串扰
local function reset()
    client.stop()
end

--[[ device_id 必须是 20 位国标编码 ]]
function t.test_start_rejects_invalid_device_id()
    reset()
    local cases = {
        { name = "nil",      v = REMOVE },
        { name = "非字符串", v = 35020000001320000001 },
        { name = "过短",     v = "3502000000132000000" },    -- 19 位
        { name = "过长",     v = "350200000013200000011" },  -- 21 位
        { name = "含字母",   v = "3502000000132000000a" },
    }
    for _, c in ipairs(cases) do
        local ok, err = client.start(base_opts({ device_id = c.v }))
        assert(ok == false, "device_id 为" .. c.name .. "时应被拒")
        assert(type(err) == "string", "应给出失败原因")
    end
    reset()
end

--[[ server_addr 必填 ]]
function t.test_start_rejects_missing_server()
    reset()
    local o = base_opts()
    o.server_addr = nil
    local ok, err = client.start(o)
    assert(ok == false, "缺 server_addr 应被拒")
    assert(type(err) == "string")

    o = base_opts({ server_addr = "" })
    ok, err = client.start(o)
    assert(ok == false, "server_addr 为空串应被拒")
    reset()
end

--[[ opts 必须是 table ]]
function t.test_start_rejects_non_table()
    reset()
    local ok, err = client.start("not a table")
    assert(ok == false, "opts 非 table 应被拒")
    assert(type(err) == "string")
    ok, err = client.start(nil)
    assert(ok == false, "opts 为 nil 应被拒")
    reset()
end

--[[ 合法配置应能启动；启动后未注册前 is_registered() 必须为 false ]]
function t.test_start_succeeds_and_is_not_registered_yet()
    reset()
    local ok, err = client.start(base_opts())
    assert(ok == true, "合法配置应能启动, 实际失败: " .. tostring(err))
    assert(client.is_registered() == false,
           "刚启动、尚未与平台完成注册时应为 false")
    reset()
end

--[[ 重复 start 应被拒(单实例) ]]
function t.test_start_twice_is_rejected()
    reset()
    assert(client.start(base_opts()) == true, "首次启动应成功")
    local ok, err = client.start(base_opts())
    assert(ok == false, "重复启动应被拒")
    assert(type(err) == "string")
    reset()
end

--[[ stop 应幂等 ]]
function t.test_stop_is_idempotent()
    reset()
    assert(client.stop() == true, "未启动时 stop 应返回 true")
    assert(client.stop() == true, "重复 stop 应返回 true")
end

--[[ 停止后应能再次启动 ]]
function t.test_restart_after_stop()
    reset()
    assert(client.start(base_opts()) == true)
    assert(client.stop() == true)
    assert(client.start(base_opts()) == true, "停止后应能重新启动")
    reset()
end

--[[ on() 只接受函数或 nil ]]
function t.test_on_accepts_function_and_nil()
    reset()
    assert(client.on(function() end) == true, "on(function) 应返回 true")
    assert(client.on(nil) == true, "on(nil) 应返回 true(取消注册)")
    assert(client.on(123) == false, "on(123) 应返回 false")
    assert(client.on("x") == false, "on(字符串) 应返回 false")
    assert(client.on({}) == false, "on(table) 应返回 false")
    reset()
end

--[[ 未注册时手动心跳应被拒(否则会向平台发无意义的心跳) ]]
function t.test_keepalive_requires_registered()
    reset()
    assert(client.keepalive() == false, "未注册时 keepalive() 应返回 false")

    client.start(base_opts())
    assert(client.keepalive() == false,
           "启动了但未注册成功时 keepalive() 仍应返回 false")
    reset()
end

--[[ 回调异常不应影响状态机(注册的回调里抛错也不能让 client 崩掉) ]]
function t.test_callback_error_is_contained()
    reset()
    client.on(function() error("回调故意抛出的异常") end)
    local ok = client.start(base_opts())
    assert(ok == true, "回调有异常不应影响启动")
    reset()
    client.on(nil)
end

return t
