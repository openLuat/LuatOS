local testfs = {}

local sys = require "sys"

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
    log.info("fdb", "init complete")
    -- 先放入一堆值
    local bootime = fdb.kv_get("boottime")
    if bootime == nil or type(bootime) ~= "number" then
        bootime = 0
    else
        bootime = bootime + 1
    end
    fdb.kv_set("boottime", bootime)

    fdb.kv_set("my_bool", true)
    fdb.kv_set("my_int", 123)
    fdb.kv_set("my_number", 1.23)
    fdb.kv_set("my_str", "luatos")
    fdb.kv_set("my_table", {name="wendal",age=18})
    
    fdb.kv_set("my_str_int", "123")
    fdb.kv_set("1", "123") -- 单字节key
    --fdb.kv_set("my_nil", nil) -- 会提示失败,不支持空值


    log.info("fdb", "boottime",      type(fdb.kv_get("boottime")),    fdb.kv_get("boottime"))
    log.info("fdb", "my_bool",      type(fdb.kv_get("my_bool")),    fdb.kv_get("my_bool"))
    log.info("fdb", "my_int",       type(fdb.kv_get("my_int")),     fdb.kv_get("my_int"))
    log.info("fdb", "my_number",    type(fdb.kv_get("my_number")),  fdb.kv_get("my_number"))
    log.info("fdb", "my_str",       type(fdb.kv_get("my_str")),     fdb.kv_get("my_str"))
    log.info("fdb", "my_table",     type(fdb.kv_get("my_table")),   json.encode(fdb.kv_get("my_table")))
    log.info("fdb", "my_str_int",     type(fdb.kv_get("my_str_int")),   fdb.kv_get("my_str_int"))
    log.info("fdb", "1 byte key",     type(fdb.kv_get("1")),   json.encode(fdb.kv_get("1")))

    -- 删除测试
    fdb.kv_del("my_bool")
    log.info("fdb", "my_bool",      type(fdb.kv_get("my_bool")),    fdb.kv_get("my_bool"))

    while true do
        sys.wait(100)
    end

end)

return testfs