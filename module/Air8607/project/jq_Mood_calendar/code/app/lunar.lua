--[[
@module  lunar
@summary 公历转农历 + 传统节日 / 法定节假日（纯 Lua，无依赖）
@author  蒋骞
@version 1.0
@date    2026.10.30

=== 覆盖范围 ===
农历数据表覆盖 2020-2040 共 21 年，超出范围返回 nil（格子第二行就不显示农历）。
表是标准 lunarInfo 编码，每年的值都用「闰月月份」和「春节公历日期」交叉验证过。

=== 编码规则（标准 lunarInfo）===
  bit0-3   闰月月份，0 表示无闰月
  bit4-15  12 个月的大小，bit4 = 正月 ... bit15 = 十二月，1 = 大月 30 天，0 = 小月 29 天
  bit16    闰月的天数，1 = 30 天，0 = 29 天

=== 对外接口 ===
lunar.cell_text(y, m, d)      -> 格子第二行文字, 是否节日
                                 节日那天返回 "国庆" 之类；初一回 "九月"（月名），平时回 "廿三"
lunar.full(y, m, d)           -> "农历九月廿一"（顶栏副标题用）
lunar.solar(y, m, d)          -> {year=农历年, month=农历月, day=农历日, leap=是否闰月, mdays=该月天数}
lunar.day_name(d)             -> "初一" .. "三十"
lunar.month_name(m)           -> "正月" .. "腊月"（十一月冬月、十二月腊月）
]]

local M = {}

--[[农历数据 2020-2040
闰月已逐年核对：2020 闰四月、2023 闰二月、2025 闰六月、2028 闰五月、
2031 闰三月、2033 闰十一月（著名的「2033 问题」）、2036 闰六月、2039 闰五月。
]]
local INFO = {
    [2020] = 0x07954, [2021] = 0x06aa0, [2022] = 0x0ad50,
    [2023] = 0x05b52, [2024] = 0x04b60, [2025] = 0x0a6e6,
    [2026] = 0x0a4e0, [2027] = 0x0d260, [2028] = 0x0ea65,
    [2029] = 0x0d530, [2030] = 0x05aa0, [2031] = 0x076a3,
    [2032] = 0x096d0, [2033] = 0x04afb, [2034] = 0x04ad0,
    [2035] = 0x0a4d0, [2036] = 0x1d0b6, [2037] = 0x0d250,
    [2038] = 0x0d520, [2039] = 0x0dd45, [2040] = 0x0b5a0,
}

local MIN_Y, MAX_Y = 2020, 2040

-- ==================== 公历 -> 儒略日 ====================
local function jd(y, m, d)
    local a = math.floor((14 - m) / 12)
    local yy = y + 4800 - a
    local mm = m + 12 * a - 3
    return d + math.floor((153 * mm + 2) / 5) + 365 * yy
        + math.floor(yy / 4) - math.floor(yy / 100) + math.floor(yy / 400) - 32045
end

-- 2020-01-25 是农历 2020 年正月初一，作为累计基准
local BASE = jd(2020, 1, 25)

-- ==================== 农历月/年天数 ====================
local function leap_month(y)
    return INFO[y] % 16
end

local function leap_days(y)
    if leap_month(y) == 0 then return 0 end
    return (math.floor(INFO[y] / 0x10000) % 2 == 1) and 30 or 29
end

-- 正月对应 0x8000，二月 0x4000 ... 十二月 0x10
local function month_days(y, m)
    local bit = 0x10000 / (2 ^ m)
    return (math.floor(INFO[y] / bit) % 2 == 1) and 30 or 29
end

local function year_days(y)
    local sum = 348                     -- 12 个月全当 29 天
    for m = 1, 12 do
        if month_days(y, m) == 30 then sum = sum + 1 end
    end
    return sum + leap_days(y)
end

-- ==================== 农历日名 ====================
local NUM = { "一", "二", "三", "四", "五", "六", "七", "八", "九", "十" }

local DAY_CN = {}
for i = 1, 30 do
    if i <= 10 then
        DAY_CN[i] = "初" .. NUM[i]
    elseif i < 20 then
        DAY_CN[i] = "十" .. NUM[i - 10]
    elseif i == 20 then
        DAY_CN[i] = "二十"
    elseif i < 30 then
        DAY_CN[i] = "廿" .. NUM[i - 20]
    else
        DAY_CN[i] = "三十"
    end
end

function M.day_name(d)
    return DAY_CN[d] or ""
end

-- 十一月叫冬月、十二月叫腊月，是农历的习惯叫法
local MONTH_CN = {
    "正月", "二月", "三月", "四月", "五月", "六月",
    "七月", "八月", "九月", "十月", "冬月", "腊月",
}

function M.month_name(m)
    return MONTH_CN[m] or ""
end

