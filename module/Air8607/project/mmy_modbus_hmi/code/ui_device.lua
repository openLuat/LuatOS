--[[
@module  ui_device
@summary 从站设备详情页：点位（寄存器）表 + 实时值 + 写入操作 + 设备信息
@version 1.0.0
@date    2026.10.25
]]
local conf = require "conf"
local theme = require "theme"
local modbus = require "modbus"
local mbdev = require "mbdev"
local mbmaster = require "mbmaster"
local mbslave = require "mbslave"

local M = {}
local C = theme.C
local SW, SH = conf.W, conf.H
local NAV_Y = 548

local root = nil
local app_ref = nil
local dev_id = 1
local dev = nil

local titleLabel, modelLabel
local statusPill, statusPillText
local rows = {}
local pollRows = {}
local infoLabels = {}
local offlineBtn, anomalyBtn, resetBtn
local statLabels = {}

local COL = { 14, 102, 246, 356, 436, 552, 614 }

local function fmt_addr(pt)
    if pt.fc == 0x01 then return string.format("0%04d", pt.addr + 1) end
    if pt.fc == 0x02 then return string.format("1%04d", pt.addr + 1) end
    if pt.fc == 0x03 then return string.format("4%04d", pt.addr + 1) end
    return string.format("3%04d", pt.addr + 1)
end

local function dtype_text(pt)
    local s = modbus.DTYPE_NAME[pt.dtype] or pt.dtype
    if pt.scale and pt.scale ~= 1 then
        s = s .. " ×" .. tostring(pt.scale)
    end
    return s
end

local function raw_text(pt)
    local r = mbdev.raw(pt.key)
    if not r or #r == 0 then return "--" end
    if pt.dtype == "bool" then return tostring(r[1]) end
    if pt.bits then return string.format("0x%04X", math.floor(mbdev.get(pt.key) or 0)) end
    return "0x" .. string.format("%04X", r[1] & 0xFFFF)
end

local function step_of(pt)
    if pt.min and pt.max then
        local s = (pt.max - pt.min) / 20
        if s < pt.scale then s = pt.scale end
        return s
    end
    return (pt.scale >= 1) and 10 or 0.5
end

-- ==================== 顶栏 ====================
local function build_header()
    theme.box(root, 0, 0, SW, 56, 0x0A1420)
    theme.accent_bar(root, 0, 54, SW, C.line)
    theme.button(root, 24, 11, 104, 34, "返回", 17, C.panel2, C.ink, function()
        theme.defer(function() if app_ref then app_ref.back_to_dashboard() end end)
    end, 9)

    titleLabel = theme.label(root, 140, 10, 420, 24, "", 21, C.ink)
    modelLabel = theme.label(root, 140, 34, 420, 16, "", 11, C.ink3)
    statusPill, statusPillText = theme.pill(root, 880, 16, 120, 26, "在线", C.ok, 14)
end

