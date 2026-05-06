-- Air8000/Air8101 共用同一份内置WiFi驱动（exnetif）
-- Air1601 使用独立的airlink SPI WiFi驱动
local model = hmeta.model()
if model:find("Air8000") or model:find("Air8101") then
    require "nwifi_a8000w"
elseif model:find("Air1601") or model:find("Air1602") then
    require "netdrv_wifi_air1601"
end
