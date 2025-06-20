-- LuaTools需要PROJECT和VERSION这两个信息
PROJECT = "fskvdemo"
VERSION = "1.0.0"

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
    local bootime = fskv.get("boottime") -- 获取键值 boottime
    if bootime == nil or type(bootime) ~= "number" then
        bootime = 0  -- 如果键值 boottime 为 nil 或不是数字，则将其设为 0
    else
        bootime = bootime + 1 -- 如果键值 boottime 是有效的数字，则将其值增加 1
    end
    fskv.set("boottime", bootime)                 -- 向键值为 boottime 的空间中存入数值，每次重启该值加 1
    fskv.set("my_bool", true)                     -- 向键值为 my_bool 的空间中存入布尔值 true
    fskv.set("my_int", 123)                       -- 向键值为 my_int 的空间中存入整型数 123
    fskv.set("my_number", 1.23)                   -- 向键值为 my_number 的空间中存入浮点数 1.23
    fskv.set("my_str", "luatos")                  -- 向键值为 my_str 的空间中存入字符串 "luatos"
    fskv.set("my_table", {name="wendal",age=18})  -- 向键值为 my_table 的空间中存入数组，数组中包含 name 和 age 两个键值对，值分别为 "wendal" 和 18
    fskv.set("my_str_int", "123")                 -- 向键值为 my_str_int 的空间中存入字符串 "123"
    fskv.set("1", "123")                          -- 单字节key
    --fskv.set("my_nil", nil) -- 会提示失败,不支持空值

    --        fskv     键值名            键值存储的类型                  键值存储的值
    log.info("fskv", "boottime",     type(fskv.get("boottime")),     fskv.get("boottime"))
    log.info("fskv", "my_bool",      type(fskv.get("my_bool")),      fskv.get("my_bool"))
    log.info("fskv", "my_int",       type(fskv.get("my_int")),       fskv.get("my_int"))
    log.info("fskv", "my_number",    type(fskv.get("my_number")),    fskv.get("my_number"))
    log.info("fskv", "my_str",       type(fskv.get("my_str")),       fskv.get("my_str"))
    log.info("fskv", "my_table",     type(fskv.get("my_table")),     json.encode(fskv.get("my_table")))
    log.info("fskv", "my_str_int",   type(fskv.get("my_str_int")),   fskv.get("my_str_int"))
    log.info("fskv", "1 byte key",   type(fskv.get("1")),            json.encode(fskv.get("1")))

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

    if fskv.sett then -- 查看是否提供了 fskv 模块是否提供了 sett 方法，如果提供继续执行
        -- 设置数据, 字符串,数值,table,布尔值,均可
        -- 但不可以是nil, function, userdata, task
        log.info("fskv", fskv.sett("mytable", "wendal", "goodgoodstudy"))
        log.info("fskv", fskv.sett("mytable", "upgrade", true))
        log.info("fskv", fskv.sett("mytable", "timer", 1))
        log.info("fskv", fskv.sett("mytable", "bigd", {name="wendal",age=123}))

        -- 下列语句将打印出4个元素的table
        log.info("fskv", fskv.get("mytable"), json.encode(fskv.get("mytable")))
        -- 注意: 如果key不存在, 或者原本的值不是table类型,将会完全覆盖
        -- 例如下列写法,最终获取到的是table,而非第一行的字符串
        log.info("fskv", fskv.set("mykv", "123")) -- 键值此时存入值为 string 类型数据 "123"
        log.info("fskv", "mykv",       type(fskv.get("mykv")),       fskv.get("mykv"))
        log.info("fskv", fskv.sett("mykv", "age", "123")) -- 因为 mykv 不是一个 table，所以 mykv 会被覆盖上一行代码，再将其值保存为 {"age":"123"}
        log.info("fskv", fskv.get("mykv"), json.encode(fskv.get("mykv")))

        -- 删除测试
        log.info("fskv", fskv.set("mytable", {age=20, name="wendal"}))          -- 这个会把原来的 mytable 中值进行覆盖
        log.info("fskv", fskv.sett("mytable", "name", nil))                     -- 删除 name 参数
        log.info("fskv", fskv.get("mytable"), json.encode(fskv.get("mytable"))) -- 最终只会打印出 {"age"=20}
    end
end)

-- 用户代码已结束---------------------------------------------
-- 结尾总是这一句
sys.run()
-- sys.run()之后后面不要加任何语句!!!!!