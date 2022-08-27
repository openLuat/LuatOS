

-- local sys = require "sys"

log.info("sys", "from win32")

-- sys.taskInit(function ()
    -- sys.wait(1000)

    if fatfs ~= nil then
        fatfs.debug(1)
        fatfs.mount("ram", 64*1024)
        fatfs.mkfs("ram")
        -- sys.wait(100)
        local data, err = fatfs.getfree("ram")
        if data then
            log.info("fatfs", "ramdisk", json.encode(data))
        else
            log.info("fatfs", "ramdisk", "err", err)
        end
        -- fatfs 在vfs中的前缀总是/sdcard
        local str = string.char(0, 1, 2, 0, 4, 6, 7, 0xff):rep(1024)
        local f = io.open("/sd/abc.txt", "wb")
        assert(f ~= nil, "fatfs io error")
        if f then
            f:write(str)
            f:write(string.rep("zzz", 1024))
            f:close()
        end
        log.info("fatfs", "file size", io.fileSize("/sd/abc.txt"))
        assert(io.fileSize("/sd/abc.txt") == str:len() + 3*1024)
        f = io.open("/sd/abc.txt", "rb")
        assert(f ~= nil, "fatfs io error")
        if f then
            local data = f:read(str:len())
            log.info("from fatfs-vfs", data:len())
            assert(data == str, "fatfs r/w error")
            local offset = f:seek("set", str:len() + 1024)
            assert(offset == str:len() + 1024)
            log.info("fatfs", "offset now", offset)
            log.info("why", f:read(3))
            assert(f:read(3) == "zzz")
            f:seek("end", 0)
            assert(f:read(1024) == nil)
            f:seek("set", 0)
            assert(f:read(str:len() + 3) == str .. "zzz")
        end
        local ret, files = io.lsdir("/sd")
        assert(files ~= nil, "fatfs lsdir shall work")
        log.info("fatfs", "lsdir", json.encode(files))
        log.info("bye")
        -- sys.wait(1000)
    end
    os.exit(0)
-- end)

-- sys.run()
