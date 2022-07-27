local sys = require("../lib/sys")

_G.temp = 1
sys.timerStart(function ()
    temp = 2
end,1)

sys.timerStart(function ()
    assert(temp == 2,"timer error")
end,100)

_G.taskCheck = nil
sys.taskInit(function ()
    sys.wait(1)
    taskCheck = true
end)

sys.timerStart(function ()
    assert(taskCheck,"task error")
end,100)

sys.timerStart(function ()
    os.exit(0)
end,50)

sys.run()
