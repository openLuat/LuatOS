PROJECT = "pgfs_manual_verify"
VERSION = "1.0.0"

sys = require("sys")

local TAG = "pgfs_manual"
local MOUNT_POINT = "/little_flash/"

local function is_pc()
    if hmeta and hmeta.model then
        return hmeta.model() == "PC"
    end
    return false
end

local function get_spi_bus()
    if os and os.getenv then
        local v = os.getenv("PGFS_SPI_BUS") or os.getenv("LF_SPI_BUS")
        if v and v ~= "" then
            local n = tonumber(v)
            if n then
                return n
            end
        end
    end
    if is_pc() then
        return 0
    end
    return 2
end

local function get_spi_cs()
    if os and os.getenv then
        local v = os.getenv("PGFS_SPI_CS") or os.getenv("LF_SPI_CS")
        if v and v ~= "" then
            local n = tonumber(v)
            if n then
                return n
            end
        end
    end
    if is_pc() then
        return 17
    end
    return 4
end

local function ensure_flash_power()
    if is_pc() then
        return
    end
    if gpio and gpio.setup then
        gpio.setup(50, 1)
        sys.wait(20)
    end
end

local function fail(msg)
    log.error(TAG, msg)
    log.error(TAG, "### PGFS_MANUAL_FAIL ###")
end

local function pass(msg)
    log.info(TAG, msg)
    log.info(TAG, "### PGFS_MANUAL_PASS ###")
end

sys.taskInit(function()
    log.info(TAG, "start")
    if hmeta and hmeta.model then
        log.info(TAG, "model", hmeta.model())
    end
    log.info(TAG, "spi config", "bus=" .. tostring(get_spi_bus()) .. " cs=" .. tostring(get_spi_cs()))

    ensure_flash_power()
    local spi_device = spi.deviceSetup(get_spi_bus(), get_spi_cs(), 0, 0, 8, 2 * 1000 * 1000, spi.MSB, 1, 0)
    if not spi_device then
        fail("spi.deviceSetup failed")
        return
    end
    log.info(TAG, "spi.deviceSetup ok")

    local flash = lf.init(spi_device)
    if not flash then
        fail("lf.init failed")
        return
    end
    log.info(TAG, "lf.init ok")

    local mounted = lf.mount(flash, MOUNT_POINT, 0, 0, "pgfs")
    if not mounted then
        fail("lf.mount failed")
        return
    end
    log.info(TAG, "lf.mount ok", MOUNT_POINT)

    local path = MOUNT_POINT .. "manual_probe.txt"
    local payload = "manual_verify_payload_v1"
    local wf = io.open(path, "wb")
    if not wf then
        fail("io.open for write failed")
        return
    end
    if not wf:write(payload) then
        fail("file write failed")
        wf:close()
        return
    end
    local close_ok = wf:close()
    log.info(TAG, "close result", tostring(close_ok))
    if not close_ok then
        fail("file close failed")
        return
    end
    log.info(TAG, "write ok", path)

    local read_back = io.readFile(path)
    log.info(TAG, "read before reset", tostring(read_back))
    if read_back ~= payload then
        fail("read before reset mismatch")
        return
    end

    if not lf.pgfsctl("reset_runtime") then
        fail("lf.pgfsctl(reset_runtime) failed")
        return
    end
    log.info(TAG, "reset_runtime ok")

    local read_after = io.readFile(path)
    log.info(TAG, "read after reset", tostring(read_after))
    if read_after ~= payload then
        fail("read after reset mismatch")
        return
    end

    pass("durable check ok")
end)

sys.run()
