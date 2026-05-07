local model = hmeta.model()
if model:find("Air8000") or model:find("Air8101") then
    require "netdrv_4g_air8000w"
elseif model:find("Air1601") or model:find("Air1602") then
    require "netdrv_4g_air1601"
end
