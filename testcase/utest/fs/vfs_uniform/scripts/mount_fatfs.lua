-- mount_fatfs.lua
-- fatfs / 挂载点 /vram (避免与 /fatfs 默认冲突)
-- 使用 fatfs.RAM 模式 (仅 PC: LUA_USE_LINUX/WIN/MACOSX)

local common = require("vfs_common")
local M = {}

function M.setup()
    local fatfs = require("fatfs")
    if not fatfs or not fatfs.mount or not fatfs.RAM then
        log.warn("vfs_uniform", "fatfs 模块不可用")
        return false
    end

    local ok, err = fatfs.mount(fatfs.RAM, "/vram", 128 * 1024)
    if not ok then
        log.warn("vfs_uniform", "fatfs.mount RAM 失败: " .. tostring(err))
        return false
    end

    common.MOUNT_POINT = "/vram"
    common.FS_NAME = "fatfs"
    -- C10: lsdir 在 fatfs 上对 d_size 支持可能不全
    -- C13: fatfs mkdir 不自动创建父目录
    common.SKIPPED = {
        "test_dir_nested_mkdir_auto_parent",
    }

    local probe = common.path("_vfs_uniform_probe")
    pcall(os.remove, probe)
    local f = io.open(probe, "wb")
    if not f then
        log.warn("vfs_uniform", "fatfs /vram 不可写")
        return false
    end
    f:close()
    pcall(os.remove, probe)
    return true
end

return M
