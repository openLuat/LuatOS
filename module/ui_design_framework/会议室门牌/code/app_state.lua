--[[
@module  app_state
@summary 会议室门牌数据层（预约表 + 当前/下一场会议 + 冲突校验 + 会议室名/部门/管理员 + 演示数据）
@version 1.2.0
@usage
1、所有数据都是本地模拟，接真实后端时把 add / update / remove 换成 MQTT 或 HTTP 下发，
   UI 层不用改；
2、时间统一用「小数小时」表示（9.5 = 09:30），星期用 1~7 表示周一~周日；
3、时钟取自 clock 模块：硬件 RTC 优先，离线时可用设置页手动校准，
   全都没有时退回固定演示时间，界面不会出现 1970 年；
4、会议室名、部门名、手动校时基准都存 fskv，掉电重启后保持；
5、负责人 / 会议主题是自由文本（page_input 的词库键盘输入），条目结构：
   { day, start, dur, topic, dept, owner, ext, emp, pwd, seats }
   owner 是姓名字符串；人员名录来自 /luadb/staff.csv（缺失时退回内置 5 条），
   工号命中名录时 owner / ext 由名录带出，未命中按访客保存。
6、名录列序：工号,姓名,分机,部门,部门代号；部门按「名称」反查 M.depts，
   代号列只作人工阅读（CSV 的 1=总经办，与 M.depts 下标不是一套）。
]]
local clock = require "clock"

local M = {}

-- 会议室信息
M.room = { name = "A栋 801 会议室", sub = "12 座 · 支持投屏 · 视频会议", seats = 12,
           open_h = 8, close_h = 20 }

-- 会议室名称预设：门牌没有中文输入法，改成「从预设里挑一个」，靠管理员密码保护
M.room_names = {
    "A栋 801 会议室", "A栋 802 会议室", "A栋 803 会议室", "B栋 201 会议室",
    "B栋 202 会议室", "C栋 301 会议室", "8F 培训室", "3F 洽谈室",
}

-- 管理员密码：改会议室名称/部门、手动校时、删除任意预约都要这一步（默认 8888）
M.admin_pwd = "8888"

M.day_names = { "周一", "周二", "周三", "周四", "周五", "周六", "周日" }

-- 部门顺序必须与 ui_theme 的 dept 色板一一对应（1 研发 / 2 市场 / 3 人事 / 4 财务 / 5 总经办 / 6 客服）
-- 部门名存 fskv，颜色仍按下标取；改数量时必须同时改 ui_theme 的 dept 色板
M.depts = { "研发部", "市场部", "人事部", "财务部", "总经办", "客服部" }

-- 负责人名录：内置兜底 5 条，/luadb/staff.csv 存在时会被 load_staff() 整体覆盖
-- emp = 工号（与预约条目的 emp 同一体系），ext = 分机号，dept = M.depts 下标
M.owners = {
    { name = "张伟", emp = "2001", ext = "888200", dept = 1 },
    { name = "李娜", emp = "3001", ext = "888300", dept = 2 },
    { name = "赵敏", emp = "4001", ext = "888400", dept = 3 },
    { name = "王强", emp = "5001", ext = "888500", dept = 4 },
    { name = "周总", emp = "1001", ext = "888100", dept = 5 },
}

-- 会议主题：只是输入页的常用词，用户可自由输入
M.topics = { "研发周会", "产品评审", "客户接待", "财务审计", "新人面试", "经营例会" }

M.durations = { 1, 2, 3 }                               -- 可选时长（小时）

M.bookings = {}                                         -- { day, start, dur, topic, dept, owner, ext, emp, pwd, seats }

-- 跨页回填：page_input 写 here，page_booking / page_setup 取走即清空
M.handoff = {}

