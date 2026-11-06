local fatfs_multi_test = {}

local MOUNT1 = "/ram1"
local MOUNT2 = "/ram2"
-- PC 模拟器 vmheap 只有 4MB, ramdisk 必须用小容量;
-- 小容量盘 FAT32 簇数不够, 需要 FM_ANY 自动选 FAT12/16
local SIZE1 = 1 * 1024 * 1024
local SIZE2 = 768 * 1024

local function write_file(path, payload)
    local f = io.open(path, "w")
    assert(f, "open for write failed: " .. path)
    assert(f:write(payload), "write failed: " .. path)
    f:close()
end

local function read_file(path)
    local f = io.open(path, "r")
    if not f then return nil end
    local data = f:read("*a")
    f:close()
    return data
end

local function mount_both()
    fatfs.unmount(MOUNT1)
    fatfs.unmount(MOUNT2)
    fatfs.config(0, 100, fatfs.FM_ANY)
    local ok, err = fatfs.mount(fatfs.RAM, MOUNT1, SIZE1)
    assert(ok == true, "mount " .. MOUNT1 .. " failed: " .. tostring(err))
    ok, err = fatfs.mount(fatfs.RAM, MOUNT2, SIZE2)
    assert(ok == true, "mount " .. MOUNT2 .. " failed: " .. tostring(err))
end

function fatfs_multi_test.test_dual_mount_rw_isolation()
    mount_both()
    local payload1 = "fatfs-multi-volume-ram1"
    local payload2 = "fatfs-multi-volume-ram2-other"
    write_file(MOUNT1 .. "/same.txt", payload1)
    write_file(MOUNT2 .. "/same.txt", payload2)
    write_file(MOUNT1 .. "/only1.txt", payload1)
    assert(read_file(MOUNT1 .. "/same.txt") == payload1, "ram1 content mismatch")
    assert(read_file(MOUNT2 .. "/same.txt") == payload2, "ram2 content mismatch")
    assert(read_file(MOUNT2 .. "/only1.txt") == nil, "ram1 file visible on ram2")
    fatfs.unmount(MOUNT1)
    fatfs.unmount(MOUNT2)
end

function fatfs_multi_test.test_dual_mount_getfree()
    mount_both()
    local d1, err1 = fatfs.getfree(MOUNT1)
    local d2, err2 = fatfs.getfree(MOUNT2)
    assert(d1, "getfree " .. MOUNT1 .. " failed: " .. tostring(err1))
    assert(d2, "getfree " .. MOUNT2 .. " failed: " .. tostring(err2))
    log.info("fatfs_multi", "ram1 sectors", d1.total_sectors, "ram2 sectors", d2.total_sectors)
    assert(d1.total_sectors > d2.total_sectors, "1MB disk should have more sectors than 768KB disk")
    fatfs.unmount(MOUNT1)
    fatfs.unmount(MOUNT2)
end

function fatfs_multi_test.test_unmount_keeps_other_alive()
    mount_both()
    write_file(MOUNT2 .. "/keep.txt", "keep-me")
    local ret = fatfs.unmount(MOUNT1)
    assert(ret == 0, "unmount ram1 ret=" .. tostring(ret))
    assert(read_file(MOUNT2 .. "/keep.txt") == "keep-me", "ram2 unreadable after ram1 unmount")
    local ok, err = fatfs.mount(fatfs.RAM, MOUNT1, SIZE1)
    assert(ok == true, "remount ram1 failed: " .. tostring(err))
    assert(read_file(MOUNT1 .. "/keep.txt") == nil, "remounted ram1 should be blank")
    fatfs.unmount(MOUNT1)
    fatfs.unmount(MOUNT2)
end

function fatfs_multi_test.test_spi_tf_and_ramdisk_coexist()
    -- PC 虚拟 SD 固定走 spi bus 20, 卡容量 64MB, 直接用 FAT32
    local bus_id, cs_pin = 20, 23
    local speed = 24 * 1000 * 1000
    spi.setup(bus_id, cs_pin, 0, 0, 8, speed, spi.MSB, 1, 1)
    fatfs.unmount("/sd")
    fatfs.unmount(MOUNT1)
    fatfs.config(0, 100, fatfs.FM_FAT32)
    local ok, err = fatfs.mount(fatfs.SPI, "/sd", bus_id, cs_pin, speed)
    assert(ok == true, "spi tf mount failed: " .. tostring(err))
    fatfs.config(0, 100, fatfs.FM_ANY)
    ok, err = fatfs.mount(fatfs.RAM, MOUNT1, SIZE2)
    assert(ok == true, "ramdisk mount failed: " .. tostring(err))
    -- 清理可能存在的残留文件(vsd 镜像跨运行持久化, 旧版本串盘 bug 曾把 ram 文件写进过 sd)
    os.remove("/sd/coexist_sd.txt")
    os.remove("/sd/coexist_ram.txt")
    write_file("/sd/coexist_sd.txt", "on-sd-card")
    write_file(MOUNT1 .. "/coexist_ram.txt", "on-ramdisk")
    assert(read_file("/sd/coexist_sd.txt") == "on-sd-card", "sd readback mismatch")
    assert(read_file(MOUNT1 .. "/coexist_ram.txt") == "on-ramdisk", "ramdisk readback mismatch")
    assert(read_file("/sd/coexist_ram.txt") == nil, "ram file visible on sd")
    assert(read_file(MOUNT1 .. "/coexist_sd.txt") == nil, "sd file visible on ramdisk")
    os.remove("/sd/coexist_sd.txt")
    fatfs.unmount("/sd")
    fatfs.unmount(MOUNT1)
end

return fatfs_multi_test
