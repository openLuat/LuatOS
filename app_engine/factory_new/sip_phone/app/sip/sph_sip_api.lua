--[[
@module  sph_sip_api
@summary SIP 设备网关：账号在线状态查询与服务端通话记录（HTTPS + RSA 认证）
@version 1.0
@date    2026.11.13
@author  江访
@usage
订阅/发布: 无，纯请求-应答；异步调用方必须跑在 sys 任务里（内部 http.request().wait() 会 yield）

  sph_sip_api.account()            -> string                当前 SIP 号码
  sph_sip_api.statuses(numbers, account) -> table|nil, err   各号码在线状态
                                                             {[号码]={status=,exists=,enabled=,extensionNum=}}
  sph_sip_api.cached_calls(page, account) -> table|nil, bool 取缓存；第二个返回值表示是否仍在30秒有效期
  sph_sip_api.calls(page, account, force) -> table|nil, err  服务端通话记录 {total=,calls={...}}

认证：账号用固件 RSA 公钥加密 → Base64 → 请求头 sip-key，账号本身不进 URL 明文之外的任何日志。
通话记录按页取（每页20条），本地只留最近3页缓存，30秒内不重复请求。

=== 设计要点 ===
1. 「通话记录」「联系人」两页原先只读本地 fskv，只保留最近5条，页面上写着
   「后续接入服务器记录」。本模块就是那个服务器侧记录的取数口。
2. 请求失败一律返回 nil, 中文原因，由页面决定是退回本地记录还是提示重试；
   本模块不写任何 UI 状态。
3. HTTP_DEBUG 只是排障开关，打开后会把请求头（含认证令牌）打进日志，
   出厂固件默认关闭。
]]

local M = {}
local store = require "sph_store"
local net = require "sph_net_app"

-- 临时排障开关：排完障关掉。打开会把请求头里的认证令牌打进日志。
local HTTP_DEBUG = false
local request_id = 0

