-- ndk_hostabi_test.lua
-- NDK host ABI fixture regression tests

local proto = require("hostabi_proto")

local tests = {}
local IMAGE = "/luadb/hostabi_v1.bin"
local IMAGE_RVC = "/luadb/hostabi_v1_rvc.bin"
local GPIO_DRIVER_REGRESSION_CONFIG_PIN = 126
local GPIO_DRIVER_REGRESSION_WRITE_PIN = 127
local HOSTABI_CMD_QUERY_RVC_STATUS = 0x04
local RVC_SMOKE_SIGNATURE = 0xC01A
local MISA_EXT_C = 1 << 2

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

local function release_ctx(ctx)
    ctx = nil
    collectgarbage("collect")
    collectgarbage("collect")
    return nil
end

function run_cmd_with_reset(ctx, opcode, a0, a1, a2, do_reset)
    return run_payload_with_reset(ctx, proto.pack_cmd(opcode, a0, a1, a2), do_reset)
end

local function run_gpio_config(ctx, pin, mode, pull, irq_mode, do_reset, extra_flags)
    return run_payload_with_reset(ctx, proto.pack_gpio_config_cmd(pin, mode, pull, irq_mode, extra_flags), do_reset)
end

local function crc32_reflect_byte(crc, b)
    crc = crc ~ b
    for _ = 1, 8 do
        if (crc & 1) ~= 0 then
            crc = (crc >> 1) ~ 0xEDB88320
        else
            crc = crc >> 1
        end
    end
    return crc
end

local function crc32_ref(data, start)
    local crc = start or 0xFFFFFFFF
    for i = 1, #data do
        crc = crc32_reflect_byte(crc, string.byte(data, i))
    end
    return crc & 0xFFFFFFFF
end

function tests.test_guest_fixture_binary_present()
    assert(io.exists(IMAGE), "missing hostabi_v1.bin")
end

function tests.test_query_meta_command_reports_magic_and_version()
    local ctx, err = ndk.rv32i(IMAGE, 32 * 1024, 1024)
    assert(ctx, tostring(err))
    local result = run_cmd(ctx, proto.CMD_QUERY_META, 0, 0, 0)
    assert(result.status == 0, "query meta should succeed")
    assert(result.value0 == proto.HOST_MAGIC, "unexpected magic")
    assert(result.value1 == proto.HOST_VERSION, "unexpected version")
    assert((result.value2 & proto.FEATURE_GPIO) ~= 0, "query meta should advertise GPIO feature")
end

function tests.test_ndk_info_exposes_abi_fields()
    local ctx, err = ndk.rv32i(IMAGE, 32 * 1024, 1024)
    assert(ctx, tostring(err))
    local info = ndk.info(ctx)
    assert(info.abi_magic == proto.HOST_MAGIC, "missing abi_magic")
    assert(info.abi_version == proto.HOST_VERSION, "missing abi_version")
    assert(type(info.features) == "number", "missing features")
    assert((info.features & proto.FEATURE_GPIO) ~= 0, "missing gpio feature bit")
    assert((info.features & proto.FEATURE_CRYPTO) ~= 0, "missing crypto feature bit")
    assert(info.last_error == 0, "missing last_error")
    assert(info.event_slots >= 1, "missing event_slots")
end

function tests.test_delay_command_succeeds_and_returns_timestamp()
    local ctx, err = ndk.rv32i(IMAGE, 32 * 1024, 1024)
    assert(ctx, tostring(err))
    local delay_us = 1000  -- Request 1ms delay
    local result = run_cmd(ctx, proto.CMD_DELAY_US, delay_us, 0, 0)
    assert(result.status == 0, "delay command should succeed")
    assert(result.value0 > 0, "timestamp should be non-zero")
end

function tests.test_delay_command_reports_pending_event_flag()
    local ctx, err = ndk.rv32i(IMAGE, 32 * 1024, 1024)
    assert(ctx, tostring(err))
    local delay_us = 500
    local result = run_cmd(ctx, proto.CMD_DELAY_US, delay_us, 0, 0)
    assert(result.status == 0, "delay command should succeed")
    assert(result.value1 == 1, "pending flag should be 1 after delay")
end

