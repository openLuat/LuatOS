--[[
@module  ui_settings
@summary 设置页：报警阈值滑条 + 运行设置（班次/轮播/蜂鸣/背光）+ 配方摘要与维护操作
@version 1.0
@date    2026.11.10
]]
local conf  = require("conf")
local theme = require("theme")
local store = require("store")
local model = require("model")

local C = theme.C
local T = theme
local M = {}

local v = { limit_lb = {}, prm_lb = {}, shift_btn = {}, sw = {} }

-- 滑条拖动会高频回调，落盘做 600ms 去抖
local save_timer = nil
local function save_later()
    if save_timer then sys.timerStop(save_timer) end
    save_timer = sys.timerStart(function()
        save_timer = nil
        store.save_settings()
    end, 600)
end

local function fmt_val(def, val)
    if def.step < 1 then return string.format("%.1f", val) end
    return string.format("%d", math.floor(val + 0.5))
end

-- 带数值回显的滑条行
local function slider_row(parent, y, def, scale)
    T.label(parent, 18, y, 260, 20, def.name, 13, C.ink2)
    local val_lb = T.label(parent, 390, y - 3, 80, 24, "", 16, C.cyan, T.TEXT_RIGHT)
    local set = store.settings()[def.key] or def.def
    T.slider(parent, 18, y + 28, 452, 20, {
        min = math.floor(def.min * scale + 0.5),
        max = math.floor(def.max * scale + 0.5),
        value = math.floor(set * scale + 0.5),
        style = {
            bg_color = C.line, indicator_color = C.cyan,
            knob_color = C.ink, radius = 3,
        },
        on_change = function(self, val)
            local nv = val / scale
            val_lb:set_text(fmt_val(def, nv) .. def.unit)
            store.set_setting(def.key, nv)
            save_later()
        end,
    })
    val_lb:set_text(fmt_val(def, set) .. def.unit)
    return val_lb
end

local function switch_row(parent, x, y, key, title, desc)
    T.label(parent, x, y, 180, 20, title, 13, C.ink2)
    local sw
    pcall(function()
        sw = airui.switch({
            parent = parent, x = x, y = y + 26, w = 60, h = 30,
            checked = (store.settings()[key] ~= 0),
            style = "success",
            on_change = function()
                local on = sw and sw:get_state()
                store.set_setting(key, on and 1 or 0)
                save_later()
            end,
        })
    end)
    if desc then
        T.label(parent, x, y + 62, 210, 16, desc, 10, C.ink3)
    end
    return sw
end

