

local sys = require "sys"

log.info("sys", "from win32")

sys.taskInit(function ()
    sys.wait(1000)

    if fatfs ~= nil then
        fatfs.debug(1)
        fatfs.mount("ram", 64*1024)
        fatfs.mkfs("ram")
        sys.wait(100)
        local data, err = fatfs.getfree("ram")
        if data then
            log.info("fatfs", "ramdisk", json.encode(data))
        else
            log.info("fatfs", "ramdisk", "err", err)
        end
        -- fatfs 在vfs中的前缀总是/sdcard
        local f = io.open("/sdcard/abc.txt", "w")
        assert(f ~= nil, "fatfs io error")
        if f then
            f:write("Hi, from LuatOS")
            f:close()
        end
        f = io.open("/sdcard/abc.txt", "r")
        assert(f ~= nil, "fatfs io error")
        if f then
            local data = f:read("a")
            log.info("from fatfs-vfs", data)
            assert(data == "Hi, from LuatOS", "fatfs r/w error")
        end
    end
    os.exit(0)
end)

sys.run()
