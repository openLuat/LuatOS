-- measure.lua
-- Micro-benchmark harness for the perf-guest-v1 suite.
--
-- Uses mcu.ticks() (1 kHz, wraps at ~24.8 days — fine for sub-second
-- test runs). mcu.tick64() returns an 8-byte STRING, not a number, so
-- we stick with the simpler 32-bit ticks() here. We DO add sys.wait(1)
-- every 500 iterations so the cooperative scheduler on embedded targets
-- (air1601 in particular) doesn't starve and trigger a watchdog reset.

local M = {}

function M.measure(tag, fn, iters, payload_size, warmup)
    warmup = warmup or 20

    -- Warmup: discard the first few runs to let any JIT/cache settle.
    for _ = 1, warmup do
        fn()
    end

    local t0 = mcu.ticks()
    for i = 1, iters do
        fn()
        if i % 500 == 0 then
            sys.wait(1)
        end
    end
    local elapsed = mcu.ticks() - t0
    if elapsed <= 0 then elapsed = 1 end
    local ops  = iters * 1000 / elapsed
    local kbps = (payload_size / 1024) * iters * 1000 / elapsed
    log.info("perf",     string.format(
        "[%s] size=%dB iters=%d warmup=%d elapsed=%dms ops=%.1f/s kbps=%.1f",
        tag, payload_size, iters, warmup, elapsed, ops, kbps))
    log.info("perf_raw", string.format(
        "PERF|tag=%s|size=%d|iters=%d|warmup=%d|elapsed_ms=%d|ops_s=%.3f|kb_s=%.3f",
        tag, payload_size, iters, warmup, elapsed, ops, kbps))
    return { elapsed_ms = elapsed, ops_s = ops, kb_s = kbps }
end

-- Plan a reasonable iters / warmup for a given payload size, based on
-- a rough estimate of the per-call cost on PC. The goal is to keep the
-- total measurement time around 100ms; we cap iters at 6000 to keep the
-- whole test under ~6 seconds per size.
function M.plan_iters(payload_size, single_us_estimate)
    single_us_estimate = single_us_estimate or 50
    local target_total_ms = 100
    local est_ms = single_us_estimate / 1000
    local iters = math.max(100, math.floor(target_total_ms / math.max(est_ms, 0.01)))
    if iters > 6000 then iters = 6000 end
    local warmup = math.max(20, math.min(math.floor(iters / 30), 200))
    return iters, warmup
end

return M
