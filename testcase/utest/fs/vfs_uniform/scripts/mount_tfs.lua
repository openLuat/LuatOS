-- mount_tfs.lua
-- tfs / 挂载点 /tfs0
-- 使用 lf.mount(flash, "/tfs0", offset, size, {fs="tfs"})
-- PC 模拟器: spi.deviceSetup(1, 255, ...) 返回 mock 后端
--
-- 分区大小: TFS OOB + 名字 marker + 初始 CP 至少需要数 MB,
-- 256KB 不够. 与 PGFS 16MB slab 策略一致, TFS 也升到 16MB.

local common = require("vfs_common")
local M = {}

-- TDD probe: tfs 应当挂载到 /tfs0/. RED 时 io.open 抛 nil, GREEN 时
-- 返回 file handle. Probe 仅日志, 不阻断 setup (与 PGFS probe 模式一致).
function M.tdd_probe_tfs_mounted()
    local p = "/tfs0/_vfs_uniform_probe"
    pcall(os.remove, p)
    local f = io.open(p, "wb")
    if not f then
        log.warn("vfs_uniform", "TDD probe FAIL: tfs not mounted at /tfs0/")
        return false
    end
    f:close()
    pcall(os.remove, p)
    log.info("vfs_uniform", "TDD probe PASS: tfs mounted at /tfs0/")
    return true
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

    local bus = 1
    local speed = 2000000
    if rtos.bsp and rtos.bsp() == "PC" then
        bus = 1
        speed = 2000000
    end

    local spidev = spi.deviceSetup(bus, 255, 0, 0, 8, speed, spi.MSB, 1, 0)
    if not spidev then
        log.warn("vfs_uniform", "spi.deviceSetup 失败")
        return false
    end
    local flash = lf.init(spidev)
    if not flash then
        log.warn("vfs_uniform", "lf.init 失败")
        return false
    end

    local TFS_MOUNT_SIZE = 16 * 1024 * 1024
    local ok = lf.mount(flash, "/tfs0", 0, TFS_MOUNT_SIZE, {fs = "tfs"})
    if not ok then
        log.warn("vfs_uniform", "tfs mount 失败 (16MB partition)")
        return false
    end

    -- TDD probe: 挂载后立刻探活
    M.tdd_probe_tfs_mounted()

    common.MOUNT_POINT = "/tfs0"
    common.FS_NAME = "tfs"
    -- C13: tfs mkdir 不自动创建父目录
    -- C22: tfs 页大小可能不是 4096
    common.SKIPPED = {
        "test_dir_nested_mkdir_auto_parent",
        "test_edge_block_size_boundary",
    }

    local probe = common.path("_vfs_uniform_probe")
    pcall(os.remove, probe)
    local f = io.open(probe, "wb")
    if not f then
        log.warn("vfs_uniform", "tfs /tfs0 不可写")
        return false
    end
    f:close()
    pcall(os.remove, probe)
    return true
end

return M
