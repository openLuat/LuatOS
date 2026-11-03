--[[
@module  rtc_util
@summary 时间读取 + 上电自动校准 RTC（烧录当天 = 今天）
@author  蒋骞
@version 1.1
@date    2026.10.30

=== 本机没有 4G / WiFi ===
无法 SNTP 授时，时间只能来自本地 RTC；而 RTC 断电 / 首次上电时是无效值，
日历就会显示成 1970 或者上次的时间。所以启动时把 RTC 拉正，时间基准按优先级取：

  1、烧录戳        app/build_stamp.lua 里的 stamp
                  由 tools/更新烧录时间.bat 在烧录前写入「当前电脑时间」，最准
  2、固件编译日期   rtos.buildDate()，形如 "Oct 30 2026"
                  注意这是「固件」的编译日，合宙官方固件往往是几个月前编的，只作兜底
  3、RTC 自身      上面两个都拿不到时，RTC 是多少就是多少

M.calibrate() 的判断（基准 = 上面选出来的那个时间）：
  RTC 年份 < conf.rtc.valid_year（默认 2020）  -> RTC 没初始化，按基准校准
  RTC 日期 < 基准日期                          -> 落后了，按基准校准
  其它                                        -> RTC 是对的，不动它
想每次上电都强制按基准重置，把 conf.rtc.force_calibrate 设成 true。

=== 基准年 / 时区 ===
rtc.setBaseYear(1900) —— 不设，时间戳换算基准不对
rtc.timezone(32)      —— 合宙时区单位是 15 分钟，东八区 8h = 32；不设，本地时间差 8 小时
rtc.set 传的是 UTC 时间戳，这里统一走 os.time()，让时区换算只在一处发生。
]]
local conf = require "conf"
local build_stamp = require "build_stamp"

local M = {}

local rtc_lib = nil

-- __DATE__ 的月份是英文缩写
local MONTH_NUM = {
    Jan = 1, Feb = 2, Mar = 3, Apr = 4, May = 5, Jun = 6,
    Jul = 7, Aug = 8, Sep = 9, Oct = 10, Nov = 11, Dec = 12,
}

--[[探测 rtc 库（全局核心库，无需 require）
注意：LuatOS 的库有的是 rotable，type() 返回的是 userdata 而不是 table，
所以这里只判「非 nil 且有 set 方法」，绝不能用 type(x) == "table" 去卡，
否则会把明明存在的 rtc 误判成不存在。
]]
local function detect_rtc()
    local ok, has = pcall(function()
        return rtc ~= nil and type(rtc.set) == "function"
    end)
    if ok and has then return rtc end
    return nil
end

--[[解析固件编译日期，返回 {year=, month=, day=, hour=8, min=0, sec=0}；拿不到返回 nil
C 的 __DATE__ 格式是 "Mmm dd yyyy"，日不足两位时前面补空格（如 "Oct  3 2026"），
所以用 %s+ 吃掉所有空白。
]]
local function build_date()
    if rtos == nil or type(rtos.buildDate) ~= "function" then return nil end
    local ok, s = pcall(rtos.buildDate)
    if not ok or type(s) ~= "string" then return nil end
    local mon, day, year = s:match("(%a+)%s+(%d+)%s+(%d+)")
    if not mon then return nil end
    local m = MONTH_NUM[mon]
    if not m then return nil end
    -- 固件编译日只知道日期，钟点用配置里的上午时刻，避开 0 点跨时区把日期算到前一天
    return {
        year = tonumber(year), month = m, day = tonumber(day),
        hour = conf.rtc.build_hour, min = 0, sec = 0,
    }
end

--[[解析烧录戳，支持 "2026-10-30 14:05:00" / "2026-10-30 14:05" / "2026-10-30"
解析不出返回 nil
]]
local function parse_stamp(s)
    if type(s) ~= "string" or s == "" then return nil end
    local y, mo, d, h, mi, se = s:match("(%d+)%-(%d+)%-(%d+)[ T](%d+):(%d+):(%d+)")
    if not y then
        y, mo, d, h, mi, se = s:match("(%d+)%-(%d+)%-(%d+)[ T](%d+):(%d+)")
    end
    if not y then
        y, mo, d = s:match("(%d+)%-(%d+)%-(%d+)")
        h, mi, se = conf.rtc.build_hour, 0, 0
    end
    if not y then return nil end
    y, mo, d = tonumber(y), tonumber(mo), tonumber(d)
    if not y or y < 2020 or mo < 1 or mo > 12 or d < 1 or d > 31 then return nil end
    return { year = y, month = mo, day = d, hour = tonumber(h), min = tonumber(mi), sec = tonumber(se) }
