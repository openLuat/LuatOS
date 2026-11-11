--[[
@module  ui
@summary 1024x600 触屏界面：金额显示 + 3列数字键盘 + 扫码提示 + 状态/结果
@note    1) 布局沿用最初版本：左侧 560 宽金额卡 / 扫码框 / 状态区，右侧 3 列数字键盘。
            金额字号由 config.ui.amount_font_size 决定（示例默认 100），仅金额标签
            自身高度做了适配，其余控件坐标、尺寸、字号全部保持原样。
         2) AirUI 控件字号字段是 font_size（不是 size）。写 size 会被忽略、退回默认小字。
         3) 货币符号用 config.ui.currency（全角「￥」），固件内置中文字库不含半角「¥」。
         4) 所有按键只做一件事：sys.publish("UI_KEY", 键值)，业务逻辑在 app.lua
         5) 「收款成功」弹窗位于左侧 x=28..588 / y=88..478，键盘 x>=612，两者相隔 24px
            不重叠；airui.label 没有 set_hidden（官方 factory_new/ui/idle_win.lua:677），
            所以整块弹窗用外层容器 set_hidden 显隐，内部 label 不单独隐藏
         6) ▲【按需 O10】界面文案、配色、控件尺寸都在本文件 M.init() 里；
            货币符号与金额字号走 config.ui（O02）。全文搜「【按需」可定位。
]]

local CFG = require "config"
local M = {}

local C = {
    bg      = 0x0F172A,
    card    = 0x1E293B,
    key     = 0x334155,
    scanbox = 0x142033,
    bar     = 0x1D4ED8,
    accent  = 0x38BDF8,
    ok      = 0x22C55E,
    warn    = 0xF59E0B,
    danger  = 0xEF4444,
    text    = 0xF1F5F9,
    sub     = 0x94A3B8,
    white   = 0xFFFFFF,
}

local amount_label, status_label, net_label, result_label
local popup_box, popup_amount_label, popup_balance_label
local popup_shown = false

local function set_text(label, text)
    if label then pcall(label.set_text, label, tostring(text or "")) end
end

function M.set_amount(text) set_text(amount_label, text) end
function M.set_status(text) set_text(status_label, text) end
function M.set_net(text)    set_text(net_label, text) end
function M.set_result(text) set_text(result_label, text) end

-- 统一的「货币符号 + 数字」文本，供 app.lua 调用
function M.money(text)
    return CFG.ui.currency .. " " .. tostring(text or "0.00")
end

-- ===== 左侧「收款成功」弹窗（只显隐外层容器，见文件头说明） =====
function M.show_pay_ok(money_text, balance_text)
    if not popup_box then return end
    set_text(popup_amount_label, money_text)
    set_text(popup_balance_label, balance_text or "")
    if popup_box.set_hidden then pcall(popup_box.set_hidden, popup_box, false) end
    popup_shown = true
end

function M.hide_pay_ok()
    if not popup_box then return end
    if popup_box.set_hidden then pcall(popup_box.set_hidden, popup_box, true) end
    popup_shown = false
end

function M.popup_visible()
    return popup_shown
end

local function button(parent, x, y, w, h, text, bg, fg, key, size)
    return airui.button({
        parent = parent,
        x = x, y = y, w = w, h = h,
        text = text,
        font_size = size or 28,
        color = bg,
        radius = 10,
        style = {
            bg_color           = bg,
            text_color         = fg,
            pressed_bg_color   = bg,
            pressed_text_color = fg,
        },
        on_click = function()
            log.info("ui", "key", key)
            sys.publish("UI_KEY", key)
        end,
    })
end

