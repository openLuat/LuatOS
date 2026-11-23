--[[
@module  settings_time_app
@summary 系统时间校准业务逻辑层
@version 1.0
@date    2026.10.22
@author  江访
@usage
本模块为系统时间校准业务逻辑层，提供系统时间读取、时间字段校验与写入系统时钟。
写入路径为 rtc.set(Unix 时间戳)，写入后由 status_provider_app 的秒定时器刷新桌面时钟。

消息协议（订阅/发布）:
订阅: TIME_GET                            → 查询当前系统时间
订阅: TIME_SET(year,mon,day,hour,min,sec) → 校验并写入系统时钟
发布: TIME_VALUE(t)                       → 当前时间 { year,mon,day,hour,min,sec }
发布: TIME_CHANGED(ts)                    → 时间写入成功，携带 Unix 时间戳
发布: TIME_SET_RESULT(ok, err)            → 写入结果，ok=false 时 err 为错误原因
]]

-- 时间字段合法区间（超出按非法处理，回发 TIME_SET_RESULT）
local LIMITS = {
    year = { 2000, 2099 },
    mon  = { 1, 12 },
    day  = { 1, 31 },
    hour = { 0, 23 },
    min  = { 0, 59 },
    sec  = { 0, 59 },
}

-- 时间字段中文名（用于错误提示）
local FIELD_CN = {
    year = "年", mon = "月", day = "日", hour = "时", min = "分", sec = "秒",
}

--[[
@function check_fields
@summary 校验时间字段的类型与取值区间
@param year 年
@param mon 月
@param day 日
@param hour 时
@param min 分
@param sec 秒
@return boolean true=合法
@return string 非法原因
]]
local function check_fields(year, mon, day, hour, min, sec)
    local args = {
        { "year", year }, { "mon", mon }, { "day", day },
        { "hour", hour }, { "min", min }, { "sec", sec },
    }
    for _, a in ipairs(args) do
        local name, v = a[1], a[2]
        if type(v) ~= "number" then
            return false, FIELD_CN[name] .. "不是数字"
        end
        local lim = LIMITS[name]
        if v < lim[1] or v > lim[2] then
            return false, string.format("%s应在%d-%d之间", FIELD_CN[name], lim[1], lim[2])
        end
    end
    return true
end

--[[
@function get_time
@summary 读取当前系统时间
@return table { year,mon,day,hour,min,sec }
]]
local function get_time()
    local t = os.date("*t")
    return {
        year = t.year, mon = t.month, day = t.day,
        hour = t.hour, min = t.min, sec = t.sec,
    }
end

--[[
@function days_in_month
@summary 取某年某月的天数（2 月按平闰年算）
@param year 年
@param mon 月
@return number 天数
]]
local function days_in_month(year, mon)
    if mon == 2 then
        local leap = (year % 4 == 0 and year % 100 ~= 0) or (year % 400 == 0)
        return leap and 29 or 28
    end
    if mon == 4 or mon == 6 or mon == 9 or mon == 11 then
        return 30
    end
    return 31
end

--[[
@function tz_bias
@summary 量出 os.time 与 os.date 之间的时区折算差值
@return number 差值（秒）

os.date("*t", t) 显示的是 t 加上 RTC 时区偏移后的时刻，
而 os.time(t) 按 mktime 的本地域折算，固件上两者不对称。
用当前时刻量出差值，写入时反向补偿，保证 os.date 显示的就是用户输入的钟面时间。
]]
local function tz_bias()
    local ok, bias = pcall(function()
        local now = tonumber(os.time())
        local shown = os.date("*t", now)
        local back = os.time({
            year = shown.year, month = shown.month, day = shown.day,
            hour = shown.hour, min = shown.min, sec = shown.sec,
        })
        return tonumber(back) - now
    end)
    if ok and type(bias) == "number" then return bias end
    return 0
end

--[[
@function set_time
@summary 校验时间字段并写入系统时钟
@param year 年
@param mon 月
@param day 日
@param hour 时
@param min 分
@param sec 秒
@return boolean true=写入成功
@return string 失败原因
]]
local function set_time(year, mon, day, hour, min, sec)
    local ok, err = check_fields(year, mon, day, hour, min, sec)
    if not ok then
        return false, err
    end

    -- 日期合法性按日历直接判定（2 月 30 日这类会在 os.time 里被归一化掉，不能靠回读比对）
    local dim = days_in_month(year, mon)
    if day > dim then
        return false, string.format("%d年%d月只有%d天", year, mon, dim)
    end

    local ok_t, ts = pcall(os.time, {
        year = year, month = mon, day = day, hour = hour, min = min, sec = sec,
    })
    if not ok_t or not ts then
        return false, "时间参数无法转换"
    end

    -- 时间戳取整后写入系统时钟（rtc.set 只收整数）
    ts = ts - tz_bias()
    local ts_int = math.tointeger and math.tointeger(ts) or math.floor(ts)
    if not ts_int then
        return false, "时间参数无法转换"
    end

    if not rtc.set(ts_int) then
        return false, "系统时钟写入失败"
    end
    log.info("settings_time", "系统时间已设置:", os.date("%Y-%m-%d %H:%M:%S", ts_int))
    sys.publish("TIME_CHANGED", ts_int)
    return true
end

-- ==================== 事件订阅 ====================
-- 订阅时间查询事件（业务层上报当前时间）
sys.subscribe("TIME_GET", function()
    sys.publish("TIME_VALUE", get_time())
end)

-- 订阅时间设置事件（校验通过后写入系统时钟，失败回发原因）
sys.subscribe("TIME_SET", function(year, mon, day, hour, min, sec)
    local ok, err = set_time(year, mon, day, hour, min, sec)
    if not ok then
        log.warn("settings_time", "时间设置失败:", err)
    end
    sys.publish("TIME_SET_RESULT", ok, err)
end)

-- ==================== 模块导出 ====================
local M = {}
M.get_time = get_time
M.set_time = set_time
return M
