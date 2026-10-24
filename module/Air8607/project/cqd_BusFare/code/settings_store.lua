-- 参数掉电保存：优先使用 LuatOS 的 fskv，桌面预览或没有 fskv 的固件
-- 自动退回内存保存，保证 UI 始终可以操作。
local M = {}

local memory = {}
local kv_ready = false

function M.init()
    if type(fskv) == "table" and type(fskv.init) == "function" then
        local ok, result = pcall(fskv.init)
        kv_ready = ok and result ~= false
    end
    return kv_ready
end

local function read(key)
    if kv_ready and type(fskv.get) == "function" then
        local ok, value = pcall(fskv.get, key)
        if ok then
            if type(value) == "string" then value = tonumber(value) end
            if type(value) == "number" then memory[key] = value end
        end
    end
    return memory[key]
end

local function write(key, value)
    memory[key] = value
    if kv_ready and type(fskv.set) == "function" then
        pcall(fskv.set, key, value)
    end
end

function M.load_number(key, default)
    local value = read(key)
    if type(value) ~= "number" then return default end
    return value
end

function M.save_number(key, value)
    write(key, value)
end

return M
