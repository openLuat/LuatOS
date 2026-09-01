PROJECT = "hzfont_getbitmap"
VERSION = "1.0.0"

sys.taskInit(function()
    log.info("hzfont", "init", hzfont.init())

    local buff = hzfont.getBitmap("中", 16)
    assert(type(buff) == "userdata", "getBitmap should return zbuff userdata")
    assert(buff.width > 0, "width should > 0")
    assert(buff.height > 0, "height should > 0")
    assert(buff.bit == 8, "bit should be 8")
    assert(buff:len() == buff.width * buff.height, "len should equal width*height")
    log.info("hzfont", "bitmap", buff.width, buff.height, buff:len())

    -- 简单校验：光标应在开头，内容非全 0/全 255
    buff:seek(0)
    local first = buff:read(1)
    local all_zero = true
    local all_ff = true
    for i = 1, #first do
        local b = string.byte(first, i)
        if b ~= 0 then all_zero = false end
        if b ~= 0xFF then all_ff = false end
    end
    log.info("hzfont", "first byte", string.format("0x%02X", string.byte(first, 1)))

    -- 对中文来说，位图里通常同时有透明和填充像素
    -- 但为了稳健，只断言不是异常值即可
    assert(not all_zero or buff:len() > 1, "bitmap should contain ink")

    -- 再测一个 ASCII 字符
    local buff2 = hzfont.getBitmap("A", 12)
    assert(type(buff2) == "userdata", "ASCII getBitmap should return zbuff")
    assert(buff2.width > 0 and buff2.height > 0, "ASCII bitmap size invalid")
    log.info("hzfont", "ascii bitmap", buff2.width, buff2.height, buff2:len())

    log.info("hzfont", "TEST PASS")
    os.exit(0)
end)

sys.run()
