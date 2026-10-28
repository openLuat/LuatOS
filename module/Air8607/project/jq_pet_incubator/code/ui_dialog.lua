--[[
@module  ui_dialog
@summary 弹层：添加宠物恒温箱 / 新建房间
@version 1.0
@date    2026.10.28

用「全屏半透明遮罩 + 居中白卡」实现，不依赖 airui.win，
所有子控件坐标都在自己的卡片里绝对定位，行为完全可控。
]]
local conf = require "conf"
local theme = require "theme"
local icon = require "icon"
local store = require "store"

local M = {}
local C = theme.C
local SW, SH = conf.W, conf.H

local overlay = nil

function M.opened() return overlay ~= nil end

function M.close()
    if overlay then
        pcall(function() overlay:destroy() end)
        overlay = nil
    end
end

--------------------------------------------------------------------
-- 外壳
--------------------------------------------------------------------
local function shell(w, h, title, pet_kind)
    M.close()
    overlay = airui.container({
        parent = nil, x = 0, y = 0, w = SW, h = SH,
        color = 0x2C211C, color_opacity = 120,
        radius = 0, border_width = 0,
        on_click = function() M.close() end,
    })
    local panel = theme.card(overlay, math.floor((SW - w) / 2), math.floor((SH - h) / 2),
        w, h, C.card, 26, C.line2, 2)

    theme.shape({ parent = panel, x = 24, y = 16, w = 40, h = 40,
                  items = icon.pet(pet_kind or "chick", 40, 40, C.butter) })
    theme.label(panel, 72, 20, w - 96, 30, title, 19, C.ink)
    theme.box(panel, 24, 66, w - 48, 2, C.line, 1)
    return panel
end

--------------------------------------------------------------------
-- 可选中卡片
--------------------------------------------------------------------
local function sel_tile(parent, x, y, kind)
    local box = theme.card(parent, x, y, 88, 88, C.card2, 20, C.line, 2)
    theme.shape({ parent = box, x = 18, y = 6, w = 52, h = 52,
                  items = icon.pet(kind, 52, 52, store.PET_COLOR[kind] or C.butter) })
    theme.label_mid(box, 0, 60, 88, 18, store.PET_LABEL[kind] or "", 11, C.ink2, airui.TEXT_ALIGN_CENTER)
    return box
end

local function paint_tile(box, active)
    box:set_color(active and C.pink2 or C.card2)
    box:set_border_color(active and C.pink or C.line, active and 3 or 2)
end

local function chip_row(parent, x, y, w, h, text, active, on_click)
    local btn = theme.tint_button(parent, x, y, w, h, text, 14,
        active and C.pink or C.card2,
        active and C.white or C.ink2,
        on_click, math.floor(h / 2),
        active and C.pink or C.line)
    return btn
end

local function paint_chip(btn, active)
    btn:set_style({
        bg_color = active and C.pink or C.card2,
        text_color = active and C.white or C.ink2,
        border_width = 2,
        border_color = active and C.pink or C.line,
    })
end

