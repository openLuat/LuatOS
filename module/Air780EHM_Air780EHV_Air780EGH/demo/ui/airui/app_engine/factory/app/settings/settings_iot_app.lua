--[[
@module  settings_iot_app
@summary IOT 账号业务模块，桥接 UI 层和 exapp 层
@version 1.0
@date    2026.05.09
@author  江访
]]
-- naming: fn(2-5char), var(2-4char)

sys.subscribe("IOT_LOGIN_REQUEST", function(account, password)
    exapp.iot_login(account, password)
end)

sys.subscribe("IOT_LOGOUT_REQUEST", function()
    exapp.iot_logout()
end)

sys.subscribe("IOT_GET_ACCOUNT_INFO", function()
    local info = exapp.iot_get_account_info()
    sys.publish("IOT_ACCOUNT_INFO", info)
end)
