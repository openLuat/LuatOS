-- LuaTools需要PROJECT和VERSION这两个信息
PROJECT = "download"
VERSION = "1.0.0"

-- 引入必要的库文件(lua编写), 内部库不需要require
local sys = require "sys"

local air101 = require "air101"

sys.taskInit(function()

    air101.download(pin.PC04,pin.PC05,2,"/luadb/AIR101.fls","1.0.7")

    while 1 do
        sys.wait(100)
    end
end)

-- 用户代码已结束---------------------------------------------
-- 结尾总是这一句
sys.run()
-- sys.run()之后后面不要加任何语句!!!!!