-- 词库键盘的候选词（page_input 用；分页显示，可自由增删）
M.words = {
    name = { "张伟", "李娜", "赵敏", "王强", "周总", "陈静", "刘洋", "杨帆", "黄磊", "吴迪",
             "徐磊", "孙悦", "马超", "朱琳", "胡军", "郭涛", "何静", "高翔", "林峰", "罗敏",
             "郑凯", "梁静", "谢军", "宋佳", "唐磊", "许晴", "韩雪", "冯刚", "邓超", "曹阳",
             "彭飞", "董洁", "袁鸣", "蒋雯", "沈杰", "于洋", "程亮", "范斌", "苏航", "任杰" },
    dept = { "研发部", "市场部", "人事部", "财务部", "总经办", "运营部", "采购部", "客服部",
             "设计部", "技术部", "品质部", "行政部", "法务部", "培训部", "工程部", "供应链",
             "项目部", "销售部", "品牌部", "数据部" },
    topic = { "研发周会", "产品评审", "客户接待", "财务审计", "新人面试", "经营例会",
              "项目启动", "方案讨论", "复盘会", "培训", "面试", "洽谈", "签约", "评审",
              "汇报", "总结会", "需求评审", "设计评审", "上线评审", "供应商会议",
              "月度例会", "季度复盘", "技术分享", "产品规划", "预算评审", "安全评审",
              "验收会议", "路演", "头脑风暴", "站会" },
    ascii = { "A", "B", "C", "D", "E", "F", "G", "H", "I", "J", "K", "L", "M", "N", "O", "P",
              "Q", "R", "S", "T", "U", "V", "W", "X", "Y", "Z", "0", "1", "2", "3", "4", "5",
              "6", "7", "8", "9", "-", "_", ".", "@", " ", "(", ")", "#", "/", ":", "&", "%" },
}

-- ==================== 当前时间 ====================
-- 无 RTC 时的固定演示时间：2026-11-19（周四）10:20
local FALLBACK = { year = 2026, hour = 10, min = 20, day = 19, mon = 11, today = 4 }

M.synced = false
M.year = FALLBACK.year
M.hour, M.min = FALLBACK.hour, FALLBACK.min
M.today = FALLBACK.today
M.day, M.mon = FALLBACK.day, FALLBACK.mon
M.now_h = M.hour + M.min / 60

-- 刷新当前时间快照（页面每秒调用一次，只做数学，开销可忽略）
function M.refresh()
    local t = clock.epoch()
    if t then
        local d = os.date("*t", t)
        if d and d.hour then
            M.synced = true
            M.hour, M.min = d.hour, d.min
            M.day, M.mon = d.day, d.month
            M.year = d.year or FALLBACK.year
            -- os.date 的 wday：1 = 周日；门牌用 1 = 周一
            M.today = (d.wday == 1) and 7 or (d.wday - 1)
            M.now_h = M.hour + M.min / 60
            return M
        end
    end
    M.synced = false
    M.year = FALLBACK.year
    M.hour, M.min = FALLBACK.hour, FALLBACK.min
    M.day, M.mon, M.today = FALLBACK.day, FALLBACK.mon, FALLBACK.today
    M.now_h = M.hour + M.min / 60
    return M
end

-- 时钟文本 "HH:MM"
function M.clock_text()
    return string.format("%02d:%02d", M.hour, M.min)
end

-- 日期文本 "11-19 周四"（未对时加标记）
function M.date_text()
    local s = string.format("%02d-%02d %s", M.mon, M.day, M.day_names[M.today])
    if not M.synced then s = s .. " · 未对时" end
    return s
end

-- 某个星期在这一周的「日」号（跨月近似处理，够门牌用）
function M.day_of_month(day)
    local delta = day - M.today
    local t = clock.epoch()
    if t then
        local ok, s = pcall(os.date, "%d", t + delta * 86400)
        if ok and s then return tonumber(s) or M.day end
    end
    local d = M.day + delta
    while d < 1 do d = d + 30 end
    while d > 30 do d = d - 30 end
    return d
end

