--[[
@module  dash_data
@summary 86盒深色部件仪表盘的数据层，时刻日期、月历、音乐与家庭配件
@version 1.0
@date    2026.11.04
@author  江访
@usage
本文件为86盒深色部件仪表盘的数据层，核心业务逻辑为：
1、时刻取设备的os.date，设备没有RTC或时钟没同步时退回固定演示时刻；
2、时间、日期里的星期与月、日数字都由本文件格式化好再交给部件，部件不自己拼字符串；
3、月历不调os.time，只用今天的日和星期倒推1号是星期几，再按平闰年算当月天数；
4、音乐和家庭配件是写死的展示数据，接真机时换成本文件里的表即可；

本文件的对外接口有9个：
1、dash_data.WEEK_NAME：星期中文名表
2、dash_data.WEEK_SHORT_NAME：星期简称表
3、dash_data.MONTH_NAME：月份中文名表
4、dash_data.MUSIC：音乐展示数据
5、dash_data.HOME_LIST：家庭配件展示数据
6、dash_data.get_clock_text()：取表盘时间文字
7、dash_data.get_date_text()：取日期里的星期与月
8、dash_data.get_day_text()：取日期里的日数字
9、dash_data.get_month_grid()：取当月月历

更多说明参考本目录下的readme.md文件
]]

local dash_data = {}

-- ==================== 展示数据 ====================

-- 星期中文名，下标与os.date的wday一致，1是周日、7是周六
dash_data.WEEK_NAME = {
    "周日", "周一", "周二", "周三", "周四", "周五", "周六",
}

-- 星期简称，月历顶上那行表头用，一个字占一格
dash_data.WEEK_SHORT_NAME = {
    "日", "一", "二", "三", "四", "五", "六",
}

-- 月份中文名，下标即月份数
dash_data.MONTH_NAME = {
    "1月", "2月", "3月", "4月", "5月", "6月",
    "7月", "8月", "9月", "10月", "11月", "12月",
}

-- 音乐展示数据
-- title：歌名
-- artist：歌手
-- playing：是否正在播放
dash_data.MUSIC = {
    title = "Danceteria Afterhours",
    artist = "Madretron & Charli xcx",
    playing = true,
}

-- 家庭配件展示数据，最多3个，正好铺满家庭部件的三行
-- name：配件名
-- icon：配件类型标识，取light、ac、curtain、plug、sensor、lock
-- on：开关状态，true为开启
dash_data.HOME_LIST = {
    { name = "主灯", icon = "light", on = true },
    { name = "空调", icon = "ac", on = true },
    { name = "窗帘", icon = "curtain", on = false },
}

-- 固定演示时刻，设备没有RTC时用它兜底
local DEMO_NOW = { year = 2026, month = 11, day = 4, wday = 4, hour = 21, min = 41 }

-- 每月天数，二月按平年写，闰年由is_leap_year补一天
local MONTH_DAY_LIST = { 31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31 }

-- ==================== 内部函数 ====================

--[[
判闰年；
能被400整除是闰年，能被100整除不是闰年，其余能被4整除是闰年；

@function (内部函数) is_leap_year

@number year
年份；

@return boolean
是闰年返回true，否则返回false
]]
local function is_leap_year(year)
    if year % 400 == 0 then
        return true
    end
    if year % 100 == 0 then
        return false
    end
    return year % 4 == 0
end

--[[
取某个月的天数；
二月在闰年是29天，其余月份查表；

@function (内部函数) get_month_day_count

@number year
年份；

@number month
月份，1到12；

@return number
天数
]]
local function get_month_day_count(year, month)
    if month == 2 and is_leap_year(year) then
        return 29
    end
    return MONTH_DAY_LIST[month]
end

--[[
取当前时刻；
只调不带参数的os.date取本机时间，不碰带时间戳的os.date和os.time，
避开时区换算的坑；年份明显不对说明设备还没同步时间，退回固定演示时刻；

@function (内部函数) get_now

@return table
时刻表，字段有year、month、day、wday、hour、min
]]
local function get_now()
    local now_table = os.date("*t")
    if now_table == nil or now_table.year == nil or now_table.year < 2024 then
        return DEMO_NOW
    end
    return now_table
end

-- ==================== 对外接口 ====================

--[[
取表盘时间文字；
24小时制，小时和分钟都补足两位；

@api dash_data.get_clock_text()

@return string
时间文字，形如"21:41"

@usage
local clock_text = dash_data.get_clock_text()
]]
function dash_data.get_clock_text()
    local now_table = get_now()
    return string.format("%02d:%02d", now_table.hour, now_table.min)
end

--[[
取日期里的星期与月；
格式是"周三 · 11月"；

@api dash_data.get_date_text()

@return string
星期与月的文字

@usage
local date_text = dash_data.get_date_text()
]]
function dash_data.get_date_text()
    local now_table = get_now()
    return string.format("%s · %s",
        dash_data.WEEK_NAME[now_table.wday], dash_data.MONTH_NAME[now_table.month])
end

--[[
取日期里的日数字；
单独一个函数是因为这块日数字要放到72的大字号上显示；

@api dash_data.get_day_text()

@return string
日数字，形如"4"

@usage
local day_text = dash_data.get_day_text()
]]
function dash_data.get_day_text()
    local now_table = get_now()
    return tostring(now_table.day)
end

--[[
取当月月历；
1号是星期几由今天的日和星期倒推，不调os.time；
返回表的字段：
year：年份
month：月份
first_wday：1号是星期几，1是周日、7是周六
day_count：当月天数
today_day：今天是几号，月历上标高亮用

@api dash_data.get_month_grid()

@return table
当月月历数据

@usage
local grid = dash_data.get_month_grid()
]]
function dash_data.get_month_grid()
    local now_table = get_now()
    -- 今天是本月第day号、星期wday，往前推day-1天就是1号的星期
    local first_wday = (now_table.wday - 1 - (now_table.day - 1)) % 7 + 1
    return {
        year = now_table.year,
        month = now_table.month,
        first_wday = first_wday,
        day_count = get_month_day_count(now_table.year, now_table.month),
        today_day = now_table.day,
    }
end

return dash_data
