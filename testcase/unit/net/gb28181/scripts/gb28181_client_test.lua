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

-- ==================================================================
-- TCP 媒体承载的 setup 方向(里程碑 5.3 / 5.5)
-- ==================================================================

--[[
平台已指定方向时只能反向 —— 两端不能同时 passive，也不能同时 active，
同向的 answer 会被平台判为协商失败。
]]
function t.test_tcp_setup_mirrors_offer()
    assert(client.tcp_setup_choice("passive") == "active",
           "平台 passive -> 本端必须 active")
    assert(client.tcp_setup_choice("active") == "passive",
           "平台 active -> 本端必须 passive")

    -- 大小写不敏感(平台的写法并不统一)
    assert(client.tcp_setup_choice("PASSIVE") == "active")
    assert(client.tcp_setup_choice("Active") == "passive")
end

--[[
平台未定方向(actpass 或压根不给该行)时才由本端选，缺省 passive。
这也是全部 setup 取值的收敛点：未知取值等同"未指定"，而不是报错 ——
GB28181 平台对这两个属性的实现相当随意，拒收会白白丢掉点播。
]]
function t.test_tcp_setup_choice_when_offer_leaves_it_open()
    assert(client.tcp_setup_choice("actpass") == "passive", "actpass 缺省选 passive")
    assert(client.tcp_setup_choice(nil) == "passive", "未给该行缺省选 passive")
    assert(client.tcp_setup_choice("") == "passive", "空值等同未给")
    assert(client.tcp_setup_choice("nonsense") == "passive", "未知取值等同未给")

    -- 调用方可改倾向(NAT 后的设备更适合主动连出去)
    assert(client.tcp_setup_choice("actpass", "active") == "active")
    assert(client.tcp_setup_choice(nil, "ACTIVE") == "active", "倾向也应大小写不敏感")
    -- 但倾向**不能**压过平台已指定的方向
    assert(client.tcp_setup_choice("passive", "passive") == "active",
           "平台指定方向时倾向不生效")

    local v, err = client.tcp_setup_choice("actpass", "sideways")
    assert(v == nil and type(err) == "string", "非法倾向应返回 nil + 原因")
end

--[[
音频会话（平台发起的 TCP 腿）同样要被失活判定覆盖。

实测见过"0 个包"挂几分钟的僵尸音频会话：平台发了音频 INVITE、本端也受理并
回了 200 OK，但 TCP 连不上（平台的发流端口没发布），于是它既收不到数据、
也不会自己消失 —— 判据与点播共用同一套。
]]
function t.test_audio_session_is_reclaimed_when_link_never_comes_up()
    -- 平台发起、TCP 承载、从未连上的音频会话
    local sess = {
        media_tcp = true, link_up = false,
        started = true, started_ms = 1000,
        state = "established", incoming = true,
    }
    assert(client.session_death_reason(sess, 5000) == nil, "建链等待期内不该回收")
    assert(type(client.session_death_reason(sess, 20000)) == "string",
           "TCP 音频会话始终连不上时应判定失活(否则会一直挂在 talks() 里)")

    -- UDP 承载的音频会话（设备发起那条腿）：没有可信判据，不猜
    local udp = {
        media_tcp = false, link_up = false,
        started = true, started_ms = 1000, state = "established",
    }
    assert(client.session_death_reason(udp, 99999999) == nil,
           "UDP 音频会话不该被超时误杀")
end

--[[
会话接口在"没有会话"时的契约。真实的 INVITE/ACK/BYE 生命周期依赖 socket，
属联调，由 tests/tools/e2e_device + gb_platform_invite.py 覆盖。
]]
function t.test_session_api_without_sessions()
    reset()
    assert(type(client.sessions()) == "table", "sessions() 应始终返回表")
    local n = 0
    for _ in pairs(client.sessions()) do n = n + 1 end
    assert(n == 0, "未点播时不该有会话")

    -- 空表/假会话:push 与 flush 都应安全返回，而不是抛错
    assert(client.push_frame(nil, "x") == false)
    assert(client.push_frame({}, "x") == false, "没有 media 的会话不应崩")
    assert(client.push_frame({}, nil) == false)
    assert(client.push_frame({ started = true }, "x") == false,
           "没有 media 句柄时应返回 false")

    assert(client.flush_session({}) == 0, "没有 media 的会话 flush 应返回 0")
end

-- ==================================================================
-- 会话失活判定(失活回收的策略核心)
-- ==================================================================