-- 由「年月日」算星期（1=周一），设置页预览用；算不出来就退回今天
function M.weekday_of(y, mo, d)
    local ok, ts = pcall(os.time, { year = y, month = mo, day = d, hour = 12, min = 0, sec = 0 })
    if not ok or not ts then return M.today end
    local ok2, wd = pcall(os.date, "%w", ts)
    local n = ok2 and tonumber(wd) or nil
    if not n then return M.today end
    return (n == 0) and 7 or n
end

-- ==================== 设置项 ====================
-- 会议室名称：存 fskv，重启后保持
local KEY_ROOM = "ui_room_name"

local function load_room_name()
    if not fskv then return end
    pcall(function()
        if fskv.init then fskv.init() end
        local n = fskv.get(KEY_ROOM)
        if type(n) == "string" and #n > 0 then
            M.room.name = n
            log.info("app_state", "读取会议室名称", n)
        end
    end)
end

function M.set_room_name(name)
    if type(name) ~= "string" or #name == 0 then return false end
    M.room.name = name
    if fskv then
        pcall(function()
            fskv.set(KEY_ROOM, name)
            log.info("app_state", "保存会议室名称", name)
        end)
    end
    return true
end

-- 预约部门：5 个名字存 fskv（"研发部|市场部|..."），颜色仍按下标取
local KEY_DEPT = "ui_depts"

