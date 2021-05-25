

local sys = require "sys"

log.info("sys", "from win32")

sys.taskInit(function ()
    sys.wait(1000)

    if lfs2 ~= nil then
        local buff = zbuff.create(64*1024)
        local drv = sfd.init("zbuff", buff)
        if drv then
            lfs2.mount("/mem", drv, true)
            --lfs2.mkfs("/mem")
            local f = io.open("/mem/abc.txt", "w")
            if f then
                f:write("Hi, from LuatOS")
                f:close()
            end
            f = io.open("/mem/abc.txt", "r")
            if f then
                local data = f:read("a")
                log.info("from lfs2-vfs", data)
                assert(data == "Hi, from LuatOS", "lfs2 r/w error")
            end
        end
    end

    os.exit(0)
end)

sys.run()
