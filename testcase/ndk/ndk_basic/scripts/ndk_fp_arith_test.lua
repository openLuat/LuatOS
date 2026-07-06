local M = {}

local IMAGE_PATH = "/luadb/baremetal.bin"
local FADD_IMAGE_PATH = "/luadb/baremetal_fadd.bin"
local FADD_FIRST_IMAGE_PATH = "/luadb/baremetal_fadd_first.bin"
local FSUBMUL_IMAGE_PATH = "/luadb/baremetal_fsubmul.bin"
local FSGNJ_IMAGE_PATH = "/luadb/baremetal_fsgnj.bin"
local FBINOP_NAN_IMAGE_PATH = "/luadb/baremetal_fbinop_nan.bin"
local FCVT_WS_INVALID_IMAGE_PATH = "/luadb/baremetal_fcvt_ws_invalid.bin"
local HARDFLOAT_MULSUB_IMAGE_PATH = "/luadb/baremetal_hardfloat_mulsub.bin"
local HARDFLOAT_FMADD_IMAGE_PATH = "/luadb/baremetal_hardfloat_fmadd.bin"
local HARDFLOAT_FMSUB_IMAGE_PATH = "/luadb/baremetal_hardfloat_fmsub.bin"
local HARDFLOAT_FNM_PROBE_IMAGE_PATH = "/luadb/baremetal_hfnm.bin"
local HARDFLOAT_DIV_IMAGE_PATH = "/luadb/baremetal_hardfloat_div.bin"
local HARDFLOAT_MINMAX_IMAGE_PATH = "/luadb/baremetal_hardfloat_minmax.bin"
local HARDFLOAT_SQRT_IMAGE_PATH = "/luadb/baremetal_hardfloat_sqrt.bin"
local MEM_SIZE = 32 * 1024
local EXCHANGE_SIZE = 1024

local CTX = nil

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

function M.test_ndk_rv32imf_executes_fadd_guest()
    assert(io.exists(FADD_IMAGE_PATH), "missing baremetal_fadd.bin in testcase directory: " .. FADD_IMAGE_PATH)

    local ctx, err = ndk.rv32i(FADD_IMAGE_PATH, MEM_SIZE, EXCHANGE_SIZE, {isa = "rv32imf"})
    assert(ctx, "ndk.rv32i with rv32imf failed: " .. tostring(err))

    local ok, ret_or_err, mcause, mtval = ndk.exec(ctx, { steps = 100000, elapsed = 500 })
    assert(ok == true, string.format("rv32imf fadd guest should succeed, got err=%s mcause=%s mtval=%s", tostring(ret_or_err), tostring(mcause), tostring(mtval)))
    assert(ret_or_err == 0x40400000, string.format("fadd guest should return 3.0f bits, got 0x%08x", tonumber(ret_or_err) or -1))

    local stop_ok, stop_err = ndk.stop(ctx, 1000)
    assert(stop_ok == true, "ndk.stop failed: " .. tostring(stop_err))
end

function M.test_ndk_rv32imf_executes_fadd_first_guest()
    assert(io.exists(FADD_FIRST_IMAGE_PATH), "missing baremetal_fadd_first.bin in testcase directory: " .. FADD_FIRST_IMAGE_PATH)

    local ctx, err = ndk.rv32i(FADD_FIRST_IMAGE_PATH, MEM_SIZE, EXCHANGE_SIZE, {isa = "rv32imf"})
    assert(ctx, "ndk.rv32i with rv32imf failed: " .. tostring(err))

    local ok, ret_or_err, mcause, mtval = ndk.exec(ctx, { steps = 100000, elapsed = 500 })
    assert(ok == true, string.format("rv32imf fadd-first guest should succeed, got err=%s mcause=%s mtval=%s", tostring(ret_or_err), tostring(mcause), tostring(mtval)))
    assert(ret_or_err == 0x00000000, string.format("fadd-first guest should return 0.0f bits, got 0x%08x", tonumber(ret_or_err) or -1))

    local stop_ok, stop_err = ndk.stop(ctx, 1000)
    assert(stop_ok == true, "ndk.stop failed: " .. tostring(stop_err))
end

