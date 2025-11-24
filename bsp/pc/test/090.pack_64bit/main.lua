
PROJECT = "airtun"
VERSION = "1.0.0"


sys.taskInit(function()
    local str = "1234567890"
    print("pack 64bit test")
    local i, num = pack.unpack(str, ">L")
    print("pack 64bit test: ", i, num)
    assert(i == 9, "必须是9呀")
    print("pack 64bit test: ", pack.pack(">L", num))
end)


-- 用户代码已结束---------------------------------------------
-- 结尾总是这一句
sys.run()
-- sys.run()之后后面不要加任何语句!!!!!
