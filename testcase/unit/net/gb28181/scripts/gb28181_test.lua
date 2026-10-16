--[[
GB28181 设备侧协议库(Lua 层 exgb28181.lua)单元测试。

注意：testrunner 通过 pairs() 遍历用例，执行顺序不确定，
因此每个用例都必须自己准备所需状态，不依赖其它用例的副作用。
]]

local exgb28181 = require("exgb28181")

local t = {}

-- 哨兵值：用于把基准配置里的某个字段显式删除。
-- 不能直接写 { device_id = nil } —— 在 Lua 中给表键赋 nil 等于删除该键，
-- pairs() 不会遍历到它，覆盖也就不会发生，测试会静默地用到基准值。
local REMOVE = {}

-- 一份合法的基准配置，各用例按需覆盖或删除字段
local function base_config(overrides)
    local c = {
        device_id       = "34020000001320000001",
        sip_server_addr = "192.168.1.100",
        sip_server_port = 5060,
        sip_password    = "12345678",
    }
    if overrides then
        for k, v in pairs(overrides) do
            if v == REMOVE then
                c[k] = nil
            else
                c[k] = v
            end
        end
    end
    return c
end

--[[
version() 应返回非空字符串。
C 层不可用时退化为 Lua 层版本号，因此只断言非空，不绑定具体值。
]]
function t.test_version_returns_non_empty_string()
    local v = exgb28181.version()
    assert(type(v) == "string", "version() 应返回字符串, 实际 " .. type(v))
    assert(#v > 0, "version() 不应返回空字符串")
end

--[[
has_core() 与 version() 的取值必须自洽。

这条不变量的价值在于覆盖 C 层的两条取用路径：
  - 真机/PC 模拟器上 C 模块存在 -> has_core() 为 true, version() 为 C 层版本
  - 纯 Lua 环境(如主机 lua 直接跑) -> has_core() 为 false, version() 带 "-lua" 后缀
无论哪种环境都必须自洽，从而捕获回退逻辑的回归。
]]
function t.test_core_probe_is_consistent_with_version()
    local has_core = exgb28181.has_core()
    local v = exgb28181.version()

    assert(type(has_core) == "boolean", "has_core() 应返回 boolean")

    if has_core then
        assert(v ~= "0.1.0-lua",
               "has_core() 为 true 时 version() 不应退化为 Lua 版本, 实际 " .. tostring(v))
    else
        assert(v == "0.1.0-lua",
               "has_core() 为 false 时 version() 应带 -lua 后缀, 实际 " .. tostring(v))
    end
end

--[[
on() 只接受函数或 nil(取消注册)。
]]
function t.test_on_rejects_non_function()
    assert(exgb28181.on(123) == false, "on(123) 应返回 false")
    assert(exgb28181.on("cb") == false, "on(\"cb\") 应返回 false")
    assert(exgb28181.on({}) == false, "on({}) 应返回 false")
end

--[[
on() 接受函数，且可用 nil 取消注册。
]]
function t.test_on_accepts_function_and_nil()
    assert(exgb28181.on(function() end) == true, "on(function) 应返回 true")
    assert(exgb28181.on(nil) == true, "on(nil) 应返回 true(取消注册)")
end

--[[
init() 对非 table 参数应返回 false 并给出原因。
]]
function t.test_init_rejects_non_table()
    local ok, err = exgb28181.init("not a table")
    assert(ok == false, "init(字符串) 应返回 false")
    assert(type(err) == "string" and #err > 0, "应返回失败原因字符串")
end

--[[
device_id 必须是 20 位数字，各类非法取值都应被拒绝。
]]
function t.test_init_rejects_invalid_device_id()
    local cases = {
        { name = "nil",     value = REMOVE },
        { name = "数字",    value = 34020000001320000001 },
        { name = "过短",    value = "3402000000132000000" },     -- 19 位
        { name = "过长",    value = "340200000013200000011" },   -- 21 位
        { name = "含字母",  value = "3402000000132000000a" },    -- 20 位但非数字
        { name = "空串",    value = "" },
    }
    for _, c in ipairs(cases) do
        local ok, err = exgb28181.init(base_config({ device_id = c.value }))
        assert(ok == false, "device_id 为" .. c.name .. "时应被拒绝")
        assert(type(err) == "string", "device_id 为" .. c.name .. "时应给出失败原因")
    end
end

--[[
sip_server_addr 必须是非空字符串。
]]
function t.test_init_rejects_missing_server()
    local ok, err = exgb28181.init(base_config({ sip_server_addr = REMOVE }))
    assert(ok == false, "缺少 sip_server_addr 时应被拒绝")
    assert(type(err) == "string", "应给出失败原因")

    ok, err = exgb28181.init(base_config({ sip_server_addr = "" }))
    assert(ok == false, "sip_server_addr 为空串时应被拒绝")
end

--[[
transport 只支持 udp / tcp，大小写不敏感，其它取值应被拒绝。
]]
function t.test_init_rejects_invalid_transport()
    local ok = exgb28181.init(base_config({ transport = "sctp" }))
    assert(ok == false, "transport=sctp 应被拒绝")

    ok = exgb28181.init(base_config({ transport = "tls" }))
    assert(ok == false, "transport=tls 应被拒绝")
end

--[[
local_port 必须是 1~65535 的合法端口。
]]
function t.test_init_rejects_invalid_local_port()
    local bad = { 0, -1, 65536, 99999, "5060" }
    for _, p in ipairs(bad) do
        local ok, err = exgb28181.init(base_config({ local_port = p }))
        assert(ok == false, "local_port=" .. tostring(p) .. " 应被拒绝")
        assert(type(err) == "string", "应给出失败原因")
    end
end

--[[
合法配置应通过，且 transport 归一化为小写。
]]
function t.test_init_succeeds_and_normalizes_transport()
    local ok, err = exgb28181.init(base_config({ transport = "TCP" }))
    assert(ok == true, "合法配置应通过, 实际失败: " .. tostring(err))

    local cfg = exgb28181.get_config()
    assert(cfg ~= nil, "init 成功后 get_config() 不应为 nil")
    assert(cfg.transport == "tcp", "transport 应归一化为小写, 实际 " .. tostring(cfg.transport))
end

--[[
未显式配置 sip_domain 时，应按国标惯例取 device_id 前 10 位。
]]
function t.test_init_derives_domain_from_device_id()
    local ok = exgb28181.init(base_config({ sip_domain = REMOVE }))
    assert(ok == true, "合法配置应通过")

    local cfg = exgb28181.get_config()
    assert(cfg.sip_domain == "3402000000",
           "应取 device_id 前 10 位作为域, 实际 " .. tostring(cfg.sip_domain))
end

--[[
显式配置的 sip_domain 不应被覆盖。
]]
function t.test_init_keeps_explicit_domain()
    local ok = exgb28181.init(base_config({ sip_domain = "9999999999" }))
    assert(ok == true, "合法配置应通过")
    assert(exgb28181.get_config().sip_domain == "9999999999", "显式域不应被覆盖")
end

--[[
get_config() 应返回副本，外部修改不能影响模块内部状态。
]]
function t.test_get_config_returns_copy()
    assert(exgb28181.init(base_config()) == true, "合法配置应通过")

    local cfg = exgb28181.get_config()
    cfg.device_id = "00000000000000000000"
    cfg.transport = "udp"

    local again = exgb28181.get_config()
    assert(again.device_id == "34020000001320000001",
           "外部修改不应影响内部状态, 实际 " .. tostring(again.device_id))
end

--[[
init() 成功时应派发 lifecycle/init 事件，负载包含设备编码。
]]
function t.test_init_emits_lifecycle_event()
    local got_event, got_action, got_data
    exgb28181.on(function(event, action, data)
        got_event, got_action, got_data = event, action, data
    end)

    assert(exgb28181.init(base_config()) == true, "合法配置应通过")
    exgb28181.on(nil)

    assert(got_event == "lifecycle", "事件大类应为 lifecycle, 实际 " .. tostring(got_event))
    assert(got_action == "init", "动作应为 init, 实际 " .. tostring(got_action))
    assert(type(got_data) == "table", "事件负载应为 table")
    assert(got_data.device_id == "34020000001320000001",
           "负载应包含 device_id, 实际 " .. tostring(got_data.device_id))
    assert(got_data.transport == "udp", "负载应包含归一化后的 transport")
end

--[[
用户回调内部抛异常时，不应向外传播，也不应影响 init() 的返回值。
]]
function t.test_callback_error_is_swallowed()
    exgb28181.on(function()
        error("用户回调故意抛出的异常")
    end)

    local ok = exgb28181.init(base_config())
    exgb28181.on(nil)

    assert(ok == true, "回调异常不应影响 init() 的返回值")
end

--[[
stop() 在未启动时应是幂等的安全操作。
]]
function t.test_stop_is_idempotent_when_not_started()
    assert(exgb28181.stop() == true, "未启动时 stop() 应返回 true")
    assert(exgb28181.stop() == true, "重复 stop() 应返回 true")
end

--[[
未启动时 is_registered() 必须为 false。

注意 exgb28181 是模块级单例，无法真正清空已保存的配置，因此这里不测
"未 init 就 start" 那条路径（它需要未初始化的干净状态）。那条分支目前
**没有用例覆盖**：client 侧没有 init()，只有门面 exgb28181.lua 有
（`return false, "请先调用 init() 完成配置"`）。
]]
function t.test_is_registered_false_when_not_started()
    assert(exgb28181.is_registered() == false,
           "未启动时 is_registered() 应为 false")
end

return t
