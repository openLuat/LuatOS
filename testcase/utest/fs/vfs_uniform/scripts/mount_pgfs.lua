-- mount_pgfs.lua
-- pgfs / 挂载点 /pgfs0
-- 使用 lf.mount(flash, "/pgfs0", offset, size, {fs="pgfs"})
-- 注意: pgfs 一次只能 mount 一个 (静态 s_pgfs_ctx)
--
-- 8MB partition 限制: PGFS 8MB 以下会被 luat_vfs_pgfs_mount 拒绝.
-- 原因: FTL 元数据 (~256KB) + 2× superblock + 2× CP + segment allocator
-- 需要 64×128KB block (8MB 起始), 256KB 的 utest 分区无法满足这些需求.

local common = require("vfs_common")
local M = {}

-- TDD probe: 验证 size gate. 256KB 必须被拒绝, 8MB/16MB 必须被接受.
-- 实际挂载在 setup() 中按 16MB 进行 (在所有 probe 之后).
--
-- TDD lifecycle:
--   RED  (修复前): 256KB mount 仍然成功, log 打印 "TDD probe FAIL
--                   256KB-must-be-rejected: expected REJECT, got ACCEPT".
--                   真实 16MB mount 仍能进行, 30-case suite 继续跑, 但
--                   score 仍卡在 16/30 (FTL no-free-blocks, 256KB 块不够).
--   GREEN (修复后): 256KB mount 返回非零 (被拒), 8MB/16MB 返回 0, 全部 PASS.
--                   真实 16MB mount 让 FTL 拿到 64×128KB 块, score 显著提升.
local function probe_size_gate(flash, maxsize, expect_accept, label)
    local mp = string.format("/pgfs_probe_%d", maxsize)
    local ok = lf.mount(flash, mp, 0, maxsize, {fs = "pgfs"})
    local got = ok and "ACCEPT" or "REJECT"
    local expected = expect_accept and "ACCEPT" or "REJECT"
    if got == expected then
        log.info("vfs_uniform", string.format("TDD probe PASS %s: maxsize=%d %s",
              label, maxsize, got))
    else
        log.warn("vfs_uniform", string.format(
              "TDD probe FAIL %s: maxsize=%d expected %s, got %s",
              label, maxsize, expected, got))
    end
    return got == expected
end

function M.setup()
    if not lf or not lf.init or not lf.mount then
        log.warn("vfs_uniform", "lf 模块不可用")
        return false
    end
    if not spi or not spi.deviceSetup then
        log.warn("vfs_uniform", "spi 模块不可用")
        return false
    end

    local bus = 20
    local speed = 2000000

    local spidev = spi.deviceSetup(bus, 21, 0, 0, 8, speed, spi.MSB, 1, 0)
    if not spidev then
        log.warn("vfs_uniform", "spi.deviceSetup 失败")
        return false
    end
    local flash = lf.init(spidev)
    if not flash then
        log.warn("vfs_uniform", "lf.init 失败")
        return false
    end

    -- TDD probe: 256KB 必须被拒绝 (硬需求 8MB minimum).
    -- Probe 仅打印日志, 不阻断 setup. 修复前 log 标 FAIL, 修复后标 PASS.
    probe_size_gate(flash, 256 * 1024, false, "256KB-must-be-rejected")

    -- TDD probe: 8MB 边界值 (PGFS_MIN_PARTITION_BYTES) 必须被接受.
    probe_size_gate(flash, 8 * 1024 * 1024, true, "8MB-boundary-must-accept")

    -- TDD probe: 16MB 必须被接受 (与 PGFS_TEST_FLASH_LARGE_SIZE 一致).
    probe_size_gate(flash, 16 * 1024 * 1024, true, "16MB-must-accept")

    -- 实际挂载: 使用 16MB (与 components/utest/pgfs/luat_pgfs_utest.c 中的
    -- s_pgfs_test_flash_slab 一致, 该 16MB BSS 静态 slab 是 PC 端可用的
    -- 最大分区, FTL "no free blocks" 失败源自 256KB 太小).
    local ok = lf.mount(flash, "/pgfs0", 0, 16 * 1024 * 1024, {fs = "pgfs"})
    if not ok then
        log.warn("vfs_uniform", "pgfs mount 失败")
        return false
    end

    common.MOUNT_POINT = "/pgfs0"
    common.FS_NAME = "pgfs"
    -- C12: pgfs rmdir 行为可能不同
    -- C13: pgfs mkdir 不自动创建父目录
    common.SKIPPED = {
        "test_dir_rmdir_nonempty_fails",
        "test_dir_nested_mkdir_auto_parent",
    }

    local probe = common.path("_vfs_uniform_probe")
    pcall(os.remove, probe)
    local f = io.open(probe, "wb")
    if not f then
        log.warn("vfs_uniform", "pgfs /pgfs0 不可写")
        return false
    end
    f:close()
    pcall(os.remove, probe)
    return true
end

return M
