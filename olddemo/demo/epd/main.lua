PROJECT = "epd_1in54"
VERSION = "1.0.0"

sys = require("sys")

-- Change only these SPI/GPIO values when using another board.
local function epd_pins()
    local bsp = rtos.bsp()
    print("bsp",bsp)
    if string.find(bsp, "Air8101") then
        return 0, 1, 0, 21, 20
    elseif string.find(bsp, "Air8000") then
        return 1, 2, 1, 12, 17
    elseif string.find(bsp, "Air1601") or string.find(bsp, "Air1602") then
        return 1, 10, 12, 8, 14
    end
end

-- local epd_mode = epd.MODEL_1IN54_SSD1607

-- local epd_mode = epd.MODEL_1IN54
-- local epd_mode = epd.MODEL_1IN54_V2
-- local epd_mode = epd.MODEL_1IN54B_V2
local epd_mode = epd.MODEL_1IN54G_V2
-- local epd_mode = epd.MODEL_1IN54_V3

local epd_spi_hz = 4 * 1000 * 1000

-- 2.13inch e-Paper V4 via the declarative custom profile.
-- Reference: components/epaper/EPD_2in13_V4.c
local profile = {
    width = 122,
    height = 250,
    format = epd.FORMAT_INDEX1,
    busy_level = 0,
    busy_timeout = 30000,

    init = {
        {reset = {high = 20, low = 2, high2 = 20}},
        {busy = 0, timeout = 30000},
        {cmd = 0x12},
        {busy = 0, timeout = 30000},
        {cmd = 0x01, data = {0xF9, 0x00, 0x00}},
        {cmd = 0x11, data = {0x03}},
        {cmd = 0x44, data = {0x00, 0x0F}},
        {cmd = 0x45, data = {0x00, 0x00, 0xF9, 0x00}},
        {cmd = 0x4E, data = {0x00}},
        {cmd = 0x4F, data = {0x00, 0x00}},
        {cmd = 0x3C, data = {0x05}},
        {cmd = 0x21, data = {0x00, 0x80}},
        {cmd = 0x18, data = {0x80}},
        {busy = 0, timeout = 30000},
    },

    fast_init = {
        {reset = {high = 20, low = 2, high2 = 20}},
        {cmd = 0x12},
        {busy = 0, timeout = 30000},
        {cmd = 0x18, data = {0x80}},
        {cmd = 0x11, data = {0x03}},
        {cmd = 0x44, data = {0x00, 0x0F}},
        {cmd = 0x45, data = {0x00, 0x00, 0xF9, 0x00}},
        {cmd = 0x4E, data = {0x00}},
        {cmd = 0x4F, data = {0x00, 0x00}},
        {cmd = 0x22, data = {0xB1}},
        {cmd = 0x20},
        {busy = 0, timeout = 30000},
        {cmd = 0x1A, data = {0x64, 0x00}},
        {cmd = 0x22, data = {0x91}},
        {cmd = 0x20},
        {busy = 0, timeout = 30000},
    },

    refresh = {
        full = {
            {write_ram = 0x24},
            {cmd = 0x22, data = {0xF7}},
            {cmd = 0x20},
            {busy = 0, timeout = 30000},
        },
        fast = {
            {write_ram = 0x24},
            {cmd = 0x22, data = {0xC7}},
            {cmd = 0x20},
            {busy = 0, timeout = 30000},
        },
        partial = {
            {cmd = 0x3C, data = {0x80}},
            {cmd = 0x01, data = {0xF9, 0x00, 0x00}},
            {cmd = 0x11, data = {0x03}},
            {cmd = 0x44, data = {0x00, 0x0F}},
            {cmd = 0x45, data = {0x00, 0x00, 0xF9, 0x00}},
            {cmd = 0x4E, data = {0x00}},
            {cmd = 0x4F, data = {0x00, 0x00}},
            {write_ram = 0x24},
            {cmd = 0x22, data = {0xFF}},
            {cmd = 0x20},
            {busy = 0, timeout = 30000},
        },
    },

    sleep = {
        deep = {
            {cmd = 0x10, data = {0x01}},
            {delay = 100},
        },
    },
}

-- 16x8 XBM, LSB-first, two bytes per row.
local xbm = string.char(
    0xFF, 0xFF, 0x81, 0x81, 0xBD, 0xBD, 0xA5, 0xA5,
    0xA5, 0xA5, 0xBD, 0xBD, 0x81, 0x81, 0xFF, 0xFF)

