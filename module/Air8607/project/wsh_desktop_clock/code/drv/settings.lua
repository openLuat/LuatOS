--[[
@module  settings
@summary 背光亮度持久化与应用
@author  王世豪
@version 1.0
@date    2026.10.26

=== 存储策略（与相册 lock.lua 一致）===
`/.clock_bright`（1~3 字节数字，点开头，界面里看不到）。
SD 卡没挂载时退化为「只在内存里生效」，不至于报错。

=== 亮度范围 ===
钳到 10~100：下限不设 0，否则拖到底屏幕全黑，设置页都看不见，
等于把自己锁在门外。
]]
local conf = require "conf"

local M = {}

local fskv_ok = nil
local KEY_BRIGHT = "clock_bright"
local BRIGHT_FILE = conf.sd.mount .. "/.clock_bright"

local PWM_CH = conf.backlight.pwm_ch
local PWM_FREQ = conf.backlight.freq
local BRIGHT_MIN = 10
local BRIGHT_MAX = 100

local function ensure_fskv()
    if fskv_ok ~= nil then return end
    fskv_ok = false
    if type(fskv) == "table" and fskv.init then
        local ok = pcall(fskv.init)
        if ok then fskv_ok = true end
    end
end

--[[钳制到合法范围]]
function M.clamp(v)
    v = tonumber(v)
    if not v then return nil end
    v = math.floor(v + 0.5)
    if v < BRIGHT_MIN then v = BRIGHT_MIN end
    if v > BRIGHT_MAX then v = BRIGHT_MAX end
    return v
end

--[[读取上次保存的亮度]]
function M.get_brightness()
    ensure_fskv()
    if fskv_ok then
        local ok, v = pcall(fskv.get, KEY_BRIGHT)
        if ok and v ~= nil then
            local n = M.clamp(v)
            if n then return n end
        end
    end
    local f = io.open(BRIGHT_FILE, "rb")
    if f then
        local s = f:read(8)
        f:close()
        if type(s) == "string" and s:match("^%d+$") then
            local n = M.clamp(s)
            if n then return n end
        end
    end
    return conf.backlight.default
end

--[[立即应用到 PWM（不写盘）。@return number 实际应用的值]]
function M.apply_brightness(v)
    v = M.clamp(v)
    if not v then return nil end
    if pwm and pwm.setup then
        pwm.setup(PWM_CH, PWM_FREQ, v)
        pwm.start(PWM_CH)
    end
    return v
end

--[[持久化 + 应用亮度。@return number 实际保存的值]]
function M.set_brightness(v)
    v = M.clamp(v)
    if not v then return nil end
    ensure_fskv()
    if fskv_ok then
        pcall(fskv.set, KEY_BRIGHT, tostring(v))
    end
    local ok_exist = pcall(io.exists, conf.sd.mount)
    if ok_exist then
        local f = io.open(BRIGHT_FILE, "wb")
        if f then
            f:write(tostring(v))
            f:close()
        end
    end
    M.apply_brightness(v)
    return v
end

return M