local function trace(id, name, value)
    if not HTTP_DEBUG then return end
    if type(value) == "table" then
        local ok, encoded = pcall(json.encode, value)
        value = ok and encoded or tostring(value)
    end
    value = tostring(value or "")
    log.info("sip_http", id, name, "bytes", #value)
    -- 小块输出，避免被设备日志缓冲截断
    for offset = 1, #value, 96 do
        log.info("sip_http", id, name, offset, value:sub(offset, offset + 95))
    end
end

local BASE = "https://api-iot.luatos.com/iot/device/api-service"
local KEY = [[-----BEGIN PUBLIC KEY-----
MIGfMA0GCSqGSIb3DQEBAQUAA4GNADCBiQKBgQCJvDI9R8kq8l8ghZPRna3IS0B3SA7aJlcg44tp7DiTx5AYqAFuBUPfnTldYpkux/zFPnZ115b3eOC10aG+/PcGBOMM+ul5LNNh3Jz82GsfDmAyeQzG8XFLIsvt/WzoKHkAAmpTWX1NZOmxnT5Te8ML+DskYSy0GieJNoOulOlJYwIDAQAB
-----END PUBLIC KEY-----
]]

--[[
@function account
@summary 当前配置的 SIP 号码
@return string
]]
function M.account() return tostring(store.get_acct().user or "") end

local function escape(value)
    return (tostring(value):gsub("([^%w%-_%.~])", function(c) return string.format("%%%02X", string.byte(c)) end))
end

local last_error
local function response_error(code, value)
    local reason
    if type(value) == "table" then
        for _, key in ipairs({ "msg", "message", "detail", "error" }) do
            if type(value[key]) == "string" and value[key] ~= "" then reason = value[key]; break end
        end
    end
    -- 只显示服务器给出的错误原因，不带请求令牌和账号
    if reason then
        reason = reason:gsub("[%c]", " ")
        local cut = utf8.offset(reason, 121)
        if cut then reason = reason:sub(1, cut - 1) end
    end
    local message = (code == 401 and "认证失败" or "服务器请求失败") .. "（HTTP " .. tostring(code) .. "）"
    if reason then message = message .. "：" .. reason end
    if message ~= last_error then log.warn("sip_api", message); last_error = message end
    return message
end

local function request(path, account)
    request_id = request_id + 1
    local id = request_id
    trace(id, "request", "GET " .. BASE .. path)
    trace(id, "SIP number (RSA plaintext)", account)
    trace(id, "network ready", tostring(net.is_up()))
    if account == "" then return nil, "请先配置 SIP 号码" end
    if not net.is_up() then return nil, "网络不可用，请检查联网状态" end
    if not (rsa and rsa.encrypt and crypto and crypto.base64_encode and http and http.request) then
        return nil, "固件缺少 RSA、Base64 或 HTTP 功能"
    end
    local ok, cipher = pcall(rsa.encrypt, KEY, account)
    if not ok or type(cipher) ~= "string" then return nil, "SIP 号码加密失败" end
    local token = crypto.base64_encode(cipher)
    if type(token) ~= "string" or token == "" then return nil, "认证编码失败" end
    local headers = { ["sip-key"] = token }
    trace(id, "RSA cipher bytes", #cipher)
    trace(id, "request headers", headers)
    trace(id, "request body", "<empty>; timeout=10000ms; RSA=PKCS1-v1.5; encoding=Base64")
    local code, response_headers, body = http.request("GET", BASE .. path, headers, nil, { timeout = 10000 }).wait()
    trace(id, "response code", code)
    trace(id, "response headers", response_headers)
    trace(id, "response body", body)
    if not net.is_up() then return nil, "网络不可用，请检查联网状态" end
    if not code or code <= 0 then return nil, "服务器无法访问或请求超时（" .. tostring(code) .. "）" end
    local parsed, value = pcall(json.decode, body or "")
    if code ~= 200 then return nil, response_error(code, parsed and value or nil) end
    last_error = nil
    if not parsed or type(value) ~= "table" then return nil, "服务器返回的 JSON 无效" end
    if value.code ~= 200 then return nil, "服务器返回错误：" .. tostring(value.msg or value.code) end
    if type(value.data) ~= "table" then return nil, "服务器返回的数据格式无效" end
    return value.data
end

--[[
@function statuses
@summary 查询一组 SIP 号码的在线状态
@param numbers table 号码数组
@param account string 当前账号（认证用）
@return table|nil, string|nil  {[号码]={status=,exists=,enabled=,extensionNum=}} 或 nil, 原因
@usage status ∈ online / ringing / in_call / offline
]]
function M.statuses(numbers, account)
    if #numbers == 0 then return {} end
    local encoded, wanted = {}, {}
    for i, number in ipairs(numbers) do encoded[i] = escape(number); wanted[number] = true end
    local data, err = request("/accounts/status?usernames=" .. table.concat(encoded, ","), account)
    if not data then return nil, err end
    local result = {}
    local states = { online = true, ringing = true, in_call = true, offline = true }
    for _, item in ipairs(data) do
        if type(item) ~= "table" or not wanted[item.extensionNum] or result[item.extensionNum] then
            return nil, "服务器返回账号与查询号码不匹配"
        end
        if item.exists == false or item.enabled == false then item.status = "offline" end
        if not states[item.status] then return nil, "服务器返回未知账号状态" end
        result[item.extensionNum] = item
    end
    for _, number in ipairs(numbers) do
        if not result[number] then return nil, "服务器未返回全部账号状态" end
    end
    return result
end

-- 通话记录缓存：按页存，最多 3 页；换账号即整体失效
local calls_cache, cache_account = {}, nil
local cache_serial = 0

--[[
@function cached_calls
@summary 取某页通话记录缓存
@param number page 页码，从 1 开始
@param string account 当前账号
@return table|nil, boolean  第二个返回值表示缓存是否仍在 30 秒有效期内
]]
function M.cached_calls(page, account)
    if cache_account ~= account then calls_cache = {}; cache_account = account end
    local entry = calls_cache[page]
    if not entry then return nil, false end
    local age = os.time() - entry.time
    return entry.data, age >= 0 and age < 30
end

--[[
@function calls
@summary 取服务端通话记录
@param number page 页码，从 1 开始
@param string account 当前账号
@param boolean|nil force true 强制重新请求，忽略 30 秒缓存
@return table|nil, string|nil  {total=,calls={...}} 或 nil, 原因
@usage 单条记录字段: caller / callee / answered / startTime / billsec / durationSec
]]
function M.calls(page, account, force)
    local cached, fresh = M.cached_calls(page, account)
    if cached and fresh and not force then return cached end
    local data, err = request("/calls?extensionNum=" .. escape(account) .. "&page=" .. page .. "&size=20", account)
    if not data then return nil, err end
    if type(data.calls) ~= "table" or type(data.total) ~= "number" or data.total < 0 then
        return nil, "通话记录格式无效"
    end
    for _, item in ipairs(data.calls) do
        if type(item) ~= "table" or type(item.caller) ~= "string" or type(item.callee) ~= "string" then
            return nil, "通话记录格式无效"
        end
    end
    if cache_account == account then
        cache_serial = cache_serial + 1
        calls_cache[page] = { data = data, time = os.time(), serial = cache_serial }
        local count, oldest, serial = 0, nil, math.huge
        for key, entry in pairs(calls_cache) do
            count = count + 1
            if entry.serial < serial then oldest, serial = key, entry.serial end
        end
        if count > 3 then calls_cache[oldest] = nil end
    end
    return data
end

return M
