PROJECT = "lf_nand_basic"
VERSION = "1.0.0"

sys = require("sys")

local function getenv(name)
    if os and os.getenv then
        return os.getenv(name)
    end
end

local function get_mode()
    local mode = rawget(_G, "LF_NAND_TEST_MODE") or getenv("LF_NAND_TEST_MODE") or "GREEN"
    mode = string.upper(tostring(mode))
    if mode ~= "RED" and mode ~= "GREEN" then
        mode = "GREEN"
    end
    return mode
end

local function get_spi_bus()
    local v = rawget(_G, "LF_SPI_BUS") or getenv("LF_SPI_BUS")
    local n = tonumber(v)
    if n then
        return n
    end
    return 0
end

local function get_spi_cs()
    local v = rawget(_G, "LF_SPI_CS") or getenv("LF_SPI_CS")
    local n = tonumber(v)
    if n then
        return n
    end
    return 17
end

local function assert_file_roundtrip(path, expected)
    assert(io.writeFile(path, expected), "io.writeFile failed: " .. path)
    local actual = io.readFile(path)
    assert(actual ~= nil, "io.readFile failed: " .. path)
    assert(actual == expected, "file content mismatch: " .. path)
end

sys.taskInit(function()
    local mode = get_mode()
    log.info("lf_nand_basic", "mode", mode)
    log.info("lf_nand_basic", "setting up spi device")
    local spi_device = spi.deviceSetup(get_spi_bus(), get_spi_cs(), 0, 0, 8, 2 * 1000 * 1000, spi.MSB, 1, 0)
    assert(spi_device, "spi.deviceSetup failed")

    local flash = lf.init(spi_device)
    if mode == "RED" then
        assert(not flash, "lf.init unexpectedly succeeded in RED mode")
        if spi_device.close then
            spi_device:close()
        end
        os.exit(0)
    end
    assert(flash, "lf.init returned nil")

    local capacity, prog_size, erase_size = lf.getInfo(flash)
    assert(capacity and capacity > 0, "invalid capacity")
    assert(prog_size and prog_size > 0, "invalid prog_size")
    assert(erase_size and erase_size > 0, "invalid erase_size")

    local test_addr = 0
    local test_data = string.rep("LF_NAND_SIM_DATA_", 32)
    assert(lf.erase(flash, test_addr, erase_size), "lf.erase failed")
    assert(lf.write(flash, test_addr, test_data), "lf.write failed")
    local read_back = lf.read(flash, test_addr, #test_data)
    assert(read_back == test_data, "lf.read mismatch")

    assert(lf.mount, "lf.mount is unavailable")
    local mounted = lf.mount(flash, "/nand/", 0, 0)
    assert(mounted, "lf.mount /nand failed")

    assert_file_roundtrip("/nand/probe.txt", "lf_nand_mount_probe")
    assert_file_roundtrip("/lfs2/probe.txt", "lf_lfs2_probe")

    if spi_device.close then
        spi_device:close()
    end
    os.exit(0)
end)

sys.run()
