local M = {}

local IMAGE_PATH = "/luadb/baremetal.bin"
local INVALID_IMAGE_PATH = "/luadb/not-exists.bin"
local MEM_SIZE = 32 * 1024
local EXCHANGE_SIZE = 1024
local NDK_FEATURE_GPIO = 1 << 3
local NDK_FEATURE_CRYPTO = 1 << 5

local CTX = nil

local function wait_until(predicate, timeout_ms)
    local waited = 0
    while waited < timeout_ms do
        if predicate() then
            return true
        end
        sys.wait(10)
        waited = waited + 10
    end
    return predicate()
end

local function assert_info_fields(info)
    local fields = {"mem", "exchange", "exchange_addr", "image", "running", "mcause", "mtval"}
    for _, key in ipairs(fields) do
        assert(info[key] ~= nil, "ndk.info missing field: " .. key)
    end
end

local function unpack_u32le(data, offset)
    local value = string.unpack("<I4", data, offset + 1)
    return value
end

function M.setUp()
    CTX = nil
    collectgarbage("collect")
    collectgarbage("collect")
    assert(io.exists(IMAGE_PATH), "missing baremetal.bin in testcase directory: " .. IMAGE_PATH)
    CTX = ndk.rv32i(IMAGE_PATH, MEM_SIZE, EXCHANGE_SIZE)
    assert(CTX, "setUp ndk.rv32i failed")
end

function M.tearDown()
    if CTX then
        ndk.stop(CTX, 1000)
        CTX = nil
    end
    collectgarbage("collect")
    collectgarbage("collect")
end

function M.test_ndk_lifecycle_regression()
    assert(io.exists(IMAGE_PATH), "missing baremetal.bin in testcase directory: " .. IMAGE_PATH)

    local ctx, err = ndk.rv32i(IMAGE_PATH, MEM_SIZE, EXCHANGE_SIZE)
    assert(ctx, "ndk.rv32i failed: " .. tostring(err))

    local info = ndk.info(ctx)
    assert(type(info) == "table", "ndk.info should return table")
    assert_info_fields(info)
    assert(info.mem == MEM_SIZE, "unexpected mem size: " .. tostring(info.mem))
    assert(info.exchange == EXCHANGE_SIZE, "unexpected exchange size: " .. tostring(info.exchange))
    assert((info.features & NDK_FEATURE_GPIO) ~= 0, "ndk.info should expose GPIO feature bit")
    assert((info.features & NDK_FEATURE_CRYPTO) ~= 0, "ndk.info should expose CRYPTO feature bit")

    local ok, ret_or_err, mcause, mtval = ndk.exec(ctx, { steps = 100000, elapsed = 500 })
    assert(ok == true, string.format("ndk.exec failed: %s mcause=%s mtval=%s", tostring(ret_or_err), tostring(mcause), tostring(mtval)))
    assert(type(ret_or_err) == "number", "ndk.exec should return numeric retval")

    local idle_info = ndk.info(ctx)
    assert(type(idle_info) == "table", "ndk.info after exec should return table")
    assert(idle_info.running == false, "ndk must be idle before ndk.reset")

    local reset_ok, reset_err = ndk.reset(ctx)
    assert(reset_ok == true, "ndk.reset failed: " .. tostring(reset_err))

    local stop_ok, stop_err = ndk.stop(ctx, 1000)
    assert(stop_ok == true, "ndk.stop no-op failed: " .. tostring(stop_err))

    ctx = nil
    collectgarbage("collect")
    collectgarbage("collect")
end

