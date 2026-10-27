--[[
@module  ui_regtool
@summary 寄存器调试工具：手选从站/功能码/地址/数量发起读写，显示原始报文与解析结果
@version 1.0.0
@date    2026.10.25
]]
local conf = require "conf"
local theme = require "theme"
local modbus = require "modbus"
local mbdev = require "mbdev"
local mbmaster = require "mbmaster"

local M = {}
local C = theme.C
local SW, SH = conf.W, conf.H
local NAV_Y = 548

local root = nil
local app_ref = nil

local P = { slave = 1, addr = 0, count = 4, value = 0 }
local fc = 0x03

local RANGES = {
    slave = { 1, 247, 1, 10 },
    addr  = { 0, 255, 1, 16 },
    count = { 1, 40, 1, 4 },
    value = { 0, 65535, 1, 100 },
}

local stepLabels = {}
local fcBtns = {}
local txVal, rxVal, resultVal
local tableRows = {}
local headerRight

local READ_FC = { 0x01, 0x02, 0x03, 0x04 }
local WRITE_FC = { 0x05, 0x06, 0x10 }

local function clamp_key(key, v)
    local r = RANGES[key]
    if v < r[1] then v = r[1] end
    if v > r[2] then v = r[2] end
    return v
end

local function mk_stepper(parent, key, name, y)
    local r = RANGES[key]
    theme.label(parent, 14, y + 2, 74, 22, name, 13, C.ink3)
    local function delta(d)
        P[key] = clamp_key(key, P[key] + d)
        if stepLabels[key] then stepLabels[key]:set_text(tostring(P[key])) end
    end
    theme.button(parent, 92, y, 42, 24, "-" .. r[4], 11, C.panel2, C.ink2,
        function() theme.defer(function() delta(-r[4]) end) end, 6)
    theme.button(parent, 138, y, 34, 24, "-", 14, C.panel2, C.ink2,
        function() theme.defer(function() delta(-r[3]) end) end, 6)
    stepLabels[key] = theme.label(parent, 176, y, 76, 24, tostring(P[key]), 15, C.ink,
        airui.TEXT_ALIGN_CENTER)
    theme.button(parent, 256, y, 34, 24, "+", 14, C.panel2, C.ink2,
        function() theme.defer(function() delta(r[3]) end) end, 6)
    theme.button(parent, 294, y, 42, 24, "+" .. r[4], 11, C.panel2, C.ink2,
        function() theme.defer(function() delta(r[4]) end) end, 6)
end

local function refresh_fc()
    for _, b in pairs(fcBtns) do
        if b.btn then
            local on = (b.fc == fc)
            b.btn:set_style({
                bg_color = on and (b.write and C.amber or C.cyan) or C.panel2,
                text_color = on and 0x05141C or C.ink2,
                border_color = on and (b.write and C.amber or C.cyan) or C.line2,
                radius = 6,
            })
        end
    end
end

