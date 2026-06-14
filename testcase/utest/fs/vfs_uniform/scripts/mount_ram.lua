-- mount_ram.lua
-- ram (registered as "ram") / 挂载点 /ram
-- PC BSP 启动时已 mount, 见 bsp/pc/port/luat_fs_mini.c:47-53

local common = require("vfs_common")
local M = {}

function M.setup()
    common.MOUNT_POINT = "/ram"
    common.FS_NAME = "ram"
    common.SKIPPED = {}  -- ram 是参考实现, 不跳过

    -- 探活: 写一个临时文件
    local probe = common.path("_vfs_uniform_probe")
    os.remove(probe)
    local f = io.open(probe, "wb")
    if not f then
        log.warn("vfs_uniform", "ram 不可用, /ram 写失败")
        return false
    end
    f:close()
    os.remove(probe)
    return true
end

return M
