local sys = require "sys"

log.info("main", "hello world")

print(_VERSION)

sys.timerLoopStart(function()
    print("hi, LuatOS")
end, 3000)

sys.run()
