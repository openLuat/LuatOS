
local sys = require "sys"

print(_VERSION)

sys.timerLoopStart(function()
    print("rdy")
end, 3000)

sys.subscribe("IRQ_27", function()
    print("IRQ_27!!!!")
end)

gpio.setup(27, function() print("IQR") end, nil, gpio.RISING)

sys.run()
