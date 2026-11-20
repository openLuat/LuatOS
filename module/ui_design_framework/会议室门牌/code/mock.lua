--[[
@module mock
@summary 会议室门牌 - 会议数据 / 状态 / 时间工具
         与 code/preview.html 的 mock 行为一一对应：
         固定 3 场会议 + 3 个可预约空闲时段，虚拟时钟从 10:35 起走。
]]
local M = {}

M.room = { name = "蓝聪会议室", en = "MEETING ROOM", floor = "3F 东区", cap = 12,
           brand = "东证创新" }

M.date = { y = 2026, m = 11, d = 19, week = "星期四", md = "11/19" }

-- 初始日程（单位：分钟，从 00:00 起算）
-- note1/note2 = 详情弹层底部那两行说明，每场会议各不相同
-- （之前三场共用一个固定串，点哪场看到的「会议内容」都一模一样）
M.base = {
    { st = 10 * 60 + 5,  et = 11 * 60 + 5,  topic = "关于多种交互方案讨论会议", people = 8,
      owner = "李工", dept = "产品部",
      agenda = { "评审三套门牌交互稿（天际线 / 商务 / 表格）", "确认预约与取消的入口位置", "下周出可点原型给行政确认" },
      note1 = "投屏 · 白板 · 交互稿 v3 已上传共享盘",
      note2 = "请提前 5 分钟到场，会前资料已随日程同步。" },
    { st = 11 * 60 + 17, et = 12 * 60 + 17, topic = "Q4 产品规划评审", people = 6,
      owner = "王敏", dept = "产品部",
      agenda = { "Q4 需求池盘点", "确定 11 月上线范围", "资源与人天确认" },
      note1 = "投屏 · 视频会议 · 需求文档见附件",
      note2 = "评审结论当天同步，会后 10 分钟出纪要。" },
    { st = 12 * 60 + 57, et = 13 * 60 + 57, topic = "客户接待 · 东证创新", people = 10,
      owner = "张伟", dept = "销售部",
      agenda = { "客户到访接待", "方案演示 20 分钟", "现场答疑" },
      note1 = "客户接待 · 咖啡已备 · 方案 PPT 已就绪",
      note2 = "接待流程见《客户到访 SOP》，门禁已授权。" },
}

-- 可预约的空闲时段（预约弹层里三选一，可连续约多场）
M.slots = {
    { st = 14 * 60 + 15, et = 15 * 60 + 30 },
    { st = 15 * 60 + 45, et = 17 * 60 + 0  },
    { st = 17 * 60 + 15, et = 18 * 60 + 30 },
}

M.VNOW0 = 10 * 60 + 35   -- 虚拟时钟起点（preview.html 的 10:35）

-- 运行态
M.state = {
    vnow      = M.VNOW0,
    cur       = 1,        -- 当前进行中的场次（base 下标）
    free      = false,    -- false = 会议中，true = 空闲
    dnd       = false,
    door      = false,    -- 门禁：false 已上锁，true 已开门
    tpl       = 1,        -- 1 天际线 2 商务 3 表格
    dial      = "clock",  -- 天际线圆盘：clock（当前时间）/ left（会议剩余时间）
    bookings  = {},       -- 我的预约列表 { bid, st, et, topic, people }
    bid       = 1,
    sel_bid   = nil,      -- 日程里被选中的那笔预约
    date      = 1,        -- 预约弹层：1 今天 2 明天
    slot      = 1,
}

function M.fmt(min)
    min = math.floor(min + 0.5)
    return string.format("%02d:%02d", math.floor(min / 60) % 24, min % 60)
end

-- 某一天的列表（1 = 今天，2 = 明天）：常规会议只在今天，预约按 day 归属
function M.daylist(day)
    day = day or 1
    local out = {}
    if day == 1 then
        for i = 1, #M.base do
            local m = M.base[i]
            out[#out + 1] = { idx = i, day = 1, st = m.st, et = m.et, topic = m.topic,
                              people = m.people, owner = m.owner, dept = m.dept,
                              agenda = m.agenda, note1 = m.note1, note2 = m.note2, mine = false }
        end
    end
    for i = 1, #M.state.bookings do
        local b = M.state.bookings[i]
        if b.day == day then
            out[#out + 1] = { idx = -b.bid, bid = b.bid, day = day, st = b.st, et = b.et,
                              topic = b.topic, people = b.people, owner = "我", dept = "产品部",
                              agenda = { "预约主题：交互方案同步", "参会人：产品部 4 人", "备注：由门牌现场预约" },
                              note1 = "投屏 · 白板 · 这是刚才在门牌上预约的时段",
                              note2 = "已同步到会议日程，取消请点「取消预约」。",
                              mine = true }
        end
    end
    table.sort(out, function(a, b) return a.st < b.st end)
    return out
