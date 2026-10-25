--[[
@module  settings
@summary 设备设置持久化（目前只有背光亮度）：fskv 优先，fskv 不可用时落 SD 卡
@version 1.0
@date    2026.10.23

=== 存储策略（与 lock.lua 一致）===
这台整机固件没启用 fskv（日志：`fskv 不可用`），所以亮度必须落在 SD 卡：
`/.album_bright`（1~3 字节数字，点开头，相册里看不到）。
app.start 会先挂 SD，所以 main 点背光时卡已就绪。

=== 亮度范围 ===
钳到 10~100：下限不设 0，否则用户把亮度拖到底屏幕全黑，
锁屏/设置页都看不见，等于把自己锁在门外。
]]
local conf = require "conf"

local M = {}

local fskv_ok = nil
local KEY_BRIGHT = "album_bright"
local BRIGHT_FILE = conf.sd.mount .. "/.album_bright"

local PWM_CH = 3            -- 背光 PWM3（GPIO13）
local PWM_FREQ = 1000
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

local function clamp(v)
    v = tonumber(v)
    if not v then return nil end
    v = math.floor(v + 0.5)
    if v < BRIGHT_MIN then v = BRIGHT_MIN end
    if v > BRIGHT_MAX then v = BRIGHT_MAX end
    return v
end

--[[读取保存的亮度（10~100）]]
function M.get_brightness()
    ensure_fskv()
    if fskv_ok then
        local ok, v = pcall(fskv.get, KEY_BRIGHT)
        if ok and v ~= nil then
            local n = clamp(v)
            if n then return n end
        end
    end
    local f = io.open(BRIGHT_FILE, "rb")
    if f then
        local s = f:read(8)
        f:close()
        if type(s) == "string" and s:match("^%d+$") then
            local n = clamp(s)
            if n then return n end
        end
    end
    return BRIGHT_MAX
end

--[[立即把亮度应用到 PWM（不写盘）。@return number 实际应用的值]]
function M.apply_brightness(v)
    v = clamp(v)
    if not v then return nil end
    if pwm and pwm.setup then
        pwm.setup(PWM_CH, PWM_FREQ, v)
        pwm.start(PWM_CH)
    end
    return v
end

--[[持久化 + 应用亮度。@return number 实际保存的值]]
function M.set_brightness(v)
    v = clamp(v)
    if not v then return nil end
    ensure_fskv()
    if fskv_ok then
        pcall(fskv.set, KEY_BRIGHT, tostring(v))
    end
    if io.exists(conf.sd.mount) then
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
