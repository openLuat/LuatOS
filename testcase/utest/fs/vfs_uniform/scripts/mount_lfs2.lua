-- mount_lfs2.lua
-- lfs2 / 挂载点 /lfs2
-- PC BSP 启动时已 mount (512KB 内存后端), 见 bsp/pc/port/luat_fs_mini.c:158-178
-- 注意: lfs2 限额 2, 已占 1, 不要再调 lfs2.mount()

local common = require("vfs_common")
local M = {}

function M.setup()
    common.MOUNT_POINT = "/lfs2"
    common.FS_NAME = "lfs2"
    -- 跳过 C13: lfs2 mkdir 不自动创建父目录 (luat/vfs/luat_fs_lfs2.c:206-223)
    common.SKIPPED = {
        "test_dir_nested_mkdir_auto_parent",
    }

    local probe = common.path("_vfs_uniform_probe")
    pcall(os.remove, probe)
    -- 写探活文件; 失败 = 该 build 不含 lfs2
    -- (LuatOS 的 io.exists 不识别挂载点目录, 不可用)
    local f = io.open(probe, "wb")
    if not f then
        log.warn("vfs_uniform", "/lfs2 不可写 (该 build 不含 lfs2)")
        return false
    end
    f:close()
    pcall(os.remove, probe)
    return true
end

return M
