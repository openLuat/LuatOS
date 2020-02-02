local sys = require "sys"

print(_VERSION)

sys.timerLoopStart(function()
    print("hi, LuatOS")
end, 3000)

sys.run()
