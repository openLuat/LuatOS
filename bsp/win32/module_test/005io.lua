

local sys = require "sys"

sys.taskInit(function()
    sys.wait(100) -- 特意的,检验sys.run在运行

    -- 读写文件1000次
    for i = 1, 100, 1 do
        local f = io.open("T", "wb")
        assert(f)
        local data = os.date()
        f:write(data)
        f:close()
        f = io.open("T", "rb")
        assert(f)
        assert(f:read("a") == data)
        f:close()
    end

    -- 快捷读写文件1000次
    for i = 1, 100, 1 do
        os.remove("T")
        io.writeFile("T", os.date())
        io.readFile("T")
    end

    log.info("sys", "all done")
    os.exit(0)
end)

os.remove("T")
io.writeFile("T", string.char(0, 0, 1, 2, 4, 0))
assert(io.fileSize("T") == 6)

sys.run()