function M.test_ndk_constructor_failure_no_gc_crash()
    local ok, msg = pcall(function()
        local ctx, err = ndk.rv32i(INVALID_IMAGE_PATH, MEM_SIZE, EXCHANGE_SIZE)
        assert(ctx == nil, "ndk.rv32i with invalid image should return nil")
        assert(type(err) == "string" and #err > 0, "ndk.rv32i with invalid image should return err string")
        collectgarbage("collect")
        collectgarbage("collect")
    end)
    assert(ok, "constructor failure path should not crash GC: " .. tostring(msg))
end

function M.test_ndk_invalid_param_constructor_no_resource_exhaustion()
    for i = 1, 2000 do
        local ctx, err = ndk.rv32i(IMAGE_PATH, MEM_SIZE + 1, EXCHANGE_SIZE)
        assert(ctx == nil, "invalid mem_size should fail, round=" .. i)
        assert(type(err) == "string" and #err > 0, "invalid mem_size should return error string")
    end

    local ctx2, err2 = ndk.rv32i(IMAGE_PATH, MEM_SIZE, EXCHANGE_SIZE)
    assert(ctx2, "valid constructor should still succeed after invalid attempts: " .. tostring(err2))
    local stop_ok, stop_err = ndk.stop(ctx2, 1000)
    assert(stop_ok == true, "ndk.stop after valid constructor failed: " .. tostring(stop_err))
end

function M.test_ndk_busy_and_stop_restart_sequence()
    local ctx, err = ndk.rv32i(IMAGE_PATH, MEM_SIZE, EXCHANGE_SIZE)
    assert(ctx, "ndk.rv32i failed: " .. tostring(err))

    local busy_seen = false
    local stopping_busy_seen = false
    local start_id = nil
    for _ = 1, 50 do
        local tid, thread_err = ndk.thread(ctx, { steps = 0, elapsed = 500 })
        assert(type(tid) == "number", "ndk.thread start failed: " .. tostring(thread_err))
        start_id = tid

        local tid2, err2 = ndk.thread(ctx, { steps = 0, elapsed = 500 })
        if tid2 == nil then
            assert(err2 == "busy", "expected busy on concurrent ndk.thread, got: " .. tostring(err2))
            busy_seen = true
        end

        local ok_exec, exec_err = ndk.exec(ctx, { steps = 1000, elapsed = 100 })
        if ok_exec == false then
            assert(exec_err == "busy", "expected busy on ndk.exec while thread active, got: " .. tostring(exec_err))
            busy_seen = true
        end

        local stop_now_ok, stop_now_err = ndk.stop(ctx, 0)
        if stop_now_ok == false then
            assert(stop_now_err == "timeout", "expected timeout on non-blocking stop, got: " .. tostring(stop_now_err))
            local stop_exec_ok, stop_exec_err = ndk.exec(ctx, { steps = 1000, elapsed = 100 })
            assert(stop_exec_ok == false and stop_exec_err == "busy", "ndk.exec should be busy while stopping")
            local stop_tid, stop_tid_err = ndk.thread(ctx, { steps = 0, elapsed = 100 })
            assert(stop_tid == nil and stop_tid_err == "busy", "ndk.thread should be busy while stopping")
            stopping_busy_seen = true
        end

        local stop_ok, stop_err = ndk.stop(ctx, 1000)
        assert(stop_ok == true, "ndk.stop failed: " .. tostring(stop_err))

        local settled = wait_until(function()
            local info = ndk.info(ctx)
            return info and info.running == false
        end, 500)
        assert(settled == true, "ndk did not settle to idle after stop")

        local tid3, err3 = ndk.thread(ctx, { steps = 0, elapsed = 200 })
        assert(type(tid3) == "number", "ndk.thread restart failed after stop: " .. tostring(err3))
        local stop_ok2, stop_err2 = ndk.stop(ctx, 1000)
        assert(stop_ok2 == true, "ndk.stop after restart failed: " .. tostring(stop_err2))
    end

    assert(type(start_id) == "number", "thread id should be returned")
    assert(busy_seen == true, "should observe busy rejection while running/stopping")
    assert(stopping_busy_seen == true, "should observe busy rejection while stopping")
end

function M.test_ndk_gc_during_active_worker_safe()
    local ctx, err = ndk.rv32i(IMAGE_PATH, MEM_SIZE, EXCHANGE_SIZE)
    assert(ctx, "ndk.rv32i failed: " .. tostring(err))

    local tid, terr = ndk.thread(ctx, { steps = 0, elapsed = 500 })
    assert(type(tid) == "number", "ndk.thread start failed: " .. tostring(terr))

    local ok_gc, gc_err = pcall(function()
        ctx = nil
        collectgarbage("collect")
        collectgarbage("collect")
    end)
    assert(ok_gc == true, "gc while worker active should be safe: " .. tostring(gc_err))

    local ctx2, err2 = ndk.rv32i(IMAGE_PATH, MEM_SIZE, EXCHANGE_SIZE)
    assert(ctx2, "ndk should remain usable after gc/worker cleanup: " .. tostring(err2))
    local ok_exec, ret_or_err = ndk.exec(ctx2, { steps = 100000, elapsed = 500 })
    assert(ok_exec == true, "ndk.exec after gc/worker cleanup failed: " .. tostring(ret_or_err))
    local stop_ok, stop_err = ndk.stop(ctx2, 1000)
    assert(stop_ok == true, "ndk.stop after gc/worker cleanup failed: " .. tostring(stop_err))
end

return M
