local M = {}

local IMAGE_PATH = "/luadb/baremetal.bin"
local FCSR_IMAGE_PATH = "/luadb/baremetal_fcsr.bin"
local FMV_IMAGE_PATH = "/luadb/baremetal_fmv.bin"
local FLWFSW_IMAGE_PATH = "/luadb/baremetal_flwfsw.bin"
local MEM_SIZE = 32 * 1024
local EXCHANGE_SIZE = 1024

local CTX = nil

local function assert_info_fields(info)
    local fields = {"mem", "exchange", "exchange_addr", "image", "running", "mcause", "mtval"}
    for _, key in ipairs(fields) do
        assert(info[key] ~= nil, "ndk.info missing field: " .. key)
    end
end

local function unpack_u32le(data, offset)
    local value = string.unpack("<I4", data, offset + 1)
    return value
end

function M.setUp()
    CTX = nil
    collectgarbage("collect")
    collectgarbage("collect")
    CTX = ndk.rv32i(IMAGE_PATH, MEM_SIZE, EXCHANGE_SIZE)
    assert(CTX, "setUp ndk.rv32i failed")
end

function M.tearDown()
    if CTX then
        ndk.stop(CTX, 1000)
        CTX = nil
    end
    collectgarbage("collect")
    collectgarbage("collect")
end

function M.test_ndk_constructor_accepts_rv32imf_isa_option()
    local ctx, err = ndk.rv32i(IMAGE_PATH, MEM_SIZE, EXCHANGE_SIZE, {isa = "rv32imf"})
    assert(ctx, "ndk.rv32i with isa option failed: " .. tostring(err))

    local info = ndk.info(ctx)
    assert(type(info) == "table", "ndk.info should return table")
    assert(info.isa == "rv32imf", "ndk.info should expose selected isa")
    assert(info.flen == 32, "ndk.info should expose flen reset value")
    assert(info.fcsr == 0, "ndk.info should expose fcsr reset value")
    assert(info.frm == 0, "ndk.info should expose frm reset value")
    assert(info.fflags == 0, "ndk.info should expose fflags reset value")

    local stop_ok, stop_err = ndk.stop(ctx, 1000)
    assert(stop_ok == true, "ndk.stop failed: " .. tostring(stop_err))
end

function M.test_ndk_default_rv32i_does_not_expose_fcsr_shadow_state()
    assert(io.exists(FCSR_IMAGE_PATH), "missing baremetal_fcsr.bin in testcase directory: " .. FCSR_IMAGE_PATH)

    local ctx, err = ndk.rv32i(FCSR_IMAGE_PATH, MEM_SIZE, EXCHANGE_SIZE)
    assert(ctx, "default ndk.rv32i failed: " .. tostring(err))

    local ok, ret_or_err, mcause, mtval = ndk.exec(ctx, { steps = 100000, elapsed = 500 })
    assert(ok == true, string.format("ndk.exec failed: %s mcause=%s mtval=%s", tostring(ret_or_err), tostring(mcause), tostring(mtval)))

    local info = ndk.info(ctx)
    assert(type(info) == "table", "ndk.info should return table")
    assert(info.isa == "rv32ima", "default ndk.rv32i should keep integer-only isa")
    assert(info.flen == 0, "default ndk.rv32i should not expose F extension flen")
    assert(info.fcsr == 0, "default ndk.rv32i should ignore guest fcsr writes")
    assert(info.frm == 0, "default ndk.rv32i should ignore guest frm writes")
    assert(info.fflags == 0, "default ndk.rv32i should ignore guest fflags writes")

    local stop_ok, stop_err = ndk.stop(ctx, 1000)
    assert(stop_ok == true, "ndk.stop failed: " .. tostring(stop_err))
end

