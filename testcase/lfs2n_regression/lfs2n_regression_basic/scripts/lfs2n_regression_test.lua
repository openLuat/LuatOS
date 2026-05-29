local M = {}
local mounted_lfs2n = false
local mounted_spi_dev = nil
local mounted_lfdev = nil
local LFS2N_DEBUG_LOG_ENABLED = false
local LFS2N_PERF_LOG_ENABLED = false

local BASELINE_INPUTS = {
    chunk_size = 4096,
    write_loops = 128,
    write_cache_hard_cap_bytes = 128 * 1024,
    write_cache_overflow_bytes = 160 * 1024,
    mount_slow_warn_ms = 3000,
    mount_timeout_ms = 30000,
    write_slow_warn_ms = 3000,
    write_timeout_ms = 60000,
    unzip_timeout_ms = 120000,
}

local TIMEOUT_DETECTION_INPUTS = {
    mount_timeout_ms = BASELINE_INPUTS.mount_timeout_ms,
    write_timeout_ms = BASELINE_INPUTS.write_timeout_ms,
    unzip_ms = BASELINE_INPUTS.unzip_timeout_ms,
    boundary_ms = {1, 1000, 3000, 30000, 60000, 120000}
}

local function now_us()
    if mcu and mcu.ticks2 then
        local high, low = mcu.ticks2(1)
        return high * 1000000 + low
    end
    if mcu and mcu.ticks then
        return mcu.ticks() * 1000
    end
    return math.floor(os.clock() * 1000000)
end

local function us_to_ms(cost_us)
    if cost_us <= 0 then
        return 1
    end
    return math.max(1, math.floor((cost_us + 500) / 1000))
end

local function now_wall_ms()
    -- Use monotonic ticks-based timing; os.time() granularity/drift can distort short-path wall metrics.
    return us_to_ms(now_us())
end

local function lfs2n_debug_log(...)
    if LFS2N_DEBUG_LOG_ENABLED then
        log.info(...)
    end
end

local function lfs2n_perf_log(...)
    if LFS2N_PERF_LOG_ENABLED then
        log.info(...)
    end
end

local function get_lfs2n_baseline_inputs()
    return BASELINE_INPUTS
end

local function get_lfs2n_timeout_detection_inputs()
    return TIMEOUT_DETECTION_INPUTS
end

local function flush_stream_for_forcepath(f)
    local pos = f:seek("cur", 0)
    assert(type(pos) == "number", "f:seek fallback flush failed")
    return "fseek"
end

local function run_forcepath_trigger_case(path, content, wait_ms)
    local f = io.open(path, "wb")
    assert(f, "open for forcepath case failed: " .. path)
    assert(f:write(content), "f:write failed in forcepath case")
    local flush_mode = flush_stream_for_forcepath(f)
    if wait_ms > 0 then
        sys.wait(wait_ms)
    end
    assert(f:close(), "f:close failed in forcepath case")
    local read_back = io.readFile(path)
    assert(read_back ~= nil, "readback failed in forcepath case")
    assert(read_back == content, "readback mismatch in forcepath case")
    os.remove(path)
    return flush_mode
end

