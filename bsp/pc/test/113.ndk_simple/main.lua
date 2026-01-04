


sys.taskInit(function()
    sys.wait(100)
    local ctx, err = ndk.rv32i("/luadb/baremetal.bin", 32 * 1024, 1024)
    if not ctx then
        log.error("ndk", err)
        return
    end
    local ok, ret = ndk.exec(ctx, {steps = 100000, elapsed = 500})
    log.info("ndk", ok, "retval", ret)
end)

sys.run()
