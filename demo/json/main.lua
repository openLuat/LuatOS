-- LuaTools需要PROJECT和VERSION这两个信息
PROJECT = "jsondemo"
VERSION = "1.0.0"

-- 引入必要的库文件(lua编写), 内部库不需要require
local sys = require "sys"

log.info("main", "json demo")
print(json.null)

local t = {
    a = 1,
    b = "abc",
    c = {
        1,2,3,4
    },
    d = {
        x = false,
        j = 111111
    },
    aaaa = 6666,
}

local s = json.encode(t)

local st = json.decode(s)

print(s)
print(st.a,st.b,st.d.x)

-- 用户代码已结束---------------------------------------------
-- 结尾总是这一句
sys.run()
-- sys.run()之后后面不要加任何语句!!!!!