function M.test_ndk_rv32imf_executes_fsubmul_guest()
    assert(io.exists(FSUBMUL_IMAGE_PATH), "missing baremetal_fsubmul.bin in testcase directory: " .. FSUBMUL_IMAGE_PATH)

    local ctx, err = ndk.rv32i(FSUBMUL_IMAGE_PATH, MEM_SIZE, EXCHANGE_SIZE, {isa = "rv32imf"})
    assert(ctx, "ndk.rv32i with rv32imf failed: " .. tostring(err))

    local ok, ret_or_err, mcause, mtval = ndk.exec(ctx, { steps = 100000, elapsed = 500 })
    assert(ok == true, string.format("rv32imf fsubmul guest should succeed, got err=%s mcause=%s mtval=%s", tostring(ret_or_err), tostring(mcause), tostring(mtval)))
    assert(ret_or_err == 0, "rv32imf fsubmul guest should return 0")

    local data = ndk.getData(ctx, 12, 0)
    assert(type(data) == "string" and #data == 12, "ndk.getData should return 12 bytes for fsubmul results")
    assert(unpack_u32le(data, 0) == 0xbf800000, string.format("FSUB.S should produce -1.0f bits, got 0x%08x", unpack_u32le(data, 0)))
    assert(unpack_u32le(data, 4) == 0xc0400000, string.format("FMUL.S should produce -3.0f bits, got 0x%08x", unpack_u32le(data, 4)))
    assert(unpack_u32le(data, 8) == 0x00, string.format("FSUB/FMUL smoke should leave guest fflags clear, got 0x%02x", unpack_u32le(data, 8)))

    local info = ndk.info(ctx)
    assert(info.fflags == 0x00, string.format("FSUB/FMUL smoke should leave final guest fflags clear, got 0x%02x", tonumber(info.fflags) or -1))

    local stop_ok, stop_err = ndk.stop(ctx, 1000)
    assert(stop_ok == true, "ndk.stop failed: " .. tostring(stop_err))
end

function M.test_ndk_rv32imf_executes_fsgnj_bits_guest()
    assert(io.exists(FSGNJ_IMAGE_PATH), "missing baremetal_fsgnj.bin in testcase directory: " .. FSGNJ_IMAGE_PATH)

    local ctx, err = ndk.rv32i(FSGNJ_IMAGE_PATH, MEM_SIZE, EXCHANGE_SIZE, {isa = "rv32imf"})
    assert(ctx, "ndk.rv32i with rv32imf failed: " .. tostring(err))

    local ok, ret_or_err, mcause, mtval = ndk.exec(ctx, { steps = 100000, elapsed = 500 })
    assert(ok == true, string.format("rv32imf fsgnj guest should succeed, got err=%s mcause=%s mtval=%s", tostring(ret_or_err), tostring(mcause), tostring(mtval)))
    assert(ret_or_err == 0, "rv32imf fsgnj guest should return 0")

    local data = ndk.getData(ctx, 16, 0)
    assert(type(data) == "string" and #data == 16, "ndk.getData should return 16 bytes for fsgnj results")
    assert(unpack_u32le(data, 0) == 0xffc12345, string.format("FSGNJ.S should copy sign from rs2, got 0x%08x", unpack_u32le(data, 0)))
    assert(unpack_u32le(data, 4) == 0x7fc23456, string.format("FSGNJN.S should invert sign from rs2, got 0x%08x", unpack_u32le(data, 4)))
    assert(unpack_u32le(data, 8) == 0x7fc34567, string.format("FSGNJX.S should xor signs, got 0x%08x", unpack_u32le(data, 8)))
    assert(unpack_u32le(data, 12) == 0x00, string.format("FSGNJ* should leave guest fflags clear, got 0x%02x", unpack_u32le(data, 12)))

    local info = ndk.info(ctx)
    assert(info.fflags == 0x00, string.format("FSGNJ* should leave final guest fflags clear, got 0x%02x", tonumber(info.fflags) or -1))

    local stop_ok, stop_err = ndk.stop(ctx, 1000)
    assert(stop_ok == true, "ndk.stop failed: " .. tostring(stop_err))
end

function M.test_ndk_rv32imf_arithmetic_nan_results_are_canonical()
    assert(io.exists(FBINOP_NAN_IMAGE_PATH), "missing baremetal_fbinop_nan.bin in testcase directory: " .. FBINOP_NAN_IMAGE_PATH)

    local ctx, err = ndk.rv32i(FBINOP_NAN_IMAGE_PATH, MEM_SIZE, EXCHANGE_SIZE, {isa = "rv32imf"})
    assert(ctx, "ndk.rv32i with rv32imf failed: " .. tostring(err))

    local ok, ret_or_err, mcause, mtval = ndk.exec(ctx, { steps = 100000, elapsed = 500 })
    assert(ok == true, string.format("rv32imf fbinop NaN guest should succeed, got err=%s mcause=%s mtval=%s", tostring(ret_or_err), tostring(mcause), tostring(mtval)))
    assert(ret_or_err == 0, "rv32imf fbinop NaN guest should return 0")

    local data = ndk.getData(ctx, 16, 0)
    assert(type(data) == "string" and #data == 16, "ndk.getData should return 16 bytes for NaN arithmetic results")
    assert(unpack_u32le(data, 0) == 0x7fc00000, string.format("FADD.S NaN result should be canonical 0x7fc00000, got 0x%08x", unpack_u32le(data, 0)))
    assert(unpack_u32le(data, 4) == 0x7fc00000, string.format("FSUB.S NaN result should be canonical 0x7fc00000, got 0x%08x", unpack_u32le(data, 4)))
    assert(unpack_u32le(data, 8) == 0x7fc00000, string.format("FMUL.S NaN result should be canonical 0x7fc00000, got 0x%08x", unpack_u32le(data, 8)))
    assert(unpack_u32le(data, 12) == 0x00, string.format("quiet-NaN arithmetic should not set guest fflags, got 0x%02x", unpack_u32le(data, 12)))

    local info = ndk.info(ctx)
    assert(info.fflags == 0x00, string.format("quiet-NaN arithmetic should leave final guest fflags clear, got 0x%02x", tonumber(info.fflags) or -1))

    local stop_ok, stop_err = ndk.stop(ctx, 1000)
    assert(stop_ok == true, "ndk.stop failed: " .. tostring(stop_err))
end

function M.test_ndk_rv32imf_compiler_generated_mulsub_smoke()
    assert(io.exists(HARDFLOAT_MULSUB_IMAGE_PATH), "missing baremetal_hardfloat_mulsub.bin in testcase directory: " .. HARDFLOAT_MULSUB_IMAGE_PATH)

    local ctx, err = ndk.rv32i(HARDFLOAT_MULSUB_IMAGE_PATH, MEM_SIZE, EXCHANGE_SIZE, {isa = "rv32imf"})
    assert(ctx, "ndk.rv32i with rv32imf failed: " .. tostring(err))

    local ok, ret_or_err, mcause, mtval = ndk.exec(ctx, { steps = 100000, elapsed = 500 })
    assert(ok == true, string.format("rv32imf hard-float mulsub guest should succeed, got err=%s mcause=%s mtval=%s", tostring(ret_or_err), tostring(mcause), tostring(mtval)))

    local data = ndk.getData(ctx, 4, 0)
    assert(type(data) == "string" and #data == 4, "ndk.getData should return 4 bytes for hard-float smoke result")
    assert(unpack_u32le(data, 0) == 0xc0600000, string.format("compiler-generated hard-float mulsub should produce -3.5f bits 0xc0600000, got 0x%08x", unpack_u32le(data, 0)))

    local stop_ok, stop_err = ndk.stop(ctx, 1000)
    assert(stop_ok == true, "ndk.stop failed: " .. tostring(stop_err))
end

function M.test_ndk_rv32imf_compiler_generated_fmadd_smoke()
    assert(io.exists(HARDFLOAT_FMADD_IMAGE_PATH), "missing baremetal_hardfloat_fmadd.bin in testcase directory: " .. HARDFLOAT_FMADD_IMAGE_PATH)

    local ctx, err = ndk.rv32i(HARDFLOAT_FMADD_IMAGE_PATH, MEM_SIZE, EXCHANGE_SIZE, {isa = "rv32imf"})
    assert(ctx, "ndk.rv32i with rv32imf failed: " .. tostring(err))

    local ok, ret_or_err, mcause, mtval = ndk.exec(ctx, { steps = 100000, elapsed = 500 })
    assert(ok == true, string.format("rv32imf hard-float fmadd guest should succeed, got err=%s mcause=%s mtval=%s", tostring(ret_or_err), tostring(mcause), tostring(mtval)))

    local data = ndk.getData(ctx, 4, 0)
    assert(type(data) == "string" and #data == 4, "ndk.getData should return 4 bytes for hard-float fmadd result")
    assert(unpack_u32le(data, 0) == 0xc0200000, string.format("compiler-generated hard-float fmadd should produce -2.5f bits 0xc0200000, got 0x%08x", unpack_u32le(data, 0)))

    local info = ndk.info(ctx)
    assert(info.fflags == 0x00, string.format("compiler-generated hard-float fmadd should leave fflags clear, got 0x%02x", tonumber(info.fflags) or -1))

    local stop_ok, stop_err = ndk.stop(ctx, 1000)
    assert(stop_ok == true, "ndk.stop failed: " .. tostring(stop_err))
end

function M.test_ndk_rv32imf_compiler_generated_fmsub_smoke()
    assert(io.exists(HARDFLOAT_FMSUB_IMAGE_PATH), "missing baremetal_hardfloat_fmsub.bin in testcase directory: " .. HARDFLOAT_FMSUB_IMAGE_PATH)

    local ctx, err = ndk.rv32i(HARDFLOAT_FMSUB_IMAGE_PATH, MEM_SIZE, EXCHANGE_SIZE, {isa = "rv32imf"})
    assert(ctx, "ndk.rv32i with rv32imf failed: " .. tostring(err))

    local ok, ret_or_err, mcause, mtval = ndk.exec(ctx, { steps = 100000, elapsed = 500 })
    assert(ok == true, string.format("rv32imf hard-float fmsub guest should succeed, got err=%s mcause=%s mtval=%s", tostring(ret_or_err), tostring(mcause), tostring(mtval)))

    local data = ndk.getData(ctx, 4, 0)
    assert(type(data) == "string" and #data == 4, "ndk.getData should return 4 bytes for hard-float fmsub result")
    assert(unpack_u32le(data, 0) == 0xc0600000, string.format("compiler-generated hard-float fmsub should produce -3.5f bits 0xc0600000, got 0x%08x", unpack_u32le(data, 0)))

    local info = ndk.info(ctx)
    assert(info.fflags == 0x00, string.format("compiler-generated hard-float fmsub should leave fflags clear, got 0x%02x", tonumber(info.fflags) or -1))

    local stop_ok, stop_err = ndk.stop(ctx, 1000)
    assert(stop_ok == true, "ndk.stop failed: " .. tostring(stop_err))
end

function M.test_ndk_rv32imf_compiler_generated_fnm_probe_smoke()
    assert(io.exists(HARDFLOAT_FNM_PROBE_IMAGE_PATH), "missing baremetal_hfnm.bin in testcase directory: " .. HARDFLOAT_FNM_PROBE_IMAGE_PATH)

    local ctx, err = ndk.rv32i(HARDFLOAT_FNM_PROBE_IMAGE_PATH, MEM_SIZE, EXCHANGE_SIZE, {isa = "rv32imf"})
    assert(ctx, "ndk.rv32i with rv32imf failed: " .. tostring(err))

    local ok, ret_or_err, mcause, mtval = ndk.exec(ctx, { steps = 100000, elapsed = 500 })
    assert(ok == true, string.format("rv32imf hard-float fnm probe guest should succeed, got err=%s mcause=%s mtval=%s", tostring(ret_or_err), tostring(mcause), tostring(mtval)))

    local data = ndk.getData(ctx, 8, 0)
    assert(type(data) == "string" and #data == 8, "ndk.getData should return 8 bytes for hard-float fnm probe result")
    assert(unpack_u32le(data, 0) == 0x40600000, string.format("compiler-generated hard-float fnm probe slot0 should produce 3.5f bits 0x40600000, got 0x%08x", unpack_u32le(data, 0)))
    assert(unpack_u32le(data, 4) == 0x40200000, string.format("compiler-generated hard-float fnm probe slot1 should produce 2.5f bits 0x40200000, got 0x%08x", unpack_u32le(data, 4)))

    local info = ndk.info(ctx)
    assert(info.fflags == 0x00, string.format("compiler-generated hard-float fnm probe should leave fflags clear, got 0x%02x", tonumber(info.fflags) or -1))

    local stop_ok, stop_err = ndk.stop(ctx, 1000)
    assert(stop_ok == true, "ndk.stop failed: " .. tostring(stop_err))
end

function M.test_ndk_rv32imf_compiler_generated_div_smoke()
    assert(io.exists(HARDFLOAT_DIV_IMAGE_PATH), "missing baremetal_hardfloat_div.bin in testcase directory: " .. HARDFLOAT_DIV_IMAGE_PATH)

    local ctx, err = ndk.rv32i(HARDFLOAT_DIV_IMAGE_PATH, MEM_SIZE, EXCHANGE_SIZE, {isa = "rv32imf"})
    assert(ctx, "ndk.rv32i with rv32imf failed: " .. tostring(err))

    local ok, ret_or_err, mcause, mtval = ndk.exec(ctx, { steps = 100000, elapsed = 500 })
    assert(ok == true, string.format("rv32imf hard-float div guest should succeed, got err=%s mcause=%s mtval=%s", tostring(ret_or_err), tostring(mcause), tostring(mtval)))

    local data = ndk.getData(ctx, 4, 0)
    assert(type(data) == "string" and #data == 4, "ndk.getData should return 4 bytes for hard-float div result")
    assert(unpack_u32le(data, 0) == 0x40600000, string.format("compiler-generated hard-float div should produce 3.5f bits 0x40600000, got 0x%08x", unpack_u32le(data, 0)))

    local info = ndk.info(ctx)
    assert(info.fflags == 0x00, string.format("compiler-generated hard-float div should leave fflags clear, got 0x%02x", tonumber(info.fflags) or -1))

    local stop_ok, stop_err = ndk.stop(ctx, 1000)
    assert(stop_ok == true, "ndk.stop failed: " .. tostring(stop_err))
end

function M.test_ndk_rv32imf_compiler_generated_minmax_smoke()
    assert(io.exists(HARDFLOAT_MINMAX_IMAGE_PATH), "missing baremetal_hardfloat_minmax.bin in testcase directory: " .. HARDFLOAT_MINMAX_IMAGE_PATH)

    local ctx, err = ndk.rv32i(HARDFLOAT_MINMAX_IMAGE_PATH, MEM_SIZE, EXCHANGE_SIZE, {isa = "rv32imf"})
    assert(ctx, "ndk.rv32i with rv32imf failed: " .. tostring(err))

    local ok, ret_or_err, mcause, mtval = ndk.exec(ctx, { steps = 100000, elapsed = 500 })
    assert(ok == true, string.format("rv32imf hard-float minmax guest should succeed, got err=%s mcause=%s mtval=%s", tostring(ret_or_err), tostring(mcause), tostring(mtval)))

    local data = ndk.getData(ctx, 8, 0)
    assert(type(data) == "string" and #data == 8, "ndk.getData should return 8 bytes for hard-float minmax result")
    assert(unpack_u32le(data, 0) == 0xc0000000, string.format("compiler-generated hard-float fmin should produce -2.0f bits 0xc0000000, got 0x%08x", unpack_u32le(data, 0)))
    assert(unpack_u32le(data, 4) == 0x40800000, string.format("compiler-generated hard-float fmax should produce 4.0f bits 0x40800000, got 0x%08x", unpack_u32le(data, 4)))

    local info = ndk.info(ctx)
    assert(info.fflags == 0x00, string.format("compiler-generated hard-float minmax should leave fflags clear, got 0x%02x", tonumber(info.fflags) or -1))

    local stop_ok, stop_err = ndk.stop(ctx, 1000)
    assert(stop_ok == true, "ndk.stop failed: " .. tostring(stop_err))
end

function M.test_ndk_rv32imf_compiler_generated_sqrt_smoke()
    assert(io.exists(HARDFLOAT_SQRT_IMAGE_PATH), "missing baremetal_hardfloat_sqrt.bin in testcase directory: " .. HARDFLOAT_SQRT_IMAGE_PATH)

    local ctx, err = ndk.rv32i(HARDFLOAT_SQRT_IMAGE_PATH, MEM_SIZE, EXCHANGE_SIZE, {isa = "rv32imf"})
    assert(ctx, "ndk.rv32i with rv32imf failed: " .. tostring(err))

    local ok, ret_or_err, mcause, mtval = ndk.exec(ctx, { steps = 100000, elapsed = 500 })
    assert(ok == true, string.format("rv32imf hard-float sqrt guest should succeed, got err=%s mcause=%s mtval=%s", tostring(ret_or_err), tostring(mcause), tostring(mtval)))

    local data = ndk.getData(ctx, 4, 0)
    assert(type(data) == "string" and #data == 4, "ndk.getData should return 4 bytes for hard-float sqrt result")
    assert(unpack_u32le(data, 0) == 0x3fc00000, string.format("compiler-generated hard-float sqrt should produce 1.5f bits 0x3fc00000, got 0x%08x", unpack_u32le(data, 0)))

    local info = ndk.info(ctx)
    assert(info.fflags == 0x00, string.format("compiler-generated hard-float sqrt should leave fflags clear, got 0x%02x", tonumber(info.fflags) or -1))

    local stop_ok, stop_err = ndk.stop(ctx, 1000)
    assert(stop_ok == true, "ndk.stop failed: " .. tostring(stop_err))
end

return M
