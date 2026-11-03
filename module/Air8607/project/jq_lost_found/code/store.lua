--[[
@module  store
@summary 失物招领公示 - 数据层（纯 Lua，不碰任何 UI）
@version 1.0
@date    2026.10.30

=== 数据模型 ===
item = {
  id      = number,             -- 唯一 ID
  kind    = "found" | "lost",   -- 拾得 / 遗失
  name    = string,             -- 物品名称
  time    = string,             -- 记录时间（显示用，YYYY-MM-DD HH:MM）
  ts      = number,             -- os.time()，用于排序 / 时间筛选
  place   = string,             -- 地点
  contact = string,             -- 联系方式
  status  = "open" | "done",    -- 公示中 / 已完成（已认领）
  claimer_tail    = string,     -- 认领人证件尾号（done 时有）
  claimer_contact = string,     -- 认领人联系方式（done 时有）
  done_time       = string,     -- 完成时间
}

=== 认领规则 ===
拾得 / 遗失两类物品认领都必须凭身份证：S.claim 校验 18 位身份证号的校验位，
同时登记认领人联系方式，通过后置为已认领并记录证件尾号与联系方式。
]]

local conf = require "conf"

local M = {}

local items = {}    -- 全部条目（数组，顺序 = 登记顺序）
local by_id = {}    -- id -> item
local next_id = 1

-- ==================== 时间工具 ====================
local function fmt_time(ts)
    if not ts then ts = os.time() end
    local ok, s = pcall(os.date, "%Y-%m-%d %H:%M", ts)
    if ok and s then return s end
    return "--"
end

local function parse_time(s)
    local y, mo, d, h, mi = (s or ""):match("(%d+)%-(%d+)%-(%d+)%s+(%d+):(%d+)")
    if not y then return nil end
    local ok, ts = pcall(os.time, {
        year = tonumber(y), month = tonumber(mo), day = tonumber(d),
        hour = tonumber(h), min = tonumber(mi), sec = 0,
    })
    if ok and ts then return ts end
    return nil
end

-- ==================== 身份证校验（GB11643）====================
local ID_W = { 7, 9, 10, 5, 8, 4, 2, 1, 6, 3, 7, 9, 10, 5, 8, 4, 2 }
local ID_C = "10X98765432"

function M.valid_id(id)
    id = tostring(id or ""):gsub("%s+", ""):upper()
    if #id ~= 18 then return false end
    if not id:sub(1, 17):match("^%d+$") then return false end
    local last = id:sub(18, 18)
    if not last:match("[%dX]") then return false end
    local sum = 0
    for i = 1, 17 do
        sum = sum + (id:byte(i) - 48) * ID_W[i]
    end
    return ID_C:sub((sum % 11) + 1, (sum % 11) + 1) == last
end

-- ==================== 初始化 ====================
function M.init()
    items = {}
    by_id = {}
    next_id = 1
    local now = os.time()
    for i, d in ipairs(conf.SAMPLE_ITEMS) do
        local ts = parse_time(d.time) or (now - i * 3600)
        local it = {
            id = next_id, kind = d.kind, name = d.name,
            time = d.time, ts = ts, place = d.place,
            contact = d.contact, status = "open",
        }
        next_id = next_id + 1
        items[#items + 1] = it
        by_id[it.id] = it
    end
    log.info("store", "失物招领数据初始化", #items, "条")
end

-- ==================== 查询 ====================
function M.all() return items end

function M.get(id) return by_id[id] end

--[[多条件查询
@param table opt { keyword, kind = "all"|"found"|"lost", time = "all"|"today"|"week", status = "all"|"open"|"done" }
@return table 结果数组（按时间倒序）
]]
function M.query(opt)
    opt = opt or {}
    local kw = (opt.keyword or ""):gsub("%s+", "")
    local kind = opt.kind or "all"
    local tr = opt.time or "all"
    local status = opt.status or "all"
    local now = os.time()

    local out = {}
    for _, it in ipairs(items) do
        local ok_status = (status == "all" or it.status == status)
        if ok_status and (kind == "all" or it.kind == kind) then
            local ok_kw = (kw == "")
                or it.name:find(kw, 1, true)
                or it.place:find(kw, 1, true)
                or it.contact:find(kw, 1, true)

            local ok_t = true
            if tr == "today" then
                local d1, d2 = os.date("*t", it.ts or now), os.date("*t", now)
                ok_t = (d1.year == d2.year and d1.month == d2.month and d1.day == d2.day)
            elseif tr == "week" then
                ok_t = ((now - (it.ts or now)) < 7 * 86400)
            end

            if ok_kw and ok_t then
                out[#out + 1] = it
            end
        end
    end

    table.sort(out, function(a, b) return (a.ts or 0) > (b.ts or 0) end)
    return out
end

-- ==================== 新增 ====================
--[[新增条目
@param table f { kind, name, place, contact, time }
@return boolean ok, table|string
]]
function M.add(f)
    f = f or {}
    if f.kind ~= "found" and f.kind ~= "lost" then
        return false, "请选择拾得或遗失"
    end
    if not f.name or (f.name:gsub("%s+", "") == "") then
        return false, "请填写物品名称"
    end
    if not f.contact or (f.contact:gsub("%s+", "") == "") then
        return false, "请填写联系方式"
    end

    local it = {
        id = next_id,
        kind = f.kind,
        name = f.name:gsub("^%s+", ""):gsub("%s+$", ""),
        place = (f.place or ""):gsub("^%s+", ""):gsub("%s+$", ""),
        contact = f.contact:gsub("%s+", ""),
        time = f.time or fmt_time(),
        ts = parse_time(f.time) or os.time(),
        status = "open",
    }
    next_id = next_id + 1
    items[#items + 1] = it
    by_id[it.id] = it
    log.info("store", "新增条目", it.kind == "found" and "拾得" or "遗失", it.name)
    return true, it
end

-- ==================== 认领 ====================
--[[认领条目（拾得 / 遗失通用）：必须凭身份证 + 登记联系方式
@param number|string id 条目 id
@param string id_card   18 位身份证号（校验位核对）
@param string contact   认领人联系方式
@return boolean ok, string|item
]]
function M.claim(id, id_card, contact)
    local it = by_id[id]
    if not it then return false, "条目不存在" end
    if it.status == "done" then return false, "该物品已认领" end

    local idn = tostring(id_card or ""):gsub("%s+", ""):upper()
    if not M.valid_id(idn) then return false, "身份证号有误，请核对后重试" end

    local c = tostring(contact or ""):gsub("%s+", "")
    if c == "" then return false, "请登记认领人联系方式" end
    if not c:match("^%d+$") then return false, "联系方式请填写数字" end

    it.status = "done"
    it.claimer_tail = idn:sub(-4)
    it.claimer_contact = c
    it.done_time = fmt_time()
    log.info("store", "物品已认领", it.name, "证件尾号", it.claimer_tail, "联系方式", c)
    return true, it
end

-- ==================== 删除 ====================
function M.remove(id)
    local it = by_id[id]
    if not it then return false, "条目不存在" end
    for i = #items, 1, -1 do
        if items[i].id == id then
            table.remove(items, i)
            break
        end
    end
    by_id[id] = nil
    log.info("store", "删除条目", it.name)
    return true, it
end

-- ==================== 统计 ====================
-- 返回 公示中条数, 已完成条数
function M.stats()
    local open, done = 0, 0
    for _, it in ipairs(items) do
        if it.status == "done" then done = done + 1 else open = open + 1 end
    end
    return open, done
end

M.fmt_time = fmt_time

return M
