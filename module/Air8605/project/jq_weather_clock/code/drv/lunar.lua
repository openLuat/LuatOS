--[[
@module  lunar
@summary 公历转农历（1900-2100）：闰月 / 大小月 / 干支 / 生肖，纯查表 + 算术
@version 1.0
@date    2026.11.08

=== 为什么自己算，不用库 ===
LuatOS 没有农历库，而农历不能按"固定 29.5 天"近似 —— 朔望月是天文量，
每年的大小月和闰月都是历书定死的，只能查表。本模块用通行的 1900-2100
压缩表（每年一个 32 位数），算一个日期是几十次整数运算，比联网查快得多。

=== 数据位含义（每年一个数 info）===
  bit0-3   闰月月份，0 = 该年无闰月
  bit4-15  正月..十二月 的大小，1 = 30 天，0 = 29 天（0x8000 是正月）
  bit16    闰月天数，1 = 30 天，0 = 29 天（无闰月时无效）

=== 基准 ===
1900-01-31 是农历 1900 年正月初一。相差天数 = 公历日差，然后按年、按月扣减。

=== 用法 ===
local lunar = require "lunar"
local L = lunar.solar2lunar(2026, 11, 8)
-- L.text     = "农历九月二十"
-- L.gz_year  = "丙午年"
-- L.zodiac   = "马"
]]

local M = {}

-- 1900..2100 每年一个压缩数
local NLDATA = {
    0x04bd8, 0x04ae0, 0x0a570, 0x054d5, 0x0d260, 0x0d950, 0x16554, 0x056a0, 0x09ad0, 0x055d2, -- 1900
    0x04ae0, 0x0a5b6, 0x0a4d0, 0x0d250, 0x1d255, 0x0b540, 0x0d6a0, 0x0ada2, 0x095b0, 0x14977, -- 1910
    0x04970, 0x0a4b0, 0x0b4b5, 0x06a50, 0x06d40, 0x1ab54, 0x02b60, 0x09570, 0x052f2, 0x04970, -- 1920
    0x06566, 0x0d4a0, 0x0ea50, 0x06e95, 0x05ad0, 0x02b60, 0x186e3, 0x092e0, 0x1c8d7, 0x0c950, -- 1930
    0x0d4a0, 0x1d8a6, 0x0b550, 0x056a0, 0x1a5b4, 0x025d0, 0x092d0, 0x0d2b2, 0x0a950, 0x0b557, -- 1940
    0x06ca0, 0x0b550, 0x15355, 0x04da0, 0x0a5b0, 0x14573, 0x052b0, 0x0a9a8, 0x0e950, 0x06aa0, -- 1950
    0x0aea6, 0x0ab50, 0x04b60, 0x0aae4, 0x0a570, 0x05260, 0x0f263, 0x0d950, 0x05b57, 0x056a0, -- 1960
    0x096d0, 0x04dd5, 0x04ad0, 0x0a4d0, 0x0d4d4, 0x0d250, 0x0d558, 0x0b540, 0x0b6a0, 0x195a6, -- 1970
    0x095b0, 0x049b0, 0x0a974, 0x0a4b0, 0x0b27a, 0x06a50, 0x06d40, 0x0af46, 0x0ab60, 0x09570, -- 1980
    0x04af5, 0x04970, 0x064b0, 0x074a3, 0x0ea50, 0x06b58, 0x055c0, 0x0ab60, 0x096d5, 0x092e0, -- 1990
    0x0c960, 0x0d954, 0x0d4a0, 0x0da50, 0x07552, 0x056a0, 0x0abb7, 0x025d0, 0x092d0, 0x0cab5, -- 2000
    0x0a950, 0x0b4a0, 0x0baa4, 0x0ad50, 0x055d9, 0x04ba0, 0x0a5b0, 0x15176, 0x052b0, 0x0a930, -- 2010
    0x07954, 0x06aa0, 0x0ad50, 0x05b52, 0x04b60, 0x0a6e6, 0x0a4e0, 0x0d260, 0x0ea65, 0x0d530, -- 2020
    0x05aa0, 0x076a3, 0x096d0, 0x04afb, 0x04ad0, 0x0a4d0, 0x1d0b6, 0x0d250, 0x0d520, 0x0dd45, -- 2030
    0x0b5a0, 0x056d0, 0x055b2, 0x049b0, 0x0a577, 0x0a4b0, 0x0aa50, 0x1b255, 0x06d20, 0x0ada0, -- 2040
    0x14b63, 0x09370, 0x049f8, 0x04970, 0x064b0, 0x168a6, 0x0ea50, 0x06b20, 0x1a6c4, 0x0aae0, -- 2050
    0x0a2e0, 0x0d2e3, 0x0c960, 0x0d557, 0x0d4a0, 0x0da50, 0x05d55, 0x056a0, 0x0a6d0, 0x055d4, -- 2060
    0x052d0, 0x0a9b8, 0x0a950, 0x0b4a0, 0x0b6a6, 0x0ad50, 0x055a0, 0x0aba4, 0x0a5b0, 0x052b0, -- 2070
    0x0b273, 0x06930, 0x07337, 0x06aa0, 0x0ad50, 0x14b55, 0x04b60, 0x0a570, 0x054e4, 0x0d160, -- 2080
    0x0e968, 0x0d520, 0x0daa0, 0x16aa6, 0x056d0, 0x04ae0, 0x0a9d4, 0x0a2d0, 0x0d150, 0x0f252, -- 2090
    0x0d520, -- 2100
}

