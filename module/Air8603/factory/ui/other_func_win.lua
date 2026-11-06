--[[
@module  other_func_win
@summary 功能测试页面（TabOS 深色玻璃态）——UVC / RS485 / 串口 / 录音播放 外设开关、状态与测试入口
@version 1.4
@date    2026.10.30
@author  江访
@usage
订阅: OPEN_OTHER_FUNC_WIN
发布: OTHER_FUNC_GET / OTHER_FUNC_SET(id, enabled)
订阅: OTHER_FUNC_STATUS(list) / OTHER_FUNC_CHANGED(list) / OTHER_FUNC_SET_RESULT(id, ok, err)

页面按 UVC / RS485 / 串口 / 音频 四组展示实例，组内保持 config.peripherals 声明顺序。
RS485 不管配了几路，列表里只出一行「RS485 测试」（见 MERGE_TITLE），几路全进同一个
收发测试页逐路列出；其余 type 一条配置一行，每条独立开关，下方显示驱动上报的状态描述。
分组标题默认取 TYPE_TITLE，配置条目写了 title 时用条目自己的（摄像头是人脸识别模组
的板子写 "摄像头"，避免「UVC 摄像头」分组配「人脸识别摄像头」行名打架）。

行可点：UVC 行进预览页（预览/拍照/录像），RS485 行进收发测试页（发送 + 收发历史），
音频行进录音播放测试页（录音/停止/播放），开窗事件见 TYPE_PAGE；没有测试页的 type 行不可点。
开关只管供电与接口打开。
合并行的开关一次通断该 type 的全部实例。
]]

local theme = require "ui_theme"

local window_id = nil
local main_container = nil

local sw, sh = 480, 800
local pad = 15

-- 外设 type → 分组标题（顺序按 TYPE_ORDER 定）
local TYPE_TITLE = {
    uvc   = "UVC 摄像头",
    rs485 = "RS485",
    uart  = "串口",
    audio = "音频",
}
local TYPE_ORDER = { "uvc", "rs485", "uart", "audio" }

-- 外设 type → 子页开窗事件；nil 表示该 type 暂无测试页，行不可点
local TYPE_PAGE = {
    uvc   = "OPEN_UVC_PREVIEW_WIN",
    rs485 = "OPEN_RS485_TEST_WIN",
    uart  = nil,
    audio = "OPEN_AUDIO_TEST_WIN",
}

-- 合并成单行入口的 type：配置里有几条都只出一行，几路全在子页里逐路列
local MERGE_TITLE = {
    rs485 = "RS485 测试",
}

-- 实例行控件：行键 → { info_label, info_w, switch, members, state, info }
-- 合并行的行键是 type 名，其余行的行键是实例 id
local rows = {}
-- 实例 id → 行键（合并行下多个 id 指向同一行）
local row_of = {}

local function update_screen_size()
    sw, sh = screen_w or 480, screen_h or 800
    sw, sh = theme.content_fit(sw, sh)
    pad = theme.page_margin()
end

-- 提示弹窗（标题 + 一句说明 + 单个确定按钮）
local function show_tip(text)
    airui.msgbox({
        title = "提示", text = text, buttons = { "确定" },
        on_action = function(self) self:hide() end,
    })
end

