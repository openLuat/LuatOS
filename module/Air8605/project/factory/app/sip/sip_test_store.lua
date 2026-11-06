--[[
@module  sip_test_store
@summary 功能测试-SIP通话：本地持久化（账号 / 联系人 / 通话记录 / 消息 / 音量）
@version 1.0
@date    2026.11.04
@description
移植自 SIP_APP demo 的 store.lua，去掉 wifi/音频自检/自动注册等工厂用不到的部分。
大数据（联系人/记录/消息）走 /luadb 双槽 JSON 文件，避免 fskv 单值大小限制；
小数据（账号索引、音量）直接存 fskv。键名统一加 siptest_ 前缀，与其它业务隔离。
]]

local M = {}

local prefix = "siptest_"
local ready = false

local function copy(v)
    if type(v) ~= "table" then return v end
    local t = {}
    for k, x in pairs(v) do t[k] = copy(x) end
    return t
end

local function failure(reason)
    log.error("sip_test_store", tostring(reason))
    return false, reason
end

function M.init()
    if ready then return true end
    if not fskv then return failure("存储不可用") end
    local ok, value = pcall(fskv.init)
    if not ok or value == false then return failure("存储初始化失败") end
    ready = true
    return true
end

local function get(key, default)
    if not ready and not M.init() then return copy(default) end
    local ok, v = pcall(fskv.get, prefix .. key)
    if not ok then
        failure("读取存储失败: " .. key)
        return copy(default)
    end
    return copy(v == nil and default or v)
end

local function put(key, value)
    if not ready and not M.init() then return false, "存储不可用" end
    local ok, result = pcall(fskv.set, prefix .. key, value)
    if not ok or result ~= true then return failure("保存失败: " .. key) end
    return true
end

-- ==================== 账号 ====================

-- demo 规则：默认用户名 = 设备 ID（十六进制）转十进制，末尾补 "0"
local function default_user()
    local ok, id = pcall(hmeta.devid)
    if ok and type(id) == "string" and id ~= "" then
        local n = tonumber(id, 16)
        if n then return tostring(n) .. "0" end
    end
    return ""
end

local defaults = {
    server = "cc.luatos.com",
    port = 8910,
    domain = "",
    user = default_user(),
    password = "123456",
    transport = "udp",
}

function M.get_acct()
    local t, saved = copy(defaults), get("acct", {})
    if type(saved) == "table" then
        for k in pairs(defaults) do
            if saved[k] ~= nil then t[k] = saved[k] end
        end
    end
    return t
end

function M.save_acct(t)
    if type(t) ~= "table" then return false, "账号格式错误" end
    local a = copy(defaults)
    for k in pairs(defaults) do
        if t[k] ~= nil then a[k] = t[k] end
    end
    return put("acct", a)
end

function M.has_acct()
    local a = M.get_acct()
    return a.server ~= "" and a.user ~= ""
end

-- 恢复默认账号（重新按设备 ID 生成用户名）
function M.reset_acct()
    local a = copy(defaults)
    a.user = default_user()
    return put("acct", a)
end

-- ==================== 联系人 ====================

local function list(key)
    local t = get(key, {})
    return type(t) == "table" and t or {}
end

function M.get_contacts() return list("contacts") end

function M.find_name(num)
    for _, c in ipairs(M.get_contacts()) do
        if c.num == num and c.name ~= "" then return c.name end
    end
    return nil
end

function M.display(num) return M.find_name(num) or num or "" end

function M.save_contact(name, num)
    if type(num) ~= "string" or num == "" then return false, "号码为空" end
    if #num > 128 or type(name) ~= "string" or #name > 128 then return false, "联系人内容过长" end
    local t = M.get_contacts()
    for _, c in ipairs(t) do
        if c.num == num then c.name = name; return put("contacts", t) end
    end
    if #t >= 100 then return false, "联系人已满（100条）" end
    table.insert(t, 1, { name = name, num = num })
    return put("contacts", t)
end

function M.del_contact(num)
    local t = M.get_contacts()
    for i, c in ipairs(t) do
        if c.num == num then table.remove(t, i); return put("contacts", t) end
    end
    return false, "联系人不存在"
end

function M.update_contact(old_num, name, num)
    if type(num) ~= "string" or num == "" or #num > 128
        or type(name) ~= "string" or #name > 128 then
        return false, "联系人格式错误"
    end
    local t = M.get_contacts()
    local target
    for _, c in ipairs(t) do
        if c.num == old_num then target = c
        elseif c.num == num then return false, "目标号码已存在" end
    end
    if not target then return false, "联系人不存在" end
    target.name, target.num = name, num
    return put("contacts", t)
end

-- ==================== 通话记录 ====================

