local sys = require("../lib/sys")

local temp = 1
sys.timerStart(function ()
    temp = 2
end,1)

sys.timerStart(function ()
    assert(temp == 2,"timer error")
end,100)

local taskCheck
sys.taskInit(function ()
    sys.wait(1)
    taskCheck = true
end)

sys.timerStart(function ()
    assert(taskCheck,"task error")
end,100)

sys.timerStart(function ()
    os.exit(0)
end,500)

sys.run()
