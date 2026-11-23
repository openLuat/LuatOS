--[[
@module  signal
@summary AD 原始值 → 温度（0.1℃ 整数），含一阶滤波与故障判定
]]

local M = {}

local cfg = require("config")
local S = cfg.scale

-- 每通道状态
local ch = {
    { raw = 0, temp = 0, filt = 0, fault = false, valid = false },
    { raw = 0, temp = 0, filt = 0, fault = false, valid = false },
}

local function to_temp(ad)
    return math.floor(ad * S.temp_max / S.ad_full + 0.5)
end

-- vals: {AD1, AD2, 心跳}
function M.update(vals)
    for i = 1, 2 do
        local c = ch[i]
        local ad = vals[cfg.channels[i].ad_index]
        if ad == nil then
            c.valid = false
        elseif ad >= S.fault_ad then
            c.raw, c.fault, c.valid = ad, true, false
        else
            c.raw, c.fault, c.valid = ad, false, true
            c.temp = to_temp(ad)
            if c.filt == 0 then
                c.filt = c.temp
            else
                c.filt = c.filt + (c.temp - c.filt) * cfg.filter_alpha
            end
        end
    end
    return ch
end

function M.get(i) return ch[i] end
function M.all() return ch end

-- 掉线时把所有通道标为无效，界面显示 --.-
function M.invalidate()
    for i = 1, 2 do
        ch[i].valid = false
    end
end

function M.temp_int(i)
    local c = ch[i]
    if not c.valid then return nil end
    return math.floor(c.filt + 0.5)
end

function M.fmt(i)
    local t = M.temp_int(i)
    if not t then return "--.-" end
    return string.format("%.1f", t / 10)
end

return M
