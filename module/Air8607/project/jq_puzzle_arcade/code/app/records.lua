--[[
@module  records
@summary 成绩榜存储（每款游戏前 5 名，优先 fskv 掉电保存，无 fskv 时退回内存）
@version 2.0
@date    2026.11.03
@usage
1、records.init()                        启动时调用一次
2、records.list(key)                     取该游戏的前 5 名：{ {v=成绩, t=时间戳}, ... }
3、records.best(key)                     取榜首成绩（没记录返回 0）
4、records.submit(key, value, "max"/"min") 交一局成绩，返回名次 1..5，没上榜返回 nil
5、records.clear(key)                    清空该游戏的榜
6、records.fmt_date(ts)                  时间戳转 "11-03"，未校时返回 "--"
   —— 兼容层（老代码还在用）：get / set / max / min

=== 为什么用紧凑字符串而不是 json 表 ===
fskv 本身支持 table（内部调 json.encode），但那会把 json 库变成硬依赖：
裁剪固件里把 json 去掉时，写入会静默失败，玩家的成绩就白丢了。
这里自己拼 "值,时间戳;值,时间戳" —— 5 条记录不到 200 字节
（fskv 单值上限 4096 字节，见 components/fskv/luat_lib_fskv.c: LUAT_FSKV_MAX_SIZE），
既不需要 json，解析也能用 pcall 兜底：脏数据最多丢掉一条，不会影响开机。

=== 为什么键名沿用 arcade_xxx 而不是加前缀 ===
第一版只存了一个数字，键名就是 arcade_2048 / arcade_puzzle_moves ...
现在同一个键改存字符串。读到 number 就说明是上一版留下的单值，
顺手迁移成"1 条记录"，玩家的老成绩不丢。
]]

local M = {}

local BOARD_MAX = 5          -- 每个榜保留 5 条
local kv_ready = false
local memory = {}            -- key -> list，避免每帧/每次点击都读 flash

-- 各游戏的"更好"方向。默认越小越好（步数、用时），只有两款是越大越好。
-- 方向写在存储层而不是各游戏里，是为了让 7 个调用点都只关心"交成绩"这一件事。
local POLICY = {
    arcade_2048        = "max",   -- 分数越高越好
    arcade_simon_round = "max",   -- 关卡越高越好
}

local function direction_of(key)
    return POLICY[key] or "min"
end

-- ==================== 序列化 ====================
local function encode(list)
    local parts = {}
    for i = 1, #list do
        parts[i] = string.format("%d,%d", list[i].v, list[i].t or 0)
    end
    return table.concat(parts, ";")
end

--[[解析存储串
任何异常（空串、老数字、被别人写坏的串）都退化成空榜，
绝不让一条脏数据把整页成绩干掉。
]]
local function decode(raw)
    local list = {}
    if type(raw) ~= "string" or raw == "" then return list end
    for seg in string.gmatch(raw, "[^;]+") do
        local v, t = string.match(seg, "^(%-?%d+),(%-?%d+)$")
        v = tonumber(v)
        if v then
            list[#list + 1] = { v = v, t = tonumber(t) or 0 }
            if #list >= BOARD_MAX then break end
        end
    end
    return list
end

local function save(key, list)
    memory[key] = list
    if kv_ready and type(fskv.set) == "function" then
        pcall(fskv.set, key, encode(list))
    end
end

local function load(key)
    local cached = memory[key]
    if cached then return cached end

    local list = {}
    if kv_ready and type(fskv.get) == "function" then
        local ok, raw = pcall(fskv.get, key)
        if ok and raw ~= nil then
            if type(raw) == "string" then
                list = decode(raw)
            elseif type(raw) == "number" then
                -- 第一版的单值成绩：迁移成 1 条（时间为 0，界面上显示 "--"）
                list = { { v = math.floor(raw), t = 0 } }
            end
        end
    end
    memory[key] = list
    return list
end

-- ==================== 对外接口 ====================
function M.init()
    if type(fskv) == "table" and type(fskv.init) == "function" then
        local ok, result = pcall(fskv.init)
        kv_ready = ok and result ~= false
    end
    log.info("records", kv_ready and "成绩榜: fskv 可用（掉电保存）"
        or "成绩榜: fskv 不可用，只在内存里保存")
    return kv_ready
end

--[[取某款游戏的前 5 名（返回的是缓存表本身，调用方只读不要改）]]
function M.list(key)
    return load(key)
end

function M.best(key)
    local list = load(key)
    if list[1] then return list[1].v end
    return 0
end

--[[交一局成绩
@param string key 记录键
@param number value 成绩（步数 / 用时秒 / 分数 / 手数）
@param string|nil dir "max" 或 "min"，省略时按 POLICY 自动判断
@return number|nil rank 名次 1..5；没进榜返回 nil
@return number best 交完之后榜首的成绩
]]
function M.submit(key, value, dir)
    value = math.floor(tonumber(value) or 0)
    if value < 0 then return nil, M.best(key) end
    dir = dir or direction_of(key)

    local list = load(key)

    local rank
    for i = 1, #list do
        local better = (dir == "max") and (value > list[i].v) or (value < list[i].v)
        if better then
            rank = i
            break
        end
    end
    if not rank and #list < BOARD_MAX then rank = #list + 1 end
    if not rank then return nil, M.best(key) end

    table.insert(list, rank, { v = value, t = os.time() })
    while #list > BOARD_MAX do
        table.remove(list)
    end
    save(key, list)

    log.info("records", string.format("%s 上榜第 %d 名: %d", key, rank, value))
    return rank, list[1].v
end

function M.clear(key)
    memory[key] = {}
    if kv_ready then
        if type(fskv.del) == "function" then
            pcall(fskv.del, key)
        elseif type(fskv.set) == "function" then
            pcall(fskv.set, key, "")
        end
    end
    log.info("records", "已清空榜", key)
end

--[[时间戳 -> "11-03"
未校时（os.time 还停在 1970）的机器上 os.date 会给出 01-01，
那比空白更误导人，所以这里直接显示 "--"。
]]
function M.fmt_date(ts)
    if type(ts) ~= "number" or ts < 1577836800 then return "--" end   -- 2020-01-01
    local ok, text = pcall(os.date, "%m-%d", ts)
    if ok and type(text) == "string" then return text end
    return "--"
end

-- ==================== 兼容层 ====================
function M.get(key, def)
    local best = M.best(key)
    if best > 0 then return best end
    return def
end

function M.set(key, value)
    M.submit(key, value)
    return math.floor(value or 0)
end

--[[越大越好（老接口，返回是否刷新了榜首）]]
function M.max(key, value)
    return M.submit(key, value, "max") == 1
end

--[[越小越好（老接口，返回是否刷新了榜首）]]
function M.min(key, value)
    return M.submit(key, value, "min") == 1
end

return M
