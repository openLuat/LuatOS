--[[
@module  ui_claim
@summary 认领浮层（拾得 / 遗失通用）：身份证 18 位 + 认领人联系方式登记
@version 1.1
@date    2026.10.30
@usage
local Cm = require "ui_claim"
Cm.open(item, function(it) ... end)   -- 认领成功后的回调
规则：认领（不分拾得/遗失）必须凭身份证（18 位校验位核对）+ 登记联系方式。
数字键盘在「身份证号」与「联系方式」两个字段间切换焦点。
]]

local conf = require "conf"
local theme = require "theme"
local store = require "store"
local ui_alert = require "ui_alert"

local M = {}

local SW, SH = conf.W, conf.H
local C = theme.C

local root, panel, lb_item, lb_place
local id_box, lb_id, lb_id_hint
local contact_box, lb_contact, lb_contact_hint

local id_text = ""
local contact_text = ""
local focus = "id"          -- "id" | "contact"
local cur_item = nil
local on_done = nil

local ID_MAX, CONTACT_MAX = 18, 20

local function set_border(obj, on)
    obj:set_border_color(on and C.accent or C.line2, on and 2 or 1)
end

local function render()
    -- 身份证号
    if id_text == "" then
        lb_id:set_text("请输入 18 位身份证号")
        lb_id:set_color(C.ink3)
    else
        lb_id:set_text(id_text)
        lb_id:set_color(C.ink)
    end
    lb_id_hint:set_text(string.format("%d / %d", #id_text, ID_MAX))
    set_border(id_box, focus == "id")

    -- 联系方式
    if contact_text == "" then
        lb_contact:set_text("请输入认领人联系方式")
        lb_contact:set_color(C.ink3)
    else
        lb_contact:set_text(contact_text)
        lb_contact:set_color(C.ink)
    end
    lb_contact_hint:set_text(string.format("%d / %d", #contact_text, CONTACT_MAX))
    set_border(contact_box, focus == "contact")
end

local function set_focus(f)
    focus = f
    render()
end

local function press(k)
    if k == "del" then
        if focus == "id" then
            id_text = id_text:sub(1, math.max(0, #id_text - 1))
        else
            contact_text = contact_text:sub(1, math.max(0, #contact_text - 1))
        end
    elseif k == "clear" then
        if focus == "id" then id_text = "" else contact_text = "" end
    elseif k == "X" then
        if focus == "id" and #id_text < ID_MAX then id_text = id_text .. "X" end
    else
        if focus == "id" then
            if #id_text < ID_MAX then id_text = id_text .. k end
        else
            if #contact_text < CONTACT_MAX then contact_text = contact_text .. k end
        end
    end
    render()
end

local function confirm()
    if id_text == "" then
        ui_alert.alert("请先输入身份证号")
        return
    end
    if contact_text == "" then
        ui_alert.alert("请登记认领人联系方式")
        return
    end
    local ok, res = store.claim(cur_item and cur_item.id, id_text, contact_text)
    if not ok then
        ui_alert.alert(res)
        return
    end
    M.close()
    ui_alert.toast("认领成功 · 证件尾号 " .. res.claimer_tail)
    if on_done then on_done(res) end
end

local KEYS = {
    { "1", "2", "3" },
    { "4", "5", "6" },
    { "7", "8", "9" },
    { "X", "0", "删除" },
}

function M.build()
    if root then return end

    root = airui.container({
        parent = nil, x = 0, y = 0, w = SW, h = SH,
        color = 0x000000, color_opacity = 150, radius = 0, border_width = 0,
    })
    root:set_hidden(true)

    panel = theme.card(root, math.floor((SW - 560) / 2), 16, 560, 560, C.panel, 16, C.line2, 1)

    theme.label(panel, 28, 14, 300, 30, "凭身份证认领", 24, C.ink)

    lb_item = theme.label(panel, 28, 50, 504, 22, "", 18, C.ink)
    lb_place = theme.label(panel, 28, 74, 504, 18, "", 14, C.ink2)
    theme.label(panel, 28, 96, 504, 18, "认领须出示身份证并登记联系方式，核对通过后完成", 14, C.danger)

    -- 身份证号字段
    theme.label(panel, 28, 120, 120, 20, "身份证号", 14, C.ink3)
    id_box = airui.container({
        parent = panel, x = 28, y = 140, w = 504, h = 44,
        color = C.card2, radius = 8, border_color = C.line2, border_width = 1,
        on_click = function() set_focus("id") end,
    })
    lb_id = theme.label(id_box, 16, 11, 380, 24, "请输入 18 位身份证号", 18, C.ink3)
    lb_id_hint = theme.label(id_box, 430, 12, 60, 22, "0 / 18", 14, C.ink3, airui.TEXT_ALIGN_RIGHT)

    -- 联系方式字段
    theme.label(panel, 28, 192, 120, 20, "联系方式", 14, C.ink3)
    contact_box = airui.container({
        parent = panel, x = 28, y = 212, w = 504, h = 44,
        color = C.card2, radius = 8, border_color = C.line2, border_width = 1,
        on_click = function() set_focus("contact") end,
    })
    lb_contact = theme.label(contact_box, 16, 11, 380, 24, "请输入认领人联系方式", 18, C.ink3)
    lb_contact_hint = theme.label(contact_box, 430, 12, 60, 22, "0 / 20", 14, C.ink3, airui.TEXT_ALIGN_RIGHT)

    -- 数字键盘
    for r = 1, 4 do
        for c = 1, 3 do
            local k = KEYS[r][c]
            local x = 28 + (c - 1) * 112
            local y = 268 + (r - 1) * 54
            theme.button(panel, x, y, 100, 46, k, 20, function()
                press(k == "删除" and "del" or k)
            end, "ghost")
        end
    end
    theme.button(panel, 380, 268, 152, 46, "清空", 18, function() press("clear") end, "ghost")
    theme.button(panel, 380, 322, 152, 46, "示例", 18, function()
        id_text = conf.SAMPLE_ID
        focus = "id"
        render()
    end, "ghost")

    theme.button(panel, 28, 492, 244, 48, "取消", 20, function() M.close() end, "ghost")
    theme.button(panel, 288, 492, 244, 48, "核对认领", 20, function() confirm() end, "lost")
end

function M.open(item, cb)
    M.build()
    cur_item = item
    on_done = cb
    id_text = ""
    contact_text = ""
    focus = "id"

    local kind = (item and item.kind == "found") and "拾得" or "遗失"
    lb_item:set_text(string.format("%s物品：%s", kind, item and item.name or ""))
    lb_place:set_text(string.format("地点：%s", item and item.place or "--"))

    render()
    root:set_hidden(false)
end

function M.close()
    on_done = nil
    cur_item = nil
    if root then root:set_hidden(true) end
end

return M
