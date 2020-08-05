
-- LuaTools需要PROJECT和VERSION这两个信息
PROJECT = "netinfo"
VERSION = "1.0.0"

-- sys库是标配
_G.sys = require("sys")

 -- 每隔60秒请求就差不多了,要看效果的话,改成10秒,千万不要少于5秒
sys.timerLoopStart(nbiot.updateCellInfo, 60000)
sys.subscribe("CELL_INFO_IND", function()
    -- nbiot.getCellInfo()返回的是[{主基站},{附近基站1},{附近基站2},{附近基站3},{附近基站4}]
    log.info("cell", json.encode(nbiot.getCellInfo()))
    log.info("cell", "powerLevel", nbiot.powerLevel())
end)
 -- 允许进入SLEEP1模式,省省电
pm.request(pm.LIGHT)

-- 用户代码已结束---------------------------------------------
-- 结尾总是这一句
sys.run()
-- sys.run()之后后面不要加任何语句!!!!!
