PROJECT = "pgfs_nes_unzip_probe"
VERSION = "1.0.0"

sys = require("sys")

local TAG = "pgfs_nes_unzip"
local ZIP_PATH = "/luadb/NES_Emulator.zip"
local MOUNT_POINT = "/little_flash/"
local TARGET_DIR = "/little_flash/app_store/"
local UNZIP_TIMEOUT_MS = 120000
local UNZIP_MAX_WALL_MS = 90000
local RESET_MAX_WALL_MS = 30000

local function is_pc()
    return hmeta and hmeta.model and hmeta.model() == "PC"
end

local function fail(msg)
    log.error(TAG, msg)
    log.error(TAG, "### PGFS_NES_UNZIP_FAIL ###")
    if is_pc() and os and os.exit then
        os.exit(1)
    end
    while true do
        sys.wait(1000)
    end
end

local function pass(msg)
    log.info(TAG, msg)
    log.info(TAG, "### PGFS_NES_UNZIP_PASS ###")
    if is_pc() and os and os.exit then
        os.exit(0)
    end
    while true do
        sys.wait(1000)
    end
end

local function spi_bus()
    if is_pc() then return 0 end
    return 2
end

local function spi_cs()
    if is_pc() then return 17 end
    return 4
end

local function now_us()
    if mcu and mcu.ticks2 then
        local high, low = mcu.ticks2(1)
        return high * 1000000 + low
    end
    if mcu and mcu.ticks then
        return mcu.ticks() * 1000
    end
    return math.floor(os.clock() * 1000000)
end

local function us_to_ms(cost_us)
    if cost_us <= 0 then
        return 1
    end
    return math.max(1, math.floor((cost_us + 500) / 1000))
end

sys.taskInit(function()
    log.info(TAG, "start", hmeta and hmeta.model and hmeta.model() or "unknown")
    if not io.exists(ZIP_PATH) then
        fail("zip not found " .. ZIP_PATH)
        return
    end

    local spi_device = spi.deviceSetup(spi_bus(), spi_cs(), 0, 0, 8, 2 * 1000 * 1000, spi.MSB, 1, 0)
    if not spi_device then
        fail("spi.deviceSetup failed")
        return
    end
    local flash = lf.init(spi_device)
    if not flash then
        fail("lf.init failed")
        return
    end
    local mount_size = 0
    if is_pc() then
        mount_size = 0x04000000
    end
    if not lf.mount(flash, MOUNT_POINT, 0, mount_size, "pgfs") then
        fail("lf.mount failed")
        return
    end

    local t_unzip = now_us()
    local ok = miniz.unzip(ZIP_PATH, TARGET_DIR, true, UNZIP_TIMEOUT_MS)
    local unzip_ms = us_to_ms(now_us() - t_unzip)
    if not ok then
        fail("miniz.unzip returned false")
        return
    end
    if unzip_ms >= UNZIP_MAX_WALL_MS then
        fail("unzip wall regression ms=" .. tostring(unzip_ms))
        return
    end

    local ls_ok, entries = io.lsdir(TARGET_DIR)
    if not ls_ok or type(entries) ~= "table" or #entries == 0 then
        fail("target dir empty after unzip")
        return
    end

    local t_reset = now_us()
    if lf.fsctrl and (not lf.fsctrl("reset_runtime")) then
        fail("reset_runtime failed")
        return
    end
    local reset_ms = us_to_ms(now_us() - t_reset)
    if reset_ms >= RESET_MAX_WALL_MS then
        fail("reset_runtime wall regression ms=" .. tostring(reset_ms))
        return
    end
    local f = io.open("/little_flash/app_store/NES_Emulator/main.lua", "rb")
    if not f then
        fail("main.lua missing after reset_runtime")
        return
    end
    local s = f:read("*a") or ""
    f:close()
    if #s == 0 then
        fail("main.lua empty after reset_runtime")
        return
    end

    log.info(TAG, string.format("### PGFS_NES_UNZIP_METRIC ### unzip_ms=%d reset_ms=%d entries=%d", unzip_ms, reset_ms, #entries))
    pass("unzip durable entries=" .. tostring(#entries))
end)

sys.run()
