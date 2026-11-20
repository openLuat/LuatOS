--[[
@module  page_booking
@summary 会议室门牌 · 预约登记页（数字键盘验身份 + 部门 chip + 负责人/主题文本输入 + 步进器）
@version 1.2.0
@note 1) 门牌没有中文软键盘：工号/密码用数字键盘，负责人/会议主题点一下进 page_input 的词库键盘，
         部门从设置页配置的 5 个 chip 里选，日期/时间/人数用步进器；
      2) 键盘区（左侧 268 宽的数字键盘、输入页 640 宽的词库键盘）都不超过「预约信息」卡片的宽度；
      3) 从输入页回来时靠 S.handoff 回填，草稿按入口参数记忆，切主题/去输入页都不会丢已填内容。
      参数：{ day = 1~7, start = 8~19 } 空白时段进入；{ idx = n } 详情页「编辑」进入
]]
local T = require "ui_theme"
local W = require "ui_widget"
local S = require "app_state"
local R = require "router"
local C, G = T.c, T.glass
local M = {}

local SW, SH = T.screen.w, T.screen.h
local TOP = { x = 18, y = 14, w = 988, h = 64 }
local LC  = { x = 18, y = 90, w = 300, h = 494 }
local RC  = { x = 330, y = 90, w = 676, h = 494 }

local PAGE, ROOT
local f, edit_idx, entry_args
local ui = {}
local page_ready = false
local draft_key, draft = nil, nil          -- 草稿：同参数重建（切主题/去输入页）时保留已填内容
local auto_owner = nil                     -- 上一次由工号自动带出的姓名；不等于它即视为用户手填

local MAX_EMP, MAX_PWD, MAX_SEATS = 8, 8, 20
local MAX_OWNER, MAX_TOPIC = 6, 10