local BASE_YEAR = 1900

local MONTH_CN = { "正", "二", "三", "四", "五", "六", "七", "八", "九", "十", "冬", "腊" }
local DAY_CN = { "一", "二", "三", "四", "五", "六", "七", "八", "九", "十" }
local GAN = { "甲", "乙", "丙", "丁", "戊", "己", "庚", "辛", "壬", "癸" }
local ZHI = { "子", "丑", "寅", "卯", "辰", "巳", "午", "未", "申", "酉", "戌", "亥" }
local ZODIAC = { "鼠", "牛", "虎", "兔", "龙", "蛇", "马", "羊", "猴", "鸡", "狗", "猪" }

local function info_of(y) return NLDATA[y - BASE_YEAR + 1] end

local function leap_month(y) return info_of(y) & 0xf end

local function leap_days(y)
    if leap_month(y) == 0 then return 0 end
    return (info_of(y) & 0x10000) ~= 0 and 30 or 29
end

--- 农历 y 年 m 月（不含闰月）的天数
local function month_days(y, m)
    return (info_of(y) & (0x10000 >> m)) ~= 0 and 30 or 29
end

--- 农历 y 年的总天数
local function year_days(y)
    local sum, info, b = 348, info_of(y), 0x8000
    while b >= 0x10 do
        if (info & b) ~= 0 then sum = sum + 1 end
        b = b >> 1
    end
    return sum + leap_days(y)
end

--[[公历 → 距 1970-01-01 的天数（纯整数算术）

不能用 os.time({year=1900}) 求日差：1900 年的时间戳是负数（约 -2.2e9），
32 位 time_t 直接报 "time result cannot be represented"，PC 和嵌入式都中招。
这里用 Howard Hinnant 的 civil calendar 反算，不受时区/夏令时/位宽影响。
]]
local function day_no(y, m, d)
    local yy = y
    if m <= 2 then yy = yy - 1 end
    local era = math.floor(yy / 400)
    local yoe = yy - era * 400                        -- [0, 399]
    local doy = math.floor((153 * ((m + 9) % 12) + 2) / 5) + d - 1
    local doe = yoe * 365 + math.floor(yoe / 4) - math.floor(yoe / 100) + doy
    return era * 146097 + doe - 719468
end

local function day_str(d)
    if d <= 10 then return "初" .. DAY_CN[d] end
    if d < 20 then return "十" .. DAY_CN[d - 10] end
    if d == 20 then return "二十" end
    if d < 30 then return "廿" .. DAY_CN[d - 20] end
    return "三十"
end

--[[公历 → 农历
@param y number 公历年
@param m number 公历月 1-12
@param d number 公历日
@return table|nil 超出 1900-2100 返回 nil
    { year, month, day, is_leap, text, gz_year, zodiac }
]]
function M.solar2lunar(y, m, d)
    if not (y and m and d) then return nil end
    if y < BASE_YEAR or y > 2100 then return nil end

    local offset = day_no(y, m, d) - day_no(BASE_YEAR, 1, 31)
    if offset < 0 then return nil end

    -- 扣年
    local ly = BASE_YEAR
    while ly <= 2100 do
        local yd = year_days(ly)
        if offset < yd then break end
        offset = offset - yd
        ly = ly + 1
    end

    -- 扣月（正常月走完，若该月是闰月则再走一个闰月）
    local lm, is_leap = 1, false
    local leap = leap_month(ly)
    while true do
        local md = is_leap and leap_days(ly) or month_days(ly, lm)
        if offset < md then break end
        offset = offset - md
        if is_leap then
            is_leap = false
            lm = lm + 1
        elseif leap > 0 and lm == leap then
            is_leap = true
        else
            lm = lm + 1
        end
    end

    local ld = offset + 1
    local gz = (ly - 4) % 60

    return {
        year = ly,
        month = lm,
        day = ld,
        is_leap = is_leap,
        text = "农历" .. (is_leap and "闰" or "") .. MONTH_CN[lm] .. "月" .. day_str(ld),
        gz_year = GAN[gz % 10 + 1] .. ZHI[gz % 12 + 1] .. "年",
        zodiac = ZODIAC[gz % 12 + 1],
    }
end

return M