-- ==================== 点位表 ====================
local function build_table()
    local card = theme.card(root, 24, 68, 700, 468)
    theme.accent_bar(card, 16, 0, 50, dev.color)

    local heads = { "地址", "点位名称", "数据类型", "原始值", "工程量", "状态", "操作" }
    for i, h in ipairs(heads) do
        theme.label(card, COL[i], 14, 90, 20, h, 12, C.ink3)
    end
    theme.box(card, 14, 36, 672, 1, C.line)

    for i, pt in ipairs(dev.points) do
        if i > 10 then break end
        local y = 44 + i * 40
        if i % 2 == 0 then
            theme.box(card, 8, y - 4, 684, 36, 0x101A28, 4)
        end

        theme.label(card, COL[1], y, 84, 20, fmt_addr(pt), 13, C.ink2)
        theme.label(card, COL[2], y, 140, 20, pt.name, 14, C.ink)
        theme.label(card, COL[3], y, 106, 20, dtype_text(pt), 11, C.ink3)

        local raw = theme.label(card, COL[4], y, 76, 20, "--", 13, C.cyan)
        local val = theme.label(card, COL[5], y, 112, 20, "--", 15, C.ink)
        local pill, pillText = theme.pill(card, COL[6], y, 58, 18, "正常", C.ok, 11)

        local act = nil
        if pt.rw then
            if pt.dtype == "bool" then
                act = theme.button(card, COL[7], y - 2, 72, 22, "切换", 12, C.panel2, C.cyan, function()
                    theme.async(function()
                        local v = mbdev.get(pt.key) or 0
                        if app_ref then app_ref.write(pt.key, (v ~= 0) and 0 or 1) end
                        M.refresh()
                    end)
                end, 6)
            else
                local st = step_of(pt)
                theme.button(card, COL[7], y - 2, 34, 22, "-", 14, C.panel2, C.ink2, function()
                    theme.async(function()
                        local v = (mbdev.get(pt.key) or 0) - st
                        if pt.min and v < pt.min then v = pt.min end
                        if app_ref then app_ref.write(pt.key, v) end
                        M.refresh()
                    end)
                end, 6)
                theme.button(card, COL[7] + 38, y - 2, 34, 22, "+", 14, C.panel2, C.ink2, function()
                    theme.async(function()
                        local v = (mbdev.get(pt.key) or 0) + st
                        if pt.max and v > pt.max then v = pt.max end
                        if app_ref then app_ref.write(pt.key, v) end
                        M.refresh()
                    end)
                end, 6)
            end
        else
            theme.label(card, COL[7], y, 72, 20, "只读", 11, C.ink3)
        end

        rows[i] = { pt = pt, raw = raw, val = val, pill = pill, pillText = pillText, act = act }
    end
end

-- ==================== 设备信息 ====================
local function build_info()
    local c = theme.card(root, 736, 68, 264, 468)
    theme.accent_bar(c, 16, 0, 50, C.cyan)
    theme.label(c, 16, 12, 232, 24, dev.name, 18, C.ink)
    theme.label(c, 16, 38, 232, 18, "型号 " .. dev.model, 12, C.ink3)
    theme.label(c, 16, 58, 232, 18, string.format("从站地址 %d · %s", dev.id, dev.desc or "RS485"), 12, C.ink3)
    theme.box(c, 16, 84, 232, 1, C.line)

    theme.label(c, 16, 94, 232, 20, "轮询报文", 14, C.ink2)
    for i, g in ipairs(dev.polls) do
        if i > 5 then break end
        local y = 118 + (i - 1) * 22
        theme.label(c, 16, y, 232, 18, string.format("FC%02X  %s  ×%d",
            g.fc, modbus.addr_text(g.fc, g.addr), g.count), 12, C.ink3)
    end

    theme.box(c, 16, 244, 232, 1, C.line)

    offlineBtn = theme.button(c, 16, 256, 232, 38, "模拟掉线", 15, C.panel2, C.ink2, function()
        theme.defer(function()
            local b = not mbmaster.is_device_offline(dev.id)
            mbmaster.set_device_offline(dev.id, b)
            if app_ref then app_ref.toast(b and (dev.name .. " 已模拟掉线") or (dev.name .. " 通讯已恢复")) end
            M.refresh()
        end)
    end, 9)

    anomalyBtn = theme.button(c, 16, 302, 232, 38, "注入异常工况", 15, C.panel2, C.amber, function()
        theme.defer(function()
            mbslave.inject_anomaly("temp")
            if app_ref then app_ref.toast("已注入异常工况，观察报警与曲线") end
        end)
    end, 9)

    resetBtn = theme.button(c, 16, 348, 232, 38, "数字量输出全复位", 15, C.panel2, C.red, function()
        theme.async(function()
            local n = 0
            for _, pt in ipairs(dev.points) do
                if pt.rw and pt.dtype == "bool" then
                    local ok, _ = mbmaster.write_point(pt.key, 0)
                    if ok then n = n + 1 end
                end
            end
            if app_ref then app_ref.toast(n > 0 and ("已复位 " .. n .. " 路输出") or "本设备无数字量输出") end
            M.refresh()
        end)
    end, 9)

    theme.box(c, 16, 394, 232, 1, C.line)
    statLabels[1] = theme.label(c, 16, 402, 232, 18, "", 12, C.ink3)
    statLabels[2] = theme.label(c, 16, 422, 232, 18, "", 12, C.ink3)
    statLabels[3] = theme.label(c, 16, 442, 232, 18, "", 12, C.ink3)
