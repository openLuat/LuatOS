PROJECT = "lfs2n_regression"
VERSION = "1.0.0"
require "testrunner"

local function test_lfs2n_mount()
    local info = io.disk("lfs2n")
    assert(info, "lfs2n mount failed")
    assert(info.total_block > 0, "lfs2n has no blocks")
    log.info("lfs2n", string.format("mounted: used=%u, total=%u", info.block_used, info.total_block))
    return true
end

local function test_lfs2n_write_performance()
    -- 简单测试：写一个 1KB 的文件到 /lfs2n
    local testfile = "/lfs2n/perf_test.bin"
    local data = string.rep("X", 1024)  -- 1KB
    
    local start_tick = rtos.tick()
    local f = io.open(testfile, "wb")
    assert(f, "failed to open " .. testfile)
    
    f:write(data)
    f:close()
    local elapsed_ms = rtos.tick() - start_tick
    
    log.info("perf", string.format("1KB write+close to /lfs2n: %ums", elapsed_ms))
    
    -- 验证文件内容
    f = io.open(testfile, "rb")
    assert(f, "failed to verify file")
    local read_data = f:read("*a")
    f:close()
    assert(read_data == data, "data mismatch")
    
    -- 清理
    os.remove(testfile)
    
    return elapsed_ms
end

sys.taskInit(function()
    log.info("test", "=== LFS2N Regression Test ===")
    
    local ok = pcall(function()
        testrunner.run("test_lfs2n_mount", test_lfs2n_mount)
        local perf = testrunner.run("test_lfs2n_write_performance", test_lfs2n_write_performance)
        if perf < 100 then
            log.info("result", "PASS - Performance acceptable")
        else
            log.warn("result", string.format("WARN - Performance slower than expected: %ums", perf))
        end
    end)
    
    if not ok then
        log.error("test", "FAIL")
        os.exit(1)
    else
        log.info("test", "PASS")
        os.exit(0)
    end
end)

sys.run()
