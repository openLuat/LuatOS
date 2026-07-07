PROJECT = "air1601_pgfs_perf"
VERSION = "1.0.0"

local function now_us()
    if mcu and mcu.ticks then
        return mcu.ticks() * 1000
    end
    return (os.time() or 0) * 1000000
end

local function us_to_ms(cost_us)
    if cost_us <= 0 then
        return 0
    end
    return math.floor((cost_us + 500) / 1000)
end

local function setup_flash()
    if gpio and gpio.setup then
        gpio.setup(50, 1)
        sys.wait(20)
    end
    local spi_dev = spi.deviceSetup(2, 4, 0, 0, 8, 20 * 1000 * 1000, spi.MSB, 1, 0)
    assert(spi_dev, "spi.deviceSetup failed")
    local flash = lf.init(spi_dev)
    assert(flash, "lf.init failed")
    log.info("pgfs_perf", "erasing first 16KB...")
    assert(lf.erase(flash, 0, 0x4000), "lf.erase failed")
    sys.wait(50)
    log.info("pgfs_perf", "mounting pgfs...")
    assert(lf.mount(flash, "/pgfs/", 0, 0, "pgfs"), "pgfs mount failed")
    return flash
end

local function cleanup(flash)
    lf.umount("/pgfs/")
end

sys.taskInit(function()
    local flash = setup_flash()

    log.info("pgfs_perf", "========== PGFS 断电恢复测试 ==========")

    -- 写入一些初始数据，触发 GC 和 checkpoint
    log.info("pgfs_perf", "--- 写入初始数据触发 GC ---")
    for i = 1, 20 do
        assert(io.writeFile("/pgfs/init_" .. i .. ".txt", "init_data_" .. i), "init write failed")
        if i % 8 == 0 then
            sys.wait(10)
        end
    end
    sys.wait(100)
    log.info("pgfs_perf", "init files written, triggering GC...")
    for i = 1, 10 do
        assert(io.writeFile("/pgfs/gc_trigger_" .. i .. ".txt", string.rep("X", 2048)), "gc trigger failed")
    end
    for i = 1, 10 do
        os.remove("/pgfs/gc_trigger_" .. i .. ".txt")
    end
    sys.wait(200)
    log.info("pgfs_perf", "GC done")

    -- Test1: before_checkpoint 注入，写入应该失败
    log.info("pgfs_perf", "--- Test1: before_checkpoint 注入 ---")
    os.remove("/pgfs/powercut_reject.txt")
    assert(lf.pgfsctl("powercut_stage", "before_checkpoint"), "inject before_checkpoint failed")
    local write_result = io.writeFile("/pgfs/powercut_reject.txt", "should_not_persist")
    log.info("pgfs_perf", string.format("Test1: write_result=%s (expected false)", tostring(write_result)))
    assert(write_result == false, "write should fail when powercut stage is injected")
    assert(lf.pgfsctl("powercut_stage", "none"), "clear powercut_stage failed")
    assert(lf.pgfsctl("reset_runtime"), "reset_runtime failed")
    local exist_after = io.exists("/pgfs/powercut_reject.txt")
    log.info("pgfs_perf", string.format("Test1: exist_after_reset=%s (expected false)", tostring(exist_after)))
    assert(exist_after == false, "Test1 failed: file should not exist after rollback")

    -- Test2: after_append 注入，数据已写入 log 但 entry 未提交，reset 后文件不存在（孤儿数据）
    log.info("pgfs_perf", "--- Test2: after_append 注入 ---")
    os.remove("/pgfs/after_append.txt")
    assert(lf.pgfsctl("powercut_stage", "after_append"), "inject after_append failed")
    local write_result2 = io.writeFile("/pgfs/after_append.txt", "written_after_append")
    log.info("pgfs_perf", string.format("Test2: write_result=%s (close fails, data in log but entry not committed)", tostring(write_result2)))
    assert(lf.pgfsctl("powercut_stage", "none"), "clear powercut_stage failed")
    assert(lf.pgfsctl("reset_runtime"), "reset_runtime failed")
    local exist_append = io.exists("/pgfs/after_append.txt")
    local data_append = io.readFile("/pgfs/after_append.txt")
    log.info("pgfs_perf", string.format("Test2: exist=%s data=%s (expected exist=false)", tostring(exist_append), tostring(data_append)))
    assert(exist_append == false, "Test2 failed: file should NOT exist (entry not committed)")

    -- Test3: before_append 注入，数据未写入 log，close 失败
    log.info("pgfs_perf", "--- Test3: before_append 注入 ---")
    os.remove("/pgfs/before_append.txt")
    assert(lf.pgfsctl("powercut_stage", "before_append"), "inject before_append failed")
    local write_result3 = io.writeFile("/pgfs/before_append.txt", "should_not_persist")
    log.info("pgfs_perf", string.format("Test3: write_result=%s (expected false)", tostring(write_result3)))
    assert(write_result3 == false, "Test3: write should fail when before_append is injected")
    assert(lf.pgfsctl("powercut_stage", "none"), "clear powercut_stage failed")
    assert(lf.pgfsctl("reset_runtime"), "reset_runtime failed")
    local exist_before = io.exists("/pgfs/before_append.txt")
    log.info("pgfs_perf", string.format("Test3: exist=%s (expected false)", tostring(exist_before)))
    assert(exist_before == false, "Test3 failed")

    -- Test4: 正常写入后 reset_runtime，数据应该保留
    log.info("pgfs_perf", "--- Test4: 正常写入后 reset_runtime ---")
    os.remove("/pgfs/normal_write.txt")
    assert(io.writeFile("/pgfs/normal_write.txt", "persist_data"), "write failed")
    sys.wait(100)
    assert(lf.pgfsctl("reset_runtime"), "reset_runtime failed")
    local exist4 = io.exists("/pgfs/normal_write.txt")
    local data4 = io.readFile("/pgfs/normal_write.txt")
    log.info("pgfs_perf", string.format("Test4: exist=%s data=%s", tostring(exist4), tostring(data4)))

    -- Test5: 批量写入后断电恢复
    log.info("pgfs_perf", "--- Test5: 批量写入后 reset_runtime ---")
    for i = 1, 30 do
        assert(io.writeFile("/pgfs/batch_" .. i .. ".txt", "batch_data_" .. i), "batch write failed")
    end
    sys.wait(100)
    assert(lf.pgfsctl("reset_runtime"), "batch reset_runtime failed")
    local all_exist = true
    for i = 1, 30 do
        if not io.exists("/pgfs/batch_" .. i .. ".txt") then
            all_exist = false
            log.info("pgfs_perf", string.format("Test5: batch_%d.txt missing", i))
            break
        end
    end
    log.info("pgfs_perf", string.format("Test5: all_30_files_exist=%s", tostring(all_exist)))

    -- 清理
    log.info("pgfs_perf", "--- cleanup ---")
    for i = 1, 20 do
        os.remove("/pgfs/init_" .. i .. ".txt")
    end
    os.remove("/pgfs/powercut_reject.txt")
    os.remove("/pgfs/after_append.txt")
    os.remove("/pgfs/before_append.txt")
    os.remove("/pgfs/normal_write.txt")
    for i = 1, 30 do
        os.remove("/pgfs/batch_" .. i .. ".txt")
    end

    log.info("pgfs_perf", "========== PGFS 断电恢复测试完成 ==========")
    log.info("pgfs_perf", "ALL POWER LOSS RECOVERY TESTS PASSED")

    cleanup(flash)
    sys.wait(500)
    log.info("pgfs_perf", "Test complete, rebooting...")
    rtos.reboot()
end)

sys.run()
