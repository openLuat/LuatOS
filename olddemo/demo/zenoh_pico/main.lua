-- SPDX-License-Identifier: MIT
PROJECT = "zenoh_pico_demo"
VERSION = "1.0.0"
local sys = require("sys")
-- LuatOS内建C库从全局取得；wlan/socket等可能是可索引rotable userdata。
local socket = assert(rawget(_G, "socket"), "目标未注册socket内建库")
local z = assert(rawget(_G, "zenohpico"), "目标未注册zenohpico内建库")
assert(type(z.poll) == "function" and type(z.open) == "function", "zenohpico接口不完整")

-- 在网卡就绪后运行；替换为自己的测试router，默认文档地址不可用于实测。
local ROUTER = "tcp/192.0.2.1:7447"
local ADAPTER = socket.LWIP_GP
local PREFIX = "test/zenohpico/manual"
local expected = "LuatOS\0zenoh-pico\255"
local handle, subscriber

-- msgbus拥堵时仍可主动派发有界结果；周期工作使用timerLoopStart。
local poll_timer = sys.timerLoopStart(z.poll, 10)
sys.taskInit(function()
    assert(type(ADAPTER) == "number", "请显式选择目标网卡")
    local err
    handle, err = z.open(ROUTER, ADAPTER, function(h, event)
        log.info("zenohpico", event.kind, event.id, event.code)
        if event.kind == "opened" then
            subscriber = assert(z.subscribe(h, PREFIX .. "/out", function(_, sample)
                assert(sample.key == PREFIX .. "/out" and sample.payload == expected)
                log.info("zenohpico", "二进制回显实收", #sample.payload)
                z.close(h)
            end))
        elseif event.kind == "subscribed" and event.id == subscriber then
            local id, code = z.publish(h, PREFIX .. "/in", expected)
            assert(id, code)
        elseif event.kind == "closed" then
            sys.timerStop(poll_timer)
        end
    end)
    assert(handle, err)
    sys.timerStart(function()
        local state, dropped, callback_errors = z.state(handle)
        log.info("zenohpico", "状态/丢弃/回调错误", state, dropped, callback_errors)
        z.close(handle)
    end, 20000)
end)
sys.run()
