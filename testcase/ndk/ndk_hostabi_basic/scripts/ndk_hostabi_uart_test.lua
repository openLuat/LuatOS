local proto = require("hostabi_proto")

local M = {}
local CTX = nil
local IMAGE = "/luadb/hostabi_v1.bin"

local function run_payload_with_reset(ctx, payload, do_reset)
    if do_reset ~= false then
        assert(ndk.reset(ctx))
    end
    assert(ndk.setData(ctx, payload))
    local ok, ret, mcause, mtval = ndk.exec(ctx, {steps = 100000, elapsed = 500})
    assert(ok == true, string.format("exec failed ret=%s mcause=%s mtval=%s", tostring(ret), tostring(mcause), tostring(mtval)))
    return proto.unpack_result(assert(ndk.getData(ctx, proto.RESULT_SIZE, proto.RESULT_OFFSET)))
end

local function run_cmd(ctx, opcode, a0, a1, a2)
    return run_cmd_with_reset(ctx, opcode, a0, a1, a2, true)
end

function run_cmd_with_reset(ctx, opcode, a0, a1, a2, do_reset)
    return run_payload_with_reset(ctx, proto.pack_cmd(opcode, a0, a1, a2), do_reset)
end

function M.setUp()
    CTX = ndk.rv32i(IMAGE, 32 * 1024, 1024)
end

function M.tearDown()
    if CTX then
        ndk.stop(CTX, 1000)
        CTX = nil
    end
    collectgarbage("collect")
    collectgarbage("collect")
end

function M.test_uart_query_meta_advertises_uart_feature()
    local ctx, err = ndk.rv32i(IMAGE, 32 * 1024, 1024)
    assert(ctx, tostring(err))
    local result = run_cmd(ctx, proto.CMD_QUERY_META, 0, 0, 0)
    assert((result.value2 & proto.FEATURE_UART) ~= 0, "query meta should advertise UART feature")
end

