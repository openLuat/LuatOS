-- SQLite3综合测试套件
-- 覆盖: CRUD、事务、约束、聚合、JOIN、索引、持久化、错误处理、实用场景
local M = {}

local DB_PATH = "test_sqlite3_suite.db"
local db = nil

-- ── 生命周期 ────────────────────────────────────────────────────────────────

-- 每个测试前: 打开数据库并清理所有测试表
function M.setUp()
    db = sqlite3.open(DB_PATH)
    assert(db ~= nil, "无法打开数据库: " .. DB_PATH)
    local tables = {"t_users", "t_orders", "t_products", "t_config", "t_sensor", "t_dept"}
    for _, t in ipairs(tables) do
        sqlite3.exec(db, "DROP TABLE IF EXISTS " .. t)
    end
end

-- 每个测试后: 关闭数据库
function M.tearDown()
    if db then
        sqlite3.close(db)
        db = nil
    end
end

-- ── 辅助函数 ────────────────────────────────────────────────────────────────

local function exec_ok(sql, msg)
    local ret, err = sqlite3.exec(db, sql)
    assert(ret, (msg or "SQL执行失败") .. ": " .. tostring(err))
end

local function query(sql)
    local ret, data = sqlite3.exec(db, sql)
    assert(ret, "查询失败: " .. tostring(data))
    return data
end

-- ── 测试用例 ────────────────────────────────────────────────────────────────

