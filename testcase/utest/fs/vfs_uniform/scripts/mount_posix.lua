-- mount_posix.lua
-- posix / 挂载点 testresult/vfs_uniform/posix_tmp (隔离 CWD)
-- PC BSP 启动时已 mount, 见 bsp/pc/port/luat_fs_mini.c:38-44
-- 父目录已由 main.lua / 运行脚本预先创建

local common = require("vfs_common")
local M = {}

function M.setup()
    -- 隔离 CWD, 避免污染 worktree 根目录
    common.MOUNT_POINT = "testresult/vfs_uniform/posix_tmp"
    common.FS_NAME = "posix"
    -- posix 跨平台语义有差异: C19/C20 在 Linux 允许 unlink/rename open file
    -- Windows 不允许. 记为 info 而非 bug
    common.SKIPPED = {}

    -- 探活
    local probe = common.path("_vfs_uniform_probe")
    pcall(os.remove, probe)
    local f = io.open(probe, "wb")
    if not f then
        log.warn("vfs_uniform", "posix 不可用")
        return false
    end
    f:close()
    pcall(os.remove, probe)
    return true
end

return M