function M.test_uart_config_command_succeeds()
    local ctx, err = ndk.rv32i(IMAGE, 32 * 1024, 1024)
    assert(ctx, tostring(err))
    local cmd, cfg = proto.pack_uart_config_cmd(proto.UART_PORT_LOOPBACK, 115200, 8, 1, 0, true)
    local pad = string.rep("\0", proto.UART_CFG_OFFSET - #cmd)
    local result = run_payload_with_reset(ctx, cmd .. pad .. cfg, true)
    assert(result.status == proto.STATUS_OK, "uart config should succeed")
end

function M.test_uart_tx_produces_rx_ready_event()
    local ctx, err = ndk.rv32i(IMAGE, 32 * 1024, 1024)
    assert(ctx, tostring(err))
    local cmd, cfg = proto.pack_uart_config_cmd(proto.UART_PORT_LOOPBACK, 115200, 8, 1, 0, true)
    local pad = string.rep("\0", proto.UART_CFG_OFFSET - #cmd)
    assert(run_payload_with_reset(ctx, cmd .. pad .. cfg, true).status == proto.STATUS_OK)

    local payload = "PING"
    local txcmd = proto.pack_uart_io_cmd(proto.CMD_UART_TX, proto.UART_PORT_LOOPBACK, proto.UART_PAYLOAD_OFFSET, #payload)
    local txpad = string.rep("\0", proto.UART_PAYLOAD_OFFSET - #txcmd)
    assert(run_payload_with_reset(ctx, txcmd .. txpad .. payload, false).status == proto.STATUS_OK)

    local exchange = ndk.getData(ctx, 1024, 0)
    local event = proto.unpack_event_slot(exchange, 0)
    assert(event.type == proto.EVENT_TYPE_UART_RX_READY, "uart tx should trigger RX_READY")
end

function M.test_uart_rx_state_read_clear_round_trip()
    local ctx, err = ndk.rv32i(IMAGE, 32 * 1024, 1024)
    assert(ctx, tostring(err))
    local cmd, cfg = proto.pack_uart_config_cmd(proto.UART_PORT_LOOPBACK, 115200, 8, 1, 0, true)
    local pad = string.rep("\0", proto.UART_CFG_OFFSET - #cmd)
    assert(run_payload_with_reset(ctx, cmd .. pad .. cfg, true).status == proto.STATUS_OK)

    local payload = "UART"
    local txcmd = proto.pack_uart_io_cmd(proto.CMD_UART_TX, proto.UART_PORT_LOOPBACK, proto.UART_PAYLOAD_OFFSET, #payload)
    local txpad = string.rep("\0", proto.UART_PAYLOAD_OFFSET - #txcmd)
    assert(run_payload_with_reset(ctx, txcmd .. txpad .. payload, false).status == proto.STATUS_OK)

    local state = run_cmd_with_reset(ctx, proto.CMD_UART_RX_STATE, proto.UART_PORT_LOOPBACK, 0, 0, false)
    local decoded = proto.decode_uart_rx_state(state)
    assert(decoded.pending == 1, "uart rx should be pending")
    assert(decoded.buffered_len == #payload, "uart buffered length should match loopback bytes")

    local read = run_payload_with_reset(ctx,
        proto.pack_uart_io_cmd(proto.CMD_UART_RX_READ, proto.UART_PORT_LOOPBACK,
            proto.UART_PAYLOAD_OFFSET, #payload),
        false)
    assert(read.status == proto.STATUS_OK, "uart rx read should succeed")
    local bytes = ndk.getData(ctx, #payload, proto.UART_PAYLOAD_OFFSET)
    assert(bytes == payload, "uart rx read should copy loopback bytes")

    local clr = run_cmd_with_reset(ctx, proto.CMD_UART_RX_CLEAR, proto.UART_PORT_LOOPBACK, 0, 0, false)
    assert(clr.status == proto.STATUS_OK, "uart rx clear should succeed")
end

function M.test_uart_config_bad_port_returns_error()
    local ctx, err = ndk.rv32i(IMAGE, 32 * 1024, 1024)
    assert(ctx, tostring(err))
    -- Port 0xFF is not a valid UART port; host must return BAD_PORT
    local cmd, cfg = proto.pack_uart_config_cmd(0xFF, 115200, 8, 1, 0, false)
    local pad = string.rep("\0", proto.UART_CFG_OFFSET - #cmd)
    local result = run_payload_with_reset(ctx, cmd .. pad .. cfg, true)
    assert(result.status == proto.STATUS_UART_BAD_PORT,
        string.format("expected STATUS_UART_BAD_PORT (%d), got %d", proto.STATUS_UART_BAD_PORT, result.status))
end

function M.test_uart_rx_state_bad_port_returns_error()
    local ctx, err = ndk.rv32i(IMAGE, 32 * 1024, 1024)
    assert(ctx, tostring(err))
    -- Port 0xFF is not a valid UART port; UART_RX_STATE must surface BAD_PORT
    -- rather than silently decoding the error code as a packed success state.
    local result = run_cmd(ctx, proto.CMD_UART_RX_STATE, 0xFF, 0, 0)
    assert(result.status == proto.STATUS_UART_BAD_PORT,
        string.format("expected STATUS_UART_BAD_PORT (%d), got %d", proto.STATUS_UART_BAD_PORT, result.status))
end

function M.test_uart_context_isolation_holds()
    local a, err = ndk.rv32i(IMAGE, 32 * 1024, 1024)
    assert(a, tostring(err))
    local b, err2 = ndk.rv32i(IMAGE, 32 * 1024, 1024)
    assert(b, tostring(err2))
    local cmd, cfg = proto.pack_uart_config_cmd(proto.UART_PORT_LOOPBACK, 115200, 8, 1, 0, true)
    local pad = string.rep("\0", proto.UART_CFG_OFFSET - #cmd)
    assert(run_payload_with_reset(a, cmd .. pad .. cfg, true).status == proto.STATUS_OK)
    assert(run_payload_with_reset(b, cmd .. pad .. cfg, true).status == proto.STATUS_OK)
    local payload = "A"
    local txcmd = proto.pack_uart_io_cmd(proto.CMD_UART_TX, proto.UART_PORT_LOOPBACK, proto.UART_PAYLOAD_OFFSET, #payload)
    local txpad = string.rep("\0", proto.UART_PAYLOAD_OFFSET - #txcmd)
    assert(run_payload_with_reset(a, txcmd .. txpad .. payload, false).status == proto.STATUS_OK)
    local state_b = run_cmd_with_reset(b, proto.CMD_UART_RX_STATE, proto.UART_PORT_LOOPBACK, 0, 0, false)
    assert(proto.decode_uart_rx_state(state_b).buffered_len == 0, "peer context should not observe foreign uart rx bytes")
end

return M