function tests.test_event_state_command_reports_pending_flag()
    local ctx, err = ndk.rv32i(IMAGE, 32 * 1024, 1024)
    assert(ctx, tostring(err))
    local state = run_cmd(ctx, proto.CMD_EVENT_STATE, 0, 0, 0)
    assert(state.status == 0, "event state command should succeed")
    assert(state.value0 == 0, "fresh context should report no pending event")
end

function tests.test_event_header_reflects_timer_event()
    local ctx, err = ndk.rv32i(IMAGE, 32 * 1024, 1024)
    assert(ctx, tostring(err))
    local delay_us = 1000
    local result = run_cmd(ctx, proto.CMD_DELAY_US, delay_us, 0, 0)
    assert(result.status == 0, "delay command should succeed")
    -- Read entire exchange buffer to inspect event header
    local exchange_data = ndk.getData(ctx, 1024, 0)
    local header = proto.unpack_event_header(exchange_data)
    assert(header.host_write == 1, "host_write should be 1")
    assert(header.guest_read == 0, "guest_read should be 0")
    assert(header.slot_count == 8, "slot_count should match configured event slots")
    assert(header.overflow == 0, "overflow should be 0")
end

function tests.test_first_event_slot_contains_timer_event()
    local ctx, err = ndk.rv32i(IMAGE, 32 * 1024, 1024)
    assert(ctx, tostring(err))
    local delay_us = 2000
    local result = run_cmd(ctx, proto.CMD_DELAY_US, delay_us, 0, 0)
    assert(result.status == 0, "delay command should succeed")
    -- Read event slot
    local exchange_data = ndk.getData(ctx, 1024, 0)
    local event = proto.unpack_event_slot(exchange_data, 0)
    assert(event.type == proto.EVENT_TYPE_TIMER, "event type should be TIMER")
    assert(event.data == delay_us, "event data should match requested delay")
end

function tests.test_gpio_config_command_succeeds()
    local ctx, err = ndk.rv32i(IMAGE, 32 * 1024, 1024)
    assert(ctx, tostring(err))
    local result = run_gpio_config(ctx, 7, proto.GPIO_MODE_OUTPUT, proto.GPIO_PULL_DEFAULT, 0)
    assert(result.status == proto.STATUS_OK, "gpio config should succeed")
end

function tests.test_gpio_write_then_read_round_trip()
    local ctx, err = ndk.rv32i(IMAGE, 32 * 1024, 1024)
    assert(ctx, tostring(err))
    local cfg = run_gpio_config(ctx, 7, proto.GPIO_MODE_OUTPUT, proto.GPIO_PULL_DEFAULT, 0)
    assert(cfg.status == proto.STATUS_OK, "gpio config should succeed")
    local wr = run_cmd_with_reset(ctx, proto.CMD_GPIO_WRITE, 7, 1, 0, false)
    assert(wr.status == proto.STATUS_OK, "gpio write should succeed")
    local rd = run_cmd_with_reset(ctx, proto.CMD_GPIO_READ, 7, 0, 0, false)
    assert(rd.status == proto.STATUS_OK, "gpio read should succeed")
    assert(rd.value0 == 1, "gpio read should report written level")
end

function tests.test_gpio_reset_clears_written_level()
    local ctx, err = ndk.rv32i(IMAGE, 32 * 1024, 1024)
    assert(ctx, tostring(err))
    local cfg = run_gpio_config(ctx, 7, proto.GPIO_MODE_OUTPUT, proto.GPIO_PULL_DEFAULT, 0)
    assert(cfg.status == proto.STATUS_OK, "gpio config should succeed")
    local wr = run_cmd_with_reset(ctx, proto.CMD_GPIO_WRITE, 7, 1, 0, false)
    assert(wr.status == proto.STATUS_OK, "gpio write should succeed")
    local rd = run_cmd(ctx, proto.CMD_GPIO_READ, 7, 0, 0)
    assert(rd.status == proto.STATUS_OK, "gpio read after reset should succeed")
    assert(rd.value0 == 0, "ndk reset should clear prior gpio output level")
end

