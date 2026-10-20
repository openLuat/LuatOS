--[[
@module  ui_485
@summary 485 温湿度页：读 Modbus RTU 温湿度传感器（UART2 + SP3485）
@version 1.0
@date    2026.10.19
@usage
    sys.publish("OPEN_485_WIN")

数据来源
    temp_hum.lua：从站 1 / 9600 8N1 / 功能码 0x03
    0x001E = 温度（有符号 16 位，/10.0 ℃）
    0x001F = 湿度（无符号 16 位，/10.0 %RH）
    后台每 5 秒读一次，页面订阅 TEMP_HUM_UPDATE / TEMP_HUM_STATUS 刷新。

界面（设计坐标，基准 800×480）
    y 8    状态卡（760×72）：485 通信状态 + 更新时间
    y 88   温度卡 / 湿度卡（370×150，并排）
    y 248  信息卡（760×88）：从站 / 寄存器 / 波特率 + 错误原因
    y 348  底部按钮：立即读取 + 接线提示
]]

local exwin  = require "exwin"
local ui     = require "ui_kit"
local T      = require "ui_theme"
local sensor = require "temp_hum"

local C, F, S, G = T.COLOR, T.FONT, T.SCREEN, T.GAP
local DW = S.DW

local CFG = sensor.get_config()

-- ===== 布局 =====
local PAD    = G.M
local CARD_W = 370
local CARD_H = 150
local CARD_Y = 88
local INFO_Y = CARD_Y + CARD_H + 10
local INFO_H = 88
local BTN_Y  = INFO_Y + INFO_H + 12

-- ===== 界面对象 =====
local win_id, page
local status_label, time_label, err_label
local temp_label, humi_label

--- 数值格式化：还没读到过显示 "--"
local function fmt(v)
    if v == nil then return "--" end
    return string.format("%.1f", v)
end

--- 刷新整页（统一从 temp_hum.get() 取，消息只当触发器）
local function refresh()
    if not page then return end

    local d = sensor.get()

    temp_label:set_text(fmt(d.t))
    humi_label:set_text(fmt(d.h))

    if d.ts then
        time_label:set_text(os.date("%H:%M:%S", d.ts))
    else
        time_label:set_text("--:--:--")
    end

    if d.online then
        status_label:set_text("在线")
        pcall(function() status_label:set_color(C.OK) end)
        err_label:set_text("")
    else
        status_label:set_text("离线")
        pcall(function() status_label:set_color(C.DANGER) end)
        err_label:set_text(d.err ~= "" and d.err or "传感器未应答")
    end
end

local function on_update()
    refresh()
end

local function on_status()
    refresh()
end

local function create_ui()
    page = ui.page({
        title = "温湿度",
        on_back = function() if win_id then exwin.close(win_id) end end,
    })

    -- ===== 状态卡：左通信状态 / 右更新时间 =====
    local card = ui.card({ parent = page.body, x = PAD, y = 8, w = DW - PAD * 2, h = 72 })
    ui.label({
        parent = card, x = 20, y = 12, w = 200, h = 22,
        text = "485 通信状态", size = F.SMALL, color = C.TEXT_SUB,
    })
    status_label = ui.label({
        parent = card, x = 20, y = 38, w = 200, h = 28,
        text = "未连接", size = F.NORMAL, color = C.TEXT_WEAK,
    })
    ui.label({
        parent = card, x = 300, y = 12, w = DW - PAD * 2 - 320, h = 22,
        text = "更新时间", size = F.SMALL, color = C.TEXT_SUB,
        align = airui.TEXT_ALIGN_RIGHT,
    })
    time_label = ui.label({
        parent = card, x = 300, y = 38, w = DW - PAD * 2 - 320, h = 28,
        text = "--:--:--", size = F.NORMAL, color = C.TEXT,
        align = airui.TEXT_ALIGN_RIGHT,
    })

    -- ===== 温度 / 湿度 数值卡（主读数，字号 XL=56） =====
    local tc = ui.card({ parent = page.body, x = PAD, y = CARD_Y, w = CARD_W, h = CARD_H })
    ui.label({
        parent = tc, x = 0, y = 12, w = CARD_W, h = 22,
        text = "温度", size = F.SMALL, color = C.TEXT_SUB,
        align = airui.TEXT_ALIGN_CENTER,
    })
    temp_label = ui.label({
        parent = tc, x = 0, y = 38, w = CARD_W, h = 76,
        text = "--", size = F.XL, color = C.PRIMARY,
        align = airui.TEXT_ALIGN_CENTER,
    })
    ui.label({
        parent = tc, x = 0, y = 116, w = CARD_W, h = 22,
        text = "℃", size = F.SMALL, color = C.TEXT_WEAK,
        align = airui.TEXT_ALIGN_CENTER,
    })

    local hc = ui.card({ parent = page.body, x = PAD + CARD_W + 20, y = CARD_Y, w = CARD_W, h = CARD_H })
    ui.label({
        parent = hc, x = 0, y = 12, w = CARD_W, h = 22,
        text = "湿度", size = F.SMALL, color = C.TEXT_SUB,
        align = airui.TEXT_ALIGN_CENTER,
    })
    humi_label = ui.label({
        parent = hc, x = 0, y = 38, w = CARD_W, h = 76,
        text = "--", size = F.XL, color = C.ICON_TEAL,
        align = airui.TEXT_ALIGN_CENTER,
    })
    ui.label({
        parent = hc, x = 0, y = 116, w = CARD_W, h = 22,
        text = "%RH", size = F.SMALL, color = C.TEXT_WEAK,
        align = airui.TEXT_ALIGN_CENTER,
    })

    -- ===== 信息卡：从站 / 寄存器 / 波特率 + 错误行 =====
    local info = ui.card({ parent = page.body, x = PAD, y = INFO_Y, w = DW - PAD * 2, h = INFO_H })
    ui.label({
        parent = info, x = 20, y = 12, w = 700, h = 22,
        text = string.format("从站 %d · 寄存器 0x%04X / 0x%04X · %d 8N1",
            CFG.slave, CFG.reg, CFG.reg + 1, CFG.baud),
        size = F.SMALL, color = C.TEXT_SUB,
    })
    err_label = ui.label({
        parent = info, x = 20, y = 42, w = DW - PAD * 2 - 40, h = 30,
        text = "", size = F.SMALL, color = C.DANGER,
    })

    -- ===== 底部：立即读取 =====
    ui.button({
        parent = page.body, x = PAD, y = BTN_Y, w = 190, h = 48, text = "立即读取",
        on_click = function() sensor.read_once() end,
    })
end

local function on_create()
    create_ui()
    refresh()
    sys.subscribe("TEMP_HUM_UPDATE", on_update)
    sys.subscribe("TEMP_HUM_STATUS", on_status)
    sensor.read_once()                -- 进页面立刻读一次
end

local function on_destroy()
    sys.unsubscribe("TEMP_HUM_UPDATE", on_update)
    sys.unsubscribe("TEMP_HUM_STATUS", on_status)
    if page then
        page.destroy()
        page = nil
    end
    status_label, time_label, err_label = nil, nil, nil
    temp_label, humi_label = nil, nil
    win_id = nil
end

sys.subscribe("OPEN_485_WIN", function()
    win_id = exwin.open({
        on_create     = on_create,
        on_destroy    = on_destroy,
        on_get_focus  = function()
            refresh()
            sensor.read_once()
        end,
        on_lose_focus = function() end,
    })
end)
