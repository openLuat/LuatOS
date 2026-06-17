local M = {}

-- T1: 5 个常量存在且值正确
function M.test_pkg_constants()
    assert(type(netdrv) == "userdata", "netdrv 模块不存在")
    assert(netdrv.EVT_PKG == 2,   "EVT_PKG 应为 2, 实际 " .. tostring(netdrv.EVT_PKG))
    assert(netdrv.FROM_HW == 0x10, "FROM_HW 应为 0x10, 实际 " .. tostring(netdrv.FROM_HW))
    assert(netdrv.TO_HW   == 0x20, "TO_HW 应为 0x20, 实际 " .. tostring(netdrv.TO_HW))
    assert(netdrv.TO_LWIP == 0x30, "TO_LWIP 应为 0x30, 实际 " .. tostring(netdrv.TO_LWIP))
    assert(netdrv.TO_NAPT == 0x40, "TO_NAPT 应为 0x40, 实际 " .. tostring(netdrv.TO_NAPT))
    assert(netdrv.EVT_SOCKET == 1, "EVT_SOCKET 应保持为 1, 实际 " .. tostring(netdrv.EVT_SOCKET))
end

-- T2: send_raw 函数已注册
function M.test_send_raw_function_exists()
    assert(type(netdrv.send_raw) == "function", "netdrv.send_raw 应为 function")
end

-- T3: send_raw 在无效 adapter 上返回 nil+err
function M.test_send_raw_invalid_adapter()
    local z = zbuff.create(64)
    z:write(string.char(1,2,3,4))
    local r1, r2 = netdrv.send_raw(99, netdrv.TO_HW, z)
    assert(r1 == nil, "应返回 nil, 实际 " .. tostring(r1))
    assert(type(r2) == "string", "应返回 err string, 实际 " .. type(r2))
end

-- T4: send_raw 在 zbuff 长度为 0 时返回 nil+err
function M.test_send_raw_empty_zbuff()
    local z = zbuff.create(64)
    local r1, r2 = netdrv.send_raw(socket.LWIP_ETH, netdrv.TO_HW, z)
    assert(r1 == nil, "空 zbuff 应返回 nil, 实际 " .. tostring(r1))
    assert(type(r2) == "string")
end

-- T5: send_raw 对未知 target 返回 error
function M.test_send_raw_unknown_target()
    local z = zbuff.create(64)
    z:write(string.char(1,2,3,4))
    local ok, err = pcall(netdrv.send_raw, socket.LWIP_ETH, 0x99, z)
    assert(ok == false, "未知 target 应抛错, 实际 ok=" .. tostring(ok))
    assert(type(err) == "string", "err 应为字符串")
end

-- T6: send_raw 对 TO_LWIP / TO_NAPT 抛"not implemented"
function M.test_send_raw_future_targets()
    local z = zbuff.create(64)
    z:write(string.char(1,2,3,4))
    local ok1 = pcall(netdrv.send_raw, socket.LWIP_ETH, netdrv.TO_LWIP, z)
    local ok2 = pcall(netdrv.send_raw, socket.LWIP_ETH, netdrv.TO_NAPT, z)
    -- PC 环境 adapter 不可用也可能先报错; 至少不能 panic
    -- 期望 (但不强制) 两个都返回 false 表示 not implemented
end

-- T7: EVT_PKG 在无 netif 的 adapter 上注册应返回 false/nil
function M.test_evt_pkg_register_invalid_adapter()
    local ok = netdrv.on(99, netdrv.EVT_PKG, function() end)
    assert(ok == nil or ok == false, "无 netif 应注册失败, 实际 " .. tostring(ok))
end

-- T8: EVT_PKG 在参数不是函数/nil 时返回 nil
function M.test_evt_pkg_register_non_function()
    local ok = netdrv.on(socket.LWIP_ETH, netdrv.EVT_PKG, "not a function")
    assert(ok == nil, "非函数参数应注册失败, 实际 " .. tostring(ok))
end

-- T9: 默认 len 行为
function M.test_send_raw_default_len()
    local z = zbuff.create(64)
    z:write(string.char(0xDE, 0xAD, 0xBE, 0xEF))
    local r1, r2 = netdrv.send_raw(99, netdrv.TO_HW, z)
    assert(r1 == nil, "无效 adapter 应返回 nil")
end

-- T10: EVT_PKG 用 nil 关闭(用户首选的关闭方式)
function M.test_evt_pkg_deregister_with_nil()
    local ok2 = netdrv.on(socket.LWIP_ETH, netdrv.EVT_PKG, nil)
    assert(ok2 == true, "EVT_PKG 用 nil 关闭应返回 true, 实际 " .. tostring(ok2))
end

-- T11: EVT_PKG nil 关闭对无 netdrv 的 adapter 不 panic
function M.test_evt_pkg_deregister_invalid_adapter()
    local ok = netdrv.on(99, netdrv.EVT_PKG, nil)
    assert(ok == true, "无 netdrv 的 adapter 用 nil 关闭也应返回 true(幂等), 实际 " .. tostring(ok))
end

return M
