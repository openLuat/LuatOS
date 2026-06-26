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
    return run_payload_with_reset(ctx, proto.pack_cmd(opcode, a0, a1, a2), true)
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

function M.test_crypto_query_meta_advertises_crypto_feature()
    local ctx, err = ndk.rv32i(IMAGE, 32 * 1024, 1024)
    assert(ctx, tostring(err))
    local result = run_cmd(ctx, proto.CMD_QUERY_META, 0, 0, 0)
    assert((result.value2 & proto.FEATURE_CRYPTO) ~= 0, "query meta should advertise CRYPTO feature")
end

function M.test_crypto_md5_hash_matches_known_vector()
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

function M.test_crypto_crc32_matches_reference_implementation()
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

function M.test_crypto_md5_rejects_exchange_bounds_overflow()
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

function M.test_crypto_crc32_rejects_out_of_bounds_input()
    local ctx, err = ndk.rv32i(IMAGE, 32 * 1024, 1024)
    assert(ctx, tostring(err))
    local result = run_cmd(ctx, proto.CMD_CRYPTO_CRC32, 1000, 64, 0xFFFFFFFF)
    assert(result.status == proto.STATUS_CRYPTO_BAD_BOUNDS,
        string.format("expected STATUS_CRYPTO_BAD_BOUNDS (%d), got %d", proto.STATUS_CRYPTO_BAD_BOUNDS, result.status))
end

return M
