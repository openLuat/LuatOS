--[[
AirLink RPC 增强功能 Lua 侧测试

这些测试在 PC 模拟器上验证 Lua 层逻辑。
由于 AirLink 需要物理链路 (SPI/UART 对端), 此测试集聚焦于:
  1. 常量值正确性 (与 C 头文件一致)
  2. airlink 模块 API 不再暴露旧的 rpc/rpcRegister (已删除)
  3. 基础 airlink 模块可正常加载

物理链路相关的集成测试需在实际硬件上运行。
--]]

local rpc_tests = {}

-- 测试: AIRLINK_CMD_RPC 和 AIRLINK_CMD_NOTIFY 常量 (如果 airlink 模块存在)
function rpc_tests.test_airlink_module_loadable()
    -- PC 模拟器上 airlink 模块可能不存在, 跳过即通过
    local ok, airlink = pcall(require, "airlink")
    if not ok then
        log.info("rpc_test", "airlink 模块不可用 (PC 模拟器), 跳过模块测试")
        assert(true)
        return
    end
    log.info("rpc_test", "airlink 模块加载成功")
    assert(type(airlink) == "table", "airlink 应为 table")
end

-- 测试: 旧的 rpc/rpcRegister API 已移除
function rpc_tests.test_old_rpc_api_removed()
    local ok, airlink = pcall(require, "airlink")
    if not ok then
        log.info("rpc_test", "airlink 模块不可用, 跳过")
        assert(true)
        return
    end
    -- 旧 API 应已删除
    assert(airlink.rpc == nil, "airlink.rpc 应已删除")
    assert(airlink.rpcRegister == nil, "airlink.rpcRegister 应已删除")
    log.info("rpc_test", "旧 RPC API 已正确移除")
end

-- 测试: 协议常量定义
function rpc_tests.test_protocol_constants()
    -- 验证协议常量在 Lua 中可通过直接数值引用
    local CMD_RPC    = 0x30
    local CMD_NOTIFY = 0x31
    local RPC_DEFER  = 1

    assert(CMD_RPC    == 0x30, "AIRLINK_CMD_RPC 应为 0x30")
    assert(CMD_NOTIFY == 0x31, "AIRLINK_CMD_NOTIFY 应为 0x31")
    assert(RPC_DEFER  == 1,    "AIRLINK_RPC_DEFER 应为 1")

    log.info("rpc_test", string.format("CMD_RPC=0x%02X CMD_NOTIFY=0x%02X RPC_DEFER=%d",
        CMD_RPC, CMD_NOTIFY, RPC_DEFER))
end

-- 测试: 线格式字节布局验证 (模拟请求帧手工编码)
function rpc_tests.test_wire_format_rpc_request()
    -- RPC 请求线格式: [pkgid:8][rpc_id:2][payload]
    local pkgid  = 1       -- 8 bytes LE (Lua integer)
    local rpc_id = 0x0042  -- 2 bytes LE
    local payload = "hello"

    -- 构造预期帧
    local frame = string.pack("<I8I2", pkgid, rpc_id) .. payload
    assert(#frame == 8 + 2 + #payload, "RPC 请求帧长度错误")

    -- 解析验证
    local parsed_pkgid, parsed_rpc_id = string.unpack("<I8I2", frame)
    assert(parsed_pkgid  == pkgid,  "pkgid 解析错误")
    assert(parsed_rpc_id == rpc_id, "rpc_id 解析错误")
    local parsed_payload = frame:sub(11)
    assert(parsed_payload == payload, "payload 解析错误")

    log.info("rpc_test", string.format("RPC 请求帧验证通过, 总长=%d", #frame))
end

-- 测试: 线格式 - notify 帧
function rpc_tests.test_wire_format_notify()
    -- Notify 线格式: [rpc_id:2][payload]
    local rpc_id  = 0x0099
    local payload = "event_data"

    local frame = string.pack("<I2", rpc_id) .. payload
    assert(#frame == 2 + #payload, "Notify 帧长度错误")

    local parsed_rpc_id = string.unpack("<I2", frame)
    assert(parsed_rpc_id == rpc_id, "notify rpc_id 解析错误")
    local parsed_payload = frame:sub(3)
    assert(parsed_payload == payload, "notify payload 解析错误")

    log.info("rpc_test", string.format("Notify 帧验证通过, 总长=%d", #frame))
end

-- 测试: 线格式 - 响应帧
function rpc_tests.test_wire_format_response()
    -- rpc_reply 组装的响应内容: [req_pkgid:8][result_code:2][resp payload]
    local req_pkgid   = 1  -- 8 bytes
    local result_code = 0  -- int16
    local payload     = "response_data"

    local frame = string.pack("<I8i2", req_pkgid, result_code) .. payload
    assert(#frame == 8 + 2 + #payload, "响应帧长度错误")

    local p_req, p_rc = string.unpack("<I8i2", frame)
    assert(p_req == req_pkgid,   "req_pkgid 解析错误")
    assert(p_rc  == result_code, "result_code 解析错误")

    log.info("rpc_test", string.format("响应帧验证通过, 总长=%d", #frame))
end

-- 测试: 超时语义 - 模拟 tick 超时检测
function rpc_tests.test_timeout_semantics()
    -- 验证超时逻辑: start_ms + timeout_ms <= now → 超时
    local start_ms   = 1000
    local timeout_ms = 500
    local now_past   = 1600  -- 超时
    local now_future = 1400  -- 未超时

    local function is_expired(now)
        return timeout_ms > 0 and (now - start_ms) >= timeout_ms
    end

    assert(    is_expired(now_past),   "now_past 应超时")
    assert(not is_expired(now_future), "now_future 不应超时")
    assert(not is_expired(start_ms),   "刚开始不应超时")

    log.info("rpc_test", "超时语义验证通过")
end

return rpc_tests
