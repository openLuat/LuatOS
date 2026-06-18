--[[
@module  sip_data
@summary SIP 应用数据持久化模块
@version 1.0.0
@date    2026.05.28
@usage
管理联系人、通话记录、聊天记录的读写和持久化。
]]

local sip_data = {}

local CONTACTS_KEY = "sip_contacts_v1"
local RECORDS_KEY = "sip_records_v1"
local CHATS_KEY = "sip_chats_v1"

-- 当前登录用户，用于数据隔离
local current_user = nil

--[[
设置当前用户，切换账户数据隔离空间
@param username string 用户名，nil 表示未登录
]]
function sip_data.set_user(username)
    current_user = username
end

-- 根据当前用户生成动态 key
local function user_key(base)
    if current_user and current_user ~= "" then
        return base .. "_" .. tostring(current_user)
    end
    return base
end

-- 默认联系人（已清空，不再提供演示数据）
local default_contacts = {}

-- 默认通话记录（已清空，不再提供演示数据）
local default_records = {}

-- 默认聊天记录（已清空，不再提供演示数据）
local default_chats = {}

-- 遗留演示号码，用于自动清理旧 fskv 数据
local LEGACY_DEFAULT_NUMS = {
    ["1002"] = true, ["1003"] = true, ["1005"] = true,
    ["1008"] = true, ["1009"] = true
}

local function deep_copy(t)
    if type(t) ~= "table" then return t end
    local res = {}
    for k, v in pairs(t) do
        res[k] = deep_copy(v)
    end
    return res
end

--[[
获取联系人列表
@return table 联系人数组
]]
function sip_data.get_contacts()
    local contacts = nil
    if fskv then
        local data = fskv.get(user_key(CONTACTS_KEY))
        if data and type(data) == "table" and #data > 0 then
            contacts = deep_copy(data)
        end
    end
    if not contacts then
        contacts = deep_copy(default_contacts)
    end
    -- 自动清理遗留演示联系人
    local filtered = {}
    local dirty = false
    for _, c in ipairs(contacts) do
        if not LEGACY_DEFAULT_NUMS[c.num] then
            table.insert(filtered, c)
        else
            dirty = true
        end
    end
    if dirty then
        sip_data.save_contacts(filtered)
    end
    -- 补全缺少 online_status 的联系人
    for _, c in ipairs(filtered) do
        if c.online_status == nil then
            c.online_status = 0
            -- c.online_status = 1
        end
    end
    return filtered
end

--[[
保存联系人列表
@param contacts table 联系人数组
]]
function sip_data.save_contacts(contacts)
    if fskv and contacts then
        fskv.set(user_key(CONTACTS_KEY), deep_copy(contacts))
    end
end

--[[
添加联系人
@param num string 号码
@param name string 名称
@param online_status int 在线状态，0=离线 1=在线 2=异常，默认1
@return boolean 成功返回 true
]]
function sip_data.add_contact(num, name, online_status)
    if not num or num == "" then return false end
    local contacts = sip_data.get_contacts()
    -- 如果已存在则更新名称和状态
    for _, c in ipairs(contacts) do
        if c.num == num then
            c.name = name or c.name
            if online_status ~= nil then
                c.online_status = online_status
            end
            sip_data.save_contacts(contacts)
            return true
        end
    end
    -- table.insert(contacts, 1, { num = num, name = name or ("联系人 " .. num), online_status = online_status or 1 })
    table.insert(contacts, 1, { num = num, name = name or ("联系人 " .. num), online_status = online_status or 0 })
    sip_data.save_contacts(contacts)
    return true
end

--[[
删除联系人
@param num string 号码
@return boolean 成功返回 true
]]
function sip_data.remove_contact(num)
    if not num or num == "" then return false end
    local contacts = sip_data.get_contacts()
    for i, c in ipairs(contacts) do
        if c.num == num then
            table.remove(contacts, i)
            sip_data.save_contacts(contacts)
            return true
        end
    end
    return false
end

--[[
根据号码获取联系人名称
@param num string 号码
@return string 名称，未找到返回 nil
]]
function sip_data.get_contact_name(num)
    local contacts = sip_data.get_contacts()
    for _, c in ipairs(contacts) do
        if c.num == num then
            return c.name
        end
    end
    return nil
end

