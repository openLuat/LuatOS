_G.sys = require("sys")

sys.taskInit(function()
    local buff = zbuff.create(1024)
    buff:write("1234567890")
    local f = io.open("test.bin", "w+")
    f:write("Hello, World!")
    f:write(buff)
    f:close()

    local data = io.readFile("test.bin")
    log.info("file", #data)
end)

sys.run()
