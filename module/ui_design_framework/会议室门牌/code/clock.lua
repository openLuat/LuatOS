--[[
@module  clock
@summary 离线校时（硬件 RTC 优先，无 RTC 退回「基准 + 单调时钟」）+ fskv 记忆
@version 1.0.0
@usage  M.init()          开机调一次：探测 rtc 库、设基准年与时区、读回上次手动基准
        M.set(y,mo,d,h,mi) 手动校准（门牌设置页调用），成功返回 true
        M.epoch()         当前时间戳；无任何可用时钟时返回 nil
        M.synced()        是否已校时（界面用它决定是否显示「未对时」）

@note 1) rtc.set 吃的是「不含本地偏移」的 UTC 秒数（见 luat_lib_rtc.c：无论时区多少，
         rtc.get/set 总是 UTC），所以要减掉时区偏置；而 rtc.timezone 的单位是 1/4 小时
         （东八区 = 32，不是 8），os.date 会按 时区/4*3600 把 UTC 秒加回本地时间
         （见 lua/src/loslib.c 的 os_date 补丁）；
      2) 时区偏置必须用**固定参考点**测，不能拿 os.time() 当参考：没校时前 os.time() 是 0，
         偏置会被算成 0，首次校时的基准就少扣一个时区，界面整体偏 8 小时；
      3) 有些板子没有 rtc 库、os.time 也永远是 0，这时用「用户设定值 + mcu.ticks()」推算，
         精度足够门牌看时间；
      4) 一旦硬件 RTC 生效，os.time() 会接管（两者差 5 分钟内以 os.time 为准），
         这样后续联网 NTP 对时也能正常覆盖手动值。
]]
local M = {}

-- v2：时区换算修正后，旧版基准（少扣了一个时区）不能再沿用，否则一开机就偏 6~8 小时
local KEY = "ui_time_base_v2"
local KEY_OLD = "ui_time_base"
-- rtc.timezone 的单位是 1/4 小时：东八区 = 32（写成 8 会变成 UTC+2，界面整体偏 6 小时）
local TZ_QUARTERS = 32
local REF_EPOCH = 1735689600      -- 2025-01-01 00:00:00 UTC，只用来测时区偏置
local rtc_lib
local now_base, now_tick          -- 手动基准 + 设定那一刻的单调时钟
local saved_base                  -- 上次开机前写进 fskv 的基准（掉电期间的流逝无法补）

local function ticks()
    if mcu and mcu.ticks then
        local ok, v = pcall(mcu.ticks)
        if ok and type(v) == "number" then return v end
    end
    return 0
end

-- os.date 与 os.time 之间的时区偏置（秒）。
-- 必须用固定参考点测：os.time() 在校时前是 0，拿它当参考会让偏置恒为 0，
-- 首次校时的基准就少扣一个时区，主页时钟/日期/此刻线整体偏 8 小时。
local function tz_bias()
    local ok, v = pcall(function() return os.time(os.date("*t", REF_EPOCH)) - REF_EPOCH end)
    if ok and type(v) == "number" then return v end
    return 0
end

function M.init()
    local ok, has = pcall(function() return rtc ~= nil and type(rtc.set) == "function" end)
    rtc_lib = (ok and has) and rtc or nil
    if rtc_lib then
        pcall(function() rtc_lib.setBaseYear(2000) end)
        -- 东八区必须是 32（单位 1/4 小时）；设错会让 os.date 只加 2 小时
        pcall(function() rtc_lib.timezone(TZ_QUARTERS) end)
    end
    if fskv then
        pcall(function()
            if fskv.init then fskv.init() end
            local n = tonumber(fskv.get(KEY))
            if n and n > 1700000000 then
                saved_base = n
            elseif fskv.get(KEY_OLD) then
                -- 旧值是按「os.time() 为 0 时时区偏置 0」存的，本身已经偏了，只能丢弃
                fskv.del(KEY_OLD)
                log.warn("clock", "旧版校时基准已作废，请在设置页重新校时")
            end
        end)
    end
    log.info("clock", "校时源", rtc_lib and "硬件RTC" or (saved_base and "手动基准" or "未校时"),
        "时区偏置(秒)", tz_bias())
    return M
end

-- 手动校准：写入硬件 RTC（若有），同时记下软件基准
function M.set(y, mo, d, h, mi)
    local ok, ts = pcall(os.time, { year = y, month = mo, day = d, hour = h, min = mi, sec = 0 })
    if not ok or type(ts) ~= "number" or ts <= 0 then
        log.error("clock", "时间参数无效", ok, ts)
        return false, "时间参数无效"
    end
    -- ts 是「输入墙钟按 UTC 解的秒数」，os.date 会再加回时区，所以这里扣掉偏置才是真 UTC
    local target = ts - tz_bias()
    if rtc_lib then
        local rok, rret = pcall(function() return rtc_lib.set(target) end)
        -- pcall 成功 != 写入成功：rtc.set 返回 false 表示固件拒绝了（部分 BSP 只支持 table）
        if not rok or rret == false then
            log.warn("clock", "写硬件 RTC 失败，仅用软件基准", rok, rret)
        else
            log.info("clock", "写硬件 RTC", target)
        end
    end
    now_base, now_tick = target, ticks()
    saved_base = target
    if fskv then
        pcall(function()
            fskv.set(KEY, target)
            log.info("clock", "手动基准已保存", target)
        end)
    end
    return true, "校时成功"
end

-- 清除手动基准（清空后只能靠 RTC / 联网）
function M.reset()
    now_base, now_tick, saved_base = nil, nil, nil
    if fskv then pcall(function() fskv.del(KEY) end) end
end

function M.epoch()
    local t = os.time()
    local valid = (t and t > 1700000000)
    if now_base then
        local el = (ticks() - now_tick) / 1000
        -- mcu.ticks 是 32 位有符号，约 24.8 天回绕变负；回绕后按 0 处理，别把基准往回拉
        if el < 0 or el >= 86400 * 60 then el = 0 end
        local guess = now_base + el
        -- RTC 生效后 os.time 与手动基准基本同步，此时交给 os.time 继续走
        if not valid or math.abs(t - guess) > 300 then return guess end
        return t
    end
    if valid then return t end
    return saved_base
end

function M.synced()
    return M.epoch() ~= nil
end

return M
