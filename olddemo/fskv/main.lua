
-- LuaTools需要PROJECT和VERSION这两个信息
PROJECT = "fskvdemo"
VERSION = "1.0.0"

-- sys库是标配
_G.sys = require("sys")

sys.taskInit(function()
    sys.wait(1000) -- 免得日志刷没了, 生产环境不需要

    -- 检查一下当前固件是否支持fskv
    if not fskv then
        while true do
            log.info("fskv", "this demo need fskv")
            sys.wait(1000)
        end
    end

    -- 初始化kv数据库
    fskv.init()
    log.info("fskv", "init complete")
    -- 先放入一堆值
    local bootime = fskv.get("boottime")
    if bootime == nil or type(bootime) ~= "number" then
        bootime = 0
    else
        bootime = bootime + 1
    end
    fskv.set("boottime", bootime)

    fskv.set("my_bool", true)
    fskv.set("my_int", 123)
    fskv.set("my_number", 1.23)
    fskv.set("my_str", "luatos")
    fskv.set("my_table", {name="wendal",age=18})
    
    fskv.set("my_str_int", "123")
    fskv.set("1", "123") -- 单字节key
    --fskv.set("my_nil", nil) -- 会提示失败,不支持空值


    log.info("fskv", "boottime",      type(fskv.get("boottime")),    fskv.get("boottime"))
    log.info("fskv", "my_bool",      type(fskv.get("my_bool")),    fskv.get("my_bool"))
    log.info("fskv", "my_int",       type(fskv.get("my_int")),     fskv.get("my_int"))
    log.info("fskv", "my_number",    type(fskv.get("my_number")),  fskv.get("my_number"))
    log.info("fskv", "my_str",       type(fskv.get("my_str")),     fskv.get("my_str"))
    log.info("fskv", "my_table",     type(fskv.get("my_table")),   json.encode(fskv.get("my_table")))
    log.info("fskv", "my_str_int",     type(fskv.get("my_str_int")),   fskv.get("my_str_int"))
    log.info("fskv", "1 byte key",     type(fskv.get("1")),   json.encode(fskv.get("1")))

    -- 删除测试
    fskv.del("my_bool")
    local t = fskv.get("my_bool")
    log.info("fskv", "my_bool",      type(t),    t)

    -- 查询kv数据库状态
    -- local used, total,kv_count = fskv.stat()
    -- log.info("fdb", "kv", used,total,kv_count)

    -- fskv.clr()
    -- local used, total,kv_count = fskv.stat()
    -- log.info("fdb", "kv", used,total,kv_count)
    

    -- 压力测试
    -- local start = mcu.ticks()
    -- local count = 1000
    -- for i=1,count do
    --     -- sys.wait(10)
    --     -- count = count - 1
    --     -- fskv.set("BENT1", "--" .. os.date() .. "--")
    --     -- fskv.set("BENT2", "--" .. os.date() .. "--")
    --     -- fskv.set("BENT3", "--" .. os.date() .. "--")
    --     -- fskv.set("BENT4", "--" .. os.date() .. "--")
    --     fskv.get("my_bool")
    -- end
    -- log.info("fskv", mcu.ticks() - start)

    if fskv.sett then
        -- 设置数据, 字符串,数值,table,布尔值,均可
        -- 但不可以是nil, function, userdata, task
        log.info("fdb", fskv.sett("mytable", "wendal", "goodgoodstudy"))
        log.info("fdb", fskv.sett("mytable", "upgrade", true))
        log.info("fdb", fskv.sett("mytable", "timer", 1))
        log.info("fdb", fskv.sett("mytable", "bigd", {name="wendal",age=123}))
        
        -- 下列语句将打印出4个元素的table
        log.info("fdb", fskv.get("mytable"), json.encode(fskv.get("mytable")))
        -- 注意: 如果key不存在, 或者原本的值不是table类型,将会完全覆盖
        -- 例如下列写法,最终获取到的是table,而非第一行的字符串
        log.info("fdb", fskv.set("mykv", "123"))
        log.info("fdb", fskv.sett("mykv", "age", "123")) -- 保存的将是 {age:"123"}

        -- 删除测试
        log.info("fdb", fskv.set("mytable", {age=18, name="wendal"}))
        log.info("fdb", fskv.sett("mytable", "name", nil))
        log.info("fdb", fskv.get("mytable"), json.encode(fskv.get("mytable")))
    end
end)

-- 用户代码已结束---------------------------------------------
-- 结尾总是这一句
sys.run()
-- sys.run()之后后面不要加任何语句!!!!!