-- ==================== 表单状态 ====================
local function refresh_fields()
    if not page_ready then return end
    local emp_empty = (f.emp == "")
    W.set(ui.emp_lbl, emp_empty and "未输入" or f.emp)
    W.color(ui.emp_lbl, emp_empty and C.text_dim or C.text)
    local pwd_empty = (f.pwd == "")
    W.set(ui.pwd_lbl, pwd_empty and "未设置" or string.rep("*", #f.pwd))
    W.color(ui.pwd_lbl, pwd_empty and C.text_dim or C.text)
    local on_emp = (ui.active == "emp")
    W.glass(ui.emp_box, on_emp and C.pri or C.tile, on_emp and 78 or G.tile_opa)
    W.glass(ui.pwd_box, (not on_emp) and C.pri or C.tile, (not on_emp) and 78 or G.tile_opa)

    local owner_empty = (f.owner == "")
    -- 命中名录时带分机号，让「工号 → 负责人」的对应关系一眼可验证
    W.set(ui.owner_lbl, owner_empty and "点击输入负责人" or S.owner_text(f.owner))
    W.color(ui.owner_lbl, owner_empty and C.text_dim or C.text)
    local topic_empty = (f.topic == "")
    W.set(ui.topic_lbl, topic_empty and "点击输入会议主题" or f.topic)
    W.color(ui.topic_lbl, topic_empty and C.text_dim or C.text)
end

local function set_active(which)
    ui.active = which
    refresh_fields()
end

-- 工号 → 负责人：负责人为空、或仍停在上次自动带出的名字时才覆盖；用户手填过就不再动
local function sync_owner_from_emp()
    if f.owner ~= "" and f.owner ~= auto_owner then return end
    local o = S.owner_by_emp(f.emp)
    f.owner = o and o.name or ""
    auto_owner = o and o.name or nil
end

local function refresh_hint()
    local conflict = S.conflict(f.day, f.start, f.dur, edit_idx)
    local txt, col
    if not edit_idx and f.day < S.today then
        txt = "该日期已过去，请改选今天或以后"
        col = C.warn
    elseif not edit_idx and f.day == S.today and f.start < S.now_h then
        txt = "今天已无可预约时段，请改选其他日期"
        col = C.warn
    elseif conflict then
        txt = "该时段已被占用，请调整时间"
        col = C.danger
    elseif f.emp ~= "" and #f.emp >= 4 and not S.owner_by_emp(f.emp) then
        txt = "工号 " .. f.emp .. " 未在人员名录，可按访客预约"
        col = C.text_dim
    else
        txt = string.format("%s · %s %s-%s · %d 人", edit_idx and "修改预约" or "新增预约",
            S.day_names[f.day], S.fmt(f.start), S.fmt(f.start + f.dur), f.seats)
        col = C.text_sub
    end
    W.set(ui.hint, txt)
    W.color(ui.hint, col)
end

local function refresh_steppers()
    if ui.st_start then W.set(ui.st_start, S.fmt(f.start)) end
    if ui.st_dur then W.set(ui.st_dur, f.dur .. " 小时") end
    if ui.st_seats then W.set(ui.st_seats, f.seats .. " 人") end
    refresh_hint()
end

-- ==================== 组件 ====================
local function build_topbar()
    local g = W.glass_card({ parent = ROOT, x = TOP.x, y = TOP.y, w = TOP.w, h = TOP.h })
    local p = g.card
    W.text_mid(p, { text = edit_idx and "修改预约" or "预约登记", x = 18, y = 6, w = 300, h = 32,
        size = 24, color = C.text })
    W.text_mid(p, { text = string.format("开放 %02d:00-%02d:00 · 单次 1~3 小时 · 时段不可重叠",
        S.room.open_h, S.room.close_h), x = 18, y = 38, w = 480, h = 20,
        size = T.f.mini, color = C.text_dim })
    R.theme_chip(p, { x = 700, y = 14, w = 86, h = 36 })
    W.chip(p, { x = 796, y = 14, w = 170, h = 36, text = "返回门牌",
        off_color = C.tile, off_opa = G.tile_opa, off_tcolor = C.text_sub,
        on_click = function() R.go("home") end })
end

-- 输入显示框：点它切换「当前输入目标」
local function field(parent, y, title, which)
    W.text_mid(parent, { text = title, x = 14, y = y, w = 140, h = 20,
        size = T.f.mini, color = C.text_sub })
    local box = airui.container({ parent = parent, x = 14, y = y + 22, w = 268, h = 44,
        color = C.tile, radius = T.r.panel, border_width = 0 })
    W.glass(box, C.tile, G.tile_opa)
    local lbl = W.text_mid(box, { text = "", x = 8, y = 0, w = 252, h = 44,
        size = 22, color = C.text_dim, align = airui.TEXT_ALIGN_CENTER })
    W.press_layer(parent, { x = 14, y = y + 22, w = 268, h = 44, radius = T.r.panel,
        target = box, tx = 14, ty = y + 22,
        on_click = function() set_active(which) end })
    return box, lbl
end

-- 可点开的文本字段（负责人 / 会议主题）
local function text_field(parent, y, title, key, current, cat, max)
    W.text_mid(parent, { text = title, x = 14, y = y, w = 300, h = 20,
        size = T.f.mini, color = C.text_sub })
    local box = airui.container({ parent = parent, x = 14, y = y + 20, w = 644, h = 42,
        color = C.tile, radius = T.r.panel, border_width = 0 })
    W.glass(box, C.tile, G.tile_opa)
    local lbl = W.text_mid(parent, { text = "", x = 30, y = y + 20, w = 500, h = 42,
        size = T.f.body, color = C.text, align = airui.TEXT_ALIGN_LEFT })
    W.text_mid(parent, { text = "修改", x = 548, y = y + 20, w = 84, h = 42,
        size = T.f.mini, color = C.pri, align = airui.TEXT_ALIGN_RIGHT })
    W.press_layer(parent, { x = 14, y = y + 20, w = 644, h = 42, radius = T.r.panel,
        target = box, tx = 14, ty = y + 20,
        on_click = function()
            R.go("input", { field = key, title = "输入" .. (key == "owner" and "负责人" or "会议主题"),
                value = current(), max = max, cat = cat,
                back = { page = "booking", args = entry_args } })
        end })
    return lbl
end

-- 步进器：− 值 +，值文字由 refresh_steppers 刷新
local function stepper(parent, x, y, w, h, on_minus, on_plus)
    local track = airui.container({ parent = parent, x = x, y = y, w = w, h = h,
        color = C.tile, radius = T.r.panel, border_width = 0 })
    W.glass(track, C.tile, G.tile_opa)
    local function key(px, text, cb)
        local box = airui.container({ parent = track, x = px, y = 4, w = 44, h = h - 8,
            color = C.btn_bg, radius = 10, border_width = 0 })
        W.glass(box, C.btn_bg, 210)
        W.text_mid(track, { text = text, x = px, y = 4, w = 44, h = h - 8, size = 20,
            color = C.text, align = airui.TEXT_ALIGN_CENTER })
        W.press_layer(track, { x = px, y = 4, w = 44, h = h - 8, radius = 10,
            target = box, tx = px, ty = 4, on_click = cb })
    end
    key(4, "-", on_minus)
    key(w - 48, "+", on_plus)
    return W.text_mid(track, { text = "", x = 50, y = 0, w = w - 100, h = h,
        size = 20, color = C.text, align = airui.TEXT_ALIGN_CENTER })
end

-- ==================== 选择组 ====================
local dept_chips, day_chips = {}, {}

local function select_dept(i)
    f.dept = i
    for k, c in ipairs(dept_chips) do c.set_active(k == i) end
end

local function select_day(i)
    -- 新建时过去的日子不可选（编辑历史记录不受限）
    if not edit_idx and i < S.today then
        R.toast("该日期已过去，请选择今天或以后")
        return
    end
    f.day = i
    for k, c in ipairs(day_chips) do c.set_active(k == i) end
    -- 新建时从「未来某天」切回今天：把开始时间推到今天最早可约的整点
    if not edit_idx then
        local lo = S.earliest_start(i)
        if f.start < lo then f.start = math.min(lo, S.room.close_h - 1) end
        refresh_steppers()                             -- 内含 refresh_hint
    else
        refresh_hint()
    end
end

local function build_left()
    local g = W.glass_card({ parent = ROOT, x = LC.x, y = LC.y, w = LC.w, h = LC.h })
    local p = g.card
    W.text_mid(p, { text = "身份验证", x = 14, y = 12, w = 180, h = 20,
        size = T.f.mini, color = C.text_dim })
    ui.emp_box, ui.emp_lbl = field(p, 40, "工号", "emp")
    ui.pwd_box, ui.pwd_lbl = field(p, 112, "密码", "pwd")
    ui.numpad = W.numpad(p, { x = 14, y = 190, w = 268, h = 292, gap = 10,
        on_key = function(k)
            local key = (ui.active == "emp") and "emp" or "pwd"
            local s = f[key]
            if k == "清空" then
                s = ""
            elseif k == "退格" then
                if #s > 0 then s = s:sub(1, #s - 1) end
            else
                local lim = (key == "emp") and MAX_EMP or MAX_PWD
                if #s < lim then s = s .. k end
            end
            f[key] = s
            if key == "emp" then
                sync_owner_from_emp()                  -- 逐位输入即时对应：2001 → 张伟
                refresh_hint()
            end
            refresh_fields()
        end })
    ui.active = "emp"
    return g
end

local function build_right()
    local g = W.glass_card({ parent = ROOT, x = RC.x, y = RC.y, w = RC.w, h = RC.h })
    local p = g.card
    W.text_mid(p, { text = "预约信息", x = 14, y = 12, w = 180, h = 20,
        size = T.f.mini, color = C.text_dim })

    -- 部门（可在设置页改名）
    W.text_mid(p, { text = "预约部门", x = 14, y = 38, w = 140, h = 20,
        size = T.f.mini, color = C.text_sub })
    -- 6 个部门一行排布：内容宽 672，左起 14，100 宽 + 8 间距，末个右缘 654 ≤ 658
    for i = 1, #S.depts do
        local dt = T.dept[i] or T.dept[1]
        dept_chips[i] = W.chip(p, { x = 14 + (i - 1) * 108, y = 58, w = 100, h = 38,
            text = W.clip(S.depts[i] or "", 4), size = T.f.mini,
            off_color = C.tile, off_opa = G.tile_opa, off_tcolor = C.text_sub,
            on_color = dt.accent, on_tcolor = C.on_accent,
            on_click = function() select_dept(i) end })
    end

    -- 负责人 / 会议主题：点开词库键盘自由输入
    ui.owner_lbl = text_field(p, 104, "负责人", "owner", function() return f.owner end,
        "name", MAX_OWNER)
    ui.topic_lbl = text_field(p, 174, "会议主题", "topic", function() return f.topic end,
        "topic", MAX_TOPIC)

    -- 日期
    W.text_mid(p, { text = "预约日期", x = 14, y = 244, w = 140, h = 20,
        size = T.f.mini, color = C.text_sub })
    for i = 1, 7 do
        day_chips[i] = W.chip(p, { x = 14 + (i - 1) * 94, y = 264, w = 86, h = 36,
            text = S.day_names[i], size = T.f.mini,
            off_color = C.tile, off_opa = G.tile_opa, off_tcolor = C.text_sub,
            on_click = function() select_day(i) end })
    end

    -- 开始时间 / 时长 / 人数
    W.text_mid(p, { text = "开始时间", x = 14, y = 306, w = 204, h = 20,
        size = T.f.mini, color = C.text_sub })
    W.text_mid(p, { text = "时长", x = 228, y = 306, w = 204, h = 20,
        size = T.f.mini, color = C.text_sub })
    W.text_mid(p, { text = "人数", x = 442, y = 306, w = 204, h = 20,
        size = T.f.mini, color = C.text_sub })

    ui.st_start = stepper(p, 14, 326, 204, 44,
        function()
            -- 新建时不能减到已开始的时段；编辑历史预约时不设下界
            local lo = (not edit_idx) and S.earliest_start(f.day) or S.room.open_h
            if f.start > lo then
                f.start = f.start - 1
                refresh_steppers()
            end
        end,
        function()
            if f.start + f.dur < S.room.close_h then
                f.start = f.start + 1
                refresh_steppers()
            end
        end)
    ui.st_dur = stepper(p, 228, 326, 204, 44,
        function()
            if f.dur > 1 then
                f.dur = f.dur - 1
                refresh_steppers()
            end
        end,
        function()
            if f.dur < 3 and f.start + f.dur < S.room.close_h then
                f.dur = f.dur + 1
                refresh_steppers()
            end
        end)
    ui.st_seats = stepper(p, 442, 326, 204, 44,
        function()
            if f.seats > 1 then
                f.seats = f.seats - 1
                refresh_steppers()
            end
        end,
        function()
            if f.seats < MAX_SEATS then
                f.seats = f.seats + 1
                refresh_steppers()
            end
        end)

    ui.hint = W.text_mid(p, { text = "", x = 14, y = 376, w = 644, h = 20,
        size = T.f.mini, color = C.text_sub })
    W.text_mid(p, { text = "输入工号自动带出负责人 · 姓名 / 主题可点开手填", x = 14, y = 402,
        w = 644, h = 20, size = T.f.mini, color = C.text_dim })

    -- 底部按钮（取消 = 丢弃草稿，避免下次进同一时段还带着上次的工号密码）
    W.button(p, { x = 14, y = 440, w = 180, h = 44, text = "取消", size = T.f.body,
        color = C.tile, opa = G.tile_opa, tcolor = C.text_sub,
        on_click = function()
            draft_key, draft = nil, nil
            R.go("home")
        end })
    W.button(p, { x = 206, y = 440, w = 464, h = 44,
        text = edit_idx and "保存修改" or "确认预约", size = T.f.body,
        color = C.pri, tcolor = C.on_accent,
        on_click = function() M.submit() end })
    return g
end

-- ==================== 提交 ====================
function M.submit()
    -- 新建预约不能选过去的日期 / 已开始的时段（编辑历史记录时不拦，否则旧数据改不了）
    if not edit_idx then
        if f.day < S.today then
            R.toast("该日期已过去，请选择今天或以后")
            return
        end
        if f.day == S.today and f.start < S.now_h then
            R.toast("开始时间已过去，请调整时间")
            return
        end
    end
    if #f.emp < 4 then
        R.toast("请输入 4 位以上工号")
        set_active("emp")
        return
    end
    -- 工号以名录为准：命中就纠正手填的负责人，未命中按访客放行（只记日志，不挡提交）
    local staff = S.owner_by_emp(f.emp)
    if not staff then
        log.warn("page_booking", "工号未在人员名录，按访客保存", f.emp, f.owner)
    elseif staff.name ~= f.owner then
        f.owner = staff.name
        auto_owner = staff.name
        refresh_fields()
    end
    if #f.pwd < 4 then
        R.toast("密码至少 4 位")
        set_active("pwd")
        return
    end
    if f.owner == "" then
        R.toast("请填写负责人")
        return
    end
    if f.topic == "" then
        R.toast("请填写会议主题")
        return
    end
    if f.start + f.dur > S.room.close_h then
        R.toast("已超出 20:00 闭馆时间")
        return
    end
    if S.conflict(f.day, f.start, f.dur, edit_idx) then
        R.toast("该时段已被占用")
        return
    end
    local b = {
        day = f.day, start = f.start, dur = f.dur, topic = f.topic,
        dept = f.dept, owner = f.owner, ext = S.ext_of(f.owner),
        emp = f.emp, pwd = f.pwd, seats = f.seats,
    }
    draft_key, draft = nil, nil                        -- 提交成功后清草稿
    if edit_idx then
        S.update(edit_idx, b)
        R.go_toast("home", { day = f.day }, "预约已更新")
    else
        S.add(b)
        R.go_toast("home", { day = f.day }, "预约成功")
    end
end

-- ==================== 生命周期 ====================
function M.root()
    return PAGE
end

function M.destroy()
    if PAGE then
        pcall(function() PAGE:destroy() end)
        PAGE = nil
    end
    ROOT = nil
    page_ready = false
    ui = {}
    dept_chips, day_chips = {}, {}
end

function M.create(args)
    -- 同一个入口参数视为「同一次填写」：切主题 / 去输入页回来都保留已填内容
    local key = tostring(args and args.idx or "-") .. "|"
        .. tostring(args and args.day or "-") .. "|"
        .. tostring(args and args.start or "-")
    local keep = (draft_key == key) and draft or nil
    entry_args = { idx = args and args.idx, day = args and args.day, start = args and args.start }

    M.destroy()
    S.refresh()
    edit_idx = args and args.idx or nil
    auto_owner = nil                                -- 每次进页面重置自动带出标记
    local b = edit_idx and S.get(edit_idx) or nil

    local day = b and b.day or (args and args.day) or S.today
    if day < 1 or day > 7 then day = S.today end
    local start = b and b.start or (args and args.start) or 9
    if start < S.room.open_h then start = S.room.open_h end
    if start > S.room.close_h - 1 then start = S.room.close_h - 1 end
    f = keep or {
        emp = b and b.emp or "",
        pwd = b and b.pwd or "",
        dept = b and b.dept or 1,
        owner = b and b.owner or "",
        topic = b and b.topic or "",
        day = day,
        start = start,
        dur = b and b.dur or 1,
        seats = b and b.seats or 4,
    }
    -- 新建：过去的日子不可约（草稿跨天也要纠正），今天已开始的时段往后推；编辑历史预约保留原值
    if not edit_idx then
        if f.day < S.today then
            f.day = S.today
            f.start = S.room.open_h
        end
        if f.day == S.today then
            local e = S.earliest_start(f.day)
            if f.start < e then f.start = math.min(e, S.room.close_h - 1) end
        end
    end

    draft_key, draft = key, f
    -- 草稿复用：负责人正好是当前工号在名录里的名字时，恢复自动带出标记，后续改工号仍能跟随
    local oe = S.owner_by_emp(f.emp)
    if oe and oe.name == f.owner then auto_owner = f.owner end

    -- 输入页回填（取走即清空）
    if S.handoff.owner then
        f.owner = S.handoff.owner
        auto_owner = nil                            -- 手填的，之后再改工号也不覆盖
        if f.emp == "" then f.emp = S.emp_of(f.owner) or "" end   -- 反向从名录补工号
        S.handoff.owner = nil
    end
    if S.handoff.topic then
        f.topic = S.handoff.topic
        S.handoff.topic = nil
    end

    PAGE = airui.container({ parent = airui.screen, x = 0, y = 0, w = SW, h = SH,
        color = 0x000000, color_opacity = 0, border_width = 0 })
    ROOT = PAGE
    page_ready = true

    build_topbar()
    build_left()
    build_right()

    select_dept(f.dept)
    select_day(f.day)
    refresh_fields()
    refresh_steppers()
    log.info("page_booking", "预约页已创建", edit_idx and "编辑" or "新增")
end

return M
