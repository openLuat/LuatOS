--[[
@module  page_detail
@summary 会议室门牌 · 预约详情页（信息明细 + 密码校验后编辑/删除）
@version 1.0.0
@note 密码校验沿用「二次点击」语义：第一次点编辑/删除先弹出键盘，输完密码再点一次才执行，
      避免误触直接删掉别人的预约。
      校验接受「预约本人密码」或「管理员密码」（S.admin_pwd，默认 8888），
      所以管理员可以编辑/删除任意一条预约，不受原预约密码限制。
]]
local T = require "ui_theme"
local W = require "ui_widget"
local S = require "app_state"
local R = require "router"
local C, G = T.c, T.glass
local M = {}

local SW, SH = T.screen.w, T.screen.h
local TOP = { x = 18,  y = 14, w = 988, h = 64 }
local LC  = { x = 18,  y = 90, w = 520, h = 494 }
local RC  = { x = 556, y = 90, w = 450, h = 494 }

local RULES = {
    "开放时间  08:00 - 20:00",
    "单次时长  1 ~ 3 小时，时段不可重叠",
    "编辑 / 删除：预约密码或管理员密码",
    "数据为本地模拟，可对接后端接口",
}

local PAGE, ROOT
local idx, booking
local pwd_mode, pwd = nil, ""
local ui = {}

