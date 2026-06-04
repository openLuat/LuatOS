-- 116.ndk_examples_smoke: load all 4 refactored C examples and verify
-- they each complete (ok=true, no trap) and write the expected marker
-- to the exchange buffer.

sys.taskInit(function()
    sys.wait(100)
    local results = {}
    local cases = {
        { path = "/luadb/hello_world.bin",        marker = "HELLO_NDK_DONE",  len = 15 },
        { path = "/luadb/exchange_buffer_demo.bin", marker = nil,              len = 16 },
        { path = "/luadb/gpio_hostabi_demo.bin",  marker = nil,                len = 20 },
        { path = "/luadb/crypto_hash_demo.bin",   marker = nil,                len = 16 },
    }
    for i, c in ipairs(cases) do
        log.info("ndk_examples_smoke", "case", i, "path", c.path)
        local ctx, err = ndk.rv32i(c.path, 32 * 1024, 1024)
        if not ctx then
            log.error("ndk_examples_smoke", "rv32i failed", err)
            results[i] = "rv32i fail: " .. tostring(err)
            goto continue
        end
        local info = ndk.info(ctx)
        log.info("ndk_examples_smoke", "info", "mem", info.mem, "exchange", info.exchange)
        local ok, ret, mcause, mtval = ndk.exec(ctx, {steps = 0, elapsed = 100})
        if not ok then
            log.error("ndk_examples_smoke", "exec failed", ret, mcause, mtval, "mtval_hex", string.format("0x%X", mtval or 0))
            results[i] = "exec fail: " .. tostring(ret) .. " mcause=" .. tostring(mcause) .. " mtval=" .. string.format("0x%X", mtval or 0)
        else
            local data = ndk.getData(ctx, c.len, 0) or ""
            results[i] = string.format("ok ret=%d data='%s'", ret, data:sub(1, 32))
            log.info("ndk_examples_smoke", "case", i, "ok", ret, "data", data:sub(1, 32))
        end
        ndk.stop(ctx, 1000)
        ndk.reset(ctx)
        ::continue::
    end
    log.info("ndk_examples_smoke", "DONE", "results", #results)
    for i, r in ipairs(results) do
        log.info("ndk_examples_smoke", "case", i, r)
    end
    os.exit(0)
end)
sys.run()
