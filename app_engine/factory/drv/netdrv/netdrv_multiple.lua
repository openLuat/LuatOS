local model = hmeta.model()
if model:find("Air8000") or model:find("Air8101") then
    require "multi_a8000w"
elseif model:find("Air1601") or model:find("Air1602") then
    require "multi_air1601"
end