function tests.test_gpio_read_only_peer_reset_does_not_clear_owner_pin()
    local owner, err = ndk.rv32i(IMAGE, 32 * 1024, 1024)
    assert(owner, tostring(err))
    local peer, peer_err = ndk.rv32i(IMAGE, 32 * 1024, 1024)
    assert(peer, tostring(peer_err))

    local cfg = run_gpio_config(owner, 7, proto.GPIO_MODE_OUTPUT, proto.GPIO_PULL_DEFAULT, 0)
    assert(cfg.status == proto.STATUS_OK, "owner gpio config should succeed")
    local wr = run_cmd_with_reset(owner, proto.CMD_GPIO_WRITE, 7, 1, 0, false)
    assert(wr.status == proto.STATUS_OK, "owner gpio write should succeed")

    local peer_rd = run_cmd_with_reset(peer, proto.CMD_GPIO_READ, 7, 0, 0, false)
    assert(peer_rd.status == proto.STATUS_OK, "peer gpio read should succeed")
    assert(peer_rd.value0 == 1, "peer should observe owner-written level")

    assert(ndk.reset(peer), "peer reset should succeed")

    local owner_rd = run_cmd_with_reset(owner, proto.CMD_GPIO_READ, 7, 0, 0, false)
    assert(owner_rd.status == proto.STATUS_OK, "owner gpio read should still succeed")
    assert(owner_rd.value0 == 1, "peer reset must not clear owner gpio state")
end

function tests.test_gpio_irq_probe_peer_reset_does_not_clear_owner_pin()
    local owner, err = ndk.rv32i(IMAGE, 32 * 1024, 1024)
    assert(owner, tostring(err))
    local peer, peer_err = ndk.rv32i(IMAGE, 32 * 1024, 1024)
    assert(peer, tostring(peer_err))

    local cfg = run_gpio_config(owner, 7, proto.GPIO_MODE_OUTPUT, proto.GPIO_PULL_DEFAULT, 0)
    assert(cfg.status == proto.STATUS_OK, "owner gpio config should succeed")
    local wr = run_cmd_with_reset(owner, proto.CMD_GPIO_WRITE, 7, 1, 0, false)
    assert(wr.status == proto.STATUS_OK, "owner gpio write should succeed")

    local probe = run_cmd_with_reset(peer, proto.CMD_GPIO_IRQ_STATE, 7, 0, 0, false)
    assert(probe.status == proto.STATUS_UNSUPPORTED, "peer irq probe should stay unsupported")

    assert(ndk.reset(peer), "peer reset should succeed")

    local owner_rd = run_cmd_with_reset(owner, proto.CMD_GPIO_READ, 7, 0, 0, false)
    assert(owner_rd.status == proto.STATUS_OK, "owner gpio read should still succeed")
    assert(owner_rd.value0 == 1, "unsupported peer irq probe must not claim gpio ownership")
end

function tests.test_gpio_owner_gc_releases_tracked_pin()
    do
        local owner, err = ndk.rv32i(IMAGE, 32 * 1024, 1024)
        assert(owner, tostring(err))

        local cfg = run_gpio_config(owner, 7, proto.GPIO_MODE_OUTPUT, proto.GPIO_PULL_DEFAULT, 0)
        assert(cfg.status == proto.STATUS_OK, "owner gpio config should succeed")
        local wr = run_cmd_with_reset(owner, proto.CMD_GPIO_WRITE, 7, 1, 0, false)
        assert(wr.status == proto.STATUS_OK, "owner gpio write should succeed")

        owner = release_ctx(owner)
    end
    collectgarbage("collect")
    collectgarbage("collect")

    local reader, reader_err = ndk.rv32i(IMAGE, 32 * 1024, 1024)
    assert(reader, tostring(reader_err))
    local rd = run_cmd(reader, proto.CMD_GPIO_READ, 7, 0, 0)
    assert(rd.status == proto.STATUS_OK, "reader gpio read should succeed")
    assert(rd.value0 == 0, "owner gc should release tracked gpio state")
end

function tests.test_gpio_read_invalid_nonboolean_result_surfaces_as_error()
    local ctx, err = ndk.rv32i(IMAGE, 32 * 1024, 1024)
    assert(ctx, tostring(err))
    local rd = run_cmd(ctx, proto.CMD_GPIO_READ, 0xB55B, 0, 0)
    assert(rd.status == proto.STATUS_UNSUPPORTED, "invalid gpio read result should map to unsupported")
    assert(rd.value0 == 0, "invalid gpio read should not leak bogus level")
end

