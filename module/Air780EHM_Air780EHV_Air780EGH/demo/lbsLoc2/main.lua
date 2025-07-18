
-- LuaTools需要PROJECT和VERSION这两个信息
PROJECT = "lbsLoc2demo"
VERSION = "1.0.0"

local lbsLoc2 = require("lbsLoc2")

sys.taskInit(function()
    sys.waitUntil("IP_READY", 30000)
    -- mobile.reqCellInfo(60)
    -- sys.wait(1000)
    while mobile do -- 没有mobile库就没有基站定位
        mobile.reqCellInfo(15)--进行基站扫描
        sys.waitUntil("CELL_INFO_UPDATE", 3000)--等到扫描成功，超时时间3S
        local lat, lng, t = lbsLoc2.request(5000)--仅需要基站定位给出的经纬度
        --local lat, lng, t = lbsLoc2.request(5000,nil,nil,true)--需要经纬度和当前时间
        --(时间格式{"year":2024,"min":56,"month":11,"day":12,"sec":44,"hour":14})
        log.info("lbsLoc2", lat, lng, (json.encode(t or {})))
        sys.wait(60000)
    end
end)

-- 用户代码已结束---------------------------------------------
-- 结尾总是这一句
sys.run()
-- sys.run()之后后面不要加任何语句!!!!!
