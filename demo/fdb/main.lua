
-- LuaTools需要PROJECT和VERSION这两个信息
PROJECT = "fdbdemo"
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
    -- 先放入一堆值
    fdb.kv_set("my_bool", true)
    fdb.kv_set("my_int", 123)
    fdb.kv_set("my_number", 1.23)
    fdb.kv_set("my_str", "luatos")
    fdb.kv_set("my_table", {name="wendal",age=18})
    fdb.kv_set("my_nil", nil) -- 会提示失败,不支持空值


    log.info("fdb", "my_bool",      type(fdb.kv_get("my_bool")),    fdb.kv_get("my_bool"))
    log.info("fdb", "my_int",       type(fdb.kv_get("my_int")),     fdb.kv_get("my_int"))
    log.info("fdb", "my_number",    type(fdb.kv_get("my_number")),  fdb.kv_get("my_number"))
    log.info("fdb", "my_str",       type(fdb.kv_get("my_str")),     fdb.kv_get("my_str"))
    log.info("fdb", "my_table",     type(fdb.kv_get("my_table")),   json.encode(fdb.kv_get("my_table")))

end)

-- 用户代码已结束---------------------------------------------
-- 结尾总是这一句
sys.run()
-- sys.run()之后后面不要加任何语句!!!!!
