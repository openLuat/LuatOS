
log.info("main", "hi")

local func = loadfile("sys.lua")
log.info("func", func)
buff = zbuff.create(32*1024)
data = luf.dump(func, false, buff)

--buff:write(data)

io.writeFile("sys.luf", data)
io.writeFile("sys.luac", string.dump(func))

os.exit(0)
