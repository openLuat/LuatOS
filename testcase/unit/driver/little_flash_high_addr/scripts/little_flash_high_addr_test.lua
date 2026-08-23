local little_flash_high_addr_test = {}

local HIGH_OFFSET = 0x1000000  -- 16 MB，验证 256 Mbit NOR Flash 高地址区域
local TEST_SIZE = 256

local function make_pattern(seed)
    local t = {}
    for i = 1, TEST_SIZE do
        t[i] = string.char(((seed + i) * 17) % 256)
    end
    return table.concat(t)
end

local function setup_flash()
    if not lf or not lf.init then
        return nil, "lf library unavailable"
    end
    if not spi or not spi.deviceSetup then
        return nil, "spi unavailable"
    end

    local bus_id = 2
    local cs_pin = 4
    local speed = 20000000
    if rtos_bsp == "PC" then
        bus_id = 1
        speed = 2000000
    end

    local spi_dev = spi.deviceSetup(bus_id, cs_pin, 0, 0, 8, speed, spi.MSB, 1, 0)
    if not spi_dev then
        return nil, "spi.deviceSetup failed"
    end

    local flash = lf.init(spi_dev)
    if not flash then
        return nil, "lf.init failed"
    end

    local capacity = lf.getInfo(flash)
    if capacity <= HIGH_OFFSET then
        return nil, "flash capacity too small for high address test"
    end

    return flash
end

function little_flash_high_addr_test.test_lf_high_addr_direct()
    local flash = setup_flash()
    if not flash then
        log.info("LF_HIGH_ADDR", "skip: no hardware flash")
        return
    end

    -- 擦除高地址的一个 sector
    local ok_erase = lf.erase(flash, HIGH_OFFSET, 0x1000)
    assert(ok_erase, "high address erase failed")

    -- 写入并回读
    local pattern = make_pattern(0x55)
    local ok_write = lf.write(flash, HIGH_OFFSET, pattern)
    assert(ok_write, "high address write failed")

    local data = lf.read(flash, HIGH_OFFSET, TEST_SIZE)
    assert(data == pattern, "high address read mismatch")

    log.info("LF_HIGH_ADDR", "direct read/write above 16 MB ok")
end

function little_flash_high_addr_test.test_lf_high_addr_lfs2()
    local flash = setup_flash()
    if not flash then
        log.info("LF_HIGH_ADDR", "skip: no hardware flash")
        return
    end

    local mount_point = "/lf_high"
    -- 先擦除要挂载的区域（1 MB）
    local ok_erase = lf.erase(flash, HIGH_OFFSET, 0x100000)
    assert(ok_erase, "high address lfs2 erase failed")

    local ok_mount = lf.mount(flash, mount_point, HIGH_OFFSET, 0x100000)
    assert(ok_mount, "high address lfs2 mount failed")

    local file_path = mount_point .. "/test.txt"
    local payload = "high_addr_lfs2_" .. tostring(os.time())

    local f = io.open(file_path, "wb")
    assert(f, "create file failed")
    f:write(payload)
    f:close()

    f = io.open(file_path, "rb")
    assert(f, "open file failed")
    local got = f:read("*a")
    f:close()
    assert(got == payload, "lfs2 file content mismatch")

    os.remove(file_path)

    local ok_unmount = lf.unmount(mount_point)
    assert(ok_unmount, "high address lfs2 unmount failed")

    log.info("LF_HIGH_ADDR", "lfs2 mount/read/write above 16 MB ok")
end

return little_flash_high_addr_test