-- ==================== 公历 -> 农历 ====================
--[[把公历日期换成农历
@return table|nil {year, month, day, leap, mdays}；超出数据范围返回 nil
]]
function M.solar(y, m, d)
    if not INFO[y] then return nil end

    local offset = jd(y, m, d) - BASE
    if offset < 0 then return nil end

    -- 先扣掉整年的天数，定位农历年
    local ly = MIN_Y
    while true do
        local yd = year_days(ly)
        if offset < yd then break end
        offset = offset - yd
        ly = ly + 1
        if not INFO[ly] then return nil end
    end

    --[[再扣掉整月的天数，定位农历月
    闰月插在 leap 月之后、leap+1 月之前：轮到 i == leap+1 时先处理闰月，
    处理完 i 不前进，下一轮再用同一个 i 处理正常的 leap+1 月。
    （早期版本的坑：闰月处理完顺手 i+1，会把 leap+1 那个整月直接跳过，
      导致闰月年之后的所有日期整体偏移一个月。）
    ]]
    local leap = leap_month(ly)
    local done_leap = false
    local i = 1
    while i <= 12 do
        local cur_m, cur_leap, md
        if leap > 0 and i == leap + 1 and not done_leap then
            cur_m, cur_leap, md = leap, true, leap_days(ly)
        else
            cur_m, cur_leap, md = i, false, month_days(ly, i)
        end

        if offset < md then
            return {
                year = ly, month = cur_m, day = offset + 1,
                leap = cur_leap, mdays = md,
            }
        end

        offset = offset - md
        if cur_leap then
            done_leap = true      -- 闰月已吃掉，i 不递增，下一轮处理正常月
        else
            i = i + 1
        end
    end
    return nil
end

-- ==================== 节日 ====================
-- 公历固定节日（法定）
local SOLAR_FEST = {
    ["1-1"]  = "元旦",
    ["5-1"]  = "劳动",
    ["10-1"] = "国庆",
}

-- 农历节日：正月初一春节、正月十五元宵、五月初五端午、八月十五中秋、
-- 九月初九重阳、腊月初八腊八（除夕单独判断：腊月最后一天）
local LUNAR_FEST = {
    ["1-1"]  = "春节",
    ["1-15"] = "元宵",
    ["5-5"]  = "端午",
    ["8-15"] = "中秋",
    ["9-9"]  = "重阳",
    ["12-8"] = "腊八",
}

--[[清明：太阳黄经 15°，21 世纪通用近似式
[Y*0.2422+4.81] - [Y/4]，Y 是年份后两位
2024 -> 4/4、2025 -> 4/4、2026 -> 4/5、2027 -> 4/5
]]
local function qingming_day(y)
    local yy = y % 100
    return math.floor(yy * 0.2422 + 4.81) - math.floor(yy / 4)
end

--[[取某个公历日期的节日名，没有返回 nil]]
function M.festival(y, m, d)
    local f = SOLAR_FEST[m .. "-" .. d]
    if f then return f end

    if m == 4 and d == qingming_day(y) then return "清明" end

    local l = M.solar(y, m, d)
    if not l or l.leap then return nil end       -- 闰月不重复过节

    f = LUNAR_FEST[l.month .. "-" .. l.day]
    if f then return f end

    -- 除夕：腊月最后一天（可能是廿九，也可能是三十）
    if l.month == 12 and l.day == l.mdays then return "除夕" end

    return nil
end

-- ==================== 格子第二行文字（带缓存）====================
local cache = {}
local cache_n = 0

--[[日历格子第二行要显示的东西
节日那天返回节日名；农历初一无「初一」可看，改显示月名（九月 / 闰四月），
让人一眼知道这是几月开头；其余日子显示日名（廿三）。
@return string 文字（节日名 / 月名 / 农历日 / 空串）
@return boolean 是否节日
]]
function M.cell_text(y, m, d)
    local k = y * 10000 + m * 100 + d
    local hit = cache[k]
    if hit then return hit[1], hit[2] end

    local txt, fest
    local f = M.festival(y, m, d)
    if f then
        txt, fest = f, true
    else
        local l = M.solar(y, m, d)
        if l then
            if l.day == 1 then
                txt = M.month_name(l.month)          -- 初一 -> 显示「九月」而不是「初一」
            else
                txt = M.day_name(l.day)
            end
            if l.leap then txt = "闰" .. txt end
            fest = false
        else
            txt, fest = "", false
        end
    end

    -- 缓存不限具体天数，超过 800 条（约两年）就整体清掉，避免长跑吃内存
    if cache_n > 800 then
        cache = {}
        cache_n = 0
    end
    cache[k] = { txt, fest }
    cache_n = cache_n + 1

    return txt, fest
end

--[[完整农历写法，给顶栏副标题用
@return string 形如 "农历九月廿一"；节日再补一句 "农历八月十五  中秋"；超出范围返回 ""
]]
function M.full(y, m, d)
    local l = M.solar(y, m, d)
    if not l then return "" end
    local s = "农历" .. (l.leap and "闰" or "") .. M.month_name(l.month) .. M.day_name(l.day)
    local f = M.festival(y, m, d)
    if f then s = s .. "  " .. f end
    return s
end

return M