function M.build(parent)
    local page = airui.container({
        parent = parent, x = 0, y = 0, w = conf.W, h = conf.H, color = -1,
    })
    v.page = page
    M.root = page

    -- ==================== 报警阈值 ====================
    local lc = T.card(page, 20, 84, 488, 300, "报警阈值", "拖动即时生效")
    for i, def in ipairs(conf.limits) do
        local y = 44 + (i - 1) * 62
        -- 低压保护时间用 0.1 精度，滑条按 x10 处理
        local scale = (def.step < 1) and 10 or 1
        v.limit_lb[i] = slider_row(lc, y, def, scale)
    end

    -- ==================== 运行设置 ====================
    local rc = T.card(page, 20, 396, 488, 192, "运行设置")
    T.label(rc, 18, 12, 100, 18, "当前班次", 12, C.ink3)
    for i, name in ipairs(conf.shifts) do
        local x = 18 + (i - 1) * 152
        v.shift_btn[i] = T.ghost(rc, x, 34, 140, 34, name, 12, C.ink2, function()
            store.set_setting("shift", i)
            store.save_settings()
            M.refresh()
        end, 8)
    end

    v.sw.rotate = switch_row(rc, 18, 80, "rotate", "自动轮播", "无操作 30s 自动切页")
    v.sw.buzzer = switch_row(rc, 250, 80, "buzzer", "报警蜂鸣", "严重报警时蜂鸣提示")

    T.label(rc, 18, 158, 80, 18, "屏幕亮度", 12, C.ink3)
    v.bl_lb = T.label(rc, 420, 156, 50, 20, "", 13, C.cyan, T.TEXT_RIGHT)
    T.slider(rc, 108, 158, 300, 20, {
        min = 20, max = 100,
        value = store.settings().backlight or 85,
        style = {
            bg_color = C.line, indicator_color = C.amber,
            knob_color = C.ink, radius = 3,
        },
        on_change = function(self, val)
            store.set_setting("backlight", val)
            v.bl_lb:set_text(val .. "%")
            if M.on_backlight then pcall(M.on_backlight, val) end
            save_later()
        end,
    })
    v.bl_lb:set_text((store.settings().backlight or 85) .. "%")

    -- ==================== 配方摘要 ====================
    local pc = T.card(page, 520, 84, 484, 504, "当前工艺配方", "全局生效")
    for i, def in ipairs(conf.params) do
        local y = 44 + (i - 1) * 30
        T.dot(pc, 18, y + 7, 6, C.line2)
        T.label(pc, 34, y + 1, 200, 20, def.name, 12, C.ink2)
        v.prm_lb[i] = T.label(pc, 240, y, 150, 20, "", 13, C.ink, T.TEXT_RIGHT)
        T.label(pc, 396, y + 2, 70, 18, def.unit, 11, C.ink3, T.TEXT_RIGHT)
    end

    T.ghost(pc, 18, 296, 216, 36, "恢复默认配方", 13, C.amber, function()
        for _, def in ipairs(conf.params) do
            store.set_param(def.key, def.def)
        end
        store.save_params()
        M.refresh()
    end, 8)
    T.ghost(pc, 250, 296, 216, 36, "清空报警记录", 13, C.red, function()
        store.clear_alarms()
        M.refresh()
    end, 8)

    T.hline(pc, 18, 352, 448, C.line)
    T.label(pc, 18, 366, 200, 20, "设备信息", 12, C.ink3)
    v.sys = {}
    local info = {
        { "控制器", "Air8607 · LuatOS" },
        { "显示屏", "10 寸 1024 x 600 RGB" },
        { "数据源", "工艺仿真（可替换 Modbus）" },
        { "累计运行", "" },
    }
    for i, it in ipairs(info) do
        local y = 394 + (i - 1) * 26
        T.label(pc, 18, y, 110, 18, it[1], 11, C.ink3)
        v.sys[i] = T.label(pc, 130, y, 330, 18, it[2], 11, C.ink2)
    end

    return true
end

function M.refresh()
    if not v.page then return end

    -- 阈值回显（外部改动时同步）
    for i, def in ipairs(conf.limits) do
        local cur = store.settings()[def.key] or def.def
        if v.limit_lb[i] then
            v.limit_lb[i]:set_text(fmt_val(def, cur) .. def.unit)
        end
    end

    -- 班次按钮
    local shift = store.settings().shift or 1
    for i, name in ipairs(conf.shifts) do
        local on = (i == shift)
        pcall(v.shift_btn[i].set_style, v.shift_btn[i], {
            bg_color = on and C.panel3 or C.panel2, bg_opa = 255,
            text_color = on and C.cyan or C.ink2, radius = 8,
            border_color = on and C.cyan or C.line2, border_width = 1,
            pressed_bg_color = C.line2, pressed_text_color = C.white,
        })
    end

    -- 配方值
    local p = store.params()
    for i, def in ipairs(conf.params) do
        if v.prm_lb[i] then
            v.prm_lb[i]:set_text(fmt_val(def, p[def.key] or def.def))
        end
    end

    -- 累计运行时长
    local mins = math.floor(mcu.ticks() / 60000)
    if v.sys[4] then
        v.sys[4]:set_text(string.format("%d 小时 %d 分",
            math.floor(mins / 60), mins % 60))
    end
end

return M
