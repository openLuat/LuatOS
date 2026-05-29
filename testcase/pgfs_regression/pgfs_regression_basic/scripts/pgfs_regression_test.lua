local pgfs_regression = {}
local s_spi_device = nil
local s_flash = nil
local s_mounted = false
local s_power_ready = false
local NES_ZIP_PATH = "/luadb/NES_Emulator.zip"
local NES_TARGET_DIR = "/pgfs/app_store/"
local NES_EXPECTED_MAIN = "/pgfs/app_store/NES_Emulator/main.lua"
local NES_EXPECTED_METAS = "/pgfs/app_store/NES_Emulator/metas.json"
local NES_UNZIP_TIMEOUT_MS = 120000
local PACMAN_ZIP_PATH = "/luadb/pac_man.zip"
local LEGACY_TARGET_DIR = "/ram/miniz_legacy_contract/"
local LEGACY_EXPECTED_MAIN = "/ram/miniz_legacy_contract/pac_man/main.lua"
local CONTRACT_PASS_TOKEN = "### MINIZ_BATCH_CONTRACT_PASS ###"
local CONTRACT_FAIL_TOKEN = "### MINIZ_BATCH_CONTRACT_FAIL ###"

local function is_pc()
    if hmeta and hmeta.model then
        return hmeta.model() == "PC"
    end
    return false
end

local function get_spi_bus()
    if os and os.getenv then
        local v = os.getenv("PGFS_SPI_BUS") or os.getenv("LF_SPI_BUS")
        if v and v ~= "" then
            local n = tonumber(v)
            if n then
                return n
            end
        end
    end
    if is_pc() then
        return 0
    end
    return 2
end

local function get_spi_cs()
    if os and os.getenv then
        local v = os.getenv("PGFS_SPI_CS") or os.getenv("LF_SPI_CS")
        if v and v ~= "" then
            local n = tonumber(v)
            if n then
                return n
            end
        end
    end
    if is_pc() then
        return 17
    end
    return 4
end

local function ensure_flash_power()
    if s_power_ready or is_pc() then
        return
    end
    if gpio and gpio.setup then
        gpio.setup(50, 1)
        sys.wait(20)
    end
    s_power_ready = true
end

local function setup_flash()
    if not s_spi_device then
        ensure_flash_power()
        s_spi_device = spi.deviceSetup(get_spi_bus(), get_spi_cs(), 0, 0, 8, 2 * 1000 * 1000, spi.MSB, 1, 0)
        assert(s_spi_device, "spi.deviceSetup failed")
        s_flash = lf.init(s_spi_device)
        assert(s_flash, "lf.init failed")
    end

    assert(lf.erase(s_flash, 0, 0x4000), "lf.erase failed")
    sys.wait(30)
    if not s_mounted then
        assert(lf.mount(s_flash, "/pgfs/", 0, 0, "pgfs"), "pgfs mount failed")
        s_mounted = true
    end
    return s_spi_device, s_flash
end

local function contract_assert(cond, msg)
    if not cond then
        log.error("miniz_batch_contract", CONTRACT_FAIL_TOKEN .. " " .. tostring(msg))
    end
    assert(cond, msg)
end

local function cleanup_nes_target()
    os.remove("/pgfs/app_store/NES_Emulator/main.lua")
    os.remove("/pgfs/app_store/NES_Emulator/metas.json")
    os.remove("/pgfs/app_store/NES_Emulator/icon.png")
    os.remove("/pgfs/app_store/NES_Emulator/pacman_game_win.lua")
    io.rmdir("/pgfs/app_store/NES_Emulator/user/")
    io.rmdir("/pgfs/app_store/NES_Emulator/")
    io.rmdir("/pgfs/app_store/")
end

local function cleanup_legacy_target()
    os.remove("/ram/miniz_legacy_contract/pac_man/main.lua")
    os.remove("/ram/miniz_legacy_contract/pac_man/meta.json")
    os.remove("/ram/miniz_legacy_contract/pac_man/icon.png")
    os.remove("/ram/miniz_legacy_contract/pac_man/user/pacman_game_win.lua")
    io.rmdir("/ram/miniz_legacy_contract/pac_man/user/")
    io.rmdir("/ram/miniz_legacy_contract/pac_man/")
    io.rmdir("/ram/miniz_legacy_contract/")
end

function pgfs_regression.test_gc_under_churn()
    setup_flash()
    for i = 1, 200 do
        local name = "/pgfs/churn_" .. i .. ".txt"
        assert(io.writeFile(name, string.rep("X", 256)))
        if i % 3 == 0 then
            os.remove(name)
        end
    end
    local ok, total = fs.fsstat("/pgfs/")
    assert(ok, "fsstat failed")
    assert(total and total > 0, "invalid total")
end

function pgfs_regression.test_bad_block_retire_hook()
    setup_flash()
    assert(lf.pgfsctl("bad_block_once", true), "inject bad_block_once failed")
    io.writeFile("/pgfs/badblock_probe.txt", "first_maybe_fail")
    assert(io.writeFile("/pgfs/badblock_probe.txt", "ok"), "write failed after retire path")
    local data = io.readFile("/pgfs/badblock_probe.txt")
    assert(data == "ok", "badblock probe mismatch")
end