function tests.test_gpio_host_error_status_is_preserved()
    local ctx, err = ndk.rv32i(IMAGE, 32 * 1024, 1024)
    assert(ctx, tostring(err))
    local rd = run_cmd(ctx, proto.CMD_GPIO_READ, 0xC55C, 0, 0)
    assert(rd.status == proto.STATUS_HOST_ERROR, "gpio host error should surface as host error")
    assert(rd.value0 == 0, "gpio host error should not leak bogus level")
end

function tests.test_gpio_irq_state_unpacks_future_packed_shape()
    local ctx, err = ndk.rv32i(IMAGE, 32 * 1024, 1024)
    assert(ctx, tostring(err))
    local unsupported = run_cmd(ctx, proto.CMD_GPIO_IRQ_STATE, 9, 0, 0)
    assert(unsupported.status == proto.STATUS_UNSUPPORTED, "current gpio irq state should still surface unsupported")
    local host_error = run_cmd(ctx, proto.CMD_GPIO_IRQ_STATE, 0xC55C, 0, 0)
    assert(host_error.status == proto.STATUS_HOST_ERROR, "gpio irq state host error should surface as host error")
    local state = run_cmd(ctx, proto.CMD_GPIO_IRQ_STATE, 0xA55A, 0, 0)
    assert(state.status == proto.STATUS_OK, "packed gpio irq state should decode as success")
    assert(state.value0 == 1, "packed gpio irq state should expose pending flag")
    assert(state.value1 == proto.GPIO_IRQ_HIGH, "packed gpio irq state should expose irq reason")
end

function tests.test_gpio_irq_state_reports_pending_after_trigger()
    local ctx, err = ndk.rv32i(IMAGE, 32 * 1024, 1024)
    assert(ctx, tostring(err))
    local cfg = run_gpio_config(ctx, 9, proto.GPIO_MODE_IRQ, proto.GPIO_PULL_UP, proto.GPIO_IRQ_HIGH)
    assert(cfg.status == proto.STATUS_OK, "gpio irq config should succeed")
    local state = run_cmd_with_reset(ctx, proto.CMD_GPIO_IRQ_STATE, 9, 0, 0, false)
    assert(state.status == proto.STATUS_OK, "gpio irq state should succeed")
    -- Pending IRQ expectation documents simulator-trigger behavior for later tasks.
    assert(state.value0 == 1, "gpio irq should be pending after simulator trigger")
    assert(state.value1 == proto.GPIO_IRQ_HIGH, "gpio irq state should preserve non-default irq mode")
end

function tests.test_gpio_irq_clear_removes_pending_state()
    local ctx, err = ndk.rv32i(IMAGE, 32 * 1024, 1024)
    assert(ctx, tostring(err))
    local cfg = run_gpio_config(ctx, 9, proto.GPIO_MODE_IRQ, proto.GPIO_PULL_UP, proto.GPIO_IRQ_HIGH)
    assert(cfg.status == proto.STATUS_OK, "gpio irq config should succeed")
    local clr = run_cmd_with_reset(ctx, proto.CMD_GPIO_IRQ_CLEAR, 9, 0, 0, false)
    assert(clr.status == proto.STATUS_OK, "gpio irq clear should succeed")
    local state = run_cmd_with_reset(ctx, proto.CMD_GPIO_IRQ_STATE, 9, 0, 0, false)
    assert(state.status == proto.STATUS_OK, "gpio irq state should succeed")
    -- Pending-clear expectation documents simulator-trigger behavior for later tasks.
    assert(state.value0 == 0, "gpio irq clear should drop pending state")
end

function tests.test_gpio_irq_event_appears_in_event_ring()
    local ctx, err = ndk.rv32i(IMAGE, 32 * 1024, 1024)
    assert(ctx, tostring(err))
    local cfg = run_gpio_config(ctx, 9, proto.GPIO_MODE_IRQ, proto.GPIO_PULL_UP, proto.GPIO_IRQ_HIGH)
    assert(cfg.status == proto.STATUS_OK, "gpio irq config should succeed")
    local exchange_data = ndk.getData(ctx, 1024, 0)
    local event = proto.unpack_event_slot(exchange_data, 0)
    local irq = proto.decode_gpio_irq_state(event.data)
    -- IRQ event expectation documents simulator-trigger behavior for later tasks.
    assert(event.type == proto.EVENT_TYPE_GPIO_IRQ, "event type should be GPIO_IRQ")
    assert(irq.pin == 9, "gpio irq payload should carry the configured pin")
    assert(irq.pending == 1, "gpio irq payload should report pending state")
    assert(irq.reason == proto.GPIO_IRQ_HIGH, "gpio irq payload should report configured irq reason")