local function refresh_pwd()
    if not ui.pwd_lbl then return end
    if pwd == "" then
        W.set(ui.pwd_lbl, "(未输入)")
        W.color(ui.pwd_lbl, C.text_dim)
    else
        W.set(ui.pwd_lbl, string.rep("*", #pwd))
        W.color(ui.pwd_lbl, C.text)
    end
end

local function set_pwd_mode(mode)
    pwd_mode = mode
    local on = (mode ~= nil)
    ui.numpad.set_visible(on)
    for i, lbl in ipairs(ui.rule_lbls) do
        W.set(lbl, on and "" or RULES[i])
    end
    if on then
        if mode == "del" then
            W.set(ui.hint, "预约密码或管理员密码，输完再点「删除」")
        else
            W.set(ui.hint, "预约密码或管理员密码，输完再点「编辑」")
        end
        W.color(ui.hint, C.warn)
    else
        W.set(ui.hint, "编辑 / 删除可用预约密码或管理员密码")
        W.color(ui.hint, C.text_sub)
        pwd = ""
        refresh_pwd()
    end
end

-- 预约状态（按当前时间判断）
local function state_of(b)
    if b.day < S.today then return "已结束", C.text_dim end
    if b.day > S.today then return "待开始", C.ok end
    local e = b.start + b.dur
    if S.now_h >= e then return "已结束", C.text_dim end
    if S.now_h >= b.start then return "进行中", C.pri end
    return "待开始", C.ok
end

local function build_topbar()
    local g = W.glass_card({ parent = ROOT, x = TOP.x, y = TOP.y, w = TOP.w, h = TOP.h })
    local p = g.card
    W.text_mid(p, { text = "预约详情", x = 18, y = 6, w = 300, h = 32, size = 24, color = C.text })
    W.text_mid(p, { text = S.day_names[booking.day] .. " " .. S.fmt(booking.start) .. "-"
        .. S.fmt(booking.start + booking.dur) .. " · " .. S.room.name,
        x = 18, y = 38, w = 560, h = 20, size = T.f.mini, color = C.text_dim })
    R.theme_chip(p, { x = 700, y = 14, w = 86, h = 36 })
    W.chip(p, { x = 796, y = 14, w = 170, h = 36, text = "返回门牌",
        off_color = C.tile, off_opa = G.tile_opa, off_tcolor = C.text_sub,
        on_click = function() R.go("home") end })
end

local function build_left()
    local g = W.glass_card({ parent = ROOT, x = LC.x, y = LC.y, w = LC.w, h = LC.h })
    local p = g.card
    local dt = T.dept[booking.dept] or T.dept[1]

    -- 部门标签
    local tag = airui.container({ parent = p, x = 16, y = 14, w = 96, h = 32,
        color = dt.accent, radius = 16, border_width = 0 })
    W.glass(tag, dt.accent, 255)
    W.text_mid(p, { text = S.dept_name(booking.dept), x = 16, y = 14, w = 96, h = 32,
        size = T.f.mini, color = C.on_accent, align = airui.TEXT_ALIGN_CENTER })

    -- 状态标签
    local st_txt, st_col = state_of(booking)
    local st = airui.container({ parent = p, x = 396, y = 14, w = 104, h = 32,
        color = st_col, radius = 16, border_width = 0 })
    W.glass(st, st_col, 60)
    W.text_mid(p, { text = st_txt, x = 396, y = 14, w = 104, h = 32,
        size = T.f.mini, color = st_col, align = airui.TEXT_ALIGN_CENTER })

    -- 主题与负责人
    W.text_mid(p, { text = W.clip(booking.topic, 10), x = 16, y = 54, w = 480, h = 34,
        size = T.f.h1, color = C.text })
    W.text_mid(p, { text = "负责人 " .. S.owner_text(booking.owner), x = 16, y = 92, w = 480, h = 22,
        size = T.f.mini, color = C.text_sub })

    -- 时段面板
    local tp = airui.container({ parent = p, x = 16, y = 122, w = 484, h = 104,
        color = C.tile, radius = T.r.panel, border_width = 0 })
    W.glass(tp, C.tile, G.tile_opa)
    W.text_mid(tp, { text = "预约时段", x = 14, y = 10, w = 200, h = 20,
        size = T.f.mini, color = C.text_dim })
    W.text_mid(tp, { text = S.fmt(booking.start) .. " - " .. S.fmt(booking.start + booking.dur),
        x = 14, y = 32, w = 300, h = 38, size = 28, color = dt.accent })
    W.text_mid(tp, { text = string.format("时长 %d 小时 · %d 人 · %s", booking.dur,
        booking.seats, S.dept_name(booking.dept)), x = 14, y = 72, w = 456, h = 22,
        size = T.f.mini, color = C.text_sub })

    -- 明细行
    local rows = {
        { "预约日期", S.day_names[booking.day] .. "（" .. S.day_of_month(booking.day) .. " 日）" },
        { "当前状态", st_txt },
        { "预约工号", (booking.emp and booking.emp ~= "") and booking.emp or "访客" },
        { "会议室",   S.room.name },
    }
    for i, row in ipairs(rows) do
        local y = 246 + (i - 1) * 40
        W.text_mid(p, { text = row[1], x = 16, y = y, w = 120, h = 22,
            size = T.f.mini, color = C.text_dim })
        W.text_mid(p, { text = row[2], x = 150, y = y, w = 350, h = 22,
            size = T.f.mini, color = C.text })
    end

    -- 分隔虚线 + 脚注
    W.shape(p, { x = 16, y = 230, w = 484, h = 1, items = {
        { type = "line", x1 = 0, y1 = 0, x2 = 484, y2 = 0, color = C.divider,
          width = 1, opacity = 110, dash_width = 6, dash_gap = 6 },
    } })
    W.text_mid(p, { text = "门牌终端 · 密码用于自助取消与修改", x = 16, y = 404, w = 484, h = 22,
        size = T.f.mini, color = C.text_dim })
    return g
end

local function build_right()
    local g = W.glass_card({ parent = ROOT, x = RC.x, y = RC.y, w = RC.w, h = RC.h })
    local p = g.card
    W.text_mid(p, { text = "预约操作", x = 16, y = 12, w = 180, h = 20,
        size = T.f.mini, color = C.text_dim })

    W.button(p, { x = 16, y = 42, w = 134, h = 46, text = "编辑", size = T.f.body,
        color = C.warn, tcolor = C.on_accent, on_click = function() M.action("edit") end })
    W.button(p, { x = 158, y = 42, w = 134, h = 46, text = "删除", size = T.f.body,
        color = C.danger, tcolor = 0xFFFFFF, on_click = function() M.action("del") end })
    W.button(p, { x = 300, y = 42, w = 130, h = 46, text = "返回", size = T.f.body,
        color = C.tile, opa = G.tile_opa, tcolor = C.text_sub,
        on_click = function() R.go("home") end })

    ui.hint = W.text_mid(p, { text = "编辑 / 删除可用预约密码或管理员密码", x = 16, y = 100,
        w = 414, h = 20, size = T.f.mini, color = C.text_sub })

    local box = airui.container({ parent = p, x = 16, y = 126, w = 414, h = 44,
        color = C.tile, radius = T.r.panel, border_width = 0 })
    W.glass(box, C.tile, G.tile_opa)
    ui.pwd_lbl = W.text_mid(box, { text = "", x = 8, y = 0, w = 398, h = 44,
        size = 22, color = C.text_dim, align = airui.TEXT_ALIGN_CENTER })

    -- 预约规则（键盘弹出时原位清空，不用 hide/open）
    ui.rule_lbls = {}
    for i, text in ipairs(RULES) do
        ui.rule_lbls[i] = W.text_mid(p, { text = text, x = 16, y = 210 + (i - 1) * 32,
            w = 414, h = 22, size = T.f.mini, color = C.text_sub })
    end

    ui.numpad = W.numpad(p, { x = 16, y = 210, w = 414, h = 276, gap = 10,
        on_key = function(k)
            if k == "清空" then
                pwd = ""
            elseif k == "退格" then
                if #pwd > 0 then pwd = pwd:sub(1, #pwd - 1) end
            else
                if #pwd < 8 then pwd = pwd .. k end
            end
            refresh_pwd()
        end })
    return g
end

-- 编辑 / 删除：第一次点只弹键盘，第二次点做密码校验
-- 删除放宽到「预约密码 或 管理员密码」，这样管理员能删掉任意一条别人的预约
function M.action(kind)
    if pwd_mode ~= kind then
        if pwd_mode ~= nil then set_pwd_mode(nil) end
        set_pwd_mode(kind)
        return
    end
    -- 管理员密码对「编辑」和「删除」都放行，可处理任意一条预约
    local ok = pwd ~= "" and (pwd == booking.pwd or pwd == S.admin_pwd)
    if not ok then
        R.toast("密码错误")
        pwd = ""
        refresh_pwd()
        return
    end
    if kind == "del" then
        local day = booking.day
        S.remove(idx)
        R.go_toast("home", { day = day }, S.day_names[day] .. " 的预约已删除")
    else
        R.go("booking", { idx = idx })
    end
end

function M.root()
    return PAGE
end

function M.destroy()
    if PAGE then
        pcall(function() PAGE:destroy() end)
        PAGE = nil
    end
    ROOT = nil
    idx, booking = nil, nil
    pwd_mode, pwd = nil, ""
    ui = {}
end

function M.create(args)
    M.destroy()
    S.refresh()
    idx = args and args.idx
    booking = idx and S.get(idx) or nil
    if not booking then
        R.go_toast("home", nil, "该预约已不存在")
        return
    end

    PAGE = airui.container({ parent = airui.screen, x = 0, y = 0, w = SW, h = SH,
        color = 0x000000, color_opacity = 0, border_width = 0 })
    ROOT = PAGE

    build_topbar()
    build_left()
    build_right()
    set_pwd_mode(nil)              -- 初始收起键盘，展示预约规则
    refresh_pwd()
    log.info("page_detail", "详情页已创建", idx)
end

return M
