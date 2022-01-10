
log.info("main", "hi")

local func = loadfile("sys.lua")
log.info("func", func)
buff = zbuff.create(32*1024)
data = luf.dump(func, false, buff)

buff:write(data)

func2 = luf.undump(data)

local sys = func2()

sys.taskInit(function()
    while true do
        log.info("sys", "task loop")
        sys.wait(1000)
    end
end)

sys.run()
