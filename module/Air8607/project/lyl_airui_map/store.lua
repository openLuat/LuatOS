--[[
@module  store
@summary 结构化数据在 SD 卡上的 JSON 读写（带内置 json 回退）
@version 1.0
@date    2026.10.28
@usage
POI、路线、轨迹摘要都用本模块持久化。优先使用固件内置全局 json；
若该固件未编入 json，则回退到本模块内置的极简编解码器
（只支持 object/array/string/number/bool/null，足够本工程使用）。
]]

local M = {}

-- 检测固件内置全局 json 是否可用（核心库不 require json）
local builtin_json
if type(_G.json) == "table" and _G.json.encode and _G.json.decode then
    builtin_json = _G.json
end

local function is_array(t)
    local n = 0
    for k, _ in pairs(t) do
        if type(k) ~= "number" then
            return false
        end
        n = n + 1
    end
    return n == #t
end

-- 极简 JSON 编码
local function simple_encode(value, pretty, indent)
    indent = indent or 0
    local tv = type(value)
    if tv == "string" then
        local s = value:gsub('[%z\1-\31\\"]', function(c)
            local map = { ['"'] = '\\"', ["\\"] = "\\\\", ["\n"] = "\\n",
                ["\r"] = "\\r", ["\t"] = "\\t" }
            if map[c] then return map[c] end
            return string.format("\\u%04x", string.byte(c))
        end)
        return '"' .. s .. '"'
    elseif tv == "number" then
        if value ~= value or value == math.huge or value == -math.huge then
            return "null"
        end
        if value % 1 == 0 and math.abs(value) < 1e15 then
            return string.format("%d", value)
        end
        return string.format("%.7f", value)
    elseif tv == "boolean" then
        return value and "true" or "false"
    elseif tv == "nil" then
        return "null"
    elseif tv == "table" then
        local nl = pretty and "\n" or ""
        local pad1 = pretty and string.rep(" ", indent + 2) or ""
        local pad0 = pretty and string.rep(" ", indent) or ""
        local parts = {}
        if is_array(value) then
            for _, v in ipairs(value) do
                parts[#parts + 1] = pad1 .. simple_encode(v, pretty, indent + 2)
            end
            if #parts == 0 then return "[]" end
            return "[" .. nl .. table.concat(parts, "," .. nl) .. nl .. pad0 .. "]"
        else
            for k, v in pairs(value) do
                parts[#parts + 1] = pad1 .. simple_encode(tostring(k), false)
                    .. (pretty and ": " or ":") .. simple_encode(v, pretty, indent + 2)
            end
            if #parts == 0 then return "{}" end
            return "{" .. nl .. table.concat(parts, "," .. nl) .. nl .. pad0 .. "}"
        end
    end
    return "null"
end

-- 极简 JSON 解码（递归下降）
local simple_decode
do
    local pos
    local text

    local function skip_ws()
        local s, e = text:find("^[ \t\r\n]*", pos)
        if e then pos = e + 1 end
    end

    local function decode_value()
        skip_ws()
        local c = text:sub(pos, pos)
        if c == "{" then
            pos = pos + 1
            local obj = {}
            skip_ws()
            if text:sub(pos, pos) == "}" then pos = pos + 1; return obj end
            while true do
                skip_ws()
                local key = decode_value()
                skip_ws()
                pos = pos + 1 -- 冒号
                obj[key] = decode_value()
                skip_ws()
                local ch = text:sub(pos, pos)
                pos = pos + 1
                if ch == "}" then break end
            end
            return obj
        elseif c == "[" then
            pos = pos + 1
            local arr = {}
            skip_ws()
            if text:sub(pos, pos) == "]" then pos = pos + 1; return arr end
            while true do
                arr[#arr + 1] = decode_value()
                skip_ws()
                local ch = text:sub(pos, pos)
                pos = pos + 1
                if ch == "]" then break end
            end
            return arr
        elseif c == '"' then
            local startp = pos + 1
            local i = startp
            -- 逐字符找未转义的右引号，正确处理 \" 和 \\
            while i <= #text do
                local ch = text:sub(i, i)
                if ch == "\\" then
                    i = i + 2
                elseif ch == '"' then
                    break
                else
                    i = i + 1
                end
            end
            local raw = text:sub(startp, i - 1)
            pos = i + 1
            raw = raw:gsub("\\(.)", function(esc)
                local map = { n = "\n", r = "\r", t = "\t", ['"'] = '"',
                    ["\\"] = "\\", ["/"] = "/" }
                if map[esc] then return map[esc] end
                if esc == "u" then return "" end -- 本工程无中文转义需求
                return esc
            end)
            return raw
        elseif text:sub(pos, pos + 3) == "true" then
            pos = pos + 4
            return true
        elseif text:sub(pos, pos + 4) == "false" then
            pos = pos + 5
            return false
        elseif text:sub(pos, pos + 3) == "null" then
            pos = pos + 4
            return nil
        else
            local s, e, num = text:find("(-?%d+%.?%d*[eE]?[%+%-]?%d*)", pos)
            pos = e + 1
            return tonumber(num)
        end
    end

    simple_decode = function(str)
        text = str
        pos = 1
        return decode_value()
    end
end

function M.encode(value, pretty)
    if builtin_json then
        local ok, ret = pcall(builtin_json.encode, value)
        if ok and type(ret) == "string" then
            return ret
        end
    end
    return simple_encode(value, pretty, 0)
end

function M.decode(str)
    if not str or type(str) ~= "string" or #str == 0 then
        return nil
    end
    if builtin_json then
        local ok, ret = pcall(builtin_json.decode, str)
        if ok and ret ~= nil then
            return ret
        end
    end
    local ok, ret = pcall(simple_decode, str)
    if ok then
        return ret
    end
    return nil
end

--[[
读取并解析一个 JSON 文件
@param path string
@return table|nil
]]
function M.load(path)
    local f = io.open(path, "r")
    if not f then
        return nil
    end
    local data = f:read("*a")
    f:close()
    return M.decode(data)
end

--[[
把表编码成 JSON 写入文件
@param path string
@param value table
@param pretty boolean 可选，缩进输出
@return boolean
]]
function M.save(path, value, pretty)
    local str = M.encode(value, pretty)
    local ok, err
    if io.writeFile then
        ok, err = pcall(io.writeFile, path, str)
    else
        local f, oerr = io.open(path, "w")
        if not f then
            return false, oerr
        end
        ok, err = pcall(f.write, f, str)
        f:close()
    end
    return ok and true or false, err
end

-- 确保目录存在（LuatOS io.mkdir 只创建一级，逐级创建）
function M.mkdir(path)
    if not io.mkdir then
        return
    end
    local parts = {}
    for part in string.gmatch(path, "[^/]+") do
        parts[#parts + 1] = part
        local cur = "/" .. table.concat(parts, "/")
        pcall(io.mkdir, cur)
    end
end

return M
