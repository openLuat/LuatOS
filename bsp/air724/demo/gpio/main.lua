
PROJECT = "gpiodemo"
VERSION = "1.0.0"

local sys = require "sys"

pmd.ldoset(1800, pmd.LDO_VLCD)

sys.taskInit(function()
    netled = gpio.setup(1, 0)
    --netmode = gpio.setup(4, 0)
    while 1 do
        netled(1)
        --netmode(0)
        sys.wait(500)
        netled(0)
        --netmode(1)
        sys.wait(500)
        log.info("luatos", "hi", os.date())
    end
end)

sys.run()
