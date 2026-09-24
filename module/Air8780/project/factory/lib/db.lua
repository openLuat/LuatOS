-- --- 模块功能：将irtu用户配置的初始值写入KV数据库，用来存储用户的数据
-- db = {}
-- local table_irtu = {}
-- local testdebug = require("testdebug")
-- if not fdb then
--     while true do
--         log.info("fdb", "this procedure need fdb")
--         sys.wait(1000)
--     end
-- end

-- -- 初始化kv数据库--[[  ]]
-- log.info("初始化kv数据库的结果",fdb.kvdb_init("irtu", "onchip_fdb"))
-- local path = "/luadb/irtu.json"
-- --将josn格式的初始化参数，转成了table
-- if io.exists(path) then
--     local ex = io.readFile(path)
--     -- log.info("存的数据是",ex)
--     table_irtu,result,err = json.decode(ex)
--     -- log.info("转table的结果",table_irtu,result,err)
-- end

--- 模块功能：用来存储用户的数据
-- @module socket
-- @author openLuat
-- @license MIT
-- @copyright openLuat
-- @release 2020.03.17
local db = {}
db.__index = db

--- 持久化序列化后的字符串
-- @param file: io.open 打开后的文件对象
-- @param o : 要求序列化的lua数据类型
-- @return nil
-- @usage io.serialize(io.open("/1.lua","w+b"),{1,2})
function serializeio(file, o)
    if type(o) == "string" then
        file:write(string.format("%q", o))
    elseif type(o) == "table" then
        file:write("{\n")
        for k, v in pairs(o) do
            file:write(" ["); serializeio(file, k); file:write("] = ")
            serializeio(file, v); file:write(",\n")
        end
        file:write("}\n")
    else
        file:write(tostring(o))
    end
end

function db.new(path)
    log.error("o.path111",path)
    if path == nil then
        log.error("db.new:", "Empty path!")
        return nil
    end
    local back = "/" .. path:match("([^/]+)$") .. ".bak"
    -- 烧录时的只读文件新建文件名
    local o = {path = io.exists(back) and back or path}
    if io.exists(o.path) then
        log.error("o.path",o.path)
        local res, val = pcall(dofile, o.path)
        if res then
            -- local c=io.readFile(o.path)
            -- log.info("c的值是",c)
            o.sheet = type(val) == "table" and val or json.decode(val)
        else
            log.error("db.new:", "Irregular data format!")
            o.sheet = {}
            return setmetatable(o, db)
            -- return nil
        end
    else
        o.sheet = {}
    end
    return setmetatable(o, db)
end
--- 查询所选key的值
-- @param key: 要查询的键
-- @param[opt=nil]...: 可选可变参数，要查询的其他key
-- @return value: 查询键对应的值
-- @return ... : 其它键对应值
-- @usage db:select("msg")
-- @usage db:select("msg","vbat")
function db:select(key, ...)
    local o = {self.sheet[key]}
    local arg= {...}
    for _, k in ipairs(arg) do
        table.insert(o, self.sheet[k])
    end
    return unpack(o)
end
--- 持久化用户表到文件
-- @return nil
-- @usage db:serialize()
function db:serialize()
    local file = io.open(self.path, "w+b")
    if not file then
        self.path = "/" .. self.path:match("([^/]+)$") .. ".bak"
        file = io.open(self.path, "w+b")
    end
    local res = file:write("return ")
    -- 下面这段代码规避4G的bug
    if not res then
        self.path = "/" .. self.path:match("([^/]+)$") .. ".bak"
        file = io.open(self.path, "w+b")
        file:write("return ")
    end
    serializeio(file, self.sheet)
    file:close()
end
--- 新增键值对
-- @param key: 新增的键
-- @param val: 新增的键值
-- @boolean[opt=nil]re,如果键值存在是否覆盖,true覆盖
-- @return nil
-- @usage db:insert("vbatt",4.39)
-- @usage db:insert("msg",{4.39,"a","b"})
function db:insert(key, val, re)
    if re == true or not self.sheet[key] == nil then
        return self:update(key, val, true)
    end
end
--- 更新键值对                                                 
-- @param key: 要更新的键
-- @param val: 要更新的值
-- @boolean[opt=nil] add: 键不存在时是否新增,true为新增
-- @return nil
-- @usage db:update("msg",{1,2})
function db:update(key, val, add)
    if type(val) ~= "table" and self.sheet[key] == val then return end
    if add or self.sheet[key] ~= nil then
        self.sheet[key] = val
        self:serialize()
    end
end
--- 删除键值对
-- @param key: 要删除的键值对
-- @param[opt=nil]...: 要删除的其它键值对
-- @return nil
-- @usage db:delete("a")
-- @usage db:delete("a",1)
function db:delete(key, ...)
    for _, k in ipairs({key, ...}) do
        if type(k) == "number" then
            table.remove(self.sheet, k)
        else
            self.sheet[k] = nil
        end
    end
    self:serialize()
end
--- 导入数据表
-- @param sheet: 支持json和table两种格式导入
-- @return table or json string
-- @usage local t = getSheet()
function db:import(sheet)
    if type(sheet) == "string" then
        self.sheet = json.decode(sheet)
    elseif type(sheet) == "table" then
        self.sheet = sheet
    else
        log.info("db:import error!", "sheet type is error!")
        return
    end
    self:serialize()
end
--- 导出数据表
-- @param dbtype: 导出数据类型可选 "string" or "table"
-- @return table or json string
-- @usage local t = getSheet()
function db:export(dbtype)
    if dbtype == "string" then
        return json.encode(self.sheet)
    end
    return self.sheet
end
--- 删除数据库文件
-- @param o： 要删除的数据库对象
-- @param[opt=nil]...: 要删除的其他数据库对象
-- @return nil
function db.remove(o, ...)
    for _, k in ipairs({o, ...}) do
        os.remove(k.path)
        k.path, k.sheet, k.type = nil, nil, nil
    end
end

return  db