local function run_baseline_write_perf_case(baseline)
    local path = "/lfs2n/lfs2n_regression_perf.bin"
    local chunk = string.rep("N", baseline.chunk_size)
    local loops = baseline.write_loops
    local f = io.open(path, "wb")
    assert(f, "open for write failed: " .. path)
    local wall0 = now_wall_ms()
    local t0 = now_us()
    for _ = 1, loops do
        assert(f:write(chunk), "f:write failed")
    end
    f:close()
    local cost_ms = us_to_ms(now_us() - t0)
    local wall_cost_ms = math.max(1, now_wall_ms() - wall0)
    local read_back = io.readFile(path)
    assert(read_back ~= nil, "readback failed")
    assert(#read_back == #chunk * loops, "readback size mismatch")
    os.remove(path)
    return cost_ms, wall_cost_ms
end

local function lfs2n_spi_bus_id()
    if os and os.getenv then
        local v = os.getenv("LFS2N_SPI_BUS") or os.getenv("LF_SPI_BUS")
        if v and v ~= "" then
            local n = tonumber(v)
            if n then
                return n
            end
        end
    end
    if hmeta and hmeta.model and hmeta.model() == "PC" then
        return 1
    end
    return 2
end

local function lfs2n_spi_cs_pin()
    if os and os.getenv then
        local v = os.getenv("LFS2N_SPI_CS") or os.getenv("LF_SPI_CS")
        if v and v ~= "" then
            local n = tonumber(v)
            if n then
                return n
            end
        end
    end
    if hmeta and hmeta.model and hmeta.model() == "PC" then
        return 4
    end
    return 4
end

local function mount_lfs2n()
    assert(spi and spi.deviceSetup, "spi.deviceSetup unavailable")
    assert(lf and lf.init and lf.mount, "lf api unavailable")
    if mounted_lfs2n then
        return
    end
    local spi_id = lfs2n_spi_bus_id()
    mounted_spi_dev = spi.deviceSetup(spi_id, lfs2n_spi_cs_pin(), 0, 0, 8, 20000000, spi.MSB, 1, 0)
    assert(mounted_spi_dev, "spi.deviceSetup failed")
    mounted_lfdev = lf.init(mounted_spi_dev)
    assert(mounted_lfdev, "lf.init failed")
    local ok = lf.mount(mounted_lfdev, "/lfs2n/", 0, 0, "lfsn")
    assert(ok, "lf.mount(/lfs2n) failed")
    mounted_lfs2n = true
    return mounted_lfdev
end

function M.test_lfs2n_mount()
    local baseline = get_lfs2n_baseline_inputs()
    local t_wall0 = now_wall_ms()
    mount_lfs2n()
    local mount_wall_ms = math.max(1, now_wall_ms() - t_wall0)
    local ok, entries = io.lsdir("/lfs2n/")
    assert(ok == true and type(entries) == "table", "lsdir /lfs2n failed")
    assert(mount_wall_ms < baseline.mount_timeout_ms, "mount timeout risk ms=" .. tostring(mount_wall_ms))
    if mount_wall_ms >= baseline.mount_slow_warn_ms then
        lfs2n_perf_log("LFS2N_MOUNT_SLOW_WARN", mount_wall_ms)
    end
    lfs2n_debug_log("LFS2N_MOUNT_INFO", "lsdir_ok entries=" .. tostring(#entries))
    lfs2n_perf_log("LFS2N_BASELINE_MOUNT_MS", mount_wall_ms)
end

function M.test_lfs2n_write_performance()
    local baseline = get_lfs2n_baseline_inputs()
    mount_lfs2n()
    local cost_ms, wall_cost_ms = run_baseline_write_perf_case(baseline)
    assert(wall_cost_ms < baseline.write_timeout_ms, "write timeout risk ms=" .. tostring(wall_cost_ms))
    if wall_cost_ms >= baseline.write_slow_warn_ms then
        lfs2n_perf_log("LFS2N_WRITE_SLOW_WARN", wall_cost_ms)
    end
    lfs2n_perf_log("LFS2N_WRITE_MS", cost_ms)
    lfs2n_perf_log("LFS2N_BASELINE_WRITE_PURE_WALL_MS", wall_cost_ms)
    lfs2n_perf_log("LFS2N_METRIC", "LFS2N_BASELINE_WRITE_PURE_WALL_MS", wall_cost_ms)
    lfs2n_perf_log("LFS2N_BASELINE_WRITE_WALL_MS", wall_cost_ms)
end

function M.test_lfs2n_write_cache_limit_overflow_behavior()
    local baseline = get_lfs2n_baseline_inputs()
    mount_lfs2n()
    local path = "/lfs2n/lfs2n_regression_cache_limit.bin"
    local chunk_size = baseline.chunk_size
    local total_bytes = baseline.write_cache_overflow_bytes
    local loops = math.floor(total_bytes / chunk_size)
    local chunk = string.rep("C", chunk_size)
    local f = io.open(path, "wb")
    assert(f, "open for write failed: " .. path)
    for _ = 1, loops do
        assert(f:write(chunk), "f:write failed")
    end
    f:close()
    local read_back = io.readFile(path)
    assert(read_back ~= nil, "readback failed")
    assert(#read_back == loops * chunk_size, "cache overflow readback size mismatch")
    assert(read_back:sub(1, 1) == "C", "cache overflow content head mismatch")
    assert(read_back:sub(-1) == "C", "cache overflow content tail mismatch")
    lfs2n_debug_log("LFS2N_CACHE_OVERFLOW_TEST", "bytes=" .. tostring(#read_back) .. " hard_cap=" .. tostring(baseline.write_cache_hard_cap_bytes))
    os.remove(path)
end

function M.test_lfs2n_unzip_if_fixture_exists()
    mount_lfs2n()
    local zip_file = "/luadb/pac_man.zip"
    if not io.exists(zip_file) then
        lfs2n_debug_log("LFS2N_UNZIP_SKIP", "missing " .. zip_file)
        return
    end
    local target = "/lfs2n/"
    local t0 = now_us()
    local timeout = get_lfs2n_timeout_detection_inputs()
    local ok = miniz.unzip(zip_file, target, true, timeout.unzip_ms)
    local cost_ms = us_to_ms(now_us() - t0)
    assert(ok == true, "miniz.unzip to /lfs2n failed")
    lfs2n_perf_log("LFS2N_UNZIP_MS", cost_ms)
end

function M.test_lfs2n_baseline_bottleneck_inputs()
    local baseline = get_lfs2n_baseline_inputs()
    assert(type(baseline) == "table", "baseline inputs missing")
    assert(type(baseline.write_loops) == "number" and baseline.write_loops >= 128, "baseline write_loops invalid")
    assert(type(baseline.chunk_size) == "number" and baseline.chunk_size >= 4096, "baseline chunk_size invalid")
    assert(type(baseline.mount_slow_warn_ms) == "number" and baseline.mount_slow_warn_ms >= 1000, "baseline mount_slow_warn_ms invalid")
    assert(type(baseline.write_timeout_ms) == "number" and baseline.write_timeout_ms > baseline.mount_slow_warn_ms, "baseline write_timeout_ms invalid")
    assert(type(baseline.write_cache_hard_cap_bytes) == "number" and baseline.write_cache_hard_cap_bytes <= 128 * 1024, "write cache hard cap must stay <=128KB")
    assert(type(baseline.write_cache_overflow_bytes) == "number" and baseline.write_cache_overflow_bytes > baseline.write_cache_hard_cap_bytes, "write cache overflow bytes invalid")
end

function M.test_lfs2n_timeout_detection_inputs()
    local timeout = get_lfs2n_timeout_detection_inputs()
    assert(type(timeout) == "table", "timeout inputs missing")
    assert(type(timeout.unzip_ms) == "number" and timeout.unzip_ms == 120000, "timeout unzip_ms baseline changed")
    assert(type(timeout.write_timeout_ms) == "number" and timeout.write_timeout_ms >= 10000, "timeout write_timeout_ms too small")
    assert(type(timeout.mount_timeout_ms) == "number" and timeout.mount_timeout_ms >= 5000, "timeout mount_timeout_ms too small")
    assert(type(timeout.boundary_ms) == "table" and #timeout.boundary_ms >= 6, "timeout boundary list missing")
    for i = 2, #timeout.boundary_ms do
        assert(timeout.boundary_ms[i] > timeout.boundary_ms[i - 1], "timeout boundaries not strictly increasing")
    end
end

function M.test_lfs2n_forcepath_trigger_boundaries()
    mount_lfs2n()
    local timeout = get_lfs2n_timeout_detection_inputs()
    local waits = {
        timeout.boundary_ms[2] + 200,
        timeout.boundary_ms[3] + 200,
    }
    local payload = string.rep("F", 512)
    local total_wait_ms = 0
    local t0 = now_us()
    for idx, wait_ms in ipairs(waits) do
        assert(wait_ms < timeout.boundary_ms[4], "forcepath wait too large")
        local path = string.format("/lfs2n/lfs2n_forcepath_case_%d.bin", idx)
        local flush_mode = run_forcepath_trigger_case(path, payload .. tostring(idx), wait_ms)
        total_wait_ms = total_wait_ms + wait_ms
        lfs2n_debug_log("LFS2N_FORCE_TRIGGER_CASE", "idx=" .. tostring(idx) .. " wait_ms=" .. tostring(wait_ms) .. " flush=" .. flush_mode)
    end
    local wall_ms = us_to_ms(now_us() - t0)
    lfs2n_perf_log("LFS2N_FORCE_TRIGGER_TOTAL_WAIT", total_wait_ms)
    lfs2n_perf_log("LFS2N_FORCE_TRIGGER_DIAG_WALL", wall_ms)
end

return M
