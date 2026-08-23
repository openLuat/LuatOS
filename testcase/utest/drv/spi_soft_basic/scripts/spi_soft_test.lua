local t = {}

local function assert_utest(case_name)
    assert(spi.utest(case_name) == true,
        "spi.utest('" .. case_name .. "') 应返回 true")
end

-- 全双工 xfer 测试: 覆盖 4 种 SPI 模式 (CPOL/CPHA 组合)
local xfer_suite = {}

function xfer_suite.test_xfer_mode0()
    -- CPOL=0, CPHA=0: 空闲低电平, 第一个边沿采样
    assert_utest("xfer_mode0")
end

function xfer_suite.test_xfer_mode1()
    -- CPOL=0, CPHA=1: 空闲低电平, 第二个边沿采样
    assert_utest("xfer_mode1")
end

function xfer_suite.test_xfer_mode2()
    -- CPOL=1, CPHA=0: 空闲高电平, 第一个边沿采样
    assert_utest("xfer_mode2")
end

function xfer_suite.test_xfer_mode3()
    -- CPOL=1, CPHA=1: 空闲高电平, 第二个边沿采样 (用户报告的场景)
    assert_utest("xfer_mode3")
end

-- 多字节 xfer 测试
local multibyte_suite = {}

function multibyte_suite.test_multibyte_mode0()
    assert_utest("xfer_multibyte_mode0")
end

function multibyte_suite.test_multibyte_mode1()
    assert_utest("xfer_multibyte_mode1")
end

function multibyte_suite.test_multibyte_mode2()
    assert_utest("xfer_multibyte_mode2")
end

function multibyte_suite.test_multibyte_mode3()
    assert_utest("xfer_multibyte_mode3")
end

-- send-only 测试
local send_suite = {}

function send_suite.test_send_mode0()
    assert_utest("send_mode0")
end

function send_suite.test_send_mode1()
    assert_utest("send_mode1")
end

function send_suite.test_send_mode2()
    assert_utest("send_mode2")
end

function send_suite.test_send_mode3()
    assert_utest("send_mode3")
end

-- recv-only 测试
local recv_suite = {}

function recv_suite.test_recv_mode0()
    assert_utest("recv_mode0")
end

function recv_suite.test_recv_mode1()
    assert_utest("recv_mode1")
end

function recv_suite.test_recv_mode2()
    assert_utest("recv_mode2")
end

function recv_suite.test_recv_mode3()
    assert_utest("recv_mode3")
end

t.xfer_suite = xfer_suite
t.multibyte_suite = multibyte_suite
t.send_suite = send_suite
t.recv_suite = recv_suite

return t
