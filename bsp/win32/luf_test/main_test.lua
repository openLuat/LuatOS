
log.info("main", "hi")

local func = loadfile("abc.lua")
log.info("func", func)
buff = zbuff.create(32*1024)
data = luf.dump(func, false, buff)

buff:write(data)
buff:seek(0, zbuff.SEEK_SET)

log.info("data", #data)
-- print(data:toHex())

io.writeFile("abc.luf", data)
io.writeFile("abc.luac", string.dump(func))
io.writeFile("abc.luacs", string.dump(func, true))

func2 = luf.undump(data)

if func2 then
    log.info("func??", func2)
    -- luf.cmp(func, func2)
    local abc = func2()
    log.info("table?", type(abc))
    log.info("table?", json.encode(abc))
    if abc.version then
        log.info("abc", abc["version"])
    else
        log.info("abc", "no version")
    end
    if abc.h2 then
        log.info("abc", abc.h2("wendal"))
    else
        log.info("abc", "no hi function")
    end
    log.info("func??", "end", abc[1])
else
    log.info("func", "nil!!!")
end

log.info("change?", buff:toStr(0, #data) == data)

os.exit(0)