end

function tests.test_gpio_conflicting_peer_cannot_steal_owner_pin()
    local owner, err = ndk.rv32i(IMAGE, 32 * 1024, 1024)
    assert(owner, tostring(err))
    local peer, peer_err = ndk.rv32i(IMAGE, 32 * 1024, 1024)
    assert(peer, tostring(peer_err))

    local cfg = run_gpio_config(owner, 7, proto.GPIO_MODE_OUTPUT, proto.GPIO_PULL_DEFAULT, 0)
    assert(cfg.status == proto.STATUS_OK, "owner gpio config should succeed")
    local wr = run_cmd_with_reset(owner, proto.CMD_GPIO_WRITE, 7, 1, 0, false)
    assert(wr.status == proto.STATUS_OK, "owner gpio write should succeed")

    local peer_cfg = run_gpio_config(peer, 7, proto.GPIO_MODE_OUTPUT, proto.GPIO_PULL_DEFAULT, 0)
    assert(peer_cfg.status == proto.STATUS_HOST_ERROR, "peer config should be rejected while owner holds pin")
    local peer_wr = run_cmd_with_reset(peer, proto.CMD_GPIO_WRITE, 7, 0, 0, false)
    assert(peer_wr.status == proto.STATUS_HOST_ERROR, "peer write should be rejected while owner holds pin")

    assert(ndk.reset(peer), "peer reset should succeed")

    local owner_rd = run_cmd_with_reset(owner, proto.CMD_GPIO_READ, 7, 0, 0, false)
    assert(owner_rd.status == proto.STATUS_OK, "owner gpio read should still succeed")
    assert(owner_rd.value0 == 1, "peer conflict must not steal owner gpio state")
end

function tests.test_gpio_shared_pc_pin_126_remains_usable()
    local ctx, err = ndk.rv32i(IMAGE, 32 * 1024, 1024)
    assert(ctx, tostring(err))

    local cfg = run_gpio_config(ctx, GPIO_DRIVER_REGRESSION_CONFIG_PIN, proto.GPIO_MODE_OUTPUT, proto.GPIO_PULL_DEFAULT, 0)
    assert(cfg.status == proto.STATUS_OK, "shared PC GPIO pin 126 should remain usable")
end

function tests.test_gpio_shared_pc_pin_127_write_remains_usable()
    local ctx, err = ndk.rv32i(IMAGE, 32 * 1024, 1024)
    assert(ctx, tostring(err))

    local cfg = run_gpio_config(ctx, GPIO_DRIVER_REGRESSION_WRITE_PIN, proto.GPIO_MODE_OUTPUT, proto.GPIO_PULL_DEFAULT, 0)
    assert(cfg.status == proto.STATUS_OK, "shared PC GPIO pin 127 config should succeed")
    local wr = run_cmd_with_reset(ctx, proto.CMD_GPIO_WRITE, GPIO_DRIVER_REGRESSION_WRITE_PIN, 1, 0, false)
    assert(wr.status == proto.STATUS_OK, "shared PC GPIO pin 127 write should remain usable")
end

function tests.test_gpio_config_host_failure_surfaces_as_error()
    local ctx, err = ndk.rv32i(IMAGE, 32 * 1024, 1024)
    assert(ctx, tostring(err))
    local cfg = run_gpio_config(ctx, 7, proto.GPIO_MODE_OUTPUT, proto.GPIO_PULL_DEFAULT, 0, true, proto.GPIO_CONFIG_TEST_HOST_FAIL)
    assert(cfg.status == proto.STATUS_HOST_ERROR, "gpio config host failure should surface as host error")
end

