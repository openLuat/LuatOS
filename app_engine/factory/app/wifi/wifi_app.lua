-- wifi_app 分发器
local ok, model = pcall(hmeta.model)
if not ok or not model then model = rtos.bsp() or "" end
if type(model) == "string" and (model:find("Air1601") or model:find("Air1602")) then
    return require "wifi_app_air1601"
else
    return require "wifi_app_air8000w"
end
