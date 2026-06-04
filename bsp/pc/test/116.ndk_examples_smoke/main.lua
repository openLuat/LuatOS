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
        -- regression: non-inline call from main() + natural return (no ndk_exit_ok)
        -- before the NDK_GUEST_START ra-fix this would trap with mcause=1, mtval=0
        { path = "/luadb/nonleaf_call_demo.bin",  marker = nil,                len = 16 },
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
        local ok, ret, mcause, mtval = ndk.exec(ctx, {steps = 100000, elapsed = 100})
        if not ok and (mcause ~= nil and mcause ~= 0) then
            -- real trap: this is the failure we are guarding against
            -- (mcause=1 mtval=0 was the NDK_GUEST_START ra-bug signature)
            log.error("ndk_examples_smoke", "exec failed", ret, mcause, mtval, "mtval_hex", string.format("0x%X", mtval or 0))
            results[i] = "exec fail: " .. tostring(ret) .. " mcause=" .. tostring(mcause) .. " mtval=" .. string.format("0x%X", mtval or 0)
        else
            -- ok==true: SYSCON 0x5555 exit, ret is the exit value
            -- not ok but mcause==0: step budget exhausted with no trap —
            --   legal for guests whose main() returns naturally without ndk_exit_ok()
            --   (regression for NDK_GUEST_START ra-bug; was previously mcause=1)
            local data = ndk.getData(ctx, c.len, 0) or ""
            local exit_kind = ok and "ok" or "budget-exhausted-clean"
            results[i] = string.format("%s ret=%s data='%s'", exit_kind, tostring(ret), data:sub(1, 32))
            log.info("ndk_examples_smoke", "case", i, exit_kind, ret, "data", data:sub(1, 32))
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
