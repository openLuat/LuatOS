-- mount_tfs.lua
-- tfs / 挂载点 /tfs0
-- 使用 lf.mount(flash, "/tfs0", offset, size, {fs="tfs"})
-- PC 模拟器: spi.deviceSetup(1, 255, ...) 返回 mock 后端

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

    local ok = lf.mount(flash, "/tfs0", 0, 256 * 1024, {fs = "tfs"})
    if not ok then
        log.warn("vfs_uniform", "tfs mount 失败")
        return false
    end

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