function M.get_calls() return list("calls") end

function M.add_call(rec)
    if type(rec) ~= "table" or not rec.num or rec.num == "" then return false, "记录缺少号码" end
    local t = M.get_calls()
    local r = copy(rec)
    r.ts = r.ts or os.time()
    r.dur = math.max(0, r.dur or 0)
    table.insert(t, 1, r)
    while #t > 200 do table.remove(t) end
    return put("calls", t)
end

function M.clear_calls() return put("calls", {}) end
function M.clear_contacts() return put("contacts", {}) end
function M.clear_messages() return put("messages", { seq = 0, items = {} }) end

-- 统计：联系人 / 通话记录 / 会话 / 未读
function M.counts()
    local threads_n = 0
    for _ in pairs(M.threads()) do threads_n = threads_n + 1 end
    return {
        contacts = #M.get_contacts(),
        calls = #M.get_calls(),
        threads = #M.threads(),
        unread = M.unread_total(),
    }
end

-- ==================== 消息 ====================

local function messages()
    local t = get("messages", { seq = 0, items = {} })
    if type(t) ~= "table" or type(t.items) ~= "table" then return { seq = 0, items = {} } end
    return t
end

function M.get_msgs() return messages().items end

function M.add_msg(num, dir, text, status)
    if type(num) ~= "string" or num == "" or type(text) ~= "string" then return false, "消息格式错误" end
    if #num > 128 or #text > 1024 then return false, "消息过长（最多1024字节）" end
    local t = messages()
    t.seq = (tonumber(t.seq) or 0) + 1
    local id = t.seq
    table.insert(t.items, {
        id = id, num = num, dir = dir, text = text,
        ts = os.time(), status = status or "recv", read = dir ~= "in",
    })
    while #t.items > 300 do table.remove(t.items, 1) end
    local ok, err = put("messages", t)
    if not ok then return false, err end
    return true, id
end

function M.update_msg(id, status, reason)
    local t = messages()
    for _, m in ipairs(t.items) do
        if m.id == id then
            m.status, m.reason = status, reason
            return put("messages", t)
        end
    end
    return false, "消息不存在"
end

function M.recover_messages()
    local t = messages()
    local changed = false
    for _, m in ipairs(t.items) do
        if m.status == "pending" then
            m.status, m.reason, changed = "unknown", "设备重启，送达结果未知", true
        end
    end
    if changed then return put("messages", t) end
    return true
end

function M.thread_msgs(num)
    local t = {}
    for _, m in ipairs(M.get_msgs()) do
        if m.num == num then t[#t + 1] = m end
    end
    return t
end

function M.delete_thread(num)
    local t = messages()
    for i = #t.items, 1, -1 do
        if t.items[i].num == num then table.remove(t.items, i) end
    end
    return put("messages", t)
end

function M.threads()
    local map, out = {}, {}
    for _, m in ipairs(M.get_msgs()) do
        local t = map[m.num]
        if not t then
            t = { num = m.num, total = 0, unread = 0 }
            map[m.num] = t
            out[#out + 1] = t
        end
        t.total = t.total + 1
        t.last, t.ts, t.id = m.text, m.ts, m.id
        if m.dir == "in" and not m.read then t.unread = t.unread + 1 end
    end
    table.sort(out, function(a, b) return a.id > b.id end)
    return out
end

function M.unread_total()
    local n = 0
    for _, t in ipairs(M.threads()) do n = n + t.unread end
    return n
end

function M.mark_read(num)
    local t = messages()
    local changed = false
    for _, m in ipairs(t.items) do
        if m.num == num and not m.read then m.read, changed = true, true end
    end
    if changed then return put("messages", t) end
    return true
end

-- ==================== 音频人工确认（自检页）====================

function M.is_audio_verified() return get("audio_ok", false) == true end
function M.set_audio_verified(on) return put("audio_ok", on == true) end

-- ==================== 音量 ====================

function M.get_vol()
    return math.max(0, math.min(100, tonumber(get("vol", 70)) or 70))
end

function M.set_vol(v)
    v = math.max(0, math.min(100, math.floor(tonumber(v) or 70)))
    local ok, err = put("vol", v)
    if not ok then return nil, err end
    return v
end

-- ==================== 格式化 ====================

function M.fmt_time(ts)
    if not ts or ts < 1577836800 then return "--:--" end
    if os.date("%Y%m%d", ts) == os.date("%Y%m%d") then return os.date("%H:%M", ts) end
    return os.date("%m-%d", ts)
end

function M.fmt_dur(sec)
    sec = math.max(0, math.floor(tonumber(sec) or 0))
    return string.format("%02d:%02d", sec // 60, sec % 60)
end

return M
