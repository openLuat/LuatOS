
-- LuaTools需要PROJECT和VERSION这两个信息
PROJECT = "helloworld"
VERSION = "1.0.0"

log.info("main", "hello world")

print(_VERSION)

sys.timerLoopStart(function()
    print("hello world")
end, 3000)


-- 用户代码已结束---------------------------------------------
-- 结尾总是这一句
sys.run()
-- sys.run()之后后面不要加任何语句!!!!!
