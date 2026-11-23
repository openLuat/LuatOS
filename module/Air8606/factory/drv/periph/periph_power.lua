-- Air8606 对外电源在开机时关闭，J18 使用 GPIO44，J17 使用 GPIO52。
local resources = require "air8606_resources"
local M = {}
local instances = {}
local function switch(self, enabled)
    local pin = self.params.pin
    local set = enabled and resources.power_on or resources.power_off
    local ok, err = set(pin, self)
    if not ok then return false, err end
    self.enabled = enabled
    return true
end
local function start(self)
    return switch(self, true)
end
local function stop(self)
    return switch(self, false)
end
function M.init(params)
    if type(params) ~= "table" or not params.id or (params.pin ~= 44 and params.pin ~= 52) then
        return false, "对外电源仅支持 GPIO44(VIN) / GPIO52(5V)"
    end
    if instances[params.id] then return false, "外设 ID 重复" end
    local h = {id=params.id,name=params.name,params=params,enabled=false}
    h.start, h.stop = start, stop
    h.status = function(self)
        return {enabled=self.enabled,info=string.format("GPIO%d 已请求%s电平，请实测端子电压",
            self.params.pin, self.enabled and "高" or "低")}
    end
    instances[params.id] = h
    return h
end
function M.get(id) return instances[id] end
return M
