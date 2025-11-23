
_G.sys = require("sys")

sys.taskInit(function()
    sys.wait(1000)
    local db = sqlite3.open("test.db")
    log.info("sqlite3", db)
    if db then
        sqlite3.exec(db, "CREATE TABLE devs(ID INT PRIMARY KEY NOT NULL, name CHAR(50))")
        sqlite3.exec(db, "insert into devs values(1, \"ABC\")")
        sqlite3.exec(db, "insert into devs values(2, \"DEF\")")
        sqlite3.exec(db, "insert into devs values(3, \"HIJ\")")
        local ret, data = sqlite3.exec(db, "select * from devs where id > 1 order by id desc limit 2")
        log.info("查询结果", ret, data)
        if ret then
            for k, v in pairs(data) do
                log.info("数据", json.encode(v))
            end
        end
        sqlite3.close(db)
    end
end)

sys.run()