function M.test_ndk_reset_preserves_rv32imf_isa_metadata()
    assert(io.exists(FCSR_IMAGE_PATH), "missing baremetal_fcsr.bin in testcase directory: " .. FCSR_IMAGE_PATH)

    local ctx, err = ndk.rv32i(FCSR_IMAGE_PATH, MEM_SIZE, EXCHANGE_SIZE, {isa = "rv32imf"})
    assert(ctx, "ndk.rv32i with isa option failed: " .. tostring(err))

    local ok, ret_or_err, mcause, mtval = ndk.exec(ctx, { steps = 100000, elapsed = 500 })
    assert(ok == true, string.format("ndk.exec failed: %s mcause=%s mtval=%s", tostring(ret_or_err), tostring(mcause), tostring(mtval)))

    local mutated_info = ndk.info(ctx)
    assert(type(mutated_info) == "table", "ndk.info should return table after exec")
    assert(mutated_info.fcsr == 0x21, "ndk.exec should surface guest-written fcsr before reset")
    assert(mutated_info.frm == 1, "ndk.exec should surface guest-written frm before reset")
    assert(mutated_info.fflags == 1, "ndk.exec should surface guest-written fflags before reset")

    local reset_ok, reset_err = ndk.reset(ctx)
    assert(reset_ok == true, "ndk.reset failed: " .. tostring(reset_err))

    local info = ndk.info(ctx)
    assert(type(info) == "table", "ndk.info should return table after reset")
    assert(info.isa == "rv32imf", "ndk.reset should preserve selected isa")
    assert(info.flen == 32, "ndk.reset should preserve flen reset value")
    assert(info.fcsr == 0, "ndk.reset should restore fcsr reset value")
    assert(info.frm == 0, "ndk.reset should restore frm reset value")
    assert(info.fflags == 0, "ndk.reset should restore fflags reset value")

    local stop_ok, stop_err = ndk.stop(ctx, 1000)
    assert(stop_ok == true, "ndk.stop failed: " .. tostring(stop_err))
end

function M.test_ndk_rv32imf_executes_fmv_roundtrip_guest()
    assert(io.exists(FMV_IMAGE_PATH), "missing baremetal_fmv.bin in testcase directory: " .. FMV_IMAGE_PATH)

    local ctx, err = ndk.rv32i(FMV_IMAGE_PATH, MEM_SIZE, EXCHANGE_SIZE, {isa = "rv32imf"})
    assert(ctx, "ndk.rv32i with rv32imf failed: " .. tostring(err))

    local ok, ret_or_err, mcause, mtval = ndk.exec(ctx, { steps = 100000, elapsed = 500 })
    assert(ok == true, string.format("rv32imf fmv guest should succeed, got err=%s mcause=%s mtval=%s", tostring(ret_or_err), tostring(mcause), tostring(mtval)))
    assert(ret_or_err == 0x3f800000, string.format("fmv roundtrip should preserve bits, got 0x%08x", tonumber(ret_or_err) or -1))

    local stop_ok, stop_err = ndk.stop(ctx, 1000)
    assert(stop_ok == true, "ndk.stop failed: " .. tostring(stop_err))
end

function M.test_ndk_default_rv32i_traps_on_fmv_guest()
    assert(io.exists(FMV_IMAGE_PATH), "missing baremetal_fmv.bin in testcase directory: " .. FMV_IMAGE_PATH)

    local ctx, err = ndk.rv32i(FMV_IMAGE_PATH, MEM_SIZE, EXCHANGE_SIZE)
    assert(ctx, "default ndk.rv32i failed: " .. tostring(err))

    local ok, ret_or_err, mcause, mtval = ndk.exec(ctx, { steps = 100000, elapsed = 500 })
    assert(ok == false, "default rv32i should trap on fmv guest")
    assert(ret_or_err == "trap", "default rv32i should surface trap, got: " .. tostring(ret_or_err))
    assert(mcause == 2, "default rv32i should raise illegal instruction trap, got mcause=" .. tostring(mcause))
    assert(type(mtval) == "number", "default rv32i trap should report mtval")

    local stop_ok, stop_err = ndk.stop(ctx, 1000)
    assert(stop_ok == true, "ndk.stop failed: " .. tostring(stop_err))
