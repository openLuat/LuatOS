local t = {}

-- RTOS 信息 API 测试
local info_suite = {}

function info_suite.test_bsp_returns_PC()
    local bsp = rtos.bsp()
    assert(type(bsp) == "string", "rtos.bsp() 应返回 string")
    assert(bsp == "PC", "PC模拟器 bsp 应为 'PC', 实际: " .. tostring(bsp))
end

function info_suite.test_version_returns_table()
    local ver = rtos.version()
    assert(ver ~= nil, "rtos.version() 不应为 nil")
    -- version 可能返回 string 或 table
    local t = type(ver)
    assert(t == "string" or t == "table", "rtos.version() 应返回 string 或 table")
end

function info_suite.test_buildDate_not_empty()
    local bd = rtos.buildDate()
    assert(type(bd) == "string", "rtos.buildDate() 应返回 string")
    assert(#bd > 0, "buildDate 不应为空")
end

function info_suite.test_meminfo_returns_number()
    local total, used, max_used = rtos.meminfo()
    assert(type(total) == "number", "meminfo total 应为 number")
    assert(total > 0, "total 应大于 0")
    assert(type(used) == "number", "meminfo used 应为 number")
    assert(used >= 0, "used 应 >= 0")
    assert(used <= total, "used 不应超过 total")
end

function info_suite.test_firmware_returns_string()
    local fw = rtos.firmware()
    -- firmware 可能返回 nil 或 string
    if fw ~= nil then
        assert(type(fw) == "string", "rtos.firmware() 应返回 string 或 nil")
    end
end

-- 软件定时器测试
local timer_suite = {}

function timer_suite.test_timer_start_stop()
    -- 启动一个定时器 id=100, 50ms 后触发
    local ok = rtos.timer_start(100, 50)
    assert(ok == true or ok == nil or ok == 0 or ok == 1,
        "timer_start 应成功")
    -- 立即停止
    rtos.timer_stop(100)
end

function timer_suite.test_timer_callback_fires()
    local fired = false
    -- 注册定时器消息处理
    sys.subscribe("TIMER_101", function()
        fired = true
    end)
    rtos.timer_start(101, 30)
    sys.wait(100)
    rtos.timer_stop(101)
    assert(fired == true, "定时器101应在100ms内触发")
end

-- 消息收发测试
local msg_suite = {}

function msg_suite.test_publish_receive()
    local got_msg = nil
    sys.subscribe("TEST_MSG_001", function(data)
        got_msg = data
    end)
    sys.publish("TEST_MSG_001", "hello_rtos")
    sys.wait(50)
    assert(got_msg == "hello_rtos",
        "应收到消息 'hello_rtos', 实际: " .. tostring(got_msg))
end

function msg_suite.test_multiple_subscribers()
    local count = 0
    sys.subscribe("TEST_MSG_002", function() count = count + 1 end)
    sys.subscribe("TEST_MSG_002", function() count = count + 1 end)
    sys.publish("TEST_MSG_002")
    sys.wait(50)
    assert(count == 2, "两个订阅者都应收到, 实际 count=" .. count)
end

t.info_suite = info_suite
t.timer_suite = timer_suite
t.msg_suite = msg_suite

return t
