local proto = require("hostabi_proto")

local M = {}
local CTX = nil
local IMAGE = "/luadb/hostabi_v1.bin"
local GPIO_DRIVER_REGRESSION_CONFIG_PIN = 126
local GPIO_DRIVER_REGRESSION_WRITE_PIN = 127

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

function M.test_gpio_config_command_succeeds()
    local ctx, err = ndk.rv32i(IMAGE, 32 * 1024, 1024)
    assert(ctx, tostring(err))
    local result = run_gpio_config(ctx, 7, proto.GPIO_MODE_OUTPUT, proto.GPIO_PULL_DEFAULT, 0)
    assert(result.status == proto.STATUS_OK, "gpio config should succeed")
end

function M.test_gpio_write_then_read_round_trip()
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

function M.test_gpio_reset_clears_written_level()
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

function M.test_gpio_read_only_peer_reset_does_not_clear_owner_pin()
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

function M.test_gpio_irq_probe_peer_reset_does_not_clear_owner_pin()
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

function M.test_gpio_owner_gc_releases_tracked_pin()
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

function M.test_gpio_read_invalid_nonboolean_result_surfaces_as_error()
    local ctx, err = ndk.rv32i(IMAGE, 32 * 1024, 1024)
    assert(ctx, tostring(err))
    local rd = run_cmd(ctx, proto.CMD_GPIO_READ, 0xB55B, 0, 0)
    assert(rd.status == proto.STATUS_UNSUPPORTED, "invalid gpio read result should map to unsupported")
    assert(rd.value0 == 0, "invalid gpio read should not leak bogus level")
end

function M.test_gpio_host_error_status_is_preserved()
    local ctx, err = ndk.rv32i(IMAGE, 32 * 1024, 1024)
    assert(ctx, tostring(err))
    local rd = run_cmd(ctx, proto.CMD_GPIO_READ, 0xC55C, 0, 0)
    assert(rd.status == proto.STATUS_HOST_ERROR, "gpio host error should surface as host error")
    assert(rd.value0 == 0, "gpio host error should not leak bogus level")
end

function M.test_gpio_irq_state_unpacks_future_packed_shape()
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

function M.test_gpio_irq_state_reports_pending_after_trigger()
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

function M.test_gpio_irq_clear_removes_pending_state()
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

function M.test_gpio_irq_event_appears_in_event_ring()
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

function M.test_gpio_conflicting_peer_cannot_steal_owner_pin()
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

function M.test_gpio_shared_pc_pin_126_remains_usable()
    local ctx, err = ndk.rv32i(IMAGE, 32 * 1024, 1024)
    assert(ctx, tostring(err))

    local cfg = run_gpio_config(ctx, GPIO_DRIVER_REGRESSION_CONFIG_PIN, proto.GPIO_MODE_OUTPUT, proto.GPIO_PULL_DEFAULT, 0)
    assert(cfg.status == proto.STATUS_OK, "shared PC GPIO pin 126 should remain usable")
end

function M.test_gpio_shared_pc_pin_127_write_remains_usable()
    local ctx, err = ndk.rv32i(IMAGE, 32 * 1024, 1024)
    assert(ctx, tostring(err))

    local cfg = run_gpio_config(ctx, GPIO_DRIVER_REGRESSION_WRITE_PIN, proto.GPIO_MODE_OUTPUT, proto.GPIO_PULL_DEFAULT, 0)
    assert(cfg.status == proto.STATUS_OK, "shared PC GPIO pin 127 config should succeed")
    local wr = run_cmd_with_reset(ctx, proto.CMD_GPIO_WRITE, GPIO_DRIVER_REGRESSION_WRITE_PIN, 1, 0, false)
    assert(wr.status == proto.STATUS_OK, "shared PC GPIO pin 127 write should remain usable")
end

function M.test_gpio_config_host_failure_surfaces_as_error()
    local ctx, err = ndk.rv32i(IMAGE, 32 * 1024, 1024)
    assert(ctx, tostring(err))
    local cfg = run_gpio_config(ctx, 7, proto.GPIO_MODE_OUTPUT, proto.GPIO_PULL_DEFAULT, 0, true, proto.GPIO_CONFIG_TEST_HOST_FAIL)
    assert(cfg.status == proto.STATUS_HOST_ERROR, "gpio config host failure should surface as host error")
end

function M.test_gpio_write_host_failure_does_not_claim_pin()
    local writer, err = ndk.rv32i(IMAGE, 32 * 1024, 1024)
    assert(writer, tostring(err))
    local peer, peer_err = ndk.rv32i(IMAGE, 32 * 1024, 1024)
    assert(peer, tostring(peer_err))

    local wr = run_cmd(writer, proto.CMD_GPIO_WRITE, 7, 1, proto.GPIO_WRITE_TEST_HOST_FAIL)
    assert(wr.status == proto.STATUS_HOST_ERROR, "gpio write host failure should surface as host error")

    local peer_cfg = run_gpio_config(peer, 7, proto.GPIO_MODE_OUTPUT, proto.GPIO_PULL_DEFAULT, 0)
    assert(peer_cfg.status == proto.STATUS_OK, "failed write must not claim gpio ownership")
end

return M