end

-- 主界面日程 / 表格用：明天的预约放在最前面，保证「我约了明天」永远看得见
-- （表格只有 6 行，如果排到最后，今天场次一多就被挤掉，又会变成「约了明天却看不到」）
function M.agenda_list()
    local out = {}
    local d2 = M.daylist(2)
    for i = 1, #d2 do out[#out + 1] = d2[i] end
    local d1 = M.daylist(1)
    for i = 1, #d1 do out[#out + 1] = d1[i] end
    return out
end

function M.find_book(bid)
    for i = 1, #M.state.bookings do
        if M.state.bookings[i].bid == bid then return M.state.bookings[i], i end
    end
    return nil
end

-- 当前场次（会议中）/ 下一场
function M.cur_meeting()
    if M.state.free then return nil end
    return M.base[M.state.cur]
end

-- 下一场：必须把「我自己的预约」也算进来
-- （之前过滤掉 mine，预约完 15:45 后界面仍说「今天暂无后续会议」，用户会以为没约上）
function M.next_meeting()
    local list = M.daylist(1)
    for i = 1, #list do
        if list[i].st > M.state.vnow then return list[i] end
    end
    return nil
end

-- 明天我的预约时段串（没有则返回 nil），例如 "明天 17:15-18:30"
function M.tomorrow_text()
    local ts = {}
    for i = 1, #M.state.bookings do
        local b = M.state.bookings[i]
        if b.day == 2 then ts[#ts + 1] = M.fmt(b.st) .. "-" .. M.fmt(b.et) end
    end
    if #ts == 0 then return nil end
    return "明天 " .. table.concat(ts, "、")
end

-- 我的预约总览（今天 + 明天），给空闲态文案用
-- 只讲今天的话，约了明天的会议在主界面上完全看不到
function M.my_text()
    local t1, t2 = {}, {}
    for i = 1, #M.state.bookings do
        local b = M.state.bookings[i]
        local s = M.fmt(b.st) .. "-" .. M.fmt(b.et)
        if b.day == 1 then t1[#t1 + 1] = s else t2[#t2 + 1] = s end
    end
    local parts = {}
    if #t1 > 0 then parts[#parts + 1] = "今天 " .. table.concat(t1, "、") end
    if #t2 > 0 then parts[#parts + 1] = "明天 " .. table.concat(t2, "、") end
    if #parts == 0 then return nil end
    return table.concat(parts, " · ")
end

M.my_today_text = M.my_text      -- 兼容旧调用名

-- 压缩版（只讲场次数量），给窄条文案用：今天 1 场 · 明天 1 场
function M.my_brief()
    local n1, n2 = 0, 0
    for i = 1, #M.state.bookings do
        if M.state.bookings[i].day == 1 then n1 = n1 + 1 else n2 = n2 + 1 end
    end
    if n1 + n2 == 0 then return nil end
    local t = {}
    if n1 > 0 then t[#t + 1] = "今天 " .. n1 .. " 场" end
    if n2 > 0 then t[#t + 1] = "明天 " .. n2 .. " 场" end
    return table.concat(t, " · ")
end

function M.left_min()
    local m = M.cur_meeting()
    if not m then return 0 end
    -- 虚拟时钟是小数分钟，对外一律给四舍五入后的整数（否则界面会显示 38.5 分钟）
    local v = math.floor(m.et - M.state.vnow + 0.5)
    if v < 0 then v = 0 end
    return v
end

function M.slot_taken(day, st)
    for i = 1, #M.state.bookings do
        local b = M.state.bookings[i]
        if b.day == day and math.abs(b.st - st) < 1 then return true end
    end
    return false
end

function M.add_booking(day, slotidx)
    local s = M.slots[slotidx] or M.slots[1]
    local b = { bid = M.state.bid, day = day, st = s.st, et = s.et,
                topic = "我的预约 · 交互方案同步会", people = 4 }
    M.state.bid = M.state.bid + 1
    M.state.bookings[#M.state.bookings + 1] = b
    return b
end

function M.del_booking(bid)
    local b, i = M.find_book(bid)
    if not b then return nil end
    table.remove(M.state.bookings, i)
    if M.state.sel_bid == bid then M.state.sel_bid = nil end
    return b
end

return M
