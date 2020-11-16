
-- LuaTools需要PROJECT和VERSION这两个信息
PROJECT = "air302_update_demo"
VERSION = "1.0.0"
PRODUCT_KEY = "RGdGtHinr6VnNu9NxGmJdQ5Nt8yP3ZMZ"

-- sys库是标配
_G.sys = require("sys")


os.remove("/update.bin")
sys.taskInit(function()
    log.info("update","info",_G.PROJECT,_G.VERSION,_G.PRODUCT_KEY,rtos.firmware(),nbiot.imei())
    while not nbiot.isReady() do
        log.info("update", "wait for network ready")
        sys.waitUntil("NET_READY", 1000)
    end
    sys.wait(8000)
    log.info("update","connected!")
    local url = "http://iot.openluat.com/api/site/firmware_upgrade?imei="..
    tostring(nbiot.imei()).."&project_key=".._G.PRODUCT_KEY.."&firmware_name="..
    _G.PROJECT.."_"..rtos.firmware().."&version="..tostring(_G.VERSION).."&need_oss_url=0"
    os.remove("/update.bin")--先删了
    http.get(url, {dw="/update.bin"}, function(get, code, headers, body)
        log.info("update","result", get, code, headers, body)
        if get == 200 then
            log.info("update","update.bin",fs.fsize("/update.bin"))
            rtos.reboot()
        else
            log.info("update","fail or already latest version",body)
            os.remove("/update.bin")
        end
    end)
end)

-- 用户代码已结束---------------------------------------------
-- 结尾总是这一句
sys.run()
-- sys.run()之后后面不要加任何语句!!!!!
