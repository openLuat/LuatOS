

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
    end
    os.exit(0)
end)

sys.run()