sys.taskInit(function()
    local spi_id, pin_rst, pin_dc, pin_cs, pin_busy = epd_pins()
    assert(spi_id, "unsupported BSP; edit epd_pins()")

    local spi_epd = spi.deviceSetup(spi_id, pin_cs, 0, 0, 8,
                                    epd_spi_hz, spi.MSB, 1, 0)

    local panel, err = epd.open(epd_mode, {
        port = "device", pin_dc = pin_dc, pin_rst = pin_rst,
        -- G V2 BUSY is low while working and high while idle.
        pin_busy = pin_busy, busy_pull = gpio.PULLUP, rotation = 0,
    }, spi_epd)

    -- profile.port = "device"
    -- profile.pin_dc = pin_dc
    -- profile.pin_rst = pin_rst
    -- profile.pin_busy = pin_busy
    -- profile.busy_pull = gpio.PULLDOWN
    -- profile.rotation = 90
    -- local panel, err = epd.open("custom", profile, spi_epd)

    assert(panel, err)
    assert(panel:init())

    local info = panel:info()
    log.info("epd", "panel", info.width, info.height, "caps", info.caps)
    local font_ready = type(panel.drawHzfont) == "function" and
                       hzfont and hzfont.init and hzfont.init()

    -- 1: clear, pixel, rotation and line.
    assert(panel:clear(epd.WHITE))
    if panel:supportsColor(epd.RED) and panel:supportsColor(epd.YELLOW) then
        assert(panel:setColor(epd.RED, epd.WHITE))
        assert(panel:rect(176, 4, 185, 18, nil, 1))
        assert(panel:setColor(epd.YELLOW, epd.WHITE))
        assert(panel:rect(186, 4, 194, 18, nil, 1))
        assert(panel:setColor(epd.BLACK, epd.WHITE))
    elseif panel:supportsColor(epd.RED) then
        assert(panel:setColor(epd.RED, epd.WHITE))
        assert(panel:rect(176, 4, 194, 18, nil, 1))
        assert(panel:setColor(epd.BLACK, epd.WHITE))
    end
    if font_ready then
        assert(panel:drawHzfont(6, 18, "1:像素/旋转/线", 16,
            {fg = epd.BLACK, bg = epd.WHITE, dither = epd.DITHER_THRESHOLD}))
    end
    assert(panel:pixel(8, 30, epd.BLACK))
    assert(panel:setRotation(90))
    assert(panel:pixel(0, 0, epd.BLACK))
    -- assert(panel:setRotation(0))
    assert(panel:line(8, 34, 62, 54, epd.BLACK))

    -- 2: rect and circle; fill=0 is hollow, fill=1 is solid.
    if font_ready then
        assert(panel:drawHzfont(6, 70, "2:矩形/圆", 16,
            {fg = epd.BLACK, bg = epd.WHITE, dither = epd.DITHER_BAYER4}))
    end
    assert(panel:rect(8, 82, 62, 112, epd.BLACK, 0))
    assert(panel:rect(70, 82, 112, 112, epd.BLACK, 1))
    assert(panel:circle(100, 96, 18, epd.BLACK, 0))
    assert(panel:circle(100, 96, 8, epd.BLACK, 1))

    -- 3: XBM, QR code and HzFont width.
    if font_ready then
        assert(panel:drawHzfont(6, 122, "3:XBM/二维码/字体", 16,
            {fg = epd.BLACK, bg = epd.WHITE, dither = epd.DITHER_THRESHOLD}))
        assert(panel:getHzfontWidth("中文", 16) > 0)
        assert(panel:drawHzfont(8, 158, "墨水屏", 16,
            {fg = epd.BLACK, bg = epd.WHITE, dither = epd.DITHER_THRESHOLD}))
    end
    assert(panel:drawXbm(8, 136, 16, 8, xbm, epd.BLACK, epd.WHITE))
    assert(panel:qrcode(58, 130, "EPD", 60, epd.BLACK))

    -- 4: refresh().wait() is asynchronous; wait only for its completion.
    if font_ready then
        assert(panel:drawHzfont(6, 180, "4:刷新", 16,
            {fg = epd.BLACK, bg = epd.WHITE, dither = epd.DITHER_THRESHOLD}))
    end
    assert(panel:refresh(epd.FULL).wait())

    -- AUTO chooses partial-rect or full refresh from the dirty area.
    assert(panel:pixel(115, 20, epd.BLACK))
    assert(panel:refresh(epd.AUTO).wait())

    -- Test optional refresh modes only when the controller advertises them.
    if (info.caps & epd.CAP_REFRESH_FAST) ~= 0 then
        assert(panel:pixel(116, 20, epd.BLACK))
        assert(panel:refresh(epd.FAST).wait())
    end
    if (info.caps & epd.CAP_REFRESH_PARTIAL) ~= 0 then
        assert(panel:pixel(117, 20, epd.BLACK))
        assert(panel:refresh(epd.PARTIAL).wait())
    end
    if (info.caps & epd.CAP_REFRESH_PARTIAL_RECT) ~= 0 then
        assert(panel:rect(160, 105, 190, 118, epd.BLACK, 1))
        assert(panel:refresh(epd.PARTIAL_RECT).wait())       -- dirty rectangle
        assert(panel:pixel(170, 105, epd.BLACK))
        assert(panel:refresh(epd.PARTIAL_RECT, 160, 105, 30, 13).wait())
    end

    log.info("epd", "demo done")
    assert(panel:sleep(epd.SLEEP_DEEP))
    assert(panel:close())
end)

sys.run()
