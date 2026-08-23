--[[
@module  settings_iot_app
@summary IOT 账号业务模块，桥接 UI 层和 exapp 层
@version 1.1
@date    2026.05.12
@author  江访

消息协议（订阅/发布）:
订阅: IOT_LOGIN_REQUEST(account, password)    → 登录 IoT 平台
订阅: IOT_LOGOUT_REQUEST                     → 登出 IoT 平台
订阅: IOT_GET_ACCOUNT_INFO                   → 获取当前账号信息
发布: IOT_LOGIN_RESULT({success, account, error}) → 登录结果
发布: IOT_LOGOUT_RESULT({success, error})         → 登出结果
发布: IOT_ACCOUNT_INFO(info) / nil               → 账号信息
]]
-- naming: fn(2-5char), var(2-4char)

sys.subscribe("IOT_LOGIN_REQUEST", function(account, password)
    local ok, err = pcall(exapp.iot_login, account, password)
    if ok then
        local info = exapp.iot_get_account_info()
        if info and info.account then
            sys.publish("IOT_LOGIN_RESULT", {success = true, account = info.account, nickname = info.nickname})
        else
            sys.publish("IOT_LOGIN_RESULT", {success = true, account = account})
        end
    else
        log.error("iot_app", "iot_login 失败:", err)
        sys.publish("IOT_LOGIN_RESULT", {success = false, error = tostring(err or "登录请求失败")})
    end
end)

sys.subscribe("IOT_LOGOUT_REQUEST", function()
    local ok, err = pcall(exapp.iot_logout)
    if ok then
        sys.publish("IOT_LOGOUT_RESULT", {success = true})
    else
        log.error("iot_app", "iot_logout 失败:", err)
        sys.publish("IOT_LOGOUT_RESULT", {success = false, error = tostring(err or "登出请求失败")})
    end
end)

sys.subscribe("IOT_GET_ACCOUNT_INFO", function()
    local ok, info = pcall(exapp.iot_get_account_info)
    if ok and info then
        sys.publish("IOT_ACCOUNT_INFO", info)
    else
        log.warn("iot_app", "获取账号信息失败")
        sys.publish("IOT_ACCOUNT_INFO", nil)
    end
end)
