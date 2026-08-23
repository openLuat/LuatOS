-- mount_fatfs.lua
-- fatfs / 挂载点 /fatfs
-- type 1 路径: 走 spi.device_setup 调到 luat_spi_bus_setup / luat_spi_setup,
-- 在 PC BSP 上设 win32spis[id].open = 1 和 g_spi_routes[id].active_cs = 23。
-- 整数参数路径在 PC 上不调 luat_spi_setup,虚拟 SPI 总线 open=0,
-- 后续 luat_spi_transfer 早退,SD 卡模拟器收不到任何字节。

local common = require("vfs_common")
local M = {}

function M.setup()

    local tf_dev = spi.deviceSetup(20, 23, 0, 8, 24*1000*1000)
    -- 保活: spi userdata 被 GC 后 fatfs 后端野指针, 后续 IO 全失败.
    M.spidev = tf_dev
    -- fatfs.mount 返回 (bool, int): 第一值 true/false, 第二值 FR_OK(0) 或错误码
    local ok, err = fatfs.mount(fatfs.SPI, "/fatfs", tf_dev)
    assert(ok, "fatfs mount failed: " .. tostring(err))

    common.MOUNT_POINT = "/fatfs"
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
        log.warn("vfs_uniform", "fatfs /fatfs 不可写")
        return false
    end
    f:close()
    pcall(os.remove, probe)
    return true
end

return M
