--[[
@module  ui_form
@summary 新增条目表单浮层：类型选择 + 四个字段（名称/时间/地点/联系方式）+ 保存
@version 1.0
@date    2026.10.30
@usage
local F = require "ui_form"
F.open(function() ... end)   -- 保存成功后的回调（刷新列表）
每个文本字段点击后调 ui_input.open 编辑。
]]

local conf = require "conf"
local theme = require "theme"
local store = require "store"
local ui_input = require "ui_input"
local ui_alert = require "ui_alert"

local M = {}

local SW, SH = conf.W, conf.H
local C = theme.C

local root, panel
local chip_found, chip_lost
local rows = {}

local fields = { kind = "found", name = "", time = "", place = "", contact = "" }
local on_saved = nil

local function now_str()
    return os.date("%Y-%m-%d %H:%M")
end

local function refresh_field(key)
    local r = rows[key]
    if not r then return end
    local v = fields[key] or ""
    if v == "" then
        r.lb:set_text(r.ph)
        r.lb:set_color(C.ink3)
    else
        r.lb:set_text(v)
        r.lb:set_color(C.ink)
    end
end

local function set_kind(k)
    fields.kind = k
    chip_found:set_active(k == "found")
    chip_lost:set_active(k == "lost")
end

local function save()
    local ok, res = store.add(fields)
    if not ok then
        ui_alert.alert(res)
        return
    end
    M.close()
    ui_alert.toast("已登记：" .. res.name)
    if on_saved then on_saved() end
end

local function field_row(parent, y, title, key, ph)
    theme.label(parent, 36, y + 8, 120, 24, title, 18, C.ink2)
    local box = airui.container({
        parent = parent, x = 168, y = y, w = 470, h = 46,
        color = C.card2, radius = 8, border_color = C.line2, border_width = 1,
        on_click = function()
            ui_input.open({
                title = title,
                initial = fields[key],
                on_done = function(t)
                    fields[key] = t
                    refresh_field(key)
                end,
            })
        end,
    })
    local lb = theme.label(box, 14, 11, 440, 24, ph, 17, C.ink3)
    rows[key] = { box = box, lb = lb, ph = ph }
end

function M.build()
    if root then return end

    root = airui.container({
        parent = nil, x = 0, y = 0, w = SW, h = SH,
        color = 0x000000, color_opacity = 150, radius = 0, border_width = 0,
    })
    root:set_hidden(true)

    panel = theme.card(root, math.floor((SW - 680) / 2), 48, 680, 504, C.panel, 16, C.line2, 1)

    theme.label(panel, 32, 20, 320, 32, "新增条目", 24, C.ink)

    -- 类型选择
    theme.label(panel, 36, 72, 120, 24, "类型", 18, C.ink2)
    chip_found = theme.chip(panel, 168, 64, 120, 40, "拾得", 18, function() set_kind("found") end)
    chip_lost = theme.chip(panel, 300, 64, 120, 40, "遗失", 18, function() set_kind("lost") end)

    -- 四个字段
    field_row(panel, 132, "物品名称", "name", "点击填写物品名称")
    field_row(panel, 198, "时间", "time", "默认当前时间")
    field_row(panel, 264, "地点", "place", "点击填写地点")
    field_row(panel, 330, "联系方式", "contact", "点击填写联系方式")

    theme.button(panel, 32, 432, 300, 52, "取消", 20, function() M.close() end, "ghost")
    theme.button(panel, 348, 432, 300, 52, "保存", 20, function() save() end, "primary")
end

function M.open(cb)
    M.build()
    on_saved = cb
    fields.kind = "found"
    fields.name = ""
    fields.time = now_str()
    fields.place = ""
    fields.contact = ""

    set_kind("found")
    refresh_field("name")
    refresh_field("time")
    refresh_field("place")
    refresh_field("contact")

    root:set_hidden(false)
end

function M.close()
    on_saved = nil
    if root then root:set_hidden(true) end
end

return M
