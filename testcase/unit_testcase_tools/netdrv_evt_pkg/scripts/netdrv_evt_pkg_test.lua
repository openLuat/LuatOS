local M = {}

-- T1: 4 个常量存在且值正确 (通道 + 事件类型)
function M.test_pkg_constants()
    assert(type(netdrv) == "userdata", "netdrv 模块不存在")
    assert(netdrv.EVT_PKG == 2,   "EVT_PKG 应为 2, 实际 " .. tostring(netdrv.EVT_PKG))
    assert(netdrv.CH_HW   == 0x10, "CH_HW 应为 0x10, 实际 " .. tostring(netdrv.CH_HW))
    assert(netdrv.CH_LWIP == 0x20, "CH_LWIP 应为 0x20, 实际 " .. tostring(netdrv.CH_LWIP))
    assert(netdrv.CH_NAPT == 0x30, "CH_NAPT 应为 0x30, 实际 " .. tostring(netdrv.CH_NAPT))
    assert(netdrv.EVT_SOCKET == 1, "EVT_SOCKET 应保持为 1, 实际 " .. tostring(netdrv.EVT_SOCKET))
    -- 旧名 FROM_*/TO_* 应该已经移除, 不应该再存在
    assert(netdrv.FROM_HW == nil, "旧名 FROM_HW 应已移除")
    assert(netdrv.TO_HW   == nil, "旧名 TO_HW 应已移除")
    assert(netdrv.TO_LWIP == nil, "旧名 TO_LWIP 应已移除")
    assert(netdrv.TO_NAPT == nil, "旧名 TO_NAPT 应已移除")
end

-- T2: send_raw 函数已注册
function M.test_send_raw_function_exists()
    assert(type(netdrv.send_raw) == "function", "netdrv.send_raw 应为 function")
end

-- T3: send_raw 在无效 adapter 上返回 nil+err
function M.test_send_raw_invalid_adapter()
    local z = zbuff.create(64)
    z:write(string.char(1,2,3,4))
    local r1, r2 = netdrv.send_raw(99, netdrv.CH_HW, z)
    assert(r1 == nil, "应返回 nil, 实际 " .. tostring(r1))
    assert(type(r2) == "string", "应返回 err string, 实际 " .. type(r2))
end

-- T4: send_raw 在 zbuff 长度为 0 时返回 nil+err
function M.test_send_raw_empty_zbuff()
    local z = zbuff.create(64)
    local r1, r2 = netdrv.send_raw(socket.LWIP_ETH, netdrv.CH_HW, z)
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

-- T6: send_raw 对 CH_LWIP / CH_NAPT 在 PC 环境下不 panic
-- (PC 上 LWIP_ETH 通常未配置 netif, send_raw 会返回 nil+err,
--  但不能再因为 "not implemented" 抛 lua_error)
function M.test_send_raw_future_targets()
    local z = zbuff.create(64)
    z:write(string.char(1,2,3,4))
    -- CH_LWIP
    local ok1, r1, r2 = pcall(netdrv.send_raw, socket.LWIP_ETH, netdrv.CH_LWIP, z)
    assert(ok1, "CH_LWIP 不应抛 lua_error, err=" .. tostring(r1))
    -- PC 上无 netif 时应该返回 nil + err 字符串, 而不是抛错
    if r1 == nil then
        assert(type(r2) == "string", "CH_LWIP 无 netif 应返 err string, 实际 " .. type(r2))
    end
    -- CH_NAPT
    local ok2, r3, r4 = pcall(netdrv.send_raw, socket.LWIP_ETH, netdrv.CH_NAPT, z)
    assert(ok2, "CH_NAPT 不应抛 lua_error, err=" .. tostring(r3))
    if r3 == nil then
        assert(type(r4) == "string", "CH_NAPT 无 netif 应返 err string, 实际 " .. type(r4))
    end
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
    local r1, r2 = netdrv.send_raw(99, netdrv.CH_HW, z)
    assert(r1 == nil, "无效 adapter 应返回 nil")
end

-- T10: EVT_PKG 用 nil 关闭(用户首选的关闭方式)
function M.test_evt_pkg_deregister_with_nil()
    local ok2 = netdrv.on(socket.LWIP_ETH, netdrv.EVT_PKG, nil)
    assert(ok2 == true, "EVT_PKG 用 nil 关闭应返回 true, 实际 " .. tostring(ok2))
end

-- T11: EVT_PKG 越界 id 应被拒绝, 不能 OOB 访问 s_pkg_evt_ref[id]
function M.test_evt_pkg_deregister_invalid_adapter()
    -- id=99 远超 NW_ADAPTER_QTY, 函数应早返 0 (无返回值), 不可 OOB 读 ref 数组
    local ret = netdrv.on(99, netdrv.EVT_PKG, nil)
    assert(ret == nil, "越界 id 应被拒绝, 实际 " .. tostring(ret))
end

-- T12: EVT_SOCKET 越界 id 同样应被拒绝, 不再依赖 netdrv_get 早返保护
function M.test_socket_deregister_invalid_adapter()
    local ret = netdrv.on(99, 0, nil)
    assert(ret == nil, "越界 id 应被拒绝, 实际 " .. tostring(ret))
end

return M
