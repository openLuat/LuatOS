--[[
@module  ui_dash
@summary 监控页：电机状态卡 + 启动/停止/急停 + 状态提示
@version 1.0.0
@date    2026.11.12

布局（内容区 1024 x 488）：
    左 电机卡 620x372      右 控制面板 344x372
    下 状态提示条 984x52
]]
local M = {}

M.TITLE = "电机监控"

local conf = require "conf"
local theme = require "ui_theme"
local C = theme.C
local data = require "app_data"
local seq = require "app_seq"
local alarm = require "app_alarm"
local modal = require "ui_modal"

local CARD_X, CARD_Y, CARD_W, CARD_H = 20, 8, 620, 372
local CTRL_X, CTRL_W = 660, 344

--[[
状态胶囊的显示文本与颜色
@param d table 电机状态
@return string text, number color
]]
local function status_of(d)
    if not d then
        return "--", C.off
    end
    if not d.online then
        return "通讯离线", C.danger
    end
    if d.fault ~= 0 then
        return "故障", C.danger
    end
    if d.running then
        if d.rev then return "运行中 反转", C.green end
        return "运行中 正转", C.green
    end
    return "已停止", C.ink2
end

local function build_card(body, api)
    local card = theme.card(body, CARD_X, CARD_Y, CARD_W, CARD_H, C.panel, 12, C.line, 1)
    theme.accent_bar(card, 12, 0, CARD_W - 24, C.cyan)

    api.name = theme.label(card, 24, 18, 360, 34, "电机", 26, C.ink)
    api.station = theme.label(card, CARD_W - 220, 24, 196, 24, "", 13, C.ink3,
        airui.TEXT_ALIGN_RIGHT)

    -- 状态胶囊：底 + 文字两层，刷新时只改颜色和文字
    api.pill = theme.box(card, 24, 62, 132, 32, C.panel2, 16, 45)
    api.pill_text = theme.label(api.pill, 0, 7, 132, 18, "已停止", 14, C.ink2,
        airui.TEXT_ALIGN_CENTER)

    -- 大字输出频率
    api.freq = theme.label(card, 24, 104, 340, 96, "0.00", 76, C.cyan)
    theme.label(card, 372, 158, 60, 32, "Hz", 24, C.ink3)

    -- 分隔线
    theme.box(card, 24, 212, CARD_W - 48, 1, C.line, 0)

    api.l_cmd = theme.label(card, 24, 228, 200, 22, "频率指令", 15, C.ink3)
    api.v_cmd = theme.label(card, 176, 224, 200, 26, "--", 20, C.ink)

    theme.label(card, 24, 266, 200, 22, "输出电流", 15, C.ink3)
    api.v_cur = theme.label(card, 176, 262, 200, 26, "--", 20, C.ink)

    theme.label(card, 24, 304, 200, 22, "运行状态", 15, C.ink3)
    api.v_fault = theme.label(card, 176, 300, CARD_W - 200, 26, "--", 20, C.ink)

    api.note = theme.label(card, 24, 340, CARD_W - 48, 20,
        "电流在本机型下处于采样盲区，长期显示 0.0 属正常", 12, C.ink3)

    return card
end