end

function M.test_ndk_rv32imf_executes_flwfsw_roundtrip_guest()
    assert(io.exists(FLWFSW_IMAGE_PATH), "missing baremetal_flwfsw.bin in testcase directory: " .. FLWFSW_IMAGE_PATH)

    local ctx, err = ndk.rv32i(FLWFSW_IMAGE_PATH, MEM_SIZE, EXCHANGE_SIZE, {isa = "rv32imf"})
    assert(ctx, "ndk.rv32i with rv32imf failed: " .. tostring(err))

    local ok, ret_or_err, mcause, mtval = ndk.exec(ctx, { steps = 100000, elapsed = 500 })
    assert(ok == true, string.format("rv32imf flw/fsw guest should succeed, got err=%s mcause=%s mtval=%s", tostring(ret_or_err), tostring(mcause), tostring(mtval)))
    assert(ret_or_err == 0x12345678, string.format("flw/fsw roundtrip should preserve bits, got 0x%08x", tonumber(ret_or_err) or -1))

    local stop_ok, stop_err = ndk.stop(ctx, 1000)
    assert(stop_ok == true, "ndk.stop failed: " .. tostring(stop_err))
end

function M.test_ndk_default_rv32i_traps_on_flwfsw_guest()
    assert(io.exists(FLWFSW_IMAGE_PATH), "missing baremetal_flwfsw.bin in testcase directory: " .. FLWFSW_IMAGE_PATH)

    local ctx, err = ndk.rv32i(FLWFSW_IMAGE_PATH, MEM_SIZE, EXCHANGE_SIZE)
    assert(ctx, "default ndk.rv32i failed: " .. tostring(err))

    local ok, ret_or_err, mcause, mtval = ndk.exec(ctx, { steps = 100000, elapsed = 500 })
    assert(ok == false, "default rv32i should trap on flw/fsw guest")
    assert(ret_or_err == "trap", "default rv32i should surface trap, got: " .. tostring(ret_or_err))
    assert(mcause == 2, "default rv32i should raise illegal instruction trap, got mcause=" .. tostring(mcause))
    assert(type(mtval) == "number", "default rv32i trap should report mtval")

    local stop_ok, stop_err = ndk.stop(ctx, 1000)
    assert(stop_ok == true, "ndk.stop failed: " .. tostring(stop_err))
end

function M.test_ndk_rv32imf_flw_mmio_raises_load_access_fault()
    assert(io.exists(FLWFSW_IMAGE_PATH), "missing baremetal_flwfsw.bin in testcase directory: " .. FLWFSW_IMAGE_PATH)

    local ctx, err = ndk.rv32i(FLWFSW_IMAGE_PATH, MEM_SIZE, EXCHANGE_SIZE, {isa = "rv32imf"})
    assert(ctx, "ndk.rv32i with rv32imf failed: " .. tostring(err))
    assert(ndk.setData(ctx, string.char(1), 0), "ndk.setData should select FLW MMIO mode")
    assert(ndk.getData(ctx, 1, 0) == string.char(1), "ndk.getData should reflect FLW MMIO mode selection")

    local ok, ret_or_err, mcause, mtval = ndk.exec(ctx, { steps = 100000, elapsed = 500 })
    assert(ok == false, "rv32imf flw mmio guest should trap")
    assert(ret_or_err == "trap", "rv32imf flw mmio guest should surface trap, got: " .. tostring(ret_or_err))
    assert(mcause == 5, "rv32imf flw mmio guest should raise load access fault, got mcause=" .. tostring(mcause))
    assert(mtval == 0x10000000, string.format("rv32imf flw mmio guest should report mtval 0x10000000, got 0x%08x", tonumber(mtval) or -1))

    local stop_ok, stop_err = ndk.stop(ctx, 1000)
    assert(stop_ok == true, "ndk.stop failed: " .. tostring(stop_err))
end

return M
