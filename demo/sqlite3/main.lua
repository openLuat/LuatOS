
-- LuaTools需要PROJECT和VERSION这两个信息
PROJECT = "sqlite3demo"
VERSION = "1.0.1"

_G.sys = require("sys")

--[[
@demo sqlite3演示
@tips
本demo需要sqlite3库, 默认固件都不会带这个库, 需要云编译
云编译地址: https://wiki.luatos.com/develop/compile/Cloud_compilation.html

大部分MCU模组都跑不了这个库, 莫念

在嵌入式环境中, sqlite3能跑, 但不要对性能和可靠性有太高的期待.
1. 不建议存放超过2000条记录
2. 务必遵循 open -- sql操作 -- close 的闭环操作
3. 对于同一个数据库文件, 只能存在一个已打开的操作
4. 当前仅对 create table/insert/update/delete/selete进行过测试,其他SQL语法未验证
5. sqlite3版本为 3.44.0
]]

sys.taskInit(function()
    if sqlite3 == nil then
        -- 没sqlite3库, 就底层未包含,需要云编译的
        while 1 do
            log.info("提示", "当前固件未包含sqlite3,请云编译一份")
            log.info("云编译文档", "https://wiki.luatos.com/develop/compile/Cloud_compilation.html")
            sys.wait(3000)
        end
    end
    sys.wait(1000)
    -- 第一步, 打开数据库连接
    local db = sqlite3.open("/ram/test.db")
    log.info("sqlite3", db)
    if db then -- 打开成功返回数据库指针,否则返回nil的
        -- 执行建表语句
        sqlite3.exec(db, "CREATE TABLE devs(ID INT PRIMARY KEY NOT NULL, name CHAR(50))")
        log.info("sys", rtos.meminfo("sys"))
        -- 插入多条数据
        sqlite3.exec(db, "insert into devs values(1, \"ABC\")")
        log.info("sys", rtos.meminfo("sys"))
        sqlite3.exec(db, "insert into devs values(2, \"DEF\")")
        log.info("sys", rtos.meminfo("sys"))
        sqlite3.exec(db, "insert into devs values(3, \"HIJ\")")
        log.info("sys", rtos.meminfo("sys"))
        -- 执行查询语句
        local ret, data = sqlite3.exec(db, "select * from devs where id > 1 order by id desc limit 2")
        log.info("查询结果", ret, data)
        if ret then
            -- 打印查询结果
            for k, v in pairs(data) do
                log.info("数据", json.encode(v))
            end
        end
        log.info("sys", rtos.meminfo("sys"))
        -- 执行全部操作后,一定要关闭数据库连接哦
        sqlite3.close(db)
    end
end)


-- 用户代码已结束---------------------------------------------
-- 结尾总是这一句
sys.run()
-- sys.run()之后后面不要加任何语句!!!!!
