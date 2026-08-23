local proto = require("hostabi_proto")

local M = {}
local CTX = nil
local IMAGE_RVC = "/luadb/hostabi_v1_rvc.bin"
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
    return run_payload_with_reset(ctx, proto.pack_cmd(opcode, a0, a1, a2), true)
end

function M.setUp()
    CTX = ndk.rv32i(IMAGE_RVC, 32 * 1024, 1024)
end

function M.tearDown()
    if CTX then
        ndk.stop(CTX, 1000)
        CTX = nil
    end
    collectgarbage("collect")
    collectgarbage("collect")
end

function M.test_rv32c_compressed_binary_exists()
    assert(io.exists(IMAGE_RVC), "missing hostabi_v1_rvc.bin in testcase directory: " .. IMAGE_RVC)
end

function M.test_rv32c_compressed_binary_reports_smoke_and_keeps_hostabi_flow()
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

return M