--------------------------------------------------------------------
-- 添加设备
--------------------------------------------------------------------
function M.add_device(app, on_done)
    local w, h = 620, 520
    local panel = shell(w, h, "添加宠物恒温箱", "cat")

    local rooms = store.rooms()
    local sel = {
        pet  = store.PET_KIND[1],
        name = conf.presets.pets[1],
        room = rooms[1] and rooms[1].id or 0,
    }

    ------------------------------------------------------------------
    -- 形象
    ------------------------------------------------------------------
    theme.label(panel, 28, 78, 300, 18, "挑选宝贝形象", 13, C.ink2)
    local pet_boxes = {}
    for i, kind in ipairs(store.PET_KIND) do
        local x = 28 + (i - 1) * 108
        local box = sel_tile(panel, x, 100, kind)
        pet_boxes[i] = box
        theme.hot(box, 0, 0, 88, 88, function()
            theme.defer(function()
                sel.pet = kind
                for j, b in ipairs(pet_boxes) do paint_tile(b, store.PET_KIND[j] == kind) end
            end)
        end)
    end

    ------------------------------------------------------------------
    -- 名字
    ------------------------------------------------------------------
    theme.label(panel, 28, 196, 300, 18, "取个名字", 13, C.ink2)
    local name_btns = {}
    for i, nm in ipairs(conf.presets.pets) do
        local col = (i - 1) % 4
        local row = math.floor((i - 1) / 4)
        local x = 28 + col * 144
        local y = 218 + row * 44
        local btn = chip_row(panel, x, y, 132, 38, nm, false, function()
            theme.defer(function()
                sel.name = nm
                for j, b in ipairs(name_btns) do paint_chip(b, conf.presets.pets[j] == nm) end
            end)
        end)
        name_btns[i] = btn
    end

    ------------------------------------------------------------------
    -- 房间
    ------------------------------------------------------------------
    theme.label(panel, 28, 308, 300, 18, "放进哪个房间", 13, C.ink2)
    local room_btns = {}
    local room_ids = {}
    for i, r in ipairs(rooms) do
        if i <= 6 then
            local col = (i - 1) % 3
            local row = math.floor((i - 1) / 3)
            local x = 28 + col * 196
            local y = 330 + row * 44
            local rid = r.id
            local btn = chip_row(panel, x, y, 180, 38, r.name, false, function()
                theme.defer(function()
                    sel.room = rid
                    for j, b in ipairs(room_btns) do paint_chip(b, room_ids[j] == rid) end
                end)
            end)
            room_btns[#room_btns + 1] = btn
            room_ids[#room_ids + 1] = rid
        end
    end
    if #room_btns == 0 then
        theme.label(panel, 28, 330, 400, 20, "还没有房间，请先在主页新建房间", 12, C.red)
    end

    ------------------------------------------------------------------
    -- 按钮
    ------------------------------------------------------------------
    theme.tint_button(panel, 28, 436, 270, 48, "取消", 16, C.card2, C.ink2, function()
        theme.defer(function() M.close() end)
    end, 24)
    theme.button(panel, 322, 436, 270, 48, "确认添加", 16, C.pink, C.white, function()
        theme.defer(function()
            -- 重名自动加序号，避免卡片看起来一模一样
            local nm = sel.name
            local dup = 0
            for _, d in ipairs(store.devices()) do
                if d.name == nm then dup = dup + 1 end
            end
            if dup > 0 then nm = nm .. " " .. (dup + 1) end

            local d = store.add_device(nm, sel.pet, sel.room)
            M.close()
            if app then
                if d then
                    app.toast("已添加 " .. nm)
                else
                    app.toast("设备数量已达上限 " .. conf.max_devices)
                end
            end
            if on_done then on_done() end
        end)
    end, 24)

    -- 初始选中态
    for i, b in ipairs(pet_boxes) do paint_tile(b, store.PET_KIND[i] == sel.pet) end
    for i, b in ipairs(name_btns) do paint_chip(b, conf.presets.pets[i] == sel.name) end
    for i, b in ipairs(room_btns) do paint_chip(b, room_ids[i] == sel.room) end

    return panel
end

--------------------------------------------------------------------
-- 修改宠物名字
--------------------------------------------------------------------
function M.rename_device(app, id, on_done)
    local d = store.get(id)
    if not d then return end

    local w, h = 520, 316
    local panel = shell(w, h, "给宝贝改名", d.pet or "cat")

    theme.label(panel, 28, 78, 300, 18, "当前名字：" .. d.name, 13, C.ink2)

    local sel = d.name
    local btns = {}
    for i, nm in ipairs(conf.presets.pets) do
        local col = (i - 1) % 4
        local row = math.floor((i - 1) / 4)
        local x = 28 + col * 118
        local y = 104 + row * 50
        local btn = chip_row(panel, x, y, 110, 42, nm, false, function()
            theme.defer(function()
                sel = nm
                for j, b in ipairs(btns) do paint_chip(b, conf.presets.pets[j] == nm) end
            end)
        end)
        btns[i] = btn
    end

    theme.tint_button(panel, 28, 240, 222, 46, "取消", 16, C.card2, C.ink2, function()
        theme.defer(function() M.close() end)
    end, 23)
    theme.button(panel, 270, 240, 222, 46, "保存名字", 16, C.pink, C.white, function()
        theme.defer(function()
            local dd = store.get(id)
            store.rename(dd, sel)
            M.close()
            if app then app.toast("名字已改为 " .. (dd and dd.name or sel)) end
            if on_done then on_done() end
        end)
    end, 23)

    for i, b in ipairs(btns) do paint_chip(b, conf.presets.pets[i] == sel) end
    return panel
end

--------------------------------------------------------------------
-- 新建房间
--------------------------------------------------------------------
function M.add_room(app, on_done)
    local w, h = 520, 316
    local panel = shell(w, h, "新建房间", "rabbit")

    local sel = conf.presets.rooms[1]
    theme.label(panel, 28, 78, 300, 18, "选择房间名称", 13, C.ink2)

    local btns = {}
    for i, nm in ipairs(conf.presets.rooms) do
        local col = (i - 1) % 3
        local row = math.floor((i - 1) / 3)
        local x = 28 + col * 162
        local y = 104 + row * 52
        local btn = chip_row(panel, x, y, 150, 42, nm, false, function()
            theme.defer(function()
                sel = nm
                for j, b in ipairs(btns) do paint_chip(b, conf.presets.rooms[j] == nm) end
            end)
        end)
        btns[i] = btn
    end

    theme.tint_button(panel, 28, 228, 222, 46, "取消", 16, C.card2, C.ink2, function()
        theme.defer(function() M.close() end)
    end, 23)
    theme.button(panel, 270, 228, 222, 46, "创建房间", 16, C.pink, C.white, function()
        theme.defer(function()
            local r = store.add_room(sel)
            M.close()
            if app then app.toast("已新建房间 " .. r.name) end
            if on_done then on_done() end
        end)
    end, 23)

    for i, b in ipairs(btns) do paint_chip(b, conf.presets.rooms[i] == sel) end
    return panel
end

return M
