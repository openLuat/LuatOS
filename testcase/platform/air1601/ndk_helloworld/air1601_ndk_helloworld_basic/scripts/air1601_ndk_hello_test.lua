--[[
@module  air1601_ndk_hello_test
@summary Air1601 真机 NDK helloworld 单用例
@version 0.1.0
@date    2026-06-03

用例:
  test_load_and_exec_hello  - ndk.rv32i 加载 hello_world.bin, ndk.exec 执行,
                              ndk.getData 读 exchange 验证 HELLO_NDK_DONE 标志位

注意:
  - 必须用 assert 抛错, 不能 if not ok then return false (testrunner "虚绿"陷阱)
  - 禁止 panic/assert/hardfault/fault/error/fatal 命名 (与 --fail-keyword 冲突)
]]

local M = {}

-- VFS 挂脚本目录为 /luadb, --script 烧入的 hello_world.bin 落在 /luadb/hello_world.bin
local IMAGE_PATH = "/luadb/hello_world.bin"
local MEM_SIZE   = 32 * 1024
local EXCHANGE   = 1024

function M.test_load_and_exec_hello()
    log.info("air1601.ndk", "===== test_load_and_exec_hello =====")

    -- 1) 创建执行上下文
    local ctx, err = ndk.rv32i(IMAGE_PATH, MEM_SIZE, EXCHANGE)
    assert(ctx, "ndk.rv32i failed: " .. tostring(err))
    log.info("air1601.ndk", "ndk.rv32i ok, ctx=" .. tostring(ctx))

    -- 2) 同步执行 guest (helloworld 写 exchange + SYSCON 0x5555 后退出)
    local ok, ret, mcause, mtval = ndk.exec(ctx, { steps = 100000, elapsed = 500 })
    log.info("air1601.ndk",
        string.format("ndk.exec ok=%s ret=%s mcause=%s mtval=%s",
            tostring(ok), tostring(ret), tostring(mcause), tostring(mtval)))
    assert(ok == true, string.format(
        "ndk.exec not ok: ok=%s ret=%s mcause=%s mtval=%s",
        tostring(ok), tostring(ret), tostring(mcause), tostring(mtval)))
    -- SYSCON 0x5555 退出时 ret = 0; ecall 退出时 ret = a0
    assert(ret == 0, "ndk.exec ret expected 0 (SYSCON 0x5555 exit), got " .. tostring(ret))

    -- 3) 读 exchange 前 16 字节, 验证 HELLO_NDK_DONE 标志
    -- guest 走 byte 写, 数据就是纯 ASCII "HELLO_NDK_DONE\0\0"
    local data = ndk.getData(ctx, 16, 0)
    log.info("air1601.ndk", "exchange[0..15] = " .. tostring(data))
    assert(type(data) == "string" and #data >= 16,
        "exchange too short, got " .. tostring(#data) .. " bytes")
    assert(data:sub(1, 14) == "HELLO_NDK_DONE",
        "exchange marker mismatch, got: " .. tostring(data))

    return true
end

return M