--[[
获取通话记录
@return table 通话记录数组
]]
function sip_data.get_records()
    local records_data = nil
    if fskv then
        local data = fskv.get(user_key(RECORDS_KEY))
        if data and type(data) == "table" and #data > 0 then
            records_data = deep_copy(data)
        end
    end
    if not records_data then
        records_data = deep_copy(default_records)
    end
    -- 补全旧数据可能缺失的字段，并过滤无效/遗留演示记录
    local valid_records = {}
    local dirty = false
    for _, r in ipairs(records_data) do
        if r.name == nil then r.name = "" end
        if r.num == nil then r.num = "" end
        if r.type == nil then r.type = "dialed" end
        if r.day == nil then r.day = "今天" end
        if r.time == nil then r.time = "" end
        -- 过滤掉号码为空或属于遗留演示号码的记录
        if r.num ~= "" and not LEGACY_DEFAULT_NUMS[r.num] then
            table.insert(valid_records, r)
        else
            dirty = true
        end
    end
    if dirty then
        sip_data.save_records(valid_records)
    end
    return valid_records
end

--[[
保存通话记录
@param records table 通话记录数组
]]
function sip_data.save_records(records)
    if fskv and records then
        fskv.set(user_key(RECORDS_KEY), deep_copy(records))
    end
end

--[[
添加通话记录
@param day string 日期分组
@param rtype string 类型：missed/answered/dialed
@param num string 号码
@param time string 时间
]]
function sip_data.add_record(day, rtype, num, time)
    if not num or num == "" then
        return false
    end
    local records = sip_data.get_records()
    local name = sip_data.get_contact_name(num) or ""
    table.insert(records, 1, { day = day or "今天", type = rtype or "dialed", num = num, time = time or "", name = name or "" })
    -- 限制最大记录数
    if #records > 200 then
        for i = 201, #records do
            records[i] = nil
        end
    end
    sip_data.save_records(records)
end

--[[
获取聊天记录
@return table 聊天数组
]]
function sip_data.get_chats()
    local chats = nil
    if fskv then
        local data = fskv.get(user_key(CHATS_KEY))
        if data and type(data) == "table" and #data > 0 then
            chats = deep_copy(data)
        end
    end
    if not chats then
        chats = deep_copy(default_chats)
    end
    -- 自动清理遗留演示聊天记录
    local filtered = {}
    local dirty = false
    for _, c in ipairs(chats) do
        if not LEGACY_DEFAULT_NUMS[c.num] then
            table.insert(filtered, c)
        else
            dirty = true
        end
    end
    if dirty then
        sip_data.save_chats(filtered)
    end
    return filtered
end

--[[
保存聊天记录
@param chats table 聊天数组
]]
function sip_data.save_chats(chats)
    if fskv and chats then
        fskv.set(user_key(CHATS_KEY), deep_copy(chats))
    end
end

--[[
添加消息到聊天
@param num string 对方号码
@param dir string 方向：in/out
@param time string 时间
@param text string 消息内容
]]
function sip_data.add_message(num, dir, time, text)
    if not num or not text then return end
    local chats = sip_data.get_chats()
    local found = nil
    for i, c in ipairs(chats) do
        if c.num == num then
            found = c
            break
        end
    end
    if not found then
        found = { day = "今天", num = num, time = time, latest = text, messages = {} }
        table.insert(chats, 1, found)
    end
    table.insert(found.messages, { dir = dir, time = time, text = text })
    found.latest = text
    found.time = time
    found.day = "今天"
    -- 限制单聊天消息数
    if #found.messages > 100 then
        for i = 1, #found.messages - 100 do
            table.remove(found.messages, 1)
        end
    end
    sip_data.save_chats(chats)
end

--[[
获取与指定号码的聊天消息
@param num string 号码
@return table 消息数组
]]
function sip_data.get_messages(num)
    local chats = sip_data.get_chats()
    for _, c in ipairs(chats) do
        if c.num == num then
            return deep_copy(c.messages)
        end
    end
    return {}
end

--[[
清除所有数据（调试用）
]]
function sip_data.clear_all()
    if fskv then
        fskv.set(user_key(CONTACTS_KEY), {})
        fskv.set(user_key(RECORDS_KEY), {})
        fskv.set(user_key(CHATS_KEY), {})
    end
end

return sip_data
