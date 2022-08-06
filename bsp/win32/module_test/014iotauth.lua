
-- LuaTools需要PROJECT和VERSION这两个信息
PROJECT = "helloworld"
VERSION = "1.0.0"

-- 引入必要的库文件(lua编写), 内部库不需要require
local sys = require "sys"

log.info("main", "hello world")

print(_VERSION)

sys.taskInit(function()
    assert(iotauth, "iotauth exist")
    local clientid, user, passwd = iotauth.onenet("qDPGh8t81z", "45463968338A185E", "MTIzNDU2")
    log.info("onenet", clientid, user, passwd)




    
    os.exit()
end)



-- 用户代码已结束---------------------------------------------
-- 结尾总是这一句
sys.run()
-- sys.run()之后后面不要加任何语句!!!!!
