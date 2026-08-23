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

local function release_ctx(ctx)
    ctx = nil
    collectgarbage("collect")
    collectgarbage("collect")
    return nil
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

function M.test_delay_command_succeeds_and_returns_timestamp()
    local ctx, err = ndk.rv32i(IMAGE, 32 * 1024, 1024)
    assert(ctx, tostring(err))
    local delay_us = 1000  -- Request 1ms delay
    local result = run_cmd(ctx, proto.CMD_DELAY_US, delay_us, 0, 0)
    assert(result.status == 0, "delay command should succeed")
    assert(result.value0 > 0, "timestamp should be non-zero")
end

function M.test_delay_command_reports_pending_event_flag()
    local ctx, err = ndk.rv32i(IMAGE, 32 * 1024, 1024)
    assert(ctx, tostring(err))
    local delay_us = 500
    local result = run_cmd(ctx, proto.CMD_DELAY_US, delay_us, 0, 0)
    assert(result.status == 0, "delay command should succeed")
    assert(result.value1 == 1, "pending flag should be 1 after delay")
end

function M.test_event_state_command_reports_pending_flag()
    local ctx, err = ndk.rv32i(IMAGE, 32 * 1024, 1024)
    assert(ctx, tostring(err))
    local state = run_cmd(ctx, proto.CMD_EVENT_STATE, 0, 0, 0)
    assert(state.status == 0, "event state command should succeed")
    assert(state.value0 == 0, "fresh context should report no pending event")
end

function M.test_event_header_reflects_timer_event()
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

function M.test_first_event_slot_contains_timer_event()
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

return M