function M.init()
    local W, H = CFG.hw.screen_w, CFG.hw.screen_h
    local root = airui.container({ x = 0, y = 0, w = W, h = H, color = C.bg })

    -- ===== 顶栏 =====
    local bar = airui.container({ parent = root, x = 0, y = 0, w = W, h = 64, color = C.bar })
    airui.label({
        parent = bar, x = 32, y = 14, w = 520, h = 38,
        text = "食堂收费终端", font_size = 28, color = C.white,
    })
    net_label = airui.label({
        parent = bar, x = 664, y = 18, w = 332, h = 30,
        text = "网络：连接中…", font_size = 18, color = C.white,
    })

    -- ===== 左侧：金额卡 =====
    local card = airui.container({
        parent = root, x = 28, y = 88, w = 560, h = 190,
        color = C.card, radius = 12,
    })
    airui.label({
        parent = card, x = 24, y = 18, w = 500, h = 32,
        text = "本次金额", font_size = 20, color = C.sub,
    })
    -- 金额标签：高度按 font_size 自适应（100px 字需约 118px 行高），其余坐标不动
    local fs = CFG.ui.amount_font_size
    amount_label = airui.label({
        parent = card, x = 24, y = 56, w = 512, h = math.max(100, fs + 18),
        text = M.money("0.00"), font_size = fs, color = C.accent,
    })

    -- ===== 左侧：扫码提示框（摄像头后台解码，不做实时取景，保持最简） =====
    local scanbox = airui.container({
        parent = root, x = 28, y = 298, w = 560, h = 170,
        color = C.scanbox, radius = 12,
    })
    airui.label({
        parent = scanbox, x = 24, y = 18, w = 500, h = 36,
        text = "扫饭卡二维码", font_size = 24, color = C.text,
    })
    airui.label({
        parent = scanbox, x = 24, y = 66, w = 512, h = 34,
        text = "请将饭卡二维码对准摄像头（10~20cm）", font_size = 18, color = C.sub,
    })
    airui.label({
        parent = scanbox, x = 24, y = 110, w = 512, h = 32,
        text = "识别后自动收款并播报结果", font_size = 18, color = C.sub,
    })

    status_label = airui.label({
        parent = root, x = 28, y = 500, w = 560, h = 36,
        text = "请输入金额，然后点确认", font_size = 20, color = C.warn,
    })
    result_label = airui.label({
        parent = root, x = 28, y = 526, w = 560, h = 44,
        text = "", font_size = 20, color = C.ok,
    })

    -- ===== 右侧：3 列数字键盘（1-9 三行 + C/0/. 一行） =====
    local keys = { "1", "2", "3", "4", "5", "6", "7", "8", "9", "C", "0", "." }
    local x0, y0, bw, bh, gx, gy = 612, 88, 122, 82, 10, 10
    for i, k in ipairs(keys) do
        local col = (i - 1) % 3
        local row = math.floor((i - 1) / 3)
        local bg = (k == "C") and 0x7F1D1D or C.key
        button(root,
            x0 + col * (bw + gx),
            y0 + row * (bh + gy),
            bw, bh, k, bg, C.white, k)
    end

    -- ===== 确认按钮 =====
    button(root, x0, y0 + 4 * (bh + gy), bw * 3 + gx * 2, bh,
        "确认", C.ok, C.white, "OK", 30)

    airui.label({
        parent = root, x = x0, y = 552, w = 386, h = 32,
        text = "确认后播报金额 → 扫码 → 收款成功", font_size = 16, color = C.sub,
    })

    -- ===== 左侧「收款成功」弹窗：最后创建，z-order 最高，盖住金额卡 + 扫码框 =====
    -- 止于 y=478，不碰状态栏/结果栏(y>=500)，也不碰右侧键盘(x>=612)
    popup_box = airui.container({
        parent = root, x = 28, y = 88, w = 560, h = 390,
        color = 0xEAF3DE, radius = 16,
    })
    airui.label({
        parent = popup_box, x = 0, y = 66, w = 560, h = 70,
        text = "收款成功", font_size = 48, color = 0x173404,
        align = airui.TEXT_ALIGN_CENTER,
    })
    popup_amount_label = airui.label({
        parent = popup_box, x = 0, y = 168, w = 560, h = 84,
        text = "", font_size = 56, color = 0x27500A,
        align = airui.TEXT_ALIGN_CENTER,
    })
    popup_balance_label = airui.label({
        parent = popup_box, x = 0, y = 258, w = 560, h = 36,
        text = "", font_size = 24, color = 0x27500A,
        align = airui.TEXT_ALIGN_CENTER,
    })
    airui.label({
        parent = popup_box, x = 0, y = 300, w = 560, h = 40,
        text = "按任意键关闭", font_size = 20, color = 0x3B6D11,
        align = airui.TEXT_ALIGN_CENTER,
    })
    if popup_box.set_hidden then
        popup_box:set_hidden(true)
    else
        log.warn("ui", "容器不支持 set_hidden，弹窗可能常显")
    end
    popup_shown = false

    return true
end

return M
