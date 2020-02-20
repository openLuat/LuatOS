local sys = require "sys"

print(_VERSION)

sys.timerLoopStart(function()
    print("")
    print(1.2)
    print(1.23456)
    print(0.00000000000000000000000000001234)
    print(2147483640)
    print(2147483647)
    print(4294967295)
    print(123445671234456712344567)
    print(collectgarbage("count"))
end, 1000)

sys.run()
