--[[
@module  settings_iot_app
@summary IOT 账号业务模块
@version 2.0
@date    2026.08.25
@author  江访

消息协议:
订阅: IOT_LOGIN_REQUEST(account, password) → 登录
订阅: IOT_LOGOUT_REQUEST                  → 登出
订阅: IOT_GET_ACCOUNT_INFO                → 获取账号信息
发布: IOT_LOGIN_RESULT({success, account, uid, error})
发布: IOT_LOGOUT_RESULT({success, error})

fskv 键: iot_uid, iot_nickname, iot_account, iot_login_time
]]

local FSKV_UID  = "iot_uid"
local FSKV_NICK = "iot_nickname"
local FSKV_ACCT = "iot_account"
local FSKV_TIME = "iot_login_time"

local function clear_iot_info()
    pcall(fskv.set, FSKV_UID, "")
    pcall(fskv.set, FSKV_NICK, "")
    pcall(fskv.set, FSKV_ACCT, "")
    pcall(fskv.set, FSKV_TIME, 0)
end

function iot_get_saved_info()
    local s, v = pcall(fskv.get, FSKV_UID)
    if not s or type(v) ~= "string" or v == "" then return nil end
    local _, nick = pcall(fskv.get, FSKV_NICK)
    local _, acct = pcall(fskv.get, FSKV_ACCT)
    return { uid = v, nickname = (type(nick) == "string" and nick) or "", account = (type(acct) == "string" and acct) or "" }
end

sys.subscribe("IOT_LOGIN_REQUEST", function(account, password)
    -- exapp.iot_login 内部处理加密/请求/保存，登录成功后发布 IOT_LOGIN_RESULT
    -- uid 由 exapp 保存到 fskv("iot_uid")
    pcall(exapp.iot_login, account, password)
end)

sys.subscribe("IOT_LOGOUT_REQUEST", function()
    local ok, err = pcall(exapp.iot_logout)
    if ok then
        clear_iot_info()
        sys.publish("IOT_LOGOUT_RESULT", {success = true})
    else
        sys.publish("IOT_LOGOUT_RESULT", {success = false, error = tostring(err)})
    end
end)

sys.subscribe("IOT_GET_ACCOUNT_INFO", function()
    local ok, info = pcall(exapp.iot_get_account_info)
    sys.publish("IOT_ACCOUNT_INFO", ok and info or nil)
end)
