-- 状态栏时间源：秒定时器比对日期与星期，变化才广播 STATUS_TIME_UPDATED。
local weekday = {"星期日", "星期一", "星期二", "星期三", "星期四", "星期五", "星期六"}
local last_time, last_date, last_day

local function update_time(force)
    local now = os.date("*t")
    if not now then return end
    local time = string.format("%02d:%02d", now.hour, now.min)
    local date = string.format("%04d-%02d-%02d", now.year, now.month, now.day)
    local day = weekday[now.wday]
    if force or time ~= last_time or date ~= last_date or day ~= last_day then
        last_time, last_date, last_day = time, date, day
        sys.publish("STATUS_TIME_UPDATED", time, date, day)
    end
end

sys.timerLoopStart(update_time, 1000)
sys.subscribe("REQUEST_STATUS_REFRESH", function() update_time(true) end)

