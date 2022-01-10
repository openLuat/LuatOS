
log.info("main", "hi")

local func = loadfile("sys.lua")
log.info("func", func)
buff = zbuff.create(32*1024)
data = luf.dump(func, false, buff)
buff:write(data)

--buff:write(data)

io.writeFile("sys.luf", data)
io.writeFile("sys.luac", string.dump(func))
io.writeFile("sys.luacs", string.dump(func, true))

f = load(data)
log.info("load", f)
if f then
    log.info("load", "f?")
    sys = f()
    sys.publish("ABC", 123)
    log.info("load sys", sys)
    sys.taskInit(function()
        log.info("sys", "wait 1s")
        sys.wait(1000)
        log.info("os", "exit now")
        os.exit()
    end)
    sys.run()
end

os.exit(0)
