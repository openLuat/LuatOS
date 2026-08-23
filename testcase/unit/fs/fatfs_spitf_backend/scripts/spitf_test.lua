local spitf_test = {}

function spitf_test.test_mount_rw_on_virtual_bus20_cs23()
    local mount_point = "/sd"
    local bus_id = 20
    local cs_pin = 23
    local speed = 24 * 1000 * 1000

    local spi_setup_ret = spi.setup(bus_id, cs_pin, 0, 0, 8, speed, spi.MSB, 1, 1)
    assert(spi_setup_ret == 0, "spi.setup failed: " .. tostring(spi_setup_ret))

    fatfs.unmount(mount_point)
    local ok, err = fatfs.mount(fatfs.SPI, mount_point, bus_id, cs_pin, speed)
    assert(ok == true, "fatfs SPI mount failed: " .. tostring(err))

    local test_file = mount_point .. "/spitf_backend_rw.txt"
    local payload = "pc-spi-sd-backend-ok"
    local f = io.open(test_file, "w")
    assert(f, "open write file failed")
    local w_ok = f:write(payload)
    f:close()
    assert(w_ok ~= nil, "write payload failed")

    local rf = io.open(test_file, "r")
    assert(rf, "open read file failed")
    local content = rf:read("*a")
    rf:close()
    assert(content == payload, "read content mismatch: " .. tostring(content))

    os.remove(test_file)
    fatfs.unmount(mount_point)
end

return spitf_test