function pgfs_regression.test_c_layer_unit_tests()
    setup_flash()
    local ok = lf.pgfsctl("run_c_tests")
    assert(ok, "pgfs C-layer unit tests failed (check logs for which case failed)")
end

function pgfs_regression.test_lock_mode_toggle()
    setup_flash()
    assert(lf.pgfsctl("lock_mode", "on"), "set lock_mode on failed")
    assert(io.writeFile("/pgfs/lock_on.txt", "on"), "write with lock on failed")
    assert(lf.pgfsctl("lock_mode", "off"), "set lock_mode off failed")
    assert(io.writeFile("/pgfs/lock_off.txt", "off"), "write with lock off failed")
    assert(io.readFile("/pgfs/lock_on.txt") == "on", "lock on file mismatch")
    assert(io.readFile("/pgfs/lock_off.txt") == "off", "lock off file mismatch")
end

function pgfs_regression.test_write_close_performance_trace()
    setup_flash()
    local loops = 120
    local payload = string.rep("P", 1024)
    local start_tick = mcu.ticks()
    for i = 1, loops do
        local ok = io.writeFile("/pgfs/perf_" .. i .. ".bin", payload)
        assert(ok, "write failed at " .. i)
    end
    local elapsed_ms = mcu.ticks() - start_tick
    local avg_ms = elapsed_ms / loops
    local trace_total_stall_us = elapsed_ms * 1000
    log.info("pgfs_perf", string.format("trace_total_stall_us=%d loops=%d elapsed_ms=%d avg_ms=%.2f", trace_total_stall_us, loops, elapsed_ms, avg_ms))
    -- PC simulator flash is file-backed (~3200ms/checkpoint flush); on real hardware this is much faster.
    -- With batch=8: 120 files -> 15 flushes. Threshold set to 150000ms for PC, tighter regression possible on HW.
    assert(elapsed_ms < 150000, "pgfs perf regression: elapsed_ms=" .. elapsed_ms)
end

function pgfs_regression.test_miniz_batch_contract_success_commit()
    setup_flash()
    if not io.exists(NES_ZIP_PATH) then
        log.warn("miniz_batch_contract", "skip success case, fixture missing " .. NES_ZIP_PATH)
        return
    end
    cleanup_nes_target()
    contract_assert(lf.pgfsctl("powercut_stage", "none"), "clear powercut_stage failed")
    local ok = miniz.unzip(NES_ZIP_PATH, NES_TARGET_DIR, true, NES_UNZIP_TIMEOUT_MS)
    contract_assert(ok == true, "batch unzip success path should succeed")
    contract_assert(io.exists(NES_EXPECTED_MAIN) == true, "main.lua missing immediately after unzip")
    contract_assert(lf.pgfsctl("reset_runtime"), "reset_runtime failed after success unzip")
    contract_assert(io.exists(NES_EXPECTED_MAIN) == true, "main.lua missing after reset_runtime")
    log.info("miniz_batch_contract", CONTRACT_PASS_TOKEN .. " success-commit")
end

function pgfs_regression.test_miniz_batch_contract_error_abort_and_no_partial_after_reset()
    setup_flash()
    if not io.exists(NES_ZIP_PATH) then
        log.warn("miniz_batch_contract", "skip error case, fixture missing " .. NES_ZIP_PATH)
        return
    end
    cleanup_nes_target()
    contract_assert(lf.pgfsctl("powercut_stage", "before_checkpoint"), "inject before_checkpoint failed")
    local ok = miniz.unzip(NES_ZIP_PATH, NES_TARGET_DIR, true, NES_UNZIP_TIMEOUT_MS)
    contract_assert(ok == false, "unzip should fail when checkpoint powercut is injected")
    contract_assert(lf.pgfsctl("powercut_stage", "none"), "clear powercut_stage failed after error")
    contract_assert(lf.pgfsctl("reset_runtime"), "reset_runtime failed after failed unzip")
    contract_assert(io.exists(NES_EXPECTED_MAIN) == false, "partial main.lua visible after failed unzip + reset")
    contract_assert(io.exists(NES_EXPECTED_METAS) == false, "partial metas.json visible after failed unzip + reset")
    log.info("miniz_batch_contract", CONTRACT_PASS_TOKEN .. " error-abort")
end

function pgfs_regression.test_miniz_unzip_legacy_default_behavior_unchanged()
    setup_flash()
    if not io.exists(PACMAN_ZIP_PATH) then
        log.warn("miniz_batch_contract", "skip legacy case, fixture missing " .. PACMAN_ZIP_PATH)
        return
    end
    cleanup_legacy_target()
    local bad = miniz.unzip(PACMAN_ZIP_PATH, "/ram/miniz_legacy_contract_no_slash")
    contract_assert(bad == false, "legacy path without trailing slash should still fail")
    local ok = miniz.unzip(PACMAN_ZIP_PATH, LEGACY_TARGET_DIR, true, 30000)
    contract_assert(ok == true, "legacy default unzip should remain successful")
    contract_assert(io.exists(LEGACY_EXPECTED_MAIN) == true, "legacy unzip main.lua missing")
    log.info("miniz_batch_contract", CONTRACT_PASS_TOKEN .. " legacy-default")
end

return pgfs_regression
