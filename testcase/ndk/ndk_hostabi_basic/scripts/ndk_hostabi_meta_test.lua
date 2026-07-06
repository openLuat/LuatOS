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

function M.test_guest_fixture_binary_present()
    assert(io.exists(IMAGE), "missing hostabi_v1.bin")
end

function M.test_query_meta_command_reports_magic_and_version()
    local ctx, err = ndk.rv32i(IMAGE, 32 * 1024, 1024)
    assert(ctx, tostring(err))
    local result = run_cmd(ctx, proto.CMD_QUERY_META, 0, 0, 0)
    assert(result.status == 0, "query meta should succeed")
    assert(result.value0 == proto.HOST_MAGIC, "unexpected magic")
    assert(result.value1 == proto.HOST_VERSION, "unexpected version")
    assert((result.value2 & proto.FEATURE_GPIO) ~= 0, "query meta should advertise GPIO feature")
end

function M.test_ndk_info_exposes_abi_fields()
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

return M
