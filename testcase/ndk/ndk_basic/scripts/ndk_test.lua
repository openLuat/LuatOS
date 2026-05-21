local ndk_tests = {}

local IMAGE_PATH = "/luadb/baremetal.bin"
local FCSR_IMAGE_PATH = "/luadb/baremetal_fcsr.bin"
local FMV_IMAGE_PATH = "/luadb/baremetal_fmv.bin"
local FLWFSW_IMAGE_PATH = "/luadb/baremetal_flwfsw.bin"
local FADD_IMAGE_PATH = "/luadb/baremetal_fadd.bin"
local FADD_FIRST_IMAGE_PATH = "/luadb/baremetal_fadd_first.bin"
local FADD_ROUNDING_IMAGE_PATH = "/luadb/baremetal_fadd_rounding.bin"
local FADD_RMM_STATIC_IMAGE_PATH = "/luadb/baremetal_fadd_rmm_static.bin"
local FADD_RMM_DYNAMIC_IMAGE_PATH = "/luadb/baremetal_fadd_rmm_dynamic.bin"
local FCMP_IMAGE_PATH = "/luadb/baremetal_fcmp.bin"
local FCLASS_IMAGE_PATH = "/luadb/baremetal_fclass.bin"
local FCVTSW_IMAGE_PATH = "/luadb/baremetal_fcvtsw.bin"
local FCVT_DYN_RUP_IMAGE_PATH = "/luadb/baremetal_fcvt_dyn_rup.bin"
local FSUBMUL_IMAGE_PATH = "/luadb/baremetal_fsubmul.bin"
local FSGNJ_IMAGE_PATH = "/luadb/baremetal_fsgnj.bin"
local FBINOP_NAN_IMAGE_PATH = "/luadb/baremetal_fbinop_nan.bin"
local FCVT_WS_INVALID_IMAGE_PATH = "/luadb/baremetal_fcvt_ws_invalid.bin"
local HARDFLOAT_MULSUB_IMAGE_PATH = "/luadb/baremetal_hardfloat_mulsub.bin"
local HARDFLOAT_CAST_IMAGE_PATH = "/luadb/baremetal_hardfloat_cast.bin"
local HARDFLOAT_FMADD_IMAGE_PATH = "/luadb/baremetal_hardfloat_fmadd.bin"
local HARDFLOAT_FMSUB_IMAGE_PATH = "/luadb/baremetal_hardfloat_fmsub.bin"
local HARDFLOAT_FNM_PROBE_IMAGE_PATH = "/luadb/baremetal_hfnm.bin"
local HARDFLOAT_DIV_IMAGE_PATH = "/luadb/baremetal_hardfloat_div.bin"
local HARDFLOAT_MINMAX_IMAGE_PATH = "/luadb/baremetal_hardfloat_minmax.bin"
local HARDFLOAT_SQRT_IMAGE_PATH = "/luadb/baremetal_hardfloat_sqrt.bin"
local MEM_SIZE = 32 * 1024
local EXCHANGE_SIZE = 1024
local INVALID_IMAGE_PATH = "/luadb/not-exists.bin"
local NDK_FEATURE_GPIO = 1 << 3
local NDK_FEATURE_CRYPTO = 1 << 5
local GUEST_IMAGE_BASE = 0x80000000

if false then
    ndk.rv32i("/luadb/baremetal_hfnm.bin", MEM_SIZE, EXCHANGE_SIZE)
end

local function wait_until(predicate, timeout_ms)
    local waited = 0
    while waited < timeout_ms do
        if predicate() then
            return true
        end
        sys.wait(10)
        waited = waited + 10
    end
    return predicate()
end

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

local function find_first_rv32f_instruction_pc(image_path)
    local data = io.readFile(image_path)
    if type(data) ~= "string" or #data < 4 then
        return nil
    end
    for offset = 0, #data - 4, 4 do
        local instruction_bits = unpack_u32le(data, offset)
        local opcode = instruction_bits & 0x7f
        local funct3 = (instruction_bits >> 12) & 0x7
        if ((opcode == 0x07 or opcode == 0x27) and funct3 == 0x2)
            or opcode == 0x43
            or opcode == 0x47
            or opcode == 0x4b
            or opcode == 0x4f
            or opcode == 0x53 then
            return GUEST_IMAGE_BASE + offset
        end
    end
    return nil
end

local function find_fadd_instruction_pc_by_rm(image_path, expected_rm)
    local data = io.readFile(image_path)
    if type(data) ~= "string" or #data < 4 then
        return nil
    end
    for offset = 0, #data - 4, 4 do
        local instruction_bits = unpack_u32le(data, offset)
        local opcode = instruction_bits & 0x7f
        local funct7 = (instruction_bits >> 25) & 0x7f
        local rm = (instruction_bits >> 12) & 0x7
        if opcode == 0x53 and funct7 == 0x00 and rm == expected_rm then
            return GUEST_IMAGE_BASE + offset
        end
    end
    return nil
end

function ndk_tests.test_ndk_lifecycle_regression()
    assert(io.exists(IMAGE_PATH), "missing baremetal.bin in testcase directory: " .. IMAGE_PATH)

    local ctx, err = ndk.rv32i(IMAGE_PATH, MEM_SIZE, EXCHANGE_SIZE)
    assert(ctx, "ndk.rv32i failed: " .. tostring(err))

    local info = ndk.info(ctx)
    assert(type(info) == "table", "ndk.info should return table")
    assert_info_fields(info)
    assert(info.mem == MEM_SIZE, "unexpected mem size: " .. tostring(info.mem))
    assert(info.exchange == EXCHANGE_SIZE, "unexpected exchange size: " .. tostring(info.exchange))
    assert((info.features & NDK_FEATURE_GPIO) ~= 0, "ndk.info should expose GPIO feature bit")
    assert((info.features & NDK_FEATURE_CRYPTO) ~= 0, "ndk.info should expose CRYPTO feature bit")

    local ok, ret_or_err, mcause, mtval = ndk.exec(ctx, { steps = 100000, elapsed = 500 })
    assert(ok == true, string.format("ndk.exec failed: %s mcause=%s mtval=%s", tostring(ret_or_err), tostring(mcause), tostring(mtval)))
    assert(type(ret_or_err) == "number", "ndk.exec should return numeric retval")

    local idle_info = ndk.info(ctx)
    assert(type(idle_info) == "table", "ndk.info after exec should return table")
    assert(idle_info.running == false, "ndk must be idle before ndk.reset")

    local reset_ok, reset_err = ndk.reset(ctx)
    assert(reset_ok == true, "ndk.reset failed: " .. tostring(reset_err))

    local stop_ok, stop_err = ndk.stop(ctx, 1000)
    assert(stop_ok == true, "ndk.stop no-op failed: " .. tostring(stop_err))

    ctx = nil
    collectgarbage("collect")
    collectgarbage("collect")
