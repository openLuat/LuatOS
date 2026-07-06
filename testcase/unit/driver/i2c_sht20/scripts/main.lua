PROJECT = "i2c_sht20_mock_test"
VERSION = "1.0.0"

local function bytes_to_u16_be(s)
    assert(#s == 2, "need 2 bytes")
    local _, v = pack.unpack(s, ">H")
    return v
end

sys.taskInit(function()
    local id = 1
    local addr = 0x40

    assert(i2c.setup(id, i2c.FAST) == 1, "i2c setup failed")

    assert(i2c.send(id, addr, string.char(0xE7)), "send E7 failed")
    local user_reg = i2c.recv(id, addr, 1)
    assert(#user_reg == 1, "E7 recv len invalid")
    assert(user_reg:byte(1) == 0x02, string.format("unexpected default user reg 0x%02X", user_reg:byte(1)))

    assert(i2c.send(id, addr, string.char(0xE6, 0xA2)), "send E6 failed")
    assert(i2c.send(id, addr, string.char(0xE7)), "send E7 failed")
    user_reg = i2c.recv(id, addr, 1)
    assert(user_reg:byte(1) == 0xA2, string.format("E6 write not applied 0x%02X", user_reg:byte(1)))

    assert(i2c.send(id, addr, string.char(0xFE)), "send FE failed")
    assert(i2c.send(id, addr, string.char(0xE7)), "send E7 failed")
    user_reg = i2c.recv(id, addr, 1)
    assert(user_reg:byte(1) == 0x02, string.format("soft reset failed, user reg=0x%02X", user_reg:byte(1)))

    assert(i2c.send(id, addr, string.char(0xF3)), "send F3 failed")
    local t_raw_buf = i2c.recv(id, addr, 2)
    local t_raw = bytes_to_u16_be(t_raw_buf)
    local temp = (((17572 * t_raw) >> 16) - 4685) / 100
    assert(math.abs(temp - 25.0) < 0.3, string.format("unexpected temp %.2f", temp))

    assert(i2c.send(id, addr, string.char(0xF5)), "send F5 failed")
    local h_raw_buf = i2c.recv(id, addr, 2)
    local h_raw = bytes_to_u16_be(h_raw_buf)
    local hum = (((12500 * h_raw) >> 16) - 600) / 100
    assert(math.abs(hum - 50.0) < 0.3, string.format("unexpected hum %.2f", hum))

    log.info("i2c_sht20", "PASS")
    os.exit(0)
end)

sys.run()
