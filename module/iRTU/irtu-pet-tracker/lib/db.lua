--[[
@module  db
@summary 配置持久化存储模块（参考 iRTU db.lua）
@version 1.0
@date    2026.07.17
@usage
将配置以 Lua table 序列化形式持久化到文件系统，支持开机加载、运行时更新。
用法：
    local db = require("lib.db")
    local cfg = db.new("/luadb/air8201.cfg")
    local sheet = cfg:export()          -- 获取当前配置
    cfg:import(new_sheet)                -- 更新配置并保存
    local val = cfg:select("key")        -- 查询某键值
]]
local db = {}
db.__index = db

-- 序列化 table 到文件
local function serializeio(file, o)
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

-- 创建 db 对象
-- @param path: 配置文件路径，如 "/luadb/air8201.cfg"
function db.new(path)
    if path == nil then
        log.error("db.new:", "Empty path!")
        return nil
    end
    local back = "/" .. path:match("([^/]+)$") .. ".bak"
    local o = {path = io.exists(back) and back or path}
    if io.exists(o.path) then
        local res, val = pcall(dofile, o.path)
        if res then
            o.sheet = type(val) == "table" and val or json.decode(val)
        else
            log.error("db.new:", "Irregular data format!")
            o.sheet = {}
            return setmetatable(o, db)
        end
    else
        o.sheet = {}
    end
    return setmetatable(o, db)
end

-- 查询所选 key 的值
function db:select(key, ...)
    local o = {self.sheet[key]}
    local arg = {...}
    for _, k in ipairs(arg) do
        table.insert(o, self.sheet[k])
    end
    return unpack(o)
end

-- 持久化到文件系统
function db:serialize()
    local file = io.open(self.path, "w+b")
    if not file then
        self.path = "/" .. self.path:match("([^/]+)$") .. ".bak"
        file = io.open(self.path, "w+b")
    end
    local res = file:write("return ")
    if not res then
        self.path = "/" .. self.path:match("([^/]+)$") .. ".bak"
        file = io.open(self.path, "w+b")
        file:write("return ")
    end
    serializeio(file, self.sheet)
    file:close()
end

-- 更新键值对
function db:update(key, val, add)
    if type(val) ~= "table" and self.sheet[key] == val then return end
    if add or self.sheet[key] ~= nil then
        self.sheet[key] = val
        self:serialize()
    end
end

-- 导入完整配置（覆盖整个 sheet 并持久化）
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

-- 导出配置表
function db:export(dbtype)
    if dbtype == "string" then
        return json.encode(self.sheet)
    end
    return self.sheet
end

return db