function tests.test_gpio_write_host_failure_does_not_claim_pin()
    local writer, err = ndk.rv32i(IMAGE, 32 * 1024, 1024)
    assert(writer, tostring(err))
    local peer, peer_err = ndk.rv32i(IMAGE, 32 * 1024, 1024)
    assert(peer, tostring(peer_err))

    local wr = run_cmd(writer, proto.CMD_GPIO_WRITE, 7, 1, proto.GPIO_WRITE_TEST_HOST_FAIL)
    assert(wr.status == proto.STATUS_HOST_ERROR, "gpio write host failure should surface as host error")

    local peer_cfg = run_gpio_config(peer, 7, proto.GPIO_MODE_OUTPUT, proto.GPIO_PULL_DEFAULT, 0)
    assert(peer_cfg.status == proto.STATUS_OK, "failed write must not claim gpio ownership")
end

-- ---------------------------------------------------------------------------
-- UART v1 tests
-- ---------------------------------------------------------------------------

function tests.test_uart_query_meta_advertises_uart_feature()
    local ctx, err = ndk.rv32i(IMAGE, 32 * 1024, 1024)
    assert(ctx, tostring(err))
    local result = run_cmd(ctx, proto.CMD_QUERY_META, 0, 0, 0)
    assert((result.value2 & proto.FEATURE_UART) ~= 0, "query meta should advertise UART feature")
end

