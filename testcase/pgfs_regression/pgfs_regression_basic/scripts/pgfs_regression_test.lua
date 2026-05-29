local pgfs_regression = {}
local s_spi_device = nil
local s_flash = nil
local s_mounted = false
local s_power_ready = false

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
    assert(elapsed_ms < 20000, "pgfs perf regression: elapsed_ms=" .. elapsed_ms)
end

return pgfs_regression
