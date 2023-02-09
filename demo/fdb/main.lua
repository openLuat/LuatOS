
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
    local t = fdb.kv_get("my_bool")
    log.info("fdb", "my_bool",      type(t),    t)

    if fdb.kv_iter then
        local iter = fdb.kv_iter()
        if iter then
            while 1 do
                local k = fdb.kv_next(iter)
                if not k then
                    log.info("fdb", "iter exit")
                    break
                end
                log.info("fdb", k, "value", fdb.kv_get(k))
            end
        else
            log.info("fdb", "iter is null")
        end
    else
        log.info("fdb", "without iter")
    end

    -- 压力测试
    local start = mcu.ticks()
    local count = 1000
    while count > 0 do
        -- sys.wait(10)
        count = count - 1
        -- fdb.kv_set("BENT1", "--" .. os.date() .. "--")
        -- fdb.kv_set("BENT2", "--" .. os.date() .. "--")
        -- fdb.kv_set("BENT3", "--" .. os.date() .. "--")
        -- fdb.kv_set("BENT4", "--" .. os.date() .. "--")
        fdb.kv_get("my_bool")
    end
    log.info("fdb", (mcu.ticks() - start) / 1000)
end)

-- 用户代码已结束---------------------------------------------
-- 结尾总是这一句
sys.run()
-- sys.run()之后后面不要加任何语句!!!!!