local function build_ctrl(body, api)
    local card = theme.card(body, CTRL_X, CARD_Y, CTRL_W, CARD_H, C.panel, 12, C.line, 1)

    theme.button(card, 10, 10, CTRL_W - 20, 80, "启  动", 30, C.green, 0x05141C, function()
        theme.defer(function()
            local ok, err = seq.start_all()
            if not ok then
                -- 拒绝执行必须给阻断式反馈：底部提示条在视线边缘，容易被忽略
                modal.open("无法启动", err, C.warn)
            end
        end)
    end, 12)

    theme.button(card, 10, 100, CTRL_W - 20, 80, "停  止", 30, C.amber, 0x05141C, function()
        theme.defer(function()
            local ok, err = seq.stop_all()
            if not ok then
                modal.open("停止失败", err, C.danger)
            end
        end)
    end, 12)

    theme.button(card, 10, 190, CTRL_W - 20, 88, "急  停", 32, C.red, 0xFFFFFF, function()
        theme.defer(function()
            seq.estop_press()
        end)
    end, 12)

    theme.ghost_button(card, 10, 288, 157, 44, "急停复位", 16, C.ink, function()
        theme.defer(function()
            if not seq.estop then
                modal.open("无需复位", "当前没有急停锁存，可以直接启动。", C.ink2)
            else
                seq.estop_reset()
                api.toast("急停已复位，可以启动", C.ok)
            end
        end)
    end, C.line2)

    theme.ghost_button(card, 177, 288, 157, 44, "故障复位", 16, C.ink, function()
        theme.defer(function()
            local n = seq.reset_fault()
            if n == 0 then
                modal.open("复位失败", "复位命令未发出，请检查通讯状态。", C.danger)
            else
                api.toast(string.format("已向 %d 台下发复位", n), C.ok)
            end
        end)
    end, C.line2)

    api.hint = theme.label(card, 12, 342, CTRL_W - 24, 20,
        "急停为软按钮，无安全等级", 12, C.ink3, airui.TEXT_ALIGN_CENTER)

    return card
end

function M.build(body)
    local api = {}

    build_card(body, api)
    build_ctrl(body, api)

    -- 底部状态提示条
    local bar = theme.card(body, CARD_X, 392, 984, 52, C.panel2, 10, C.line, 1)
    api.msg = theme.label(bar, 18, 14, 940, 24, "就绪", 16, C.ink2)

    --[[
    底部提示（3 秒后自动清除）
    @param text string
    @param color number
    ]]
    function api.toast(text, color)
        theme.set_text(api.msg, text or "")
        theme.set_color(api.msg, color or C.ink2)
        api._toast_at = os.time()
    end

    -- 建页时记下当前失败计数，避免把上一页遗留的失败事件重复弹出来
    api._fail_seen = seq.fail_id

    return api
end

--[[
刷新：每 500ms 由 ui_main 调用
@param api table
]]
function M.refresh(api)
    if not api then return end

    local d = data.get(1)
    local c = conf.motors[1]

    if d then
        theme.set_text(api.name, d.name or (c and c.name) or "电机")
        theme.set_text(api.station, string.format("站号 %d", d.station or 0))

        local txt, col = status_of(d)
        theme.set_text(api.pill_text, txt)
        theme.set_color(api.pill_text, col)
        pcall(api.pill.set_style, api.pill, {
            bg_color = (col == C.danger and C.red or (col == C.green and C.green) or C.panel2),
            bg_opa = 45,
            radius = 16,
            border_width = 1,
            border_color = (col == C.danger and C.red or (col == C.green and C.green) or C.line2),
        })

        theme.set_text(api.freq, string.format("%.2f", d.freq_out or 0))
        theme.set_color(api.freq, d.running and C.cyan or C.ink3)

        theme.set_text(api.v_cmd, string.format("%.2f Hz", d.freq_cmd or 0))
        theme.set_text(api.v_cur, string.format("%.1f A", d.current or 0))

        if d.fault and d.fault ~= 0 then
            theme.set_text(api.v_fault, alarm.fault_text(d.fault))
            theme.set_color(api.v_fault, C.danger)
        elseif not d.online then
            theme.set_text(api.v_fault, "通讯中断")
            theme.set_color(api.v_fault, C.danger)
        else
            theme.set_text(api.v_fault, "正常")
            theme.set_color(api.v_fault, C.ok)
        end
    end

    -- 状态提示：优先显示序列消息，其次超时清除
    if api._toast_at and os.time() - api._toast_at > 3 then
        api._toast_at = nil
        theme.set_text(api.msg, "")
    elseif not api._toast_at and seq.last_msg ~= "" then
        theme.set_text(api.msg, seq.last_msg)
        theme.set_color(api.msg, C.ink2)
    end

    -- 启动命令发出但没生效：必须弹窗，底部一行会被忽略
    if (api._fail_seen or 0) ~= seq.fail_id then
        api._fail_seen = seq.fail_id
        modal.open("启动未生效", seq.fail_msg, C.warn)
    end
end

function M.on_show(api)
    M.refresh(api)
end

return M
