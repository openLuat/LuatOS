

local sys = require "sys"

log.info("sys", "from win32")

sys.taskInit(function ()
    while true do
        _G.abc = 123
        log.info("hi", os.date())
        log.info("sys", rtos.meminfo("sys"))
        log.info("lua", rtos.meminfo("lua"))
        log.info("pack", string.toHex(pack.pack(">I",1619431773)))
        sys.wait(1000)
        log.info("abc", _G.abc)
    end
end)

sys.run()
