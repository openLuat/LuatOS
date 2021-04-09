

local sys = require "sys"

sys.taskInit(function()
    sys.wait(100) -- 特意的,检验sys.run在运行

    -- 读写文件1000次
    for i = 1, 1000, 1 do
        local f = io.open("T", "wb")
        assert(f)
        f:write(os.date())
        f:close()
        f = io.open("T", "rb")
        assert(f)
        f:close()
    end

    -- 快捷读写文件1000次
    for i = 1, 1000, 1 do
        os.remove("T")
        io.writeFile("T", os.date())
        io.readFile("T")
    end

    os.exit(0)
end)

sys.run()