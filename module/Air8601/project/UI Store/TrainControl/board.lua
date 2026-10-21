-- Air8601 (Air1601 host) / 7-inch HX8282 RGB / GT911, 1024 x 600.
-- 初始化顺序取自合宙官方 Air8601 工厂工程，需 Air1601/Air1602 102 号固件。
local M = {
    width = 1024,
    height = 600,
    profile = "Air8601_7inch_1024x600",
    source_commit = "cebcfbf25e0d19491b853c4989cb1cbdf5f93cf3"
}

local function power_on()
    pins.setup(43, "GPIO13")
    local steps = {
        {42, 1, 50},
        {65, 0, 100},
        {65, 1, 1000},
        {43, 1},
        {52, 1},
        {56, 1},
        {73, 1, 200}
    }
    for _, step in ipairs(steps) do
        gpio.setup(step[1], 0)
        gpio.set(step[1], step[2])
        if step[3] then sys.wait(step[3]) end
    end
end

-- 必须在 sys.taskInit 内调用，因为官方上电时序会主动让出协程。
function M.init(config)
    if config and config.width then M.width = config.width end
    if config and config.height then M.height = config.height end

    if not display or not display.init then
        return false, "display core missing: use the official Air8601 102 firmware"
    end
    if not airui or not airui.init then
        return false, "airui core missing"
    end
    if not pins or not gpio or not tp or not i2c then
        return false, "Air8601 board core libraries are missing"
    end

    power_on()

    local ok, err = display.init("custom", {
        id = 0,
        interface = "rgb",
        w = M.width,
        h = M.height,
        hbp = 140,
        hspw = 20,
        hfp = 160,
        vbp = 20,
        vspw = 3,
        vfp = 12,
        pclk_hz = 50000000,
        pin_rst = 15
    })
    if not ok then return false, "display.init failed: " .. tostring(err) end

    local width, height = display.getSize()
    if width ~= M.width or height ~= M.height then
        return false, "unexpected screen size " .. tostring(width) .. "x" .. tostring(height)
    end
    if not airui.init(width, height) then return false, "airui.init failed" end

    local font_ok = airui.font_load({
        type = "hzfont",
        size = 16,
        cache_size = 1024,
        antialias = 1,
        global = true
    })
    if not font_ok then return false, "built-in hzfont load failed" end
    airui.set_rotation(0)

    gpio.setup(38, 0)
    gpio.set(38, 1)
    i2c.setup(1)
    M.touch = tp.init("gt911", {
        port = 1,
        pin_rst = 56,
        pin_int = 51,
        int_type = tp.FALLING,
        w = width,
        h = height
    })
    if not M.touch then return false, "GT911 touch initialization failed" end
    if not airui.device_bind_touch(M.touch) then
        return false, "AirUI touch binding failed"
    end

    log.info("board", M.profile, "AirUI", airui.version())
    return true, width, height
end

return M