local function load_depts()
    if not fskv then return end
    pcall(function()
        if fskv.init then fskv.init() end
        local s = fskv.get(KEY_DEPT)
        if type(s) ~= "string" or #s == 0 then return end
        local list, n = {}, 1
        for item in string.gmatch(s, "([^|]+)") do
            list[n] = item
            n = n + 1
        end
        for i = 1, math.min(#list, #M.depts) do M.depts[i] = list[i] end
        log.info("app_state", "读取部门名称", s)
    end)
end

function M.set_depts(list)
    if type(list) ~= "table" then return false end
    for i = 1, #M.depts do
        if type(list[i]) == "string" and #list[i] > 0 then M.depts[i] = list[i] end
    end
    if fskv then
        pcall(function()
            local s = table.concat(M.depts, "|")
            fskv.set(KEY_DEPT, s)
            log.info("app_state", "保存部门名称", s)
        end)
    end
    return true
end

-- ==================== 人员名录（/luadb/staff.csv） ====================
-- 列序：工号,姓名,分机,部门,部门代号
-- 部门按「名称」反查 M.depts；代号列只作人工阅读（CSV 的 1=总经办，与 M.depts 下标不是一套）
local STAFF_PATHS = { "/luadb/staff.csv", "/luadb/img/staff.csv", "/staff.csv" }
local STAFF_MAX = 500
local emp_index, name_index = {}, {}                    -- 工号 / 姓名 → 名录记录

-- 多路径探测：打包是否把 code/ 下的子目录拍平取决于下载工具
local function read_staff()
    for _, p in ipairs(STAFF_PATHS) do
        local ok, data = pcall(io.readFile, p)
        if ok and type(data) == "string" and #data > 0 then return data, p end
    end
    return nil
end

-- 部门名 → M.depts 下标；也接受纯数字（1~#M.depts）。查不到返回 nil
local function dept_of_name(v)
    if not v or v == "" then return nil end
    for i, name in ipairs(M.depts) do
        if name == v then return i end
    end
    local n = tonumber(v)
    if n and n >= 1 and n <= #M.depts then return math.floor(n) end
    return nil
end

-- 粗略 UTF-8 校验：GBK 文本的首字节会落到非法分支（0x80~0xC1 不是合法首字节）
-- 名录必须 UTF-8，否则 hzfont 渲染乱码、部门名也反查不到
local function is_utf8(s)
    local i, n = 1, #s
    while i <= n do
        local c = s:byte(i)
        if c < 0x80 then
            i = i + 1
        elseif c >= 0xC2 and c <= 0xDF then
            local c2 = s:byte(i + 1)
            if not c2 or c2 < 0x80 or c2 > 0xBF then return false end
            i = i + 2
        elseif c >= 0xE0 and c <= 0xEF then
            local c2, c3 = s:byte(i + 1), s:byte(i + 2)
            if not c2 or not c3 or c2 < 0x80 or c2 > 0xBF or c3 < 0x80 or c3 > 0xBF then
                return false
            end
            i = i + 3
        elseif c >= 0xF0 and c <= 0xF4 then
            local c2, c3, c4 = s:byte(i + 1), s:byte(i + 2), s:byte(i + 3)
            if not c2 or not c3 or not c4 then return false end
            i = i + 4
        else
            return false
        end
    end
    return true
end

local function build_index(list)
    emp_index, name_index = {}, {}
    for _, o in ipairs(list) do
        if o.emp then emp_index[o.emp] = o end
        name_index[o.name] = o
    end
end

local function load_staff()
    local data, path = read_staff()
    if not data then
        build_index(M.owners)                          -- 内置名录也要能用工号查
        log.info("app_state", "未找到人员名录，使用内置", #M.owners, "条")
        return false
    end
    if data:sub(1, 3) == "\239\187\191" then data = data:sub(4) end   -- 去 UTF-8 BOM
    if not is_utf8(data) then
        build_index(M.owners)
        log.error("app_state", "staff.csv 不是 UTF-8（疑似 GBK/ANSI），请另存为 UTF-8 后重新下载")
        return false
    end

    local list, by_emp, by_name, dup, bad, no_dept = {}, {}, {}, 0, 0, 0
    for line in data:gmatch("[^\r\n]+") do
        line = line:match("^%s*(.-)%s*$")
        if line ~= "" and line:sub(1, 1) ~= "#" then
            -- 拆列：行尾补一个逗号，空尾列才不会被 gmatch 漏掉
            local cols = {}
            for c in (line .. ","):gmatch("([^,]*),") do
                local v = c:match("^%s*(.-)%s*$") or ""
                cols[#cols + 1] = (v:gsub('^"(.*)"$', "%1"))
            end
            local a, b = cols[1], cols[2]
            -- 列序自适应：表头写的是「工号,姓名」，实际数据是「姓名,工号」（首列是中文名）
            local emp, name
            if a and b and a:match("^%d+$") and not b:match("^%d+$") then
                emp, name = a, b
            elseif a and b and b:match("^%d+$") and not a:match("^%d+$") then
                emp, name = b, a
            else
                emp, name = a, b
            end
            if a == "工号" or a == "姓名" or b == "工号" or b == "姓名" then
                -- 表头行，跳过
            elseif emp and emp ~= "" and name and name ~= "" then
                if by_emp[emp] or by_name[name] then
                    dup = dup + 1
                    log.warn("app_state", "名录工号/姓名重复，已跳过", emp, name)
                else
                    local d = dept_of_name(cols[4])
                    if not d then no_dept = no_dept + 1 end
                    by_emp[emp], by_name[name] = true, true
                    list[#list + 1] = { name = name, emp = emp,
                        ext = (cols[3] and cols[3] ~= "") and cols[3] or "--", dept = d }
                    if #list >= STAFF_MAX then break end
                end
            else
                bad = bad + 1
                log.warn("app_state", "名录行字段不足，已跳过", line)
            end
        end
    end

    if #list == 0 then
        build_index(M.owners)
        log.warn("app_state", "人员名录解析出 0 条，保留内置", #M.owners, "条")
        return false
    end

    M.owners = list
    build_index(list)

    -- 姓名词库跟随名录，消除「能选到人但没有分机」的两套名单
    local names = {}
    for _, o in ipairs(list) do names[#names + 1] = o.name end
    M.words.name = names

    log.info("app_state", "人员名录加载完成", #list, "条", path,
        dup > 0 and ("重复 " .. dup) or "", bad > 0 and ("格式错 " .. bad) or "",
        no_dept > 0 and ("未映射部门 " .. no_dept) or "")
    return true
end

-- 工号 → 名录记录（未命中返回 nil，调用方按访客处理）
function M.owner_by_emp(emp)
    if not emp or emp == "" then return nil end
    return emp_index[emp]
end

function M.emp_of(name)
    local o = name_index[name]
    return o and o.emp or nil
end

-- 姓名 → 所属部门下标（预约时自动带部门用；查不到返回 nil）
function M.dept_of_owner(name)
    local o = name_index[name]
    return o and o.dept or nil
end

-- 手动校时：硬件 RTC + 软件基准一起更新，随后刷新快照
function M.set_time(y, mo, d, h, mi)
    local ok, msg = clock.set(y, mo, d, h, mi)
    if ok then M.refresh() end
    return ok, msg
end

function M.time_source()
    local ep = clock.epoch()
    if not ep then return "未校时" end
    return M.synced and "已校时" or "未校时"
end

load_room_name()
load_depts()
load_staff()                                   -- 必须在 load_depts 之后：部门按名称反查 M.depts

-- ==================== 时间格式 ====================
function M.fmt(h)
    local hh = math.floor(h)
    local mm = math.floor((h - hh) * 60 + 0.5)
    if mm >= 60 then hh, mm = hh + 1, mm - 60 end
    return string.format("%02d:%02d", hh, mm)
end

function M.range(b)
    return M.fmt(b.start) .. "-" .. M.fmt(b.start + b.dur)
end

function M.now_text()
    return M.fmt(M.now_h)
end

-- ==================== 查询 ====================
function M.current()
    for i, b in ipairs(M.bookings) do
        if b.day == M.today and M.now_h >= b.start and M.now_h < b.start + b.dur then
            return b, i
        end
    end
    return nil
end

-- 今天接下来最近的一场
function M.next_today()
    local best, bi
    for i, b in ipairs(M.bookings) do
        if b.day == M.today and b.start > M.now_h then
            if not best or b.start < best.start then best, bi = b, i end
        end
    end
    return best, bi
end

-- 不限今天：按未来 7 天顺序找最近一场
function M.next_any()
    for step = 0, 6 do
        local d = ((M.today - 1 + step) % 7) + 1
        local best, bi, bd
        for i, b in ipairs(M.bookings) do
            if b.day == d then
                if step == 0 then
                    if b.start > M.now_h and (not best or b.start < best.start) then best, bi = b, i end
                elseif not best or b.start < best.start then
                    best, bi = b, i
                end
            end
        end
        if best then return best, bi, d end
    end
    return nil
end

-- 某一天全部预约（按开始时间升序）
function M.day_list(day)
    local list = {}
    for i, b in ipairs(M.bookings) do
        if b.day == day then list[#list + 1] = { b = b, i = i } end
    end
    table.sort(list, function(a, b) return a.b.start < b.b.start end)
    return list
end

function M.today_list()
    return M.day_list(M.today)
end

-- 冲突校验：同一星期、时间区间相交即冲突。skip 为编辑中的自身下标
function M.conflict(day, start, dur, skip)
    for i, b in ipairs(M.bookings) do
        if i ~= skip and b.day == day
            and start < b.start + b.dur and b.start < start + dur then
            return true, i
        end
    end
    return false
end

-- 某天允许的最早开始小时：
--   周视图按「周一~周日」排列，day < today 就是本周已过去的日子
--   已过去的日子返回 close_h（整日不可约，free_start 会返回 nil）
--   今天从「下一个整点」起（已开始/已过去的时段不可约）
--   其余天从开放时间起
function M.earliest_start(day)
    if day < M.today then return M.room.close_h end
    if day == M.today then
        local e = math.ceil(M.now_h)
        if e < M.room.open_h then e = M.room.open_h end
        return e
    end
    return M.room.open_h
end

-- 某天下一个整点空档；今天已无可用时段时返回 nil（调用方必须判空）
function M.free_start(day)
    local from = M.earliest_start(day)
    if from > M.room.close_h - 1 then return nil end
    for h = from, M.room.close_h - 1 do
        if not M.conflict(day, h, 1) then return h end
    end
    return nil
end

-- ==================== 增删改 ====================
function M.add(b)
    M.bookings[#M.bookings + 1] = b
    return #M.bookings
end

function M.update(idx, b)
    if not M.bookings[idx] then return false end
    M.bookings[idx] = b
    return true
end

function M.remove(idx)
    if not M.bookings[idx] then return false end
    table.remove(M.bookings, idx)
    return true
end

function M.get(idx)
    return M.bookings[idx]
end

function M.dept_name(i)
    return M.depts[i] or "未指定"
end

-- 姓名 → 分机号（名录里没有就返回 "--"）
function M.ext_of(name)
    for _, o in ipairs(M.owners) do
        if o.name == name then return o.ext end
    end
    return "--"
end

-- 负责人展示文本："李娜 · 分机 8802" / "外来访客"
function M.owner_text(name)
    name = name or ""
    if name == "" then return "未指定" end
    local ext = M.ext_of(name)
    if ext == "--" then return name end
    return name .. " · 分机 " .. ext
end

-- ==================== 演示数据 ====================
local function seed_one(day, hour, dur, topic, dept, owner, emp, pwd, seats)
    if day < 1 or day > 7 then return end
    if hour < M.room.open_h or hour + dur > M.room.close_h then return end
    if M.conflict(day, hour, dur) then return end
    emp = M.emp_of(owner) or emp                   -- 工号以人员名录为准，名录里没有才用演示值
    M.add({ day = day, start = hour, dur = dur, topic = topic, dept = dept,
            owner = owner, ext = M.ext_of(owner), emp = emp, pwd = pwd, seats = seats })
end

function M.seed()
    M.bookings = {}
    M.refresh()

    local d = M.today
    local function wrap(k) return ((k - 1) % 7) + 1 end

    -- 今天：先放一场「正在进行」，再往后排两场，保证门牌开机即有内容
    local st = math.floor(M.now_h)
    if M.now_h - st < 0.3 then st = st - 1 end
    if st < M.room.open_h then st = M.room.open_h end
    local dur = 2
    if st + dur > M.room.close_h then dur = M.room.close_h - st end
    if dur >= 1 then
        seed_one(d, st, dur, "产品评审", 2, "李娜", "8801", "8888", 5)
        if st + dur + 1 + 2 <= M.room.close_h then
            seed_one(d, st + dur + 1, 2, "研发周会", 1, "张伟", "1024", "8888", 8)
        end
        if st + dur + 4 + 1 <= M.room.close_h then
            seed_one(d, st + dur + 4, 1, "新人面试", 3, "王强", "2011", "6666", 2)
        end
    end

    -- 本周其余几天：覆盖 5 个部门、1~3 小时不同时长
    seed_one(wrap(d + 1), 9,  2, "财务审计",   4, "赵敏", "3055", "8888", 3)
    seed_one(wrap(d + 1), 14, 1, "客户接待",   2, "李娜", "8801", "8888", 6)
    seed_one(wrap(d + 2), 10, 1, "研发周会",   1, "张伟", "1024", "8888", 8)
    seed_one(wrap(d + 3), 15, 3, "经营例会",   5, "周总", "0001", "8888", 12)
    seed_one(wrap(d + 4), 9,  2, "产品评审",   1, "张伟", "1024", "8888", 6)
    seed_one(wrap(d + 5), 13, 2, "客户接待",   2, "李娜", "8801", "8888", 5)
    seed_one(wrap(d + 6), 10, 1, "新人面试",   3, "王强", "2011", "6666", 2)

    return M.bookings
end

M.refresh()

return M
