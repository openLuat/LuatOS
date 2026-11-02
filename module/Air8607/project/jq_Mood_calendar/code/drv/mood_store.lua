--[[
@module  mood_store
@summary 心情数据按月读写（fskv 优先 / 不可用时退化到 SD 卡）
@author  蒋骞
@version 1.0
@date    2026.10.30

=== 为什么按月存 ===
一条记录 = 「几号 = 几分」，一个月最多 31 条。
按年存一年就是 365 条，序列化后接近 fskv 单值上限（4KB 左右），
按月存一条最长也就 200 字节，读写都稳。

=== 存储键 ===
fskv   key = "mood_202610"
SD 卡  文件 = /sd/.mood/202610.txt   （点开头，界面上看不到）

=== 编码 ===
"1:5,2:3,10:4"   —— 号数:分数，逗号分隔。

=== 策略 ===
优先 fskv（片内 flash，掉电不丢、不用挂卡）；
只有在 fskv 不可用时才去挂 SD 卡读写文件。
两者都不可用时退化为「只在内存里生效」，界面照常能点，不至于崩。
]]
local conf = require "conf"
local sd_card = require "sd_card"

local M = {}

local KEY_PREFIX = conf.mood_key_prefix or "mood_"
local SD_DIR = conf.sd.mount .. "/.mood"

local fskv_ok = nil      -- nil = 还没探测
local mem = {}           -- key -> table，兜底缓存

-- ==================== 存储后端 ====================
local function has_fskv()
    local ok, r = pcall(function()
        return fskv ~= nil and type(fskv.init) == "function" and type(fskv.get) == "function"
    end)
    return ok and r
end

local function ensure_fskv()
    if fskv_ok ~= nil then return fskv_ok end
    fskv_ok = false
    if has_fskv() then
        local ok = pcall(fskv.init)
        if ok then
            fskv_ok = true
            log.info("mood_store", "使用 fskv 存储心情数据")
        else
            log.warn("mood_store", "fskv.init 失败，退化到内存存储")
        end
    else
        log.warn("mood_store", "固件无 fskv，退化到 SD 卡 / 内存")
    end
    return fskv_ok
end

local function key_of(y, m)
    return string.format("%s%04d%02d", KEY_PREFIX, y, m)
end

local function file_of(y, m)
    return string.format("%s/%04d%02d.txt", SD_DIR, y, m)
end

-- ==================== 编解码 ====================
local function encode(t)
    local parts = {}
    for d = 1, 31 do
        local s = t[d]
        if s then parts[#parts + 1] = d .. ":" .. s end
    end
    return table.concat(parts, ",")
end

local function decode(s)
    local t = {}
    if type(s) ~= "string" then return t end
    for d, v in s:gmatch("(%d+):(%d+)") do
        local day, score = tonumber(d), tonumber(v)
        if day and score and day >= 1 and day <= 31 and score >= 1 and score <= 5 then
            t[day] = score
        end
    end
    return t
end

-- ==================== SD 卡读写 ====================
--[[只在卡「已经挂上」时读，绝不在这里主动挂卡：
sd_card.mount() 里有 sys.wait，而 load 可能被 main chunk（非协程）调用，
在那里 yield 会直接报 "attempt to yield from outside a coroutine" 把 VM 打死。
]]
local function read_sd(y, m)
    if not sd_card.is_mounted() then return nil end
    local f = io.open(file_of(y, m), "rb")
    if not f then return nil end
    local s = f:read(2048)
    f:close()
    return s
end

--[[写卡：这里才挂卡（write 只会在协程里被调用）。
整个流程用 pcall 兜住，挂卡失败 / 没卡都只是不能持久化，不许影响界面。
]]
local function write_sd(y, m, s)
    local ok, ret = pcall(function()
        if not sd_card.mount() then return false end
        if type(io.mkdir) == "function" then pcall(io.mkdir, SD_DIR) end
        local f = io.open(file_of(y, m), "wb")
        if not f then return false end
        f:write(s)
        f:close()
        return true
    end)
    if not ok then
        log.warn("mood_store", "写 SD 异常", tostring(ret))
        return false
    end
    if not ret then
        log.warn("mood_store", "写 SD 失败", file_of(y, m))
    end
    return ret
end

-- ==================== 对外接口 ====================
--[[读取某月数据
@return table { [day] = score }，没有记录返回空表（非 nil）
]]
function M.load(y, m)
    local key = key_of(y, m)

    if ensure_fskv() then
        local ok, v = pcall(fskv.get, key)
        if ok and type(v) == "string" and #v > 0 then
            local t = decode(v)
            mem[key] = t
            return t
        end
    end

    -- fskv 没有：看看 SD 卡上有没有（比如从别的机器拷过来的数据）
    local s = read_sd(y, m)
    if s and #s > 0 then
        local t = decode(s)
        mem[key] = t
        if ensure_fskv() then pcall(fskv.set, key, s) end
        log.info("mood_store", "从 SD 卡载入", key, "记录", encode(t) or "")
        return t
    end

    return mem[key] or {}
end

--[[写入某月数据
@param table t { [day] = score }
@return boolean ok
]]
function M.save(y, m, t)
    local key = key_of(y, m)
    local s = encode(t)
    mem[key] = t

    local ok_flash = false
    if ensure_fskv() then
        ok_flash = pcall(fskv.set, key, s)
    end

    if ok_flash then
        return true
    end

    -- flash 不可用：落 SD 卡
    if write_sd(y, m, s) then
        return true
    end

    log.warn("mood_store", "无法持久化，仅内存生效", key)
    return false
end

--[[删掉某天的记录（传 nil 分数时用）]]
function M.clear(y, m, day)
    local t = M.load(y, m)
    t[day] = nil
    return M.save(y, m, t)
end

return M
