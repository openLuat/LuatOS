--[[
@module  sip_config
@summary SIP 账户配置持久化模块
@version 1.0.0
@date    2026.05.28
@usage
使用 fskv 保存和读取 SIP 账户配置及登录状态。
]]

local sip_config = {}

local CONFIG_KEY = "sip_account_v1"
local LOGIN_KEY = "sip_logged_in_v1"

-- 登录状态使用内存变量（绕过 fskv 存储异常问题）
-- 每次应用启动/重新加载时自动重置为未登录
local memory_logged_in = false

-- 默认账户配置
local default_account = {
    sip_server_addr = "180.152.6.34",
    sip_server_port = 8910,
    sip_domain = "180.152.6.34",
    sip_username = "100000",
    sip_password = "Mm123.",
    sip_transport = "UDP",
    adapter = nil,
    display_name = "JQ"
}
local function build_auto_account()
    local ok, imei = pcall(mobile.imei)
    local last6 = nil
    if ok and imei and imei ~= "" and imei ~= "pc_simulator" then
        imei = tostring(imei):gsub("%s+", "")
        last6 = imei:match(".*(%d%d%d%d%d%d)$")
        -- last4 = imei:match(".*(%d%d%d%d)$")
        log.info("sip_config", "build_auto_account", "imei=", imei, "last6=", last6)
    end

    if last6 and tonumber(last6) then
        return {
            sip_server_addr = "180.152.6.34",
            sip_server_port = 8910,
            sip_domain = "180.152.6.34",
            sip_username = "1" .. last6 .. "0",
            sip_password = "Air." .. last6,
            sip_transport = "UDP",
            adapter = nil,
            display_name = "JQ"
        }
    end

    -- PC 模拟器或 IMEI 不可用时回退到默认值
    return {
        sip_server_addr = "180.152.6.34",
        sip_server_port = 8910,
        sip_domain = "180.152.6.34",
        sip_username = "100117",
        sip_password = "Air.123",
        sip_transport = "UDP",
        adapter = nil,
        display_name = "JQ"
    }
end

--[[
获取自动登录账户配置
根据模块 IMEI 动态生成，IMEI 不可用时回退到默认值
@return table 自动登录账户配置的深拷贝
]]
function sip_config.get_auto_account()
    local auto_account = build_auto_account()
    local account = {}
    for k, v in pairs(auto_account) do
        account[k] = v
    end
    account.sip_server_address = account.sip_server_addr
    return account
end

--[[
获取当前账户配置
@return table 账户配置表
]]
function sip_config.get_account()
    if fskv then
        local data = fskv.get(CONFIG_KEY)
        if data and type(data) == "table" then
            -- 合并默认值，防止新增字段缺失
            local account = {}
            for k, v in pairs(default_account) do
                account[k] = data[k] ~= nil and data[k] or v
            end
            -- UI 层使用 sip_server_address，做兼容映射
            account.sip_server_address = data.sip_server_address ~= nil
                and data.sip_server_address or account.sip_server_addr
            return account
        end
    end
    -- 深拷贝返回默认值
    local account = {}
    for k, v in pairs(default_account) do
        account[k] = v
    end
    account.sip_server_address = account.sip_server_addr
    return account
end

--[[
保存账户配置
@param account table 账户配置表
]]
function sip_config.save_account(account)
    if fskv and account then
        -- 内部协议栈使用 sip_server_addr，做兼容映射
        if account.sip_server_address ~= nil and account.sip_server_addr == nil then
            account.sip_server_addr = account.sip_server_address
        end
        fskv.set(CONFIG_KEY, account)
        log.info("sip_config", "账户配置已保存")
    end
end

--[[
检查是否已登录
@return boolean 已登录返回 true
]]
function sip_config.is_logged_in()
    if memory_logged_in then
        return true
    end
    -- 尝试从 fskv 恢复持久化状态
    if fskv then
        local ok, val = pcall(function()
            return fskv.get(LOGIN_KEY)
        end)
        if ok and val == true then
            memory_logged_in = true
            return true
        end
    end
    return false
end

--[[
设置登录状态
@param val boolean true 表示已登录，false 表示未登录
]]
function sip_config.set_logged_in(val)
    memory_logged_in = (val == true)
    -- 同时尝试写入 fskv（如果可用），但不依赖它
    if fskv then
        local ok, err = pcall(function()
            fskv.set(LOGIN_KEY, memory_logged_in)
        end)
        if not ok then
            log.warn("sip_config", "fskv 写入登录状态失败:", err)
        end
    end
end

--[[
检查是否已保存过账户配置
@return boolean 已保存过返回 true
]]
function sip_config.has_saved_account()
    if fskv then
        local data = fskv.get(CONFIG_KEY)
        if data and type(data) == "table" then
            return data.sip_username ~= nil and data.sip_username ~= ""
        end
    end
    return false
end

--[[
清除所有配置（注销时使用）
]]
function sip_config.clear()
    memory_logged_in = false
    if fskv then
        local ok, err = pcall(function()
            fskv.set(LOGIN_KEY, false)
        end)
        if ok then
            log.info("sip_config", "登录状态已清除")
        else
            log.warn("sip_config", "fskv 清除登录状态失败:", err)
        end
    end
end

--[[
清除保存的账户配置
]]
function sip_config.clear_account()
    if fskv then
        local ok, err = pcall(function()
            fskv.set(CONFIG_KEY, nil)
        end)
        if ok then
            log.info("sip_config", "账户配置已清除")
        else
            log.warn("sip_config", "清除账户配置失败:", err)
        end
    end
end

-- 模块加载时强制重置为未登录
sip_config.set_logged_in(false)

return sip_config
