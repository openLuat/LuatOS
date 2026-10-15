testdebug = {}

local g_Debug_Flag = true
-- function log(msg)
--     if g_Debug_Flag == false then return end
--     cclog(msg)
-- end

---
-- @function  dump()
-- @param value table 需要打印的
-- @param description string 描述
-- @param nesting int table嵌套层级
-- @end

function dump(value, description, nesting)
    if g_Debug_Flag == false then return end

    -- 默认打印层级3
    if type(nesting) ~= "number" then nesting = 3 end

    local lookupTable = {}
    local result = {}

    local function _v(v)
        if type(v) == "string" then v = '"' .. v .. '"' end
        return tostring(v)
    end

    local function _dump(value, description, indent, nest, keylen)
        description = description or "<var>"
        spc = ""
        if type(keylen) == "number" then
            spc = string.rep(" ", keylen - string.len(_v(description)))
        end

        if type(value) ~= "table" then
            result[#result + 1] = string.format("%s%s%s = %s", indent,
                                                _v(description), spc, _v(value))
        elseif lookupTable[value] then
            result[#result + 1] = string.format("%s%s%s = *REF*", indent,
                                                description, spc)
        else
            lookupTable[value] = true
            if nest > nesting then
                result[#result + 1] = string.format("%s%s = *MAX NESTING*",
                                                    indent, description)
            else
                result[#result + 1] = string.format("%s%s = {", indent,
                                                    _v(description))
                local indent2 = indent .. "    "
                local keys = {}
                local keylen = 0
                local values = {}
                for k, v in pairs(value) do
                    keys[#keys + 1] = k
                    local vk = _v(k)
                    local vk1 = string.len(vk)
                    if vk1 > keylen then keylen = vk1 end
                    values[k] = v
                end
                table.sort(keys, function(a, b)
                    if type(a) == "number" and type(b) == "number" then
                        return a < b
                    else
                        return tostring(a) < tostring(b)
                    end
                end)

                for i, k in pairs(keys) do
                    _dump(values[k], k, indent2, nest + 1, keylen)
                end
                result[#result + 1] = string.format("%s}", indent)
            end
        end
    end
    _dump(value, description, "- ", 1)

    for i, line in pairs(result) do print(line) end
end

return {dump = dump}