--[[
@function collect_instances
@summary 按 usb_mode 过滤后的 config.peripherals 收集可管理实例，按 type 分组并保持声明顺序
合并类型的全部实例并成一行，成员 id 全挂在这一行上
@return table  { { type=, title=, items={ {key=, name=, type=, page=, members={id...}}, ... } }, ... }
]]
local function collect_instances()
    local cfg = _G.project_config or {}
    local usb_mode = require "usb_mode"
    local list = usb_mode.filter(cfg.peripherals)
    local groups = {}
    local by_type = {}
    local seen = {}
    if type(list) == "table" then
        for i, p in ipairs(list) do
            local t = p and p.type
            if TYPE_TITLE[t] then
                -- id 是 UI 与业务层的匹配键，必填且全表唯一；缺/重直接跳过，与业务层同规则
                if not p.id then
                    log.warn("other_func_win", "外设缺 id，跳过", t, "#" .. i)
                elseif seen[p.id] then
                    log.warn("other_func_win", "外设 id 重复，跳过", p.id)
                else
                    seen[p.id] = true
                    local g = by_type[t]
                    if not g then
                        g = { type = t, title = p.title or TYPE_TITLE[t], items = {} }
                        by_type[t] = g
                        groups[#groups + 1] = g
                    end
                    if MERGE_TITLE[t] then
                        -- 同 type 全并一行，行里挂全部成员 id
                        local it = g.items[1]
                        if not it then
                            it = {
                                key = t,
                                name = MERGE_TITLE[t],
                                type = t,
                                page = TYPE_PAGE[t],
                                members = {},
                            }
                            g.items[1] = it
                        end
                        it.members[#it.members + 1] = p.id
                    else
                        g.items[#g.items + 1] = {
                            key = p.id,
                            name = p.name or p.id or t,
                            type = t,
                            page = TYPE_PAGE[t],
                            members = { p.id },
                        }
                    end
                end
            end
        end
    end

    -- 分组按 TYPE_ORDER 排定，未出现的 type 不建组
    local out = {}
    for _, t in ipairs(TYPE_ORDER) do
        if by_type[t] then out[#out + 1] = by_type[t] end
    end
    return out
end

--[[
@function build_item_row
@summary 单行入口：名称 + 状态描述 + （可点进子页）+ 开关
@param parent 父容器
@param x, y, w, h 行几何
@param it 实例行 { key, name, type, page, members }
]]
local function build_item_row(parent, x, y, w, h, it)
    -- 有子页的行整行可点；开关是行的子控件，点开关不会冒泡到行的 on_click
    local row = theme.box(parent, {
        x = x, y = y, w = w, h = h, color = theme.C.black, opa = 0,
        on_click = it.page and function() sys.publish(it.page, it.members[1]) end or nil,
    })

    local pad2 = theme.dp(12)
    local gap2 = theme.dp(10)
    local sw_w = theme.dp(52)
    local sw_h = theme.dp(28)
    -- 可点行在开关左边补一个 ">" 提示，宽度从文本区让出
    local chev_w = it.page and (theme.dp(10) + gap2) or 0

    local fs = theme.fs("body")
    local fs_sub = theme.fs("micro")
    local lh = fs + 3
    local lh_sub = fs_sub + 3
    local total = lh + theme.dp(2) + lh_sub
    local ty = math.floor((h - total) / 2)
    if ty < 0 then ty = 0 end

    local txw = w - pad2 * 2 - sw_w - gap2 - chev_w
    if txw < theme.dp(40) then txw = theme.dp(40) end

    theme.label(row, {
        x = pad2, y = ty, w = txw, h = lh,
        text = theme.fit_text(tostring(it.name or ""), txw, fs), px_size = fs,
        color = theme.C.t1, align = airui.TEXT_ALIGN_LEFT,
    })

    local info_label = theme.label(row, {
        x = pad2, y = ty + lh + theme.dp(2), w = txw, h = lh_sub,
        text = "读取中...", px_size = fs_sub,
        color = theme.C.t3, align = airui.TEXT_ALIGN_LEFT,
    })

    if it.page then
        theme.label(row, {
            x = w - pad2 - sw_w - gap2 - theme.dp(10),
            y = math.floor((h - lh) / 2), w = theme.dp(10), h = lh,
            text = ">", px_size = fs,
            color = theme.C.t3, align = airui.TEXT_ALIGN_CENTER,
        })
    end

    local togg = theme.switch(row, {
        x = w - pad2 - sw_w, y = math.floor((h - sw_h) / 2),
        w = sw_w, h = sw_h, checked = false,
        on_change = function(handle)
            -- 合并行一次通断该 type 的全部实例
            local on = handle:get_state()
            for i = 1, #it.members do
                sys.publish("OTHER_FUNC_SET", it.members[i], on)
            end
        end,
    })

    local rec = {
        info_label = info_label, info_w = txw, switch = togg,
        members = it.members, state = {}, info = {},
    }
    rows[it.key] = rec
    for i = 1, #it.members do
        row_of[it.members[i]] = it.key
    end
end

local function build_ui()
    update_screen_size()
    main_container = theme.page_bg(airui.screen, sw, sh)
    local _, th = theme.header(main_container, {
        x = pad, y = pad, w = sw - 2 * pad,
        title = "功能测试",
        sub = "外设接口开关与状态",
        on_back = function() exwin.close(window_id) end,
    })

    local y = pad + th + pad
    local card_w = sw - 2 * pad
    local avail = sh - y - pad

    -- 内容区可滚动：实例数随机型变化（1~4 条），放不下时向下滚
    local body = theme.box(main_container, {
        x = pad, y = y, w = card_w, h = avail,
        color = theme.C.black, opa = 0, scrollable = true,
    })

    local groups = collect_instances()
    if #groups == 0 then
        theme.label(body, {
            x = 0, y = theme.dp(20), w = card_w, h = theme.fs("body") + 3,
            text = "当前机型未配置外设", px_size = theme.fs("body"),
            color = theme.C.t3, align = airui.TEXT_ALIGN_CENTER,
        })
        return
    end

    local gap = theme.dp(12)
    local row_h = theme.dp(56)
    local sec_h = theme.fs("micro") + 3 + theme.dp(6)
    local bw = 1
    local cy = 0

    for _, g in ipairs(groups) do
        theme.section(body, {
            x = theme.dp(4), y = cy, w = card_w - theme.dp(8), h = sec_h,
            text = g.title, px_size = theme.fs("micro"), color = theme.C.t3,
        })
        cy = cy + sec_h

        local n = #g.items
        local card = theme.card(body, {
            x = 0, y = cy, w = card_w, h = n * row_h + 2 * bw, border_w = bw,
        })
        local inner_w = card_w - 2 * bw
        for i, it in ipairs(g.items) do
            local ry = (i - 1) * row_h
            build_item_row(card, 0, ry, inner_w, row_h, it)
            if i < n then
                theme.divider(card, {
                    x = theme.dp(12), y = ry + row_h, w = inner_w - 2 * theme.dp(12),
                })
            end
        end
        cy = cy + n * row_h + 2 * bw + gap
    end

    theme.label(body, {
        x = 0, y = cy, w = card_w, h = theme.fs("micro") + 3,
        text = "点击行进入测试页 | 开关只控制供电与接口打开", px_size = theme.fs("micro"),
        color = theme.C.t3, align = airui.TEXT_ALIGN_CENTER,
    })
end

-- 开关动作容错：theme.switch 返回的是普通 table，没有 is_destroyed，只能靠 pcall 兜住
local function safe_switch(togg, method, ...)
    if type(togg) ~= "table" or type(togg[method]) ~= "function" then return end
    pcall(togg[method], togg, ...)
end

--[[
@function row_text
@summary 行的第二行文字：单实例给驱动描述，合并行给「几路 / 打开几路」
@param r 行记录
@return string
]]
local function row_text(r)
    local n = #r.members
    local on, known = 0, 0
    for i = 1, n do
        local v = r.state[r.members[i]]
        if v ~= nil then
            known = known + 1
            if v then on = on + 1 end
        end
    end
    if known == 0 then return "驱动未就绪" end
    if n == 1 then return tostring(r.info[r.members[1]] or "") end
    return string.format("%d 路 | 已打开 %d/%d", n, on, n)
end

--[[
@function update_row
@summary 按行内各实例的状态刷新文字与开关
@param r 行记录
]]
local function update_row(r)
    if not r then return end
    local n = #r.members
    local on, known = 0, 0
    for i = 1, n do
        local v = r.state[r.members[i]]
        if v ~= nil then
            known = known + 1
            if v then on = on + 1 end
        end
    end
    if r.info_label and not r.info_label:is_destroyed() then
        r.info_label:set_text(theme.fit_text(row_text(r), r.info_w or 0, theme.fs("micro")))
    end
    if known == 0 then
        safe_switch(r.switch, "set_state", false)
        safe_switch(r.switch, "set_enabled", false)
    else
        safe_switch(r.switch, "set_enabled", true)
        -- 合并行要全开才算开，部分打开时开关保持关
        safe_switch(r.switch, "set_state", on == n)
    end
end

--[[
@function apply_list
@summary 用驱动状态列表刷新各行开关与状态描述
@param list { { id=, enabled=, info= }, ... }
]]
local function apply_list(list)
    if type(list) ~= "table" then return end
    -- 每次整份重填，列表始终是全量快照，避免上一轮的残留状态
    for _, r in pairs(rows) do
        r.state = {}
        r.info = {}
    end
    for _, s in ipairs(list) do
        if s then
            local r = rows[row_of[s.id] or s.id]
            if r then
                r.state[s.id] = s.enabled and true or false
                r.info[s.id] = tostring(s.info or "")
            end
        end
    end
    for _, r in pairs(rows) do
        update_row(r)
    end
end

--[[
@function on_set_result
@summary 开关操作回执，失败时给出原因
@param id 实例 id
@param ok 是否成功
@param err 失败原因

开关的最终状态不在这里回滚：on_set 的 CHANGED 带着驱动的权威状态紧随其后，
会把开关对齐到真实值，这里只负责报错。
]]
local function on_set_result(id, ok, err)
    if not ok then
        show_tip(tostring(err or "操作失败"))
    end
end

local function on_create()
    rows = {}
    row_of = {}
    build_ui()
    sys.subscribe("OTHER_FUNC_STATUS", apply_list)
    sys.subscribe("OTHER_FUNC_CHANGED", apply_list)
    sys.subscribe("OTHER_FUNC_SET_RESULT", on_set_result)
    sys.publish("OTHER_FUNC_GET")
end

local function on_destroy()
    sys.unsubscribe("OTHER_FUNC_STATUS", apply_list)
    sys.unsubscribe("OTHER_FUNC_CHANGED", apply_list)
    sys.unsubscribe("OTHER_FUNC_SET_RESULT", on_set_result)
    if main_container then main_container:destroy(); main_container = nil end
    rows = {}
    row_of = {}
end

local function on_get_focus() end
local function on_lose_focus() end

local function open_handler()
    window_id = exwin.open({
        on_create = on_create,
        on_destroy = on_destroy,
        on_lose_focus = on_lose_focus,
        on_get_focus = on_get_focus,
    })
end

sys.subscribe("OPEN_OTHER_FUNC_WIN", open_handler)
