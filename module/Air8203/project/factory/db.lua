--[[
@module  db
@summary 配置持久化存储模块（★ 非合宙官方库，工程自带）
@version 1.0（8203）
@date    2026.09.28
@usage
=== ★ 本文件不是合宙官方扩展库 ===
合宙官方库清单 = `LuatOS/script/libs/`（等价于 Luatools 的
`resource/soc_script/<版本>/lib/`）。查证日期 2026-09-28，
**该目录中不存在 db.lua** → 本文件属工程自带库（源自 iRTU 工程）。

因此它按现场约定**放在项目根目录**，而不是 `lib/`：
`lib/` 只放"与官方同名、但本工程用了定制版本"的库（工具遇到同名会 skip 自己那份）；
这些非官方库若放进 `lib/` 会让人误以为是官方库。
⚠️ 但**不要删除**：`cfg_fetch.lua` 需要 `require("db")` 才能工作。
（LuatOS 的 luadb 是扁平命名空间，按文件名索引、与目录无关，放哪都能 require 到。）

将配置以 Lua table 序列化形式持久化到文件系统，支持开机加载、运行时更新。
用法：
    local db = require("db")                   -- ★注意：不是 require("lib.db")
    local cfg = db.new("/luadb/air8203.cfg")   -- ★8203：文件名与 8201/8202 隔离，避免配置串台
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
-- @param path: 配置文件路径，如 "/luadb/air8203.cfg"
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