local function build_param_card()
    local c = theme.card(root, 24, 68, 470, 250)
    theme.accent_bar(c, 16, 0, 50, C.amber)
    theme.label(c, 14, 10, 240, 22, "请求参数", 16, C.ink)

    mk_stepper(c, "slave", "从站号", 36)
    mk_stepper(c, "addr", "起始地址", 68)

    theme.label(c, 14, 100, 74, 22, "功能码", 13, C.ink3)
    local all = {}
    for _, f in ipairs(READ_FC) do all[#all + 1] = { fc = f, write = false } end
    for _, f in ipairs(WRITE_FC) do all[#all + 1] = { fc = f, write = true } end
    for i, a in ipairs(all) do
        local x = 92 + (i - 1) * 53
        local txt = string.format("%02X", a.fc)
        local btn = theme.button(c, x, 98, 49, 26, txt, 12, C.panel2, C.ink2, function()
            theme.defer(function()
                fc = a.fc
                refresh_fc()
                if app_ref then
                    app_ref.toast("功能码 " .. txt .. " · " .. (modbus.FC_NAME[a.fc] or ""))
                end
            end)
        end, 6)
        fcBtns[i] = { btn = btn, fc = a.fc, write = a.write }
    end
    theme.label(c, 92, 126, 380, 14, "01/02 位读写  03/04 字读取  05 单线圈  06 单寄存器  10 多寄存器", 10, C.ink3)

    mk_stepper(c, "count", "数量", 142)
    mk_stepper(c, "value", "写入值", 176)

    theme.button(c, 14, 208, 110, 36, "读取", 17, C.cyan, 0x05141C, function()
        theme.defer(M.do_read)
    end, 9)
    theme.button(c, 136, 208, 110, 36, "写入", 17, C.amber, 0x05141C, function()
        theme.defer(M.do_write)
    end, 9)
    theme.button(c, 258, 208, 110, 36, "清空", 15, C.panel2, C.ink2, function()
        theme.defer(function()
            if txVal then txVal:set_text("") end
            if rxVal then rxVal:set_text("") end
            if resultVal then resultVal:set_text("") end
            for _, r in ipairs(tableRows) do
                for _, l in ipairs(r) do l:set_text("") end
            end
        end)
    end, 9)
end

local function build_frame_card()
    local c = theme.card(root, 506, 68, 494, 250)
    theme.accent_bar(c, 16, 0, 50, C.green)
    theme.label(c, 14, 10, 240, 22, "报文监视 (HEX)", 16, C.ink)

    theme.label(c, 14, 40, 30, 18, "TX", 12, C.cyan)
    txVal = theme.label(c, 48, 38, 432, 40, "", 11, C.ink2)
    theme.label(c, 14, 88, 30, 18, "RX", 12, C.green)
    rxVal = theme.label(c, 48, 86, 432, 40, "", 11, C.ink2)
    theme.box(c, 14, 132, 466, 1, C.line)
    resultVal = theme.label(c, 14, 142, 466, 60, "", 13, C.ink)
    theme.label(c, 14, 210, 466, 30,
        "提示：写操作会真实修改从站寄存器，轮询时即可看到新值", 11, C.ink3)
end

local function build_table()
    local c = theme.card(root, 24, 330, 976, 206)
    theme.accent_bar(c, 16, 0, 50, C.violet)
    theme.label(c, 16, 10, 240, 22, "响应解析", 16, C.ink)

    local heads = { "#", "地址", "HEX", "UINT16", "INT16", "FLOAT32", "BIT" }
    local hx = { 16, 62, 160, 276, 376, 476, 606 }
    for i, h in ipairs(heads) do
        theme.label(c, hx[i], 40, 100, 18, h, 12, C.ink3)
    end
    theme.box(c, 16, 58, 944, 1, C.line)

    for i = 1, 6 do
        local y = 64 + (i - 1) * 24
        local r = {}
        for j = 1, 7 do
            r[j] = theme.label(c, hx[j], y, 120, 20, "", 12, C.ink2)
        end
        tableRows[i] = r
    end
end

local function bits_text(v)
    local t = {}
    for j = 0, 15 do
        t[16 - j] = (((v >> j) & 1) == 1) and "1" or "0"
    end
    return table.concat(t)
end

-- ==================== 操作 ====================
function M.do_read()
    local res, err = mbmaster.read_raw(P.slave, fc, P.addr, P.count)
    if txVal then txVal:set_text(modbus.hex(mbmaster.last_tx())) end
    if rxVal then rxVal:set_text(modbus.hex(mbmaster.last_rx())) end
    for _, r in ipairs(tableRows) do
        for _, l in ipairs(r) do l:set_text("") end
    end

    if res and res.ok then
        local txt = string.format("FC%02X %s 成功，返回 %s",
            fc, modbus.FC_NAME[fc] or "",
            (fc == 0x01 or fc == 0x02) and (tostring(res.count) .. " 位") or (tostring(res.count) .. " 寄存器"))
        if resultVal then resultVal:set_text(txt); resultVal:set_color(C.ok) end

        if res.regs then
            for i, v in ipairs(res.regs) do
                local r = tableRows[i]
                if not r then break end
                local pair = { v, res.regs[i + 1] or 0 }
                local u32 = modbus.decode(pair, "u32", 1)
                r[1]:set_text(tostring(i - 1))
                r[2]:set_text(modbus.addr_text(fc, P.addr + i - 1))
                r[3]:set_text(string.format("0x%04X", v))
                r[4]:set_text(tostring(v))
                r[5]:set_text(tostring(modbus.decode({ v }, "i16", 1)))
                r[6]:set_text(string.format("%.4f", modbus.decode(pair, "f32", 1)))
                r[7]:set_text(bits_text(v))
            end
        elseif res.bits then
            for i, b in ipairs(res.bits) do
                local r = tableRows[i]
                if not r then break end
                r[1]:set_text(tostring(i - 1))
                r[2]:set_text(modbus.addr_text(fc, P.addr + i - 1))
                r[3]:set_text(b and "0xFF" or "0x00")
                r[4]:set_text(b and "1" or "0")
                r[5]:set_text(b and "1" or "0")
                r[6]:set_text("—")
                r[7]:set_text(b and "ON" or "OFF")
            end
        end
    else
        local msg
        if res then
            msg = "异常响应：" .. modbus.err_text(res)
        else
            msg = "无响应：" .. tostring(err or "未知错误")
        end
        if resultVal then resultVal:set_text(msg); resultVal:set_color(C.danger) end
    end
end

function M.do_write()
    if fc ~= 0x05 and fc ~= 0x06 and fc ~= 0x10 then
        if resultVal then
            resultVal:set_text("当前功能码 " .. string.format("%02X", fc) .. " 为读功能码，请切换到 05/06/10 再写")
            resultVal:set_color(C.amber)
        end
        return
    end
    local res, err = mbmaster.write_raw(P.slave, fc, P.addr, P.value, P.count)
    if txVal then txVal:set_text(modbus.hex(mbmaster.last_tx())) end
    if rxVal then rxVal:set_text(modbus.hex(mbmaster.last_rx())) end
    for _, r in ipairs(tableRows) do
        for _, l in ipairs(r) do l:set_text("") end
    end
    if res and res.ok then
        if resultVal then
            resultVal:set_text(string.format("写入成功：%s  地址 %s  值 %d",
                modbus.FC_NAME[fc] or "", modbus.addr_text(fc, P.addr), P.value))
            resultVal:set_color(C.ok)
        end
        if app_ref then app_ref.toast("写入成功") end
    else
        local msg = res and ("异常响应：" .. modbus.err_text(res)) or ("无响应：" .. tostring(err or "未知"))
        if resultVal then resultVal:set_text(msg); resultVal:set_color(C.danger) end
        if app_ref then app_ref.toast("写入失败") end
    end
end

-- ==================== 构建 / 刷新 ====================
function M.build(app)
    M.destroy()
    app_ref = app

    root = airui.container({
        parent = nil, x = 0, y = 0, w = SW, h = SH,
        color = C.bg1, radius = 0, border_width = 0,
    })
    theme.gradient(root, 0, 0, SW, SH, C.bg1, C.bg2, 12)

    headerRight = theme.page_header(root, "寄存器调试工具 · Register Tool",
        mbmaster.transport_name() .. " · " .. mbmaster.transport_desc(), C.cyan)

    build_param_card()
    build_frame_card()
    build_table()

    theme.navbar(root, "regtool", NAV_Y, function(id)
        if app_ref then app_ref.show(id) end
    end)

    refresh_fc()
    M.refresh()
end

function M.refresh()
    if not root then return end
    if headerRight then
        headerRight:set_text(mbmaster.transport_name() .. " · " .. mbmaster.transport_desc())
    end
end

function M.destroy()
    if root then
        pcall(function() root:destroy() end)
        root = nil
    end
    app_ref = nil
    stepLabels, fcBtns, tableRows = {}, {}, {}
    txVal, rxVal, resultVal, headerRight = nil, nil, nil, nil
end

return M