-- 1. 基础建表与增删改查
function M.test_basic_crud()
    exec_ok("CREATE TABLE t_users(id INTEGER PRIMARY KEY, name TEXT NOT NULL, score REAL)")

    exec_ok("INSERT INTO t_users VALUES(1,'Alice',95.5)")
    exec_ok("INSERT INTO t_users VALUES(2,'Bob',80.0)")
    exec_ok("INSERT INTO t_users VALUES(3,'Charlie',72.3)")

    -- SELECT 全量
    local rows = query("SELECT * FROM t_users ORDER BY id")
    assert(#rows == 3, "应有3行, 实际" .. #rows)
    assert(rows[1].name == "Alice", "第1行name应为Alice")
    assert(rows[3].name == "Charlie", "第3行name应为Charlie")

    -- UPDATE
    exec_ok("UPDATE t_users SET score=99.0 WHERE name='Alice'")
    local r = query("SELECT score FROM t_users WHERE name='Alice'")
    assert(math.abs(tonumber(r[1].score) - 99.0) < 0.001, "UPDATE后score应为99.0")

    -- DELETE
    exec_ok("DELETE FROM t_users WHERE id=3")
    local cnt = query("SELECT COUNT(*) as n FROM t_users")
    assert(cnt[1].n == "2", "DELETE后应剩2行, 实际" .. tostring(cnt[1].n))
end

-- 2. WHERE / ORDER BY / LIMIT / OFFSET
function M.test_select_filter()
    exec_ok("CREATE TABLE t_users(id INTEGER PRIMARY KEY, name TEXT, score INTEGER)")
    for i = 1, 10 do
        exec_ok(string.format("INSERT INTO t_users VALUES(%d,'User%d',%d)", i, i, i * 10))
    end

    -- WHERE
    local rows = query("SELECT * FROM t_users WHERE score > 50")
    assert(#rows == 5, "score>50应有5行, 实际" .. #rows)

    -- ORDER BY DESC + LIMIT
    local top3 = query("SELECT * FROM t_users ORDER BY score DESC LIMIT 3")
    assert(#top3 == 3, "LIMIT 3应返回3行")
    assert(tonumber(top3[1].score) > tonumber(top3[2].score), "ORDER BY DESC排序错误")

    -- LIMIT + OFFSET
    local page = query("SELECT * FROM t_users ORDER BY id ASC LIMIT 3 OFFSET 5")
    assert(#page == 3, "LIMIT+OFFSET应返回3行")
    assert(page[1].id == "6", "OFFSET 5后第1行id应为6, 实际" .. tostring(page[1].id))
end

-- 3. 聚合函数: COUNT / SUM / AVG / MIN / MAX
function M.test_aggregates()
    exec_ok("CREATE TABLE t_users(id INTEGER PRIMARY KEY, name TEXT, score REAL)")
    exec_ok("INSERT INTO t_users VALUES(1,'Alice',90.0)")
    exec_ok("INSERT INTO t_users VALUES(2,'Bob',80.0)")
    exec_ok("INSERT INTO t_users VALUES(3,'Charlie',70.0)")

    local r = query("SELECT COUNT(*) as cnt, SUM(score) as total, AVG(score) as avg, MIN(score) as mn, MAX(score) as mx FROM t_users")
    assert(r[1].cnt   == "3",   "COUNT应为3")
    assert(math.abs(tonumber(r[1].total) - 240.0) < 0.01, "SUM应为240")
    assert(math.abs(tonumber(r[1].avg)   -  80.0) < 0.01, "AVG应为80")
    assert(math.abs(tonumber(r[1].mn)    -  70.0) < 0.01, "MIN应为70")
    assert(math.abs(tonumber(r[1].mx)    -  90.0) < 0.01, "MAX应为90")
end

-- 4. GROUP BY / HAVING
function M.test_group_by()
    exec_ok("CREATE TABLE t_orders(id INTEGER PRIMARY KEY, user_id INTEGER, amount REAL)")
    local data = {
        {1, 1, 100}, {2, 1, 200}, {3, 1,  50},
        {4, 2, 300}, {5, 2, 150},
        {6, 3,  80},
    }
    for _, row in ipairs(data) do
        exec_ok(string.format("INSERT INTO t_orders VALUES(%d,%d,%.1f)", row[1], row[2], row[3]))
    end

    -- 每个用户的总金额
    local rows = query("SELECT user_id, SUM(amount) as total FROM t_orders GROUP BY user_id ORDER BY user_id")
    assert(#rows == 3, "GROUP BY应有3组")
    assert(tonumber(rows[1].total) == 350.0, "user1总额应为350")
    assert(tonumber(rows[2].total) == 450.0, "user2总额应为450")

    -- HAVING: 只取总额>300的用户
    local big = query("SELECT user_id FROM t_orders GROUP BY user_id HAVING SUM(amount) > 300 ORDER BY user_id")
    assert(#big == 2, "HAVING应筛出2个用户, 实际" .. #big)
    -- ORDER BY user_id: user1(总额350)在前, user2(总额450)在后
    assert(big[1].user_id == "1", "第1个大客户应为user1, 实际" .. tostring(big[1].user_id))
    assert(big[2].user_id == "2", "第2个大客户应为user2, 实际" .. tostring(big[2].user_id))
end

-- 5. 事务提交
function M.test_transaction_commit()
    exec_ok("CREATE TABLE t_users(id INTEGER PRIMARY KEY, name TEXT)")
    exec_ok("BEGIN")
    exec_ok("INSERT INTO t_users VALUES(1,'Alice')")
    exec_ok("INSERT INTO t_users VALUES(2,'Bob')")
    exec_ok("COMMIT")

    local cnt = query("SELECT COUNT(*) as n FROM t_users")
    assert(cnt[1].n == "2", "COMMIT后应有2行, 实际" .. tostring(cnt[1].n))
end

-- 6. 事务回滚
function M.test_transaction_rollback()
    exec_ok("CREATE TABLE t_users(id INTEGER PRIMARY KEY, name TEXT)")
    exec_ok("INSERT INTO t_users VALUES(1,'Alice')")

    exec_ok("BEGIN")
    exec_ok("INSERT INTO t_users VALUES(2,'Bob')")
    exec_ok("INSERT INTO t_users VALUES(3,'Charlie')")
    exec_ok("ROLLBACK")

    local cnt = query("SELECT COUNT(*) as n FROM t_users")
    assert(cnt[1].n == "1", "ROLLBACK后应只有1行, 实际" .. tostring(cnt[1].n))
end

-- 7. 主键约束
function M.test_primary_key_constraint()
    exec_ok("CREATE TABLE t_users(id INTEGER PRIMARY KEY, name TEXT)")
    exec_ok("INSERT INTO t_users VALUES(1,'Alice')")

    local ret, err = sqlite3.exec(db, "INSERT INTO t_users VALUES(1,'Duplicate')")
    assert(ret == nil, "重复主键插入应失败")
    assert(type(err) == "string" and #err > 0, "应返回错误信息字符串")

    -- 原数据不变
    local r = query("SELECT name FROM t_users WHERE id=1")
    assert(r[1].name == "Alice", "原数据应不变")
end

-- 8. NOT NULL约束
function M.test_not_null_constraint()
    exec_ok("CREATE TABLE t_users(id INTEGER PRIMARY KEY, name TEXT NOT NULL)")

    local ret, err = sqlite3.exec(db, "INSERT INTO t_users VALUES(1,NULL)")
    assert(ret == nil, "NOT NULL字段插入NULL应失败")
    assert(type(err) == "string", "应返回错误信息")
end

-- 9. NULL值处理
function M.test_null_values()
    exec_ok("CREATE TABLE t_users(id INTEGER PRIMARY KEY, name TEXT, email TEXT)")
    exec_ok("INSERT INTO t_users VALUES(1,'Alice',NULL)")
    exec_ok("INSERT INTO t_users VALUES(2,'Bob','bob@test.com')")

    -- IS NULL查询
    local rows = query("SELECT * FROM t_users WHERE email IS NULL")
    assert(#rows == 1, "IS NULL应返回1行")
    assert(rows[1].name == "Alice", "NULL email的用户应为Alice")
    assert(rows[1].email == nil, "NULL字段在Lua中应为nil")

    -- IS NOT NULL查询
    local rows2 = query("SELECT * FROM t_users WHERE email IS NOT NULL")
    assert(#rows2 == 1 and rows2[1].name == "Bob", "IS NOT NULL应返回Bob")

    -- COALESCE
    local r = query("SELECT COALESCE(email,'(无)') as email FROM t_users WHERE id=1")
    assert(r[1].email == "(无)", "COALESCE应返回默认值")
end

-- 10. 字符串操作: LIKE / UPPER / SUBSTR / ||
function M.test_string_operations()
    exec_ok("CREATE TABLE t_users(id INTEGER PRIMARY KEY, name TEXT, city TEXT)")
    exec_ok("INSERT INTO t_users VALUES(1,'Alice Zhang','Beijing')")
    exec_ok("INSERT INTO t_users VALUES(2,'Bob Smith','Shanghai')")
    exec_ok("INSERT INTO t_users VALUES(3,'Charlie Brown','Beijing')")

    -- LIKE前缀
    local a = query("SELECT * FROM t_users WHERE name LIKE 'A%'")
    assert(#a == 1 and a[1].name == "Alice Zhang", "LIKE 'A%'应返回Alice")

    -- LIKE中缀
    local b = query("SELECT * FROM t_users WHERE name LIKE '%Smith%'")
    assert(#b == 1 and b[1].name == "Bob Smith", "LIKE '%Smith%'应返回Bob")

    -- UPPER
    local c = query("SELECT UPPER(name) as uname FROM t_users WHERE id=1")
    assert(c[1].uname == "ALICE ZHANG", "UPPER结果错误: " .. tostring(c[1].uname))

    -- 字符串拼接 ||
    local d = query("SELECT name || ' (' || city || ')' as label FROM t_users WHERE id=2")
    assert(d[1].label == "Bob Smith (Shanghai)", "拼接结果错误: " .. tostring(d[1].label))
end

-- 11. 多表JOIN (INNER / LEFT)
function M.test_multi_table_join()
    exec_ok("CREATE TABLE t_dept(id INTEGER PRIMARY KEY, name TEXT)")
    exec_ok("CREATE TABLE t_users(id INTEGER PRIMARY KEY, name TEXT, dept_id INTEGER)")
    exec_ok("INSERT INTO t_dept VALUES(1,'Engineering')")
    exec_ok("INSERT INTO t_dept VALUES(2,'Marketing')")
    exec_ok("INSERT INTO t_users VALUES(1,'Alice',1)")
    exec_ok("INSERT INTO t_users VALUES(2,'Bob',1)")
    exec_ok("INSERT INTO t_users VALUES(3,'Charlie',2)")
    exec_ok("INSERT INTO t_users VALUES(4,'Dave',NULL)")  -- 无部门

    -- INNER JOIN
    local inner = query("SELECT u.name, d.name as dept FROM t_users u INNER JOIN t_dept d ON u.dept_id=d.id ORDER BY u.id")
    assert(#inner == 3, "INNER JOIN应返回3行, 实际" .. #inner)
    assert(inner[1].dept == "Engineering", "Alice应在Engineering")

    -- LEFT JOIN (包含无部门的Dave)
    local left = query("SELECT u.name, d.name as dept FROM t_users u LEFT JOIN t_dept d ON u.dept_id=d.id ORDER BY u.id")
    assert(#left == 4, "LEFT JOIN应返回4行, 实际" .. #left)
    assert(left[4].name == "Dave" and left[4].dept == nil, "Dave的dept应为nil")

    -- 聚合JOIN: 每个部门人数
    local cnt = query("SELECT d.name, COUNT(u.id) as cnt FROM t_dept d LEFT JOIN t_users u ON d.id=u.dept_id GROUP BY d.id ORDER BY d.id")
    assert(cnt[1].cnt == "2" and cnt[2].cnt == "1", "部门人数统计错误")
end

-- 12. 创建索引并查询
function M.test_create_index()
    exec_ok("CREATE TABLE t_users(id INTEGER PRIMARY KEY, name TEXT, score INTEGER)")
    exec_ok("BEGIN")
    for i = 1, 20 do
        exec_ok(string.format("INSERT INTO t_users VALUES(%d,'User%d',%d)", i, i, i * 5))
    end
    exec_ok("COMMIT")

    exec_ok("CREATE INDEX idx_score ON t_users(score)")
    exec_ok("CREATE UNIQUE INDEX idx_name ON t_users(name)")

    -- 利用索引查询
    local rows = query("SELECT * FROM t_users WHERE score BETWEEN 50 AND 80 ORDER BY score")
    -- score=50(i=10), 55(11), 60(12), 65(13), 70(14), 75(15), 80(16) → 7行
    assert(#rows == 7, "BETWEEN 50 AND 80应有7行, 实际" .. #rows)
    assert(rows[1].score == "50" and rows[7].score == "80", "范围边界错误")

    -- UNIQUE索引: 重复name应失败
    local ret, err = sqlite3.exec(db, "INSERT INTO t_users VALUES(21,'User1',999)")
    assert(ret == nil, "唯一索引违反应失败")
    assert(type(err) == "string", "应返回错误信息")
end

-- 13. 持久化: 关闭后重新打开数据仍在
function M.test_persistence()
    exec_ok("CREATE TABLE t_config(key TEXT PRIMARY KEY, value TEXT)")
    exec_ok("INSERT INTO t_config VALUES('version','1.0.0')")
    exec_ok("INSERT INTO t_config VALUES('device_id','DEV001')")

    -- 关闭再重开
    sqlite3.close(db)
    db = nil
    db = sqlite3.open(DB_PATH)
    assert(db ~= nil, "重新打开数据库失败")

    local r = query("SELECT value FROM t_config WHERE key='version'")
    assert(#r == 1 and r[1].value == "1.0.0", "持久化失败: version数据丢失")

    local cnt = query("SELECT COUNT(*) as n FROM t_config")
    assert(cnt[1].n == "2", "持久化失败: 行数不对, 实际" .. tostring(cnt[1].n))
end

-- 14. 错误处理: 无效SQL / 不存在的表
function M.test_error_handling()
    -- 无效SQL语法
    local r1, e1 = sqlite3.exec(db, "INVALID SQL STATEMENT")
    assert(r1 == nil, "无效SQL应返回nil")
    assert(type(e1) == "string" and #e1 > 0, "应返回错误字符串, 实际: " .. tostring(e1))

    -- 查询不存在的表
    local r2, e2 = sqlite3.exec(db, "SELECT * FROM no_such_table")
    assert(r2 == nil, "查询不存在的表应返回nil")
    assert(type(e2) == "string", "应返回错误字符串")

    -- 错误后数据库仍可正常使用
    local r3 = query("SELECT 1+1 as result")
    assert(r3[1].result == "2", "出错后数据库应仍可用")
end

-- 15. 实用场景: 键值配置存储 (INSERT OR REPLACE / UPSERT)
function M.test_kv_config_store()
    exec_ok("CREATE TABLE t_config(key TEXT PRIMARY KEY NOT NULL, value TEXT)")

    local configs = {
        {"server_url",          "mqtt://iot.example.com"},
        {"device_id",           "AIR780E_001"},
        {"heartbeat_interval",  "60"},
        {"report_enabled",      "1"},
    }
    exec_ok("BEGIN")
    for _, c in ipairs(configs) do
        exec_ok(string.format("INSERT INTO t_config VALUES('%s','%s')", c[1], c[2]))
    end
    exec_ok("COMMIT")

    -- 读取单条配置
    local r = query("SELECT value FROM t_config WHERE key='device_id'")
    assert(r[1].value == "AIR780E_001", "读取device_id失败")

    -- UPSERT: 更新已有配置
    exec_ok("INSERT OR REPLACE INTO t_config VALUES('device_id','AIR780E_002')")
    local r2 = query("SELECT value FROM t_config WHERE key='device_id'")
    assert(r2[1].value == "AIR780E_002", "UPSERT更新失败")

    -- 总数不变 (REPLACE = DELETE+INSERT, 行数应仍为4)
    local cnt = query("SELECT COUNT(*) as n FROM t_config")
    assert(cnt[1].n == "4", "UPSERT后总数应为4, 实际" .. tostring(cnt[1].n))
end

-- 16. 实用场景: 传感器时序数据 + 分批写入事务
function M.test_sensor_timeseries()
    exec_ok("CREATE TABLE t_sensor(id INTEGER PRIMARY KEY AUTOINCREMENT, ts INTEGER NOT NULL, temp REAL, humi REAL)")

    -- 批量插入10条
    exec_ok("BEGIN")
    for i = 1, 10 do
        exec_ok(string.format("INSERT INTO t_sensor(ts,temp,humi) VALUES(%d,%.1f,%.1f)",
            1000000 + i * 60, 20.0 + i * 0.5, 50.0 + i))
    end
    exec_ok("COMMIT")

    -- 行数
    local cnt = query("SELECT COUNT(*) as n FROM t_sensor")
    assert(cnt[1].n == "10", "应有10行传感器数据, 实际" .. tostring(cnt[1].n))

    -- AUTOINCREMENT: id应从1连续
    local first = query("SELECT id FROM t_sensor ORDER BY id ASC LIMIT 1")
    assert(first[1].id == "1", "AUTOINCREMENT第1行id应为1")

    -- 最近3条 (时间降序)
    local recent = query("SELECT * FROM t_sensor ORDER BY ts DESC LIMIT 3")
    assert(#recent == 3, "最近3条应返回3行")
    assert(tonumber(recent[1].ts) > tonumber(recent[2].ts), "时序应为降序")

    -- 时间范围内的统计
    local stat = query("SELECT AVG(temp) as avg_temp, MAX(humi) as max_humi FROM t_sensor WHERE ts > 1000300")
    -- ts > 1000300: i=6..10 → temp=23.0..25.0, avg=24.0
    assert(math.abs(tonumber(stat[1].avg_temp) - 24.0) < 0.01, "平均温度应为24.0, 实际" .. tostring(stat[1].avg_temp))

    -- 在已有10条基础上再追加5条
    exec_ok("BEGIN")
    for i = 11, 15 do
        exec_ok(string.format("INSERT INTO t_sensor(ts,temp,humi) VALUES(%d,%.1f,%.1f)",
            1000000 + i * 60, 20.0 + i * 0.5, 50.0 + i))
    end
    exec_ok("COMMIT")
    local cnt2 = query("SELECT COUNT(*) as n FROM t_sensor")
    assert(cnt2[1].n == "15", "追加后应有15行, 实际" .. tostring(cnt2[1].n))
end

-- 17. 空结果集处理
function M.test_empty_result()
    exec_ok("CREATE TABLE t_users(id INTEGER PRIMARY KEY, name TEXT)")

    -- 查询空表
    local rows = query("SELECT * FROM t_users")
    assert(type(rows) == "table" and #rows == 0, "空表查询应返回空table")

    -- WHERE匹配不到
    exec_ok("INSERT INTO t_users VALUES(1,'Alice')")
    local rows2 = query("SELECT * FROM t_users WHERE name='nobody'")
    assert(#rows2 == 0, "匹配不到时应返回空table")

    -- COUNT在空表上
    local cnt = query("SELECT COUNT(*) as n FROM t_users WHERE name='nobody'")
    assert(cnt[1].n == "0", "COUNT在空集上应为0")
end

-- 18. 子查询
function M.test_subquery()
    exec_ok("CREATE TABLE t_users(id INTEGER PRIMARY KEY, name TEXT, score REAL)")
    exec_ok("INSERT INTO t_users VALUES(1,'Alice',90.0)")
    exec_ok("INSERT INTO t_users VALUES(2,'Bob',80.0)")
    exec_ok("INSERT INTO t_users VALUES(3,'Charlie',70.0)")
    exec_ok("INSERT INTO t_users VALUES(4,'Dave',85.0)")

    -- 高于平均分的用户
    local rows = query("SELECT name FROM t_users WHERE score > (SELECT AVG(score) FROM t_users) ORDER BY name")
    assert(#rows == 2, "高于平均分(81.25)的用户应有2人, 实际" .. #rows)
    assert(rows[1].name == "Alice" and rows[2].name == "Dave", "应为Alice和Dave")

    -- IN子查询: id在某个子集中
    local rows2 = query("SELECT name FROM t_users WHERE id IN (SELECT id FROM t_users WHERE score >= 85) ORDER BY name")
    assert(#rows2 == 2, "IN子查询应返回2行, 实际" .. #rows2)
end

return M