end

-- ==================== 构建 ====================
function M.build(app, id)
    M.destroy()
    app_ref = app
    dev_id = id or 1
    dev = mbdev.dev(dev_id)
    if not dev then dev = mbdev.devices()[1]; dev_id = dev.id end

    root = airui.container({
        parent = nil, x = 0, y = 0, w = SW, h = SH,
        color = C.bg1, radius = 0, border_width = 0,
    })
    theme.gradient(root, 0, 0, SW, SH, C.bg1, C.bg2, 12)

    build_header()
    build_table()
    build_info()
    theme.navbar(root, "dashboard", NAV_Y, function(pid)
        if app_ref then app_ref.show(pid) end
    end)

    M.refresh()
end

-- ==================== 刷新 ====================
function M.refresh()
    if not root or not dev then return end

    titleLabel:set_text(string.format("#%d %s", dev.id, dev.name))
    modelLabel:set_text(string.format("%s · %s · %s", dev.model, dev.desc or "RS485",
        mbmaster.transport_name()))

    local online = mbdev.online(dev.id)
    local col = online and C.ok or C.off
    statusPill:set_color(col)
    statusPillText:set_text(online and "通讯正常" or "通讯中断")
    statusPillText:set_color(col)

    for _, r in ipairs(rows) do
        local pt = r.pt
        local st = mbdev.status(pt.key)
        local c = theme.state_color(st)
        r.raw:set_text(raw_text(pt))
        if pt.bits then
            r.val:set_text(mbdev.bit_text(pt.key))
        elseif pt.dtype == "bool" then
            r.val:set_text(mbdev.fmt(pt.key, mbdev.get(pt.key)))
        else
            r.val:set_text(mbdev.fmt(pt.key, mbdev.get(pt.key)) .. pt.unit)
        end
        r.pill:set_color(c)
        r.pillText:set_text(theme.state_text(st))
        r.pillText:set_color(c)
    end

    if offlineBtn then
        local off = mbmaster.is_device_offline(dev.id)
        offlineBtn:set_text(off and "恢复在线" or "模拟掉线")
        offlineBtn:set_style({
            bg_color = off and C.green or C.panel2,
            text_color = off and 0x05141C or C.ink2,
            border_color = off and C.green or C.line2,
            radius = 9,
        })
    end

    if statLabels[1] then
        local npt, nrw = 0, 0
        for _, pt in ipairs(dev.points) do
            npt = npt + 1
            if pt.rw then nrw = nrw + 1 end
        end
        statLabels[1]:set_text(string.format("点位 %d 个（可写 %d）", npt, nrw))
        statLabels[2]:set_text(string.format("当前告警 %d 项", mbdev.dev_alarm_count(dev.id)))
        statLabels[3]:set_text(string.format("轮询周期 %d ms · 重试 %d",
            conf.comm.poll_interval_ms, conf.comm.retry))
    end
end

function M.destroy()
    if root then
        pcall(function() root:destroy() end)
        root = nil
    end
    app_ref = nil
    dev = nil
    rows, pollRows, infoLabels, statLabels = {}, {}, {}, {}
    titleLabel, modelLabel, statusPill, statusPillText = nil, nil, nil, nil
    offlineBtn, anomalyBtn, resetBtn = nil, nil, nil
end

return M