function tests.test_uart_config_command_succeeds()
    local ctx, err = ndk.rv32i(IMAGE, 32 * 1024, 1024)
    assert(ctx, tostring(err))
    local cmd, cfg = proto.pack_uart_config_cmd(proto.UART_PORT_LOOPBACK, 115200, 8, 1, 0, true)
    local pad = string.rep("\0", proto.UART_CFG_OFFSET - #cmd)
    local result = run_payload_with_reset(ctx, cmd .. pad .. cfg, true)
    assert(result.status == proto.STATUS_OK, "uart config should succeed")
end

function tests.test_uart_tx_produces_rx_ready_event()
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

function tests.test_uart_rx_state_read_clear_round_trip()
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

function tests.test_uart_config_bad_port_returns_error()
    local ctx, err = ndk.rv32i(IMAGE, 32 * 1024, 1024)
    assert(ctx, tostring(err))
    -- Port 0xFF is not a valid UART port; host must return BAD_PORT
    local cmd, cfg = proto.pack_uart_config_cmd(0xFF, 115200, 8, 1, 0, false)
    local pad = string.rep("\0", proto.UART_CFG_OFFSET - #cmd)
    local result = run_payload_with_reset(ctx, cmd .. pad .. cfg, true)
    assert(result.status == proto.STATUS_UART_BAD_PORT,
        string.format("expected STATUS_UART_BAD_PORT (%d), got %d", proto.STATUS_UART_BAD_PORT, result.status))
end

function tests.test_uart_rx_state_bad_port_returns_error()
    local ctx, err = ndk.rv32i(IMAGE, 32 * 1024, 1024)
    assert(ctx, tostring(err))
    -- Port 0xFF is not a valid UART port; UART_RX_STATE must surface BAD_PORT
    -- rather than silently decoding the error code as a packed success state.
    local result = run_cmd(ctx, proto.CMD_UART_RX_STATE, 0xFF, 0, 0)
    assert(result.status == proto.STATUS_UART_BAD_PORT,
        string.format("expected STATUS_UART_BAD_PORT (%d), got %d", proto.STATUS_UART_BAD_PORT, result.status))
end

function tests.test_uart_context_isolation_holds()
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

-- ---------------------------------------------------------------------------
-- CRYPTO tests
-- ---------------------------------------------------------------------------

function tests.test_crypto_query_meta_advertises_crypto_feature()
    local ctx, err = ndk.rv32i(IMAGE, 32 * 1024, 1024)
    assert(ctx, tostring(err))
    local result = run_cmd(ctx, proto.CMD_QUERY_META, 0, 0, 0)
    assert((result.value2 & proto.FEATURE_CRYPTO) ~= 0, "query meta should advertise CRYPTO feature")
end

function tests.test_crypto_md5_hash_matches_known_vector()
    local ctx, err = ndk.rv32i(IMAGE, 32 * 1024, 1024)
    assert(ctx, tostring(err))
    local payload = "abc"
    local cmd = proto.pack_crypto_md5_cmd(proto.CRYPTO_INPUT_OFFSET, #payload, proto.CRYPTO_OUTPUT_OFFSET)
    local pad = string.rep("\0", proto.CRYPTO_INPUT_OFFSET - #cmd)
    local result = run_payload_with_reset(ctx, cmd .. pad .. payload, true)
    assert(result.status == proto.STATUS_OK, "crypto md5 should succeed")
    local digest = ndk.getData(ctx, 16, proto.CRYPTO_OUTPUT_OFFSET)
    local expected = proto.hex_to_bin("900150983cd24fb0d6963f7d28e17f72")
    assert(digest == expected, "crypto md5 digest mismatch")
end

function tests.test_crypto_crc32_matches_reference_implementation()
    local ctx, err = ndk.rv32i(IMAGE, 32 * 1024, 1024)
    assert(ctx, tostring(err))
    local payload = "123456789"
    local cmd = proto.pack_crypto_crc32_cmd(proto.CRYPTO_INPUT_OFFSET, #payload, 0xFFFFFFFF)
    local pad = string.rep("\0", proto.CRYPTO_INPUT_OFFSET - #cmd)
    local result = run_payload_with_reset(ctx, cmd .. pad .. payload, true)
    assert(result.status == proto.STATUS_OK, "crypto crc32 should succeed")
    local expected = crc32_ref(payload, 0xFFFFFFFF)
    assert(result.value0 == expected, string.format("expected crc32 0x%08X got 0x%08X", expected, result.value0))
end

function tests.test_crypto_md5_rejects_exchange_bounds_overflow()
    local ctx, err = ndk.rv32i(IMAGE, 32 * 1024, 1024)
    assert(ctx, tostring(err))
    local payload = "xx"
    local bad_output_offset = 1020
    local cmd = proto.pack_crypto_md5_cmd(proto.CRYPTO_INPUT_OFFSET, #payload, bad_output_offset)
    local pad = string.rep("\0", proto.CRYPTO_INPUT_OFFSET - #cmd)
    local result = run_payload_with_reset(ctx, cmd .. pad .. payload, true)
    assert(result.status == proto.STATUS_CRYPTO_BAD_BOUNDS,
        string.format("expected STATUS_CRYPTO_BAD_BOUNDS (%d), got %d", proto.STATUS_CRYPTO_BAD_BOUNDS, result.status))
end

function tests.test_crypto_crc32_rejects_out_of_bounds_input()
    local ctx, err = ndk.rv32i(IMAGE, 32 * 1024, 1024)
    assert(ctx, tostring(err))
    local result = run_cmd(ctx, proto.CMD_CRYPTO_CRC32, 1000, 64, 0xFFFFFFFF)
    assert(result.status == proto.STATUS_CRYPTO_BAD_BOUNDS,
        string.format("expected STATUS_CRYPTO_BAD_BOUNDS (%d), got %d", proto.STATUS_CRYPTO_BAD_BOUNDS, result.status))
end

function tests.test_rv32c_compressed_binary_exists()
    assert(io.exists(IMAGE_RVC), "missing hostabi_v1_rvc.bin in testcase directory: " .. IMAGE_RVC)
end

function tests.test_rv32c_compressed_binary_reports_smoke_and_keeps_hostabi_flow()
    local ctx, err = ndk.rv32i(IMAGE_RVC, 32 * 1024, 1024)
    assert(ctx, tostring(err))

    local smoke = run_cmd(ctx, HOSTABI_CMD_QUERY_RVC_STATUS, 0, 0, 0)
    assert(smoke.status == proto.STATUS_OK, "compressed status command should succeed")
    assert(smoke.value0 == RVC_SMOKE_SIGNATURE,
        string.format("expected compressed smoke signature 0x%X, got 0x%X", RVC_SMOKE_SIGNATURE, smoke.value0))
    assert((smoke.value1 & MISA_EXT_C) ~= 0, string.format("misa should advertise C extension, got 0x%X", smoke.value1))

    local meta = run_cmd(ctx, proto.CMD_QUERY_META, 0, 0, 0)
    assert(meta.status == proto.STATUS_OK, "query meta should still succeed after compressed smoke check")
    assert(meta.value0 == proto.HOST_MAGIC, "unexpected magic")
    assert(meta.value1 == proto.HOST_VERSION, "unexpected version")
    assert((meta.value2 & proto.FEATURE_GPIO) ~= 0, "query meta should advertise GPIO feature")
end

return tests
