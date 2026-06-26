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

-- 默认联系人
local default_contacts = {
    { num = "1002", name = "运动馆前台" },
    { num = "1003", name = "仓储网关" },
    { num = "1005", name = "值班终端" }
}

-- 默认通话记录
local default_records = {
    { day = "今天", type = "missed", num = "1008", time = "09:26", name = "" },
    { day = "今天", type = "answered", num = "1002", time = "08:41", name = "运动馆前台" },
    { day = "昨天", type = "dialed", num = "1005", time = "18:10", name = "值班终端" },
    { day = "昨天", type = "missed", num = "1009", time = "16:22", name = "" }
}

-- 默认聊天记录
local default_chats = {
    {
        day = "今天", num = "1002", time = "09:18", latest = "请确认网关在线状态。",
        messages = {
            { dir = "in", time = "09:12", text = "设备已恢复连接。" },
            { dir = "out", time = "09:15", text = "收到，我会检查 SIP 注册。" },
            { dir = "in", time = "09:18", text = "请确认网关在线状态。" }
        }
    },
    {
        day = "昨天", num = "1005", time = "17:40", latest = "巡检完成，语音链路正常。",
        messages = {
            { dir = "out", time = "17:30", text = "开始链路巡检。" },
            { dir = "in", time = "17:40", text = "巡检完成，语音链路正常。" }
        }
    }
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
    if fskv then
        local data = fskv.get(CONTACTS_KEY)
        if data and type(data) == "table" and #data > 0 then
            return deep_copy(data)
        end
    end
    return deep_copy(default_contacts)
end

--[[
保存联系人列表
@param contacts table 联系人数组
]]
function sip_data.save_contacts(contacts)
    if fskv and contacts then
        fskv.set(CONTACTS_KEY, deep_copy(contacts))
    end
end

--[[
添加联系人
@param num string 号码
@param name string 名称
@return boolean 成功返回 true
]]
function sip_data.add_contact(num, name)
    if not num or num == "" then return false end
    local contacts = sip_data.get_contacts()
    -- 如果已存在则更新名称
    for _, c in ipairs(contacts) do
        if c.num == num then
            c.name = name or c.name
            sip_data.save_contacts(contacts)
            return true
        end
    end
    table.insert(contacts, 1, { num = num, name = name or ("联系人 " .. num) })
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
    if fskv then
        local data = fskv.get(RECORDS_KEY)
        if data and type(data) == "table" and #data > 0 then
            return deep_copy(data)
        end
    end
    return deep_copy(default_records)
end

--[[
保存通话记录
@param records table 通话记录数组
]]
function sip_data.save_records(records)
    if fskv and records then
        fskv.set(RECORDS_KEY, deep_copy(records))
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
    local records = sip_data.get_records()
    local name = sip_data.get_contact_name(num) or ""
    table.insert(records, 1, { day = day, type = rtype, num = num, time = time, name = name })
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
    if fskv then
        local data = fskv.get(CHATS_KEY)
        if data and type(data) == "table" and #data > 0 then
            return deep_copy(data)
        end
    end
    return deep_copy(default_chats)
end

--[[
保存聊天记录
@param chats table 聊天数组
]]
function sip_data.save_chats(chats)
    if fskv and chats then
        fskv.set(CHATS_KEY, deep_copy(chats))
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
        fskv.set(CONTACTS_KEY, {})
        fskv.set(RECORDS_KEY, {})
        fskv.set(CHATS_KEY, {})
    end
end

return sip_data
