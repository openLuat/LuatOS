-- LuaTools需要PROJECT和VERSION这两个信息
PROJECT = "setApnDemo"
VERSION = "1.0.0"

log.info("main", PROJECT, VERSION)

-- 一定要添加sys.lua !!!!
sys = require("sys")

mobile.apn(0,1,"name","user","password",nil,3) -- 专网卡设置的demo，name，user，password联系卡商获取

local function main_task()
    while true do
        sys.wait(2000)
        local apn = mobile.apn(0,1,"","","",nil,0) --获取APN,第三个参数不填就是获取APN
        log.info("main  apn", apn)
    end 
end

sys.taskInit(main_task)

-- 用户代码已结束---------------------------------------------
-- 结尾总是这一句
sys.run()
-- sys.run()之后后面不要加任何语句!!!!!
