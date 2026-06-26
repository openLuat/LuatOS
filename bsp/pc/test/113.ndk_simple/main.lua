sys.taskInit(function()
    sys.wait(100)
    -- regression for NDK 512K ceiling (replaces the old 32K smoke test)
    local ctx, err = ndk.rv32i("/luadb/baremetal.bin", 512 * 1024, 1024)
    if not ctx then
        log.error("ndk", err)
        os.exit(1)
        return
    end
    local info = ndk.info(ctx)
    log.info("ndk", "mem", info.mem, "exchange", info.exchange, "running", info.running)
    assert(info.mem == 512 * 1024, "expected 512KiB RAM ceiling, got " .. tostring(info.mem))

    local wrote, wrote_err = ndk.setData(ctx, "hello ndk")
    assert(wrote and wrote ~= false, "ndk.setData failed: " .. tostring(wrote_err))
    log.info("ndk", "setData", wrote)

    local ok, ret_or_err, mcause, mtval = ndk.exec(ctx, {steps = 100000, elapsed = 500})
    if not ok then
        log.error("ndk", "exec", ret_or_err, "mcause", mcause, "mtval", mtval)
        ndk.stop(ctx, 1000)
        os.exit(1)
        return
    end
    log.info("ndk", "retval", ret_or_err)

    local data, data_err = ndk.getData(ctx, 16, 0)
    assert(data and data ~= false, "ndk.getData failed: " .. tostring(data_err))
    log.info("ndk", "getData", data)

    assert(ndk.stop(ctx, 1000), "ndk.stop failed")
    log.info("ndk", "stop", true)

    assert(ndk.reset(ctx), "ndk.reset failed")
    log.info("ndk", "reset", true)

    ctx = nil
    collectgarbage("collect")
    collectgarbage("collect")
    os.exit(0)
end)

sys.run()
