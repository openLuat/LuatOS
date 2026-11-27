PROJECT = "tiny_epd_jd7601"
VERSION = "1.0.0"

sys.taskInit(function()
    local panel, err = epd.open(epd.MODEL_JD7601, {
        port = 0, pin_dc = 1, pin_rst = 2, pin_busy = 3
    }, nil)
    assert(panel, err)

    local info = panel:info()
    assert(info.native_width == 720 and info.native_height == 480)
    assert(info.stride == 360 and info.bits_per_pixel == 4)
    assert(info.color_count == 6)

    assert(panel:drawIndex4(0, 0, 2, 1, string.char(0x01)))
    local ok, w, h = panel:drawJpg(0, 0, "/luadb/epd_demo.jpg", 64, 64)
    assert(ok and w == 64 and h == 64, w)
    ok, w, h = panel:drawJpg(0, 0, "/luadb/epd_demo.jpg")
    assert(ok and w > 0 and h > 0, w)

    local f = assert(io.open("/luadb/epd_demo.jpg", "rb"))
    local jpg = f:read("*a")
    f:close()
    ok, w, h = panel:drawJpg(0, 0, jpg, 32, 32)
    assert(ok and w == 32 and h == 32, w)
    ok, w, h = panel:drawJpg(0, 0, jpg, 40)
    assert(ok and w == 40 and h > 0, w)

    local bad = panel:drawJpg(0, 0, "not a jpeg", 8, 8)
    assert(bad == false)
    assert(panel:setDrf(1) and panel:getDrf() == 1)
    assert(panel:setTemp(42) and panel:getTemp() == 42)
    assert(panel:setFast(true) and panel:getTemp() == 48)
    assert(panel:setFast(false) and panel:getTemp() == 42)

    assert(panel:close())
    log.info("tiny_epd_jd7601", "PASS")
    os.exit(0)
end)

sys.run()
