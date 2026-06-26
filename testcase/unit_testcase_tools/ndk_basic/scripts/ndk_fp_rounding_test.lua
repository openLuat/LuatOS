local M = {}

local IMAGE_PATH = "/luadb/baremetal.bin"
local FADD_ROUNDING_IMAGE_PATH = "/luadb/baremetal_fadd_rounding.bin"
local FADD_RMM_STATIC_IMAGE_PATH = "/luadb/baremetal_fadd_rmm_static.bin"
local FADD_RMM_DYNAMIC_IMAGE_PATH = "/luadb/baremetal_fadd_rmm_dynamic.bin"
local FCMP_IMAGE_PATH = "/luadb/baremetal_fcmp.bin"
local FCLASS_IMAGE_PATH = "/luadb/baremetal_fclass.bin"
local FCVTSW_IMAGE_PATH = "/luadb/baremetal_fcvtsw.bin"
local FCVT_DYN_RUP_IMAGE_PATH = "/luadb/baremetal_fcvt_dyn_rup.bin"
local FCVT_WS_INVALID_IMAGE_PATH = "/luadb/baremetal_fcvt_ws_invalid.bin"
local HARDFLOAT_CAST_IMAGE_PATH = "/luadb/baremetal_hardfloat_cast.bin"
local MEM_SIZE = 32 * 1024
local EXCHANGE_SIZE = 1024
local GUEST_IMAGE_BASE = 0x80000000

local CTX = nil

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

function M.test_ndk_rv32imf_fadd_ignores_ambient_host_round_up()
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

function M.test_ndk_rv32imf_traps_on_static_rmm_rounding_mode()
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

function M.test_ndk_rv32imf_traps_on_dynamic_rmm_rounding_mode()
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

function M.test_ndk_rv32imf_compare_tracks_nan_results_and_flags()
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

function M.test_ndk_rv32imf_fclass_smoke_bits()
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

function M.test_ndk_rv32imf_fcvt_sw_ignores_ambient_host_round_up()
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

function M.test_ndk_rv32imf_fcvt_sw_honors_dynamic_frm_rup()
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

function M.test_ndk_rv32imf_fcvt_ws_invalid_clips_per_spec()
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

function M.test_ndk_rv32imf_compiler_generated_cast_smoke()
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

return M
