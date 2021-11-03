
-- LuaTools需要PROJECT和VERSION这两个信息
PROJECT = "fdb"
VERSION = "1.0.0"

-- sys库是标配
_G.sys = require("sys")

sys.taskInit(function()
    sys.wait(1000) -- 免得日志刷了, 生产环境不需要

    -- 检查一下当前固件是否支持fdb
    if not fdb then
        while true do
            log.info("fdb", "this demo need fdb")
            sys.wait(1000)
        end
    end

    -- 初始化kv数据库
    fdb.kvdb_init("onchip_flash")
    if not fdb.kv_get("goods") then
        log.info("fdb", "first set goods")
        fdb.kv_set("goods", "apple")
    end
    log.info("fdb", "goods", fdb.kv_get("goods"))
end)

-- 用户代码已结束---------------------------------------------
-- 结尾总是这一句
sys.run()
-- sys.run()之后后面不要加任何语句!!!!!
