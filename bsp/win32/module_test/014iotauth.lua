
-- LuaTools需要PROJECT和VERSION这两个信息
PROJECT = "helloworld"
VERSION = "1.0.0"

-- 引入必要的库文件(lua编写), 内部库不需要require
local sys = require "sys"

log.info("main", "hello world")

print(_VERSION)

sys.taskInit(function()
    assert(iotauth, "iotauth exist")
    local client_id,user_name,password = iotauth.onenet("qDPGh8t81z", "45463968338A185E", "MTIzNDU2")
    log.info("onenet", client_id,user_name,password)

    local client_id,user_name,password = iotauth.iotda("6203cc94c7fb24029b110408_88888888","123456789")
    log.info("iotda",client_id,user_name,password)

    local client_id,user_name,password = iotauth.tuya(" 6c95875d0f5ba69607nzfl","fb803786602df760")
    log.info("tuya",client_id,user_name,password)

    local client_id,user_name,password = iotauth.baidu("abcd123","mydevice","ImSeCrEt0I1M2jkl")
    log.info("baidu",client_id,user_name,password)

    local client_id,user_name,password = iotauth.qcloud("LD8S5J1L07","test","acyv3QDJrRa0fW5UE58KnQ==")
    log.info("qcloud",client_id,user_name,password)

    local client_id,user_name,password = iotauth.aliyun("123456789","abcdefg","Y877Bgo8X5owd3lcB5wWDjryNPoB")
    log.info("aliyun",client_id,user_name,password)


    
    os.exit()
end)



-- 用户代码已结束---------------------------------------------
-- 结尾总是这一句
sys.run()
-- sys.run()之后后面不要加任何语句!!!!!
