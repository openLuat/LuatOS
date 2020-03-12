
local sys = require "sys"

log.info("main", "gpio demo")
print(_VERSION)

sys.timerLoopStart(function()
    print("rdy")
end, 3000)

--sys.subscribe("IRQ_27", function(id, msg)
--    log.info("IRQ_27!!!!", id, msg)
--end)
local PB7 = 27
gpio.setup(PB7, function(msg) log.info("IQR", "PB7/27", msg) end)

sys.run()
