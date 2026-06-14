-- mount_pgfs.lua
-- pgfs / 挂载点 /pgfs0
-- 使用 lf.mount(flash, "/pgfs0", offset, size, {fs="pgfs"})
-- 注意: pgfs 一次只能 mount 一个 (静态 s_pgfs_ctx)

local common = require("vfs_common")
local M = {}

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

    local ok = lf.mount(flash, "/pgfs0", 0, 256 * 1024, {fs = "pgfs"})
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