end

local function key_of(t)
    return t.year * 10000 + t.month * 100 + t.day
end

local function fmt(t)
    return string.format("%04d-%02d-%02d %02d:%02d:%02d", t.year, t.month, t.day, t.hour, t.min, t.sec)
end

local function is_pc()
    local ok, bsp = pcall(rtos.bsp)
    return ok and bsp == "PC"
end

--[[选时间基准：烧录戳 > 固件编译日期，返回 目标时间表 和 来源说明]]
local function pick_base()
    local st = parse_stamp(build_stamp.stamp)
    local bd = build_date()
    if st and bd and key_of(bd) > key_of(st) then
        return bd, "固件编译日期"
    end
    if st then return st, "烧录戳" end
    if bd then return bd, "固件编译日期" end
    return nil, nil
end

--[[初始化：设置 RTC 基准年与时区]]
function M.init()
    rtc_lib = detect_rtc()
    log.info("rtc_util", "rtc 探测", "type(rtc) =", type(rtc), "可用 =", tostring(rtc_lib ~= nil))
    if rtc_lib then
        pcall(rtc_lib.setBaseYear, conf.rtc.base_year)
        pcall(rtc_lib.timezone, conf.rtc.timezone)
        return "rtc"
    end
    log.warn("rtc_util", "固件无 rtc 库：时间只能读，不能写入")
    return "none"
end

--[[校准 RTC
返回 true 表示「这次真的写了 RTC」，false 表示没动。
]]
function M.calibrate()
    rtc_lib = rtc_lib or detect_rtc()

    local base, from = pick_base()
    if base then
        log.info("rtc_util", "时间基准 =", from, fmt(base))
    else
        log.warn("rtc_util", "既没有烧录戳也没有固件编译日期（可先运行 tools/更新烧录时间.bat）")
    end

    -- PC 模拟器直接用电脑时间，绝不能去写（会改到系统时钟）
    if is_pc() then
        log.info("rtc_util", "PC 模拟器，使用电脑时间，跳过校时")
        return false
    end
    if not rtc_lib then return false end
    if not base then return false end

    local t = os.date("*t")
    local reason
    if conf.rtc.force_calibrate then
        reason = "配置要求强制校准"
    elseif t.year < conf.rtc.valid_year then
        reason = string.format("RTC 未初始化(%04d-%02d-%02d)", t.year, t.month, t.day)
    elseif key_of(t) < key_of(base) then
        reason = string.format("RTC(%04d-%02d-%02d) 早于%s", t.year, t.month, t.day, from)
    end

    if not reason then
        log.info("rtc_util", "RTC 正常，不校准", fmt(t))
        return false
    end

    -- os.time 内部走 mktime，嵌入式上把参数当 UTC 算（未减时区），
    -- 而 os.date("*t") 会 +时区偏移显示本地时间。两者不对称会让写入的
    -- 时间戳比正确值快「时区」小时，读回来就跨天（显示成明天）。
    -- 这里手动减掉时区偏移，让 rtc.set 拿到的是真正的 UTC 时间戳。
    local ts = os.time({
        year = base.year, month = base.month, day = base.day,
        hour = base.hour, min = base.min, sec = base.sec,
    })
    ts = ts - (conf.rtc.timezone // 4) * 3600
    local ok, ret = pcall(rtc_lib.set, ts)
    if not ok or ret == false or ret == nil then
        log.error("rtc_util", "校时失败", tostring(ret))
        return false
    end

    log.info("rtc_util", reason, "-> 已校准为", fmt(os.date("*t")))
    return true
end

--[[当前时间，返回 os.date 风格的日历表]]
function M.now()
    return os.date("*t")
end

return M