end

function ndk_tests.test_ndk_constructor_failure_no_gc_crash()
    local ok, msg = pcall(function()
        local ctx, err = ndk.rv32i(INVALID_IMAGE_PATH, MEM_SIZE, EXCHANGE_SIZE)
        assert(ctx == nil, "ndk.rv32i with invalid image should return nil")
        assert(type(err) == "string" and #err > 0, "ndk.rv32i with invalid image should return err string")
        collectgarbage("collect")
        collectgarbage("collect")
    end)
    assert(ok, "constructor failure path should not crash GC: " .. tostring(msg))
end

function ndk_tests.test_ndk_constructor_accepts_rv32imf_isa_option()
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

function ndk_tests.test_ndk_default_rv32i_does_not_expose_fcsr_shadow_state()
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

function ndk_tests.test_ndk_reset_preserves_rv32imf_isa_metadata()
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

function ndk_tests.test_ndk_rv32imf_executes_fmv_roundtrip_guest()
    assert(io.exists(FMV_IMAGE_PATH), "missing baremetal_fmv.bin in testcase directory: " .. FMV_IMAGE_PATH)

    local ctx, err = ndk.rv32i(FMV_IMAGE_PATH, MEM_SIZE, EXCHANGE_SIZE, {isa = "rv32imf"})
    assert(ctx, "ndk.rv32i with rv32imf failed: " .. tostring(err))

    local ok, ret_or_err, mcause, mtval = ndk.exec(ctx, { steps = 100000, elapsed = 500 })
    assert(ok == true, string.format("rv32imf fmv guest should succeed, got err=%s mcause=%s mtval=%s", tostring(ret_or_err), tostring(mcause), tostring(mtval)))
    assert(ret_or_err == 0x3f800000, string.format("fmv roundtrip should preserve bits, got 0x%08x", tonumber(ret_or_err) or -1))

    local stop_ok, stop_err = ndk.stop(ctx, 1000)
    assert(stop_ok == true, "ndk.stop failed: " .. tostring(stop_err))
end

function ndk_tests.test_ndk_default_rv32i_traps_on_fmv_guest()
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

function ndk_tests.test_ndk_rv32imf_executes_flwfsw_roundtrip_guest()
    assert(io.exists(FLWFSW_IMAGE_PATH), "missing baremetal_flwfsw.bin in testcase directory: " .. FLWFSW_IMAGE_PATH)

    local ctx, err = ndk.rv32i(FLWFSW_IMAGE_PATH, MEM_SIZE, EXCHANGE_SIZE, {isa = "rv32imf"})
    assert(ctx, "ndk.rv32i with rv32imf failed: " .. tostring(err))

    local ok, ret_or_err, mcause, mtval = ndk.exec(ctx, { steps = 100000, elapsed = 500 })
    assert(ok == true, string.format("rv32imf flw/fsw guest should succeed, got err=%s mcause=%s mtval=%s", tostring(ret_or_err), tostring(mcause), tostring(mtval)))
    assert(ret_or_err == 0x12345678, string.format("flw/fsw roundtrip should preserve bits, got 0x%08x", tonumber(ret_or_err) or -1))

    local stop_ok, stop_err = ndk.stop(ctx, 1000)
    assert(stop_ok == true, "ndk.stop failed: " .. tostring(stop_err))
end

function ndk_tests.test_ndk_default_rv32i_traps_on_flwfsw_guest()
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

function ndk_tests.test_ndk_rv32imf_flw_mmio_raises_load_access_fault()
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

function ndk_tests.test_ndk_rv32imf_executes_fadd_guest()
    assert(io.exists(FADD_IMAGE_PATH), "missing baremetal_fadd.bin in testcase directory: " .. FADD_IMAGE_PATH)

    local ctx, err = ndk.rv32i(FADD_IMAGE_PATH, MEM_SIZE, EXCHANGE_SIZE, {isa = "rv32imf"})
    assert(ctx, "ndk.rv32i with rv32imf failed: " .. tostring(err))

    local ok, ret_or_err, mcause, mtval = ndk.exec(ctx, { steps = 100000, elapsed = 500 })
    assert(ok == true, string.format("rv32imf fadd guest should succeed, got err=%s mcause=%s mtval=%s", tostring(ret_or_err), tostring(mcause), tostring(mtval)))
    assert(ret_or_err == 0x40400000, string.format("fadd guest should return 3.0f bits, got 0x%08x", tonumber(ret_or_err) or -1))

    local stop_ok, stop_err = ndk.stop(ctx, 1000)
    assert(stop_ok == true, "ndk.stop failed: " .. tostring(stop_err))
end

function ndk_tests.test_ndk_rv32imf_executes_fadd_first_guest()
    assert(io.exists(FADD_FIRST_IMAGE_PATH), "missing baremetal_fadd_first.bin in testcase directory: " .. FADD_FIRST_IMAGE_PATH)

    local ctx, err = ndk.rv32i(FADD_FIRST_IMAGE_PATH, MEM_SIZE, EXCHANGE_SIZE, {isa = "rv32imf"})
    assert(ctx, "ndk.rv32i with rv32imf failed: " .. tostring(err))

    local ok, ret_or_err, mcause, mtval = ndk.exec(ctx, { steps = 100000, elapsed = 500 })
    assert(ok == true, string.format("rv32imf fadd-first guest should succeed, got err=%s mcause=%s mtval=%s", tostring(ret_or_err), tostring(mcause), tostring(mtval)))
    assert(ret_or_err == 0x00000000, string.format("fadd-first guest should return 0.0f bits, got 0x%08x", tonumber(ret_or_err) or -1))

    local stop_ok, stop_err = ndk.stop(ctx, 1000)
    assert(stop_ok == true, "ndk.stop failed: " .. tostring(stop_err))
end

function ndk_tests.test_ndk_rv32imf_fadd_ignores_ambient_host_round_up()
    assert(io.exists(FADD_ROUNDING_IMAGE_PATH), "missing baremetal_fadd_rounding.bin in testcase directory: " .. FADD_ROUNDING_IMAGE_PATH)
    assert(hostfenv ~= nil, "hostfenv helper should be available on PC simulator")

    local ctx, err = ndk.rv32i(FADD_ROUNDING_IMAGE_PATH, MEM_SIZE, EXCHANGE_SIZE, {isa = "rv32imf"})
    assert(ctx, "ndk.rv32i with rv32imf failed: " .. tostring(err))

    local original_mode = hostfenv.get()
    assert(type(original_mode) == "string", "hostfenv.get should return current rounding mode")
    assert(type(hostfenv.getflags) == "function", "hostfenv.getflags should expose host FP status flags")
    assert(type(hostfenv.clearflags) == "function", "hostfenv.clearflags should clear host FP status flags")
    assert(type(hostfenv.FLAG_INEXACT) == "number", "hostfenv should expose FLAG_INEXACT constant")
    assert(hostfenv.set("upward") == true, "hostfenv.set should switch host rounding upward")
    assert(hostfenv.clearflags() == true, "hostfenv.clearflags should clear host FP status flags")

    local ok, exec_err = pcall(function()
        local exec_ok, exec_ret_or_err, exec_mcause, exec_mtval = ndk.exec(ctx, { steps = 100000, elapsed = 500 })
        assert(exec_ok == true, string.format("rv32imf rounding guest should succeed, got err=%s mcause=%s mtval=%s", tostring(exec_ret_or_err), tostring(exec_mcause), tostring(exec_mtval)))
        assert(exec_ret_or_err == 0x3f800000, string.format("rv32imf rounding guest should keep RNE result 0x3f800000, got 0x%08x", tonumber(exec_ret_or_err) or -1))
        local info = ndk.info(ctx)
        assert(type(info) == "table", "ndk.info should return runtime info after FADD")
        assert(info.fflags == 0x01, string.format("rv32imf rounding guest should record NX in guest fflags, got 0x%02x", tonumber(info.fflags) or -1))
        assert(info.fcsr == 0x01, string.format("rv32imf rounding guest should preserve guest fcsr NX bit, got 0x%02x", tonumber(info.fcsr) or -1))
        assert(info.frm == 0x00, string.format("rv32imf rounding guest should keep frm at RNE, got 0x%02x", tonumber(info.frm) or -1))
        assert(hostfenv.get() == "upward", "ndk.exec should restore ambient host rounding mode after FADD")
        assert((hostfenv.getflags() & hostfenv.FLAG_INEXACT) == 0, "ndk.exec should restore host FP status flags after FADD")
    end)

    assert(hostfenv.set(original_mode) == true, "hostfenv.set should restore original host rounding mode")
    assert(ok == true, tostring(exec_err))

    local stop_ok, stop_err = ndk.stop(ctx, 1000)
    assert(stop_ok == true, "ndk.stop failed: " .. tostring(stop_err))
end

function ndk_tests.test_ndk_rv32imf_traps_on_static_rmm_rounding_mode()
    assert(io.exists(FADD_RMM_STATIC_IMAGE_PATH), "missing baremetal_fadd_rmm_static.bin in testcase directory: " .. FADD_RMM_STATIC_IMAGE_PATH)

    local ctx, err = ndk.rv32i(FADD_RMM_STATIC_IMAGE_PATH, MEM_SIZE, EXCHANGE_SIZE, {isa = "rv32imf"})
    assert(ctx, "ndk.rv32i with rv32imf failed: " .. tostring(err))

    local ok, ret_or_err, mcause, mtval = ndk.exec(ctx, { steps = 100000, elapsed = 500 })
    assert(ok == false, "rv32imf should trap on static RMM (rm=4)")
    assert(ret_or_err == "trap", "rv32imf static RMM should surface trap, got: " .. tostring(ret_or_err))
    assert(mcause == 2, "rv32imf static RMM should raise illegal instruction trap, got mcause=" .. tostring(mcause))
    local expected_mtval = find_fadd_instruction_pc_by_rm(FADD_RMM_STATIC_IMAGE_PATH, 4)
    assert(expected_mtval ~= nil, "should locate FADD.S rm=4 instruction in static RMM guest")
    assert(mtval == expected_mtval, string.format("rv32imf static RMM should trap at FADD.S rm=4, got 0x%08x expected 0x%08x", tonumber(mtval) or -1, tonumber(expected_mtval) or -1))

    local stop_ok, stop_err = ndk.stop(ctx, 1000)
    assert(stop_ok == true, "ndk.stop failed: " .. tostring(stop_err))
end

function ndk_tests.test_ndk_rv32imf_traps_on_dynamic_rmm_rounding_mode()
    assert(io.exists(FADD_RMM_DYNAMIC_IMAGE_PATH), "missing baremetal_fadd_rmm_dynamic.bin in testcase directory: " .. FADD_RMM_DYNAMIC_IMAGE_PATH)

    local ctx, err = ndk.rv32i(FADD_RMM_DYNAMIC_IMAGE_PATH, MEM_SIZE, EXCHANGE_SIZE, {isa = "rv32imf"})
    assert(ctx, "ndk.rv32i with rv32imf failed: " .. tostring(err))

    local ok, ret_or_err, mcause, mtval = ndk.exec(ctx, { steps = 100000, elapsed = 500 })
    assert(ok == false, "rv32imf should trap on dynamic RMM (frm=4 + rm=dyn)")
    assert(ret_or_err == "trap", "rv32imf dynamic RMM should surface trap, got: " .. tostring(ret_or_err))
    assert(mcause == 2, "rv32imf dynamic RMM should raise illegal instruction trap, got mcause=" .. tostring(mcause))
    local expected_mtval = find_fadd_instruction_pc_by_rm(FADD_RMM_DYNAMIC_IMAGE_PATH, 7)
    assert(expected_mtval ~= nil, "should locate FADD.S rm=dyn instruction in dynamic RMM guest")
    assert(mtval == expected_mtval, string.format("rv32imf dynamic RMM should trap at FADD.S rm=dyn with frm=4, got 0x%08x expected 0x%08x", tonumber(mtval) or -1, tonumber(expected_mtval) or -1))

    local stop_ok, stop_err = ndk.stop(ctx, 1000)
    assert(stop_ok == true, "ndk.stop failed: " .. tostring(stop_err))
end

function ndk_tests.test_ndk_rv32imf_compare_tracks_nan_results_and_flags()
    assert(io.exists(FCMP_IMAGE_PATH), "missing baremetal_fcmp.bin in testcase directory: " .. FCMP_IMAGE_PATH)

    local ctx, err = ndk.rv32i(FCMP_IMAGE_PATH, MEM_SIZE, EXCHANGE_SIZE, {isa = "rv32imf"})
    assert(ctx, "ndk.rv32i with rv32imf failed: " .. tostring(err))

    local ok, ret_or_err, mcause, mtval = ndk.exec(ctx, { steps = 100000, elapsed = 500 })
    assert(ok == true, string.format("rv32imf compare guest should succeed, got err=%s mcause=%s mtval=%s", tostring(ret_or_err), tostring(mcause), tostring(mtval)))
    assert(ret_or_err == 0, "rv32imf compare guest should return 0")

    local data = ndk.getData(ctx, 32, 0)
    assert(type(data) == "string" and #data == 32, "ndk.getData should return 32 bytes for compare results")
    assert(unpack_u32le(data, 0) == 0, "FEQ.S qNaN should return 0")
    assert(unpack_u32le(data, 4) == 0, "FEQ.S qNaN should not set NV")
    assert(unpack_u32le(data, 8) == 0, "FEQ.S sNaN should return 0")
    assert(unpack_u32le(data, 12) == 0x10, string.format("FEQ.S sNaN should set NV, got 0x%02x", unpack_u32le(data, 12)))
    assert(unpack_u32le(data, 16) == 0, "FLT.S qNaN should return 0")
    assert(unpack_u32le(data, 20) == 0x10, string.format("FLT.S qNaN should set NV, got 0x%02x", unpack_u32le(data, 20)))
    assert(unpack_u32le(data, 24) == 0, "FLE.S qNaN should return 0")
    assert(unpack_u32le(data, 28) == 0x10, string.format("FLE.S qNaN should set NV, got 0x%02x", unpack_u32le(data, 28)))

    local info = ndk.info(ctx)
    assert(info.fflags == 0x10, string.format("compare guest should leave NV set in guest fflags, got 0x%02x", tonumber(info.fflags) or -1))

    local stop_ok, stop_err = ndk.stop(ctx, 1000)
    assert(stop_ok == true, "ndk.stop failed: " .. tostring(stop_err))
end

function ndk_tests.test_ndk_rv32imf_fclass_smoke_bits()
    assert(io.exists(FCLASS_IMAGE_PATH), "missing baremetal_fclass.bin in testcase directory: " .. FCLASS_IMAGE_PATH)

    local ctx, err = ndk.rv32i(FCLASS_IMAGE_PATH, MEM_SIZE, EXCHANGE_SIZE, {isa = "rv32imf"})
    assert(ctx, "ndk.rv32i with rv32imf failed: " .. tostring(err))

    local ok, ret_or_err, mcause, mtval = ndk.exec(ctx, { steps = 100000, elapsed = 500 })
    assert(ok == true, string.format("rv32imf fclass guest should succeed, got err=%s mcause=%s mtval=%s", tostring(ret_or_err), tostring(mcause), tostring(mtval)))
    assert(ret_or_err == 0, "rv32imf fclass guest should return 0")

    local data = ndk.getData(ctx, 16, 0)
    assert(type(data) == "string" and #data == 16, "ndk.getData should return 16 bytes for fclass results")
    assert(unpack_u32le(data, 0) == 0x08, string.format("FCLASS.S should classify -0 as bit 3, got 0x%03x", unpack_u32le(data, 0)))
    assert(unpack_u32le(data, 4) == 0x20, string.format("FCLASS.S should classify +subnormal as bit 5, got 0x%03x", unpack_u32le(data, 4)))
    assert(unpack_u32le(data, 8) == 0x100, string.format("FCLASS.S should classify sNaN as bit 8, got 0x%03x", unpack_u32le(data, 8)))
    assert(unpack_u32le(data, 12) == 0x200, string.format("FCLASS.S should classify qNaN as bit 9, got 0x%03x", unpack_u32le(data, 12)))

    local info = ndk.info(ctx)
    assert(info.fflags == 0, string.format("FCLASS.S should not set guest fflags, got 0x%02x", tonumber(info.fflags) or -1))

    local stop_ok, stop_err = ndk.stop(ctx, 1000)
    assert(stop_ok == true, "ndk.stop failed: " .. tostring(stop_err))
end

function ndk_tests.test_ndk_rv32imf_fcvt_sw_ignores_ambient_host_round_up()
    assert(io.exists(FCVTSW_IMAGE_PATH), "missing baremetal_fcvtsw.bin in testcase directory: " .. FCVTSW_IMAGE_PATH)
    assert(hostfenv ~= nil, "hostfenv helper should be available on PC simulator")

    local ctx, err = ndk.rv32i(FCVTSW_IMAGE_PATH, MEM_SIZE, EXCHANGE_SIZE, {isa = "rv32imf"})
    assert(ctx, "ndk.rv32i with rv32imf failed: " .. tostring(err))

    local original_mode = hostfenv.get()
    assert(type(original_mode) == "string", "hostfenv.get should return current rounding mode")
    assert(hostfenv.set("upward") == true, "hostfenv.set should switch host rounding upward")
    assert(hostfenv.clearflags() == true, "hostfenv.clearflags should clear host FP status flags")

    local ok, exec_err = pcall(function()
        local exec_ok, ret_or_err, mcause, mtval = ndk.exec(ctx, { steps = 100000, elapsed = 500 })
        assert(exec_ok == true, string.format("rv32imf fcvt guest should succeed, got err=%s mcause=%s mtval=%s", tostring(ret_or_err), tostring(mcause), tostring(mtval)))
        assert(ret_or_err == 0, "rv32imf fcvt guest should return 0")

        local data = ndk.getData(ctx, 16, 0)
        assert(type(data) == "string" and #data == 16, "ndk.getData should return 16 bytes for fcvt results")
        assert(unpack_u32le(data, 0) == 0x4b800000, string.format("FCVT.S.W should keep RNE result 0x4b800000, got 0x%08x", unpack_u32le(data, 0)))
        assert(unpack_u32le(data, 4) == 0x3f800000, string.format("FCVT.S.WU should convert 1u to 1.0f, got 0x%08x", unpack_u32le(data, 4)))
        assert(unpack_u32le(data, 8) == 0x01, string.format("FCVT.S.W should set NX for 16777217, got 0x%02x", unpack_u32le(data, 8)))
        assert(unpack_u32le(data, 12) == 0x00, string.format("FCVT.S.WU should stay exact for 1u, got 0x%02x", unpack_u32le(data, 12)))

        local info = ndk.info(ctx)
        assert(info.fflags == 0x00, string.format("final guest fflags should reflect last exact FCVT.S.WU, got 0x%02x", tonumber(info.fflags) or -1))
        assert(hostfenv.get() == "upward", "ndk.exec should restore ambient host rounding mode after FCVT")
        assert((hostfenv.getflags() & hostfenv.FLAG_INEXACT) == 0, "ndk.exec should restore host FP status flags after FCVT")
    end)

    assert(hostfenv.set(original_mode) == true, "hostfenv.set should restore original host rounding mode")
    assert(ok == true, tostring(exec_err))

    local stop_ok, stop_err = ndk.stop(ctx, 1000)
    assert(stop_ok == true, "ndk.stop failed: " .. tostring(stop_err))
end

function ndk_tests.test_ndk_rv32imf_fcvt_sw_honors_dynamic_frm_rup()
    assert(io.exists(FCVT_DYN_RUP_IMAGE_PATH), "missing baremetal_fcvt_dyn_rup.bin in testcase directory: " .. FCVT_DYN_RUP_IMAGE_PATH)

    local ctx, err = ndk.rv32i(FCVT_DYN_RUP_IMAGE_PATH, MEM_SIZE, EXCHANGE_SIZE, {isa = "rv32imf"})
    assert(ctx, "ndk.rv32i with rv32imf failed: " .. tostring(err))

    local ok, ret_or_err, mcause, mtval = ndk.exec(ctx, { steps = 100000, elapsed = 500 })
    assert(ok == true, string.format("rv32imf fcvt dyn-rup guest should succeed, got err=%s mcause=%s mtval=%s", tostring(ret_or_err), tostring(mcause), tostring(mtval)))
    assert(ret_or_err == 0, "rv32imf fcvt dyn-rup guest should return 0")

    local data = ndk.getData(ctx, 8, 0)
    assert(type(data) == "string" and #data == 8, "ndk.getData should return 8 bytes for dyn-rup fcvt results")
    assert(unpack_u32le(data, 0) == 0x4b800001, string.format("FCVT.S.W with dynamic RUP should round 16777217 upward to 0x4b800001, got 0x%08x", unpack_u32le(data, 0)))
    assert(unpack_u32le(data, 4) == 0x01, string.format("FCVT.S.W with dynamic RUP should set NX, got 0x%02x", unpack_u32le(data, 4)))

    local info = ndk.info(ctx)
    assert(info.frm == 0x03, string.format("dynamic-RUP guest should leave frm at 3, got 0x%02x", tonumber(info.frm) or -1))
    assert(info.fflags == 0x01, string.format("dynamic-RUP guest should leave NX set, got 0x%02x", tonumber(info.fflags) or -1))

    local stop_ok, stop_err = ndk.stop(ctx, 1000)
    assert(stop_ok == true, "ndk.stop failed: " .. tostring(stop_err))
end

function ndk_tests.test_ndk_rv32imf_executes_fsubmul_guest()
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

function ndk_tests.test_ndk_rv32imf_executes_fsgnj_bits_guest()
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

function ndk_tests.test_ndk_rv32imf_arithmetic_nan_results_are_canonical()
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

function ndk_tests.test_ndk_rv32imf_fcvt_ws_invalid_clips_per_spec()
    assert(io.exists(FCVT_WS_INVALID_IMAGE_PATH), "missing baremetal_fcvt_ws_invalid.bin in testcase directory: " .. FCVT_WS_INVALID_IMAGE_PATH)

    local ctx, err = ndk.rv32i(FCVT_WS_INVALID_IMAGE_PATH, MEM_SIZE, EXCHANGE_SIZE, {isa = "rv32imf"})
    assert(ctx, "ndk.rv32i with rv32imf failed: " .. tostring(err))

    local ok, ret_or_err, mcause, mtval = ndk.exec(ctx, { steps = 100000, elapsed = 500 })
    assert(ok == true, string.format("rv32imf invalid fcvt guest should succeed, got err=%s mcause=%s mtval=%s", tostring(ret_or_err), tostring(mcause), tostring(mtval)))
    assert(ret_or_err == 0, "rv32imf invalid fcvt guest should return 0")

    local data = ndk.getData(ctx, 40, 0)
    assert(type(data) == "string" and #data == 40, "ndk.getData should return 40 bytes for invalid fcvt results")
    assert(unpack_u32le(data, 0) == 0x7fffffff, string.format("FCVT.W.S +Inf should clip to 0x7fffffff, got 0x%08x", unpack_u32le(data, 0)))
    assert(unpack_u32le(data, 4) == 0x10, string.format("FCVT.W.S +Inf should set NV, got 0x%02x", unpack_u32le(data, 4)))
    assert(unpack_u32le(data, 8) == 0x7fffffff, string.format("FCVT.W.S qNaN should clip to 0x7fffffff, got 0x%08x", unpack_u32le(data, 8)))
    assert(unpack_u32le(data, 12) == 0x10, string.format("FCVT.W.S qNaN should set NV, got 0x%02x", unpack_u32le(data, 12)))
    assert(unpack_u32le(data, 16) == 0x7fffffff, string.format("FCVT.W.S 2^31 should clip to 0x7fffffff, got 0x%08x", unpack_u32le(data, 16)))
    assert(unpack_u32le(data, 20) == 0x10, string.format("FCVT.W.S 2^31 should set NV, got 0x%02x", unpack_u32le(data, 20)))
    assert(unpack_u32le(data, 24) == 0x00000000, string.format("FCVT.WU.S -1.0f should clip to 0, got 0x%08x", unpack_u32le(data, 24)))
    assert(unpack_u32le(data, 28) == 0x10, string.format("FCVT.WU.S -1.0f should set NV, got 0x%02x", unpack_u32le(data, 28)))
    assert(unpack_u32le(data, 32) == 0x00000000, string.format("FCVT.WU.S -Inf should clip to 0, got 0x%08x", unpack_u32le(data, 32)))
    assert(unpack_u32le(data, 36) == 0x10, string.format("FCVT.WU.S -Inf should set NV, got 0x%02x", unpack_u32le(data, 36)))

    local info = ndk.info(ctx)
    assert(info.fflags == 0x10, string.format("invalid fcvt guest should leave NV set, got 0x%02x", tonumber(info.fflags) or -1))

    local stop_ok, stop_err = ndk.stop(ctx, 1000)
    assert(stop_ok == true, "ndk.stop failed: " .. tostring(stop_err))
end

function ndk_tests.test_ndk_rv32imf_compiler_generated_mulsub_smoke()
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

function ndk_tests.test_ndk_rv32imf_compiler_generated_cast_smoke()
    assert(io.exists(HARDFLOAT_CAST_IMAGE_PATH), "missing baremetal_hardfloat_cast.bin in testcase directory: " .. HARDFLOAT_CAST_IMAGE_PATH)

    local ctx, err = ndk.rv32i(HARDFLOAT_CAST_IMAGE_PATH, MEM_SIZE, EXCHANGE_SIZE, {isa = "rv32imf"})
    assert(ctx, "ndk.rv32i with rv32imf failed: " .. tostring(err))

    local ok, ret_or_err, mcause, mtval = ndk.exec(ctx, { steps = 100000, elapsed = 500 })
    assert(ok == true, string.format("rv32imf hard-float cast guest should succeed, got err=%s mcause=%s mtval=%s", tostring(ret_or_err), tostring(mcause), tostring(mtval)))

    local data = ndk.getData(ctx, 8, 0)
    assert(type(data) == "string" and #data == 8, "ndk.getData should return 8 bytes for hard-float cast result")
    assert(unpack_u32le(data, 0) == 123, string.format("compiler-generated hard-float cast should truncate 123.75f to 123, got %d", unpack_u32le(data, 0)))
    assert(unpack_u32le(data, 4) == 42, string.format("compiler-generated hard-float unsigned cast should produce 42, got %d", unpack_u32le(data, 4)))

    local info = ndk.info(ctx)
    assert(info.fflags == 0x01, string.format("compiler-generated hard-float cast should leave NX set, got 0x%02x", tonumber(info.fflags) or -1))

    local stop_ok, stop_err = ndk.stop(ctx, 1000)
    assert(stop_ok == true, "ndk.stop failed: " .. tostring(stop_err))
end

function ndk_tests.test_ndk_rv32imf_compiler_generated_fmadd_smoke()
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

function ndk_tests.test_ndk_rv32imf_compiler_generated_fmsub_smoke()
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

function ndk_tests.test_ndk_rv32imf_compiler_generated_fnm_probe_smoke()
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

function ndk_tests.test_ndk_rv32imf_compiler_generated_div_smoke()
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

function ndk_tests.test_ndk_rv32imf_compiler_generated_minmax_smoke()
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

function ndk_tests.test_ndk_rv32imf_compiler_generated_sqrt_smoke()
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

function ndk_tests.test_ndk_default_rv32i_traps_on_compiler_generated_fmadd_smoke()
    assert(io.exists(HARDFLOAT_FMADD_IMAGE_PATH), "missing baremetal_hardfloat_fmadd.bin in testcase directory: " .. HARDFLOAT_FMADD_IMAGE_PATH)

    local ctx, err = ndk.rv32i(HARDFLOAT_FMADD_IMAGE_PATH, MEM_SIZE, EXCHANGE_SIZE)
    assert(ctx, "default ndk.rv32i failed: " .. tostring(err))

    local ok, ret_or_err, mcause, mtval = ndk.exec(ctx, { steps = 100000, elapsed = 500 })
    assert(ok == false, "default rv32i should trap on compiler-generated fmadd guest")
    assert(ret_or_err == "trap", "default rv32i should surface trap, got: " .. tostring(ret_or_err))
    assert(mcause == 2, "default rv32i should raise illegal instruction trap, got mcause=" .. tostring(mcause))
    local expected_mtval = find_first_rv32f_instruction_pc(HARDFLOAT_FMADD_IMAGE_PATH)
    assert(expected_mtval ~= nil, "should locate the first emitted RV32F instruction in the guest binary")
    assert(mtval == expected_mtval, string.format("default rv32i should trap at the guest's first RV32F instruction, got 0x%08x expected 0x%08x", tonumber(mtval) or -1, tonumber(expected_mtval) or -1))

    local stop_ok, stop_err = ndk.stop(ctx, 1000)
    assert(stop_ok == true, "ndk.stop failed: " .. tostring(stop_err))
end

function ndk_tests.test_ndk_default_rv32i_traps_on_compiler_generated_fmsub_smoke()
    assert(io.exists(HARDFLOAT_FMSUB_IMAGE_PATH), "missing baremetal_hardfloat_fmsub.bin in testcase directory: " .. HARDFLOAT_FMSUB_IMAGE_PATH)

    local ctx, err = ndk.rv32i(HARDFLOAT_FMSUB_IMAGE_PATH, MEM_SIZE, EXCHANGE_SIZE)
    assert(ctx, "default ndk.rv32i failed: " .. tostring(err))

    local ok, ret_or_err, mcause, mtval = ndk.exec(ctx, { steps = 100000, elapsed = 500 })
    assert(ok == false, "default rv32i should trap on compiler-generated fmsub guest")
    assert(ret_or_err == "trap", "default rv32i should surface trap, got: " .. tostring(ret_or_err))
    assert(mcause == 2, "default rv32i should raise illegal instruction trap, got mcause=" .. tostring(mcause))
    local expected_mtval = find_first_rv32f_instruction_pc(HARDFLOAT_FMSUB_IMAGE_PATH)
    assert(expected_mtval ~= nil, "should locate the first emitted RV32F instruction in the guest binary")
    assert(mtval == expected_mtval, string.format("default rv32i should trap at the guest's first RV32F instruction, got 0x%08x expected 0x%08x", tonumber(mtval) or -1, tonumber(expected_mtval) or -1))

    local stop_ok, stop_err = ndk.stop(ctx, 1000)
    assert(stop_ok == true, "ndk.stop failed: " .. tostring(stop_err))
end

function ndk_tests.test_ndk_default_rv32i_traps_on_compiler_generated_fnm_probe_smoke()
    assert(io.exists(HARDFLOAT_FNM_PROBE_IMAGE_PATH), "missing baremetal_hfnm.bin in testcase directory: " .. HARDFLOAT_FNM_PROBE_IMAGE_PATH)

    local ctx, err = ndk.rv32i(HARDFLOAT_FNM_PROBE_IMAGE_PATH, MEM_SIZE, EXCHANGE_SIZE)
    assert(ctx, "default ndk.rv32i failed: " .. tostring(err))

    local ok, ret_or_err, mcause, mtval = ndk.exec(ctx, { steps = 100000, elapsed = 500 })
    assert(ok == false, "default rv32i should trap on compiler-generated fnm probe guest")
    assert(ret_or_err == "trap", "default rv32i should surface trap, got: " .. tostring(ret_or_err))
    assert(mcause == 2, "default rv32i should raise illegal instruction trap, got mcause=" .. tostring(mcause))
    local expected_mtval = find_first_rv32f_instruction_pc(HARDFLOAT_FNM_PROBE_IMAGE_PATH)
    assert(expected_mtval ~= nil, "should locate the first emitted RV32F instruction in the guest binary")
    assert(mtval == expected_mtval, string.format("default rv32i should trap at the guest's first RV32F instruction, got 0x%08x expected 0x%08x", tonumber(mtval) or -1, tonumber(expected_mtval) or -1))

    local stop_ok, stop_err = ndk.stop(ctx, 1000)
    assert(stop_ok == true, "ndk.stop failed: " .. tostring(stop_err))
end

function ndk_tests.test_ndk_default_rv32i_traps_on_compiler_generated_div_smoke()
    assert(io.exists(HARDFLOAT_DIV_IMAGE_PATH), "missing baremetal_hardfloat_div.bin in testcase directory: " .. HARDFLOAT_DIV_IMAGE_PATH)

    local ctx, err = ndk.rv32i(HARDFLOAT_DIV_IMAGE_PATH, MEM_SIZE, EXCHANGE_SIZE)
    assert(ctx, "default ndk.rv32i failed: " .. tostring(err))

    local ok, ret_or_err, mcause, mtval = ndk.exec(ctx, { steps = 100000, elapsed = 500 })
    assert(ok == false, "default rv32i should trap on compiler-generated div guest")
    assert(ret_or_err == "trap", "default rv32i should surface trap, got: " .. tostring(ret_or_err))
    assert(mcause == 2, "default rv32i should raise illegal instruction trap, got mcause=" .. tostring(mcause))
    local expected_mtval = find_first_rv32f_instruction_pc(HARDFLOAT_DIV_IMAGE_PATH)
    assert(expected_mtval ~= nil, "should locate the first emitted RV32F instruction in the guest binary")
    assert(mtval == expected_mtval, string.format("default rv32i should trap at the guest's first RV32F instruction, got 0x%08x expected 0x%08x", tonumber(mtval) or -1, tonumber(expected_mtval) or -1))

    local stop_ok, stop_err = ndk.stop(ctx, 1000)
    assert(stop_ok == true, "ndk.stop failed: " .. tostring(stop_err))
end

function ndk_tests.test_ndk_default_rv32i_traps_on_compiler_generated_minmax_smoke()
    assert(io.exists(HARDFLOAT_MINMAX_IMAGE_PATH), "missing baremetal_hardfloat_minmax.bin in testcase directory: " .. HARDFLOAT_MINMAX_IMAGE_PATH)

    local ctx, err = ndk.rv32i(HARDFLOAT_MINMAX_IMAGE_PATH, MEM_SIZE, EXCHANGE_SIZE)
    assert(ctx, "default ndk.rv32i failed: " .. tostring(err))

    local ok, ret_or_err, mcause, mtval = ndk.exec(ctx, { steps = 100000, elapsed = 500 })
    assert(ok == false, "default rv32i should trap on compiler-generated minmax guest")
    assert(ret_or_err == "trap", "default rv32i should surface trap, got: " .. tostring(ret_or_err))
    assert(mcause == 2, "default rv32i should raise illegal instruction trap, got mcause=" .. tostring(mcause))
    local expected_mtval = find_first_rv32f_instruction_pc(HARDFLOAT_MINMAX_IMAGE_PATH)
    assert(expected_mtval ~= nil, "should locate the first emitted RV32F instruction in the guest binary")
    assert(mtval == expected_mtval, string.format("default rv32i should trap at the guest's first RV32F instruction, got 0x%08x expected 0x%08x", tonumber(mtval) or -1, tonumber(expected_mtval) or -1))

    local stop_ok, stop_err = ndk.stop(ctx, 1000)
    assert(stop_ok == true, "ndk.stop failed: " .. tostring(stop_err))
end

function ndk_tests.test_ndk_default_rv32i_traps_on_compiler_generated_sqrt_smoke()
    assert(io.exists(HARDFLOAT_SQRT_IMAGE_PATH), "missing baremetal_hardfloat_sqrt.bin in testcase directory: " .. HARDFLOAT_SQRT_IMAGE_PATH)

    local ctx, err = ndk.rv32i(HARDFLOAT_SQRT_IMAGE_PATH, MEM_SIZE, EXCHANGE_SIZE)
    assert(ctx, "default ndk.rv32i failed: " .. tostring(err))

    local ok, ret_or_err, mcause, mtval = ndk.exec(ctx, { steps = 100000, elapsed = 500 })
    assert(ok == false, "default rv32i should trap on compiler-generated sqrt guest")
    assert(ret_or_err == "trap", "default rv32i should surface trap, got: " .. tostring(ret_or_err))
    assert(mcause == 2, "default rv32i should raise illegal instruction trap, got mcause=" .. tostring(mcause))
    local expected_mtval = find_first_rv32f_instruction_pc(HARDFLOAT_SQRT_IMAGE_PATH)
    assert(expected_mtval ~= nil, "should locate the first emitted RV32F instruction in the guest binary")
    assert(mtval == expected_mtval, string.format("default rv32i should trap at the guest's first RV32F instruction, got 0x%08x expected 0x%08x", tonumber(mtval) or -1, tonumber(expected_mtval) or -1))

    local stop_ok, stop_err = ndk.stop(ctx, 1000)
    assert(stop_ok == true, "ndk.stop failed: " .. tostring(stop_err))
end

function ndk_tests.test_ndk_default_rv32i_traps_on_first_fadd_guest()
    assert(io.exists(FADD_FIRST_IMAGE_PATH), "missing baremetal_fadd_first.bin in testcase directory: " .. FADD_FIRST_IMAGE_PATH)

    local ctx, err = ndk.rv32i(FADD_FIRST_IMAGE_PATH, MEM_SIZE, EXCHANGE_SIZE)
    assert(ctx, "default ndk.rv32i failed: " .. tostring(err))

    local ok, ret_or_err, mcause, mtval = ndk.exec(ctx, { steps = 100000, elapsed = 500 })
    assert(ok == false, "default rv32i should trap on first fadd guest")
    assert(ret_or_err == "trap", "default rv32i should surface trap, got: " .. tostring(ret_or_err))
    assert(mcause == 2, "default rv32i should raise illegal instruction trap, got mcause=" .. tostring(mcause))
    assert(mtval == 0x80000000, string.format("default rv32i should trap at guest entry where FADD.S is the first instruction, got 0x%08x", tonumber(mtval) or -1))

    local stop_ok, stop_err = ndk.stop(ctx, 1000)
    assert(stop_ok == true, "ndk.stop failed: " .. tostring(stop_err))
end

function ndk_tests.test_ndk_default_rv32i_traps_on_compare_guest()
    assert(io.exists(FCMP_IMAGE_PATH), "missing baremetal_fcmp.bin in testcase directory: " .. FCMP_IMAGE_PATH)

    local ctx, err = ndk.rv32i(FCMP_IMAGE_PATH, MEM_SIZE, EXCHANGE_SIZE)
    assert(ctx, "default ndk.rv32i failed: " .. tostring(err))

    local ok, ret_or_err, mcause, mtval = ndk.exec(ctx, { steps = 100000, elapsed = 500 })
    assert(ok == false, "default rv32i should trap on compare guest")
    assert(ret_or_err == "trap", "default rv32i should surface trap, got: " .. tostring(ret_or_err))
    assert(mcause == 2, "default rv32i should raise illegal instruction trap, got mcause=" .. tostring(mcause))
    assert(type(mtval) == "number", "default rv32i compare trap should report mtval")

    local stop_ok, stop_err = ndk.stop(ctx, 1000)
    assert(stop_ok == true, "ndk.stop failed: " .. tostring(stop_err))
end

function ndk_tests.test_ndk_invalid_param_constructor_no_resource_exhaustion()
    for i = 1, 2000 do
        local ctx, err = ndk.rv32i(IMAGE_PATH, MEM_SIZE + 1, EXCHANGE_SIZE)
        assert(ctx == nil, "invalid mem_size should fail, round=" .. i)
        assert(type(err) == "string" and #err > 0, "invalid mem_size should return error string")
    end

    local ctx2, err2 = ndk.rv32i(IMAGE_PATH, MEM_SIZE, EXCHANGE_SIZE)
    assert(ctx2, "valid constructor should still succeed after invalid attempts: " .. tostring(err2))
    local stop_ok, stop_err = ndk.stop(ctx2, 1000)
    assert(stop_ok == true, "ndk.stop after valid constructor failed: " .. tostring(stop_err))
end

function ndk_tests.test_ndk_busy_and_stop_restart_sequence()
    local ctx, err = ndk.rv32i(IMAGE_PATH, MEM_SIZE, EXCHANGE_SIZE)
    assert(ctx, "ndk.rv32i failed: " .. tostring(err))

    local busy_seen = false
    local stopping_busy_seen = false
    local start_id = nil
    for _ = 1, 50 do
        local tid, thread_err = ndk.thread(ctx, { steps = 0, elapsed = 500 })
        assert(type(tid) == "number", "ndk.thread start failed: " .. tostring(thread_err))
        start_id = tid

        local tid2, err2 = ndk.thread(ctx, { steps = 0, elapsed = 500 })
        if tid2 == nil then
            assert(err2 == "busy", "expected busy on concurrent ndk.thread, got: " .. tostring(err2))
            busy_seen = true
        end

        local ok_exec, exec_err = ndk.exec(ctx, { steps = 1000, elapsed = 100 })
        if ok_exec == false then
            assert(exec_err == "busy", "expected busy on ndk.exec while thread active, got: " .. tostring(exec_err))
            busy_seen = true
        end

        local stop_now_ok, stop_now_err = ndk.stop(ctx, 0)
        if stop_now_ok == false then
            assert(stop_now_err == "timeout", "expected timeout on non-blocking stop, got: " .. tostring(stop_now_err))
            local stop_exec_ok, stop_exec_err = ndk.exec(ctx, { steps = 1000, elapsed = 100 })
            assert(stop_exec_ok == false and stop_exec_err == "busy", "ndk.exec should be busy while stopping")
            local stop_tid, stop_tid_err = ndk.thread(ctx, { steps = 0, elapsed = 100 })
            assert(stop_tid == nil and stop_tid_err == "busy", "ndk.thread should be busy while stopping")
            stopping_busy_seen = true
        end

        local stop_ok, stop_err = ndk.stop(ctx, 1000)
        assert(stop_ok == true, "ndk.stop failed: " .. tostring(stop_err))

        local settled = wait_until(function()
            local info = ndk.info(ctx)
            return info and info.running == false
        end, 500)
        assert(settled == true, "ndk did not settle to idle after stop")

        local tid3, err3 = ndk.thread(ctx, { steps = 0, elapsed = 200 })
        assert(type(tid3) == "number", "ndk.thread restart failed after stop: " .. tostring(err3))
        local stop_ok2, stop_err2 = ndk.stop(ctx, 1000)
        assert(stop_ok2 == true, "ndk.stop after restart failed: " .. tostring(stop_err2))
    end

    assert(type(start_id) == "number", "thread id should be returned")
    assert(busy_seen == true, "should observe busy rejection while running/stopping")
    assert(stopping_busy_seen == true, "should observe busy rejection while stopping")
end

function ndk_tests.test_ndk_gc_during_active_worker_safe()
    local ctx, err = ndk.rv32i(IMAGE_PATH, MEM_SIZE, EXCHANGE_SIZE)
    assert(ctx, "ndk.rv32i failed: " .. tostring(err))

    local tid, terr = ndk.thread(ctx, { steps = 0, elapsed = 500 })
    assert(type(tid) == "number", "ndk.thread start failed: " .. tostring(terr))

    local ok_gc, gc_err = pcall(function()
        ctx = nil
        collectgarbage("collect")
        collectgarbage("collect")
    end)
    assert(ok_gc == true, "gc while worker active should be safe: " .. tostring(gc_err))

    local ctx2, err2 = ndk.rv32i(IMAGE_PATH, MEM_SIZE, EXCHANGE_SIZE)
    assert(ctx2, "ndk should remain usable after gc/worker cleanup: " .. tostring(err2))
    local ok_exec, ret_or_err = ndk.exec(ctx2, { steps = 100000, elapsed = 500 })
    assert(ok_exec == true, "ndk.exec after gc/worker cleanup failed: " .. tostring(ret_or_err))
    local stop_ok, stop_err = ndk.stop(ctx2, 1000)
    assert(stop_ok == true, "ndk.stop after gc/worker cleanup failed: " .. tostring(stop_err))
end

return ndk_tests