--[[
UDP 会话在任何情况下都判"活着" —— 这是刻意的。
实测对端端口关闭、ICMP port unreachable 回来后，socket.tx 依然返回成功，
既无 CLOSED 事件也无错误码；Play 会话里平台又只收不发。
没有可信判据时不做超时：误杀平台暂停中的会话(画面卡住)虽然能自愈，
但"猜错了就杀"是错的方向。
]]
function t.test_death_reason_never_guesses_for_udp()
    local sess = {
        media_tcp = false,
        -- 故意把 TCP 的失活迹象全塞进去，UDP 也不该据此回收
        link_bad_ms = 1000,
        tx_fail_ms  = 0,
        started     = true, started_ms = 0, link_up = false,
    }
    assert(client.session_death_reason(sess, 99999999) == nil,
           "UDP 上没有可信判据，不应判定失活")
end

--[[
TCP：param ~= 0 的 EVENT 表示链路断了，但**单条不立刻判死** ——
适配器里本地可恢复的错误(收包分配失败)也走这条，那条会随即恢复。
持续到阈值(期间没有任何发送成功)才回收。
]]
function t.test_death_reason_tcp_link_bad_needs_persist()
    local sess = { media_tcp = true, link_up = false, link_bad_ms = 5000 }

    assert(client.session_death_reason(sess, 5100, 10000) == nil,
           "刚收到中断事件就判死，会把可恢复的本地错误误判掉")
    assert(client.session_death_reason(sess, 14999, 10000) == nil, "差一毫秒不该判定")
    local r = client.session_death_reason(sess, 15000, 10000)
    assert(type(r) == "string", "持续未恢复应判定失活, 实际 " .. tostring(r))

    -- 期间只要有一次发送成功就该清零(flush_session 负责)
    sess.link_bad_ms = nil
    assert(client.session_death_reason(sess, 99999999, 10000) == nil)
end

--[[
TCP：连续发送失败要"持续"到阈值才算死。
缓冲区一时满也会失败，所以阈值要按**经过时间**而不是按次数 ——
次数阈值会在丢帧率高的瞬间误杀。
]]
function t.test_death_reason_tcp_tx_fail_needs_persist()
    local sess = { media_tcp = true, link_up = true, tx_fail_ms = 10000 }

    assert(client.session_death_reason(sess, 10500, 10000) == nil,
           "刚失败就开始算死会把瞬时拥塞误判")
    assert(client.session_death_reason(sess, 19999, 10000) == nil,
           "差一毫秒不该判定")
    local r = client.session_death_reason(sess, 20000, 10000)
    assert(type(r) == "string", "持续失败满阈值应判定失活")

    -- 发出去过一次就该清零，之后重新计时
    sess.tx_fail_ms = nil
    assert(client.session_death_reason(sess, 99999999, 10000) == nil,
           "清零后不应再判定")
end

--[[ TCP：平台约定了连接却一直建不起来，端口没必要一直占着 ]]
function t.test_death_reason_tcp_link_never_established()
    local alive = {
        media_tcp = true, link_up = false,
        started = true, started_ms = 1000,
    }
    assert(client.session_death_reason(alive, 5000) == nil,
           "建链等待期内不该判定")
    local r = client.session_death_reason(alive, 20000)
    assert(type(r) == "string", "建链超时应判定失活")

    -- 还没收到 ACK 就不算：平台可能还没走到建链那一步
    local not_started = {
        media_tcp = true, link_up = false, started = false, started_ms = 1000,
    }
    assert(client.session_death_reason(not_started, 99999999) == nil,
           "未收到 ACK 的会话不该按建链超时回收")

    -- 链路已建好就不看这条
    local up = {
        media_tcp = true, link_up = true,
        started = true, started_ms = 1000,
    }
    assert(client.session_death_reason(up, 99999999) == nil, "链路正常不该回收")

    --[[
    中途断链的会话：link_up 会变 false，但**不能**因此落到"未能建立"这条 ——
    否则 started_ms 早已超过阈值，一条中断事件就会立刻杀掉会话。
    此时只应由 link_bad_ms 按阈值判定。
    ]]
    local broke = {
        media_tcp = true, link_up = false, link_up_once = true,
        started = true, started_ms = 1000, link_bad_ms = 90000,
    }
    assert(client.session_death_reason(broke, 20000, 10000) == nil,
           "中途断链不应立刻按'未能建立'回收")
    assert(type(client.session_death_reason(broke, 105000, 10000)) == "string",
           "但中断满阈值后仍应回收")

    -- 非表/空值不应崩
    assert(client.session_death_reason(nil, 1) == nil)
    assert(client.session_death_reason({}, 1) == nil)
end

return t
