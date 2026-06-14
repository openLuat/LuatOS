-- vfs_uniform_lfs2 main.lua
-- 在 /lfs2 上跑 VFS 统一接口测试

PROJECT = "vfs_uniform_lfs2"
VERSION = "1.0.0"

local testrunner = require("testrunner")
local cases = require("vfs_cases")
local mount = require("vfs_uniform_mount")
local common = require("vfs_common")

-- 1) 挂载 / 探活
local fs_ok = mount.setup()
if not fs_ok then
    log.warn("vfs_uniform", "lfs2 FS 不可用, 退出")
    if rtos and rtos.bsp and rtos.bsp() == "PC" then
        os.exit(0)
    end
    return
end

log.info("vfs_uniform", string.format("FS=%s MOUNT=%s SKIPPED=%d", common.FS_NAME, common.MOUNT_POINT, #common.SKIPPED))
common.wrap_skips(cases)  -- SKIPPED 中的用例直接 return

-- 2) setUp / tearDown 钩子
function cases.setUp() end
function cases.tearDown()
    common.dump_bugs()
end

-- 3) 跑
sys.taskInit(function()
    testrunner.runBatch("vfs_uniform_" .. common.FS_NAME, {
        {testTable = cases, testcase = "VFS uniform test on " .. common.FS_NAME}
    })
end)
sys.run()
