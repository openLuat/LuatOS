local M = {}

local IMAGE_PATH = "/luadb/baremetal.bin"
local HARDFLOAT_FMADD_IMAGE_PATH = "/luadb/baremetal_hardfloat_fmadd.bin"
local HARDFLOAT_FMSUB_IMAGE_PATH = "/luadb/baremetal_hardfloat_fmsub.bin"
local HARDFLOAT_FNM_PROBE_IMAGE_PATH = "/luadb/baremetal_hfnm.bin"
local HARDFLOAT_DIV_IMAGE_PATH = "/luadb/baremetal_hardfloat_div.bin"
local HARDFLOAT_MINMAX_IMAGE_PATH = "/luadb/baremetal_hardfloat_minmax.bin"
local HARDFLOAT_SQRT_IMAGE_PATH = "/luadb/baremetal_hardfloat_sqrt.bin"
local FADD_FIRST_IMAGE_PATH = "/luadb/baremetal_fadd_first.bin"
local FCMP_IMAGE_PATH = "/luadb/baremetal_fcmp.bin"
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

function M.test_ndk_default_rv32i_traps_on_compiler_generated_fmadd_smoke()
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

function M.test_ndk_default_rv32i_traps_on_compiler_generated_fmsub_smoke()
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

function M.test_ndk_default_rv32i_traps_on_compiler_generated_fnm_probe_smoke()
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

function M.test_ndk_default_rv32i_traps_on_compiler_generated_div_smoke()
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

function M.test_ndk_default_rv32i_traps_on_compiler_generated_minmax_smoke()
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

function M.test_ndk_default_rv32i_traps_on_compiler_generated_sqrt_smoke()
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

function M.test_ndk_default_rv32i_traps_on_first_fadd_guest()
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

function M.test_ndk_default_rv32i_traps_on_compare_guest()
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

return M
