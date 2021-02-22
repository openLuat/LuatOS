
PROJECT = "hi"
VERSION = "1.0.0"

local sys = require "sys"

sys.taskInit(function()
    while 1 do
        log.info("luatos", "hi", os.date())
        sys.wait(1000)
    end
end)

sys.run()
