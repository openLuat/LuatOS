--[[
@module  ui_modal
@summary 通用模态提示框：操作被拒绝时挡住画面，必须点确认
@version 1.0.0
@date    2026.11.12

为什么不用底部提示条：
    底部那一行在视线边缘，操作员按完按钮就往别处看了，很容易被忽略，
    表现为"按了没反应"。涉及"拒绝执行"的场景必须给阻断式反馈。

层级：
    弹窗是独立顶层容器（parent = nil），层级高于页面根容器，
    与 ui_alarm 的报警弹窗同级。切页时由 ui_main 统一关闭。
]]
local M = {}

local conf = require "conf"
local theme = require "ui_theme"
local C = theme.C

local cur = nil

--[[
关闭弹窗
@return nil
]]
function M.close()
    if cur then
        pcall(cur.destroy, cur)
        cur = nil
    end
end

--[[
是否正在显示
@return boolean
]]
function M.is_open()
    return cur ~= nil
end

--[[
打开提示框
@param title string 标题（简短）
@param text string 正文（建议 30 字以内）
@param color number|nil 强调色，默认琥珀
@return nil
]]
function M.open(title, text, color)
    M.close()

    local W, H = conf.W, conf.H
    local pw, ph = 560, 250
    local px, py = math.floor((W - pw) / 2), math.floor((H - ph) / 2)

    -- 半透明遮罩，同时拦掉底层点击
    cur = airui.container({
        parent = nil, x = 0, y = 0, w = W, h = H,
        color = 0x000000, color_opacity = 140, radius = 0, border_width = 0,
    })

    local accent = color or C.amber
    local card = theme.card(cur, px, py, pw, ph, C.panel, 14, accent, 2)
    theme.accent_bar(card, 14, 0, pw - 28, accent)

    theme.label(card, 28, 28, pw - 56, 30, title or "提示", 22, accent)

    -- 正文按 \n 拆行：airui.label 不处理换行符，必须拆成多个控件
    local lines = {}
    for line in (text or ""):gmatch("[^\n]+") do
        lines[#lines + 1] = line
        if #lines >= 3 then break end
    end
    if #lines == 0 then lines[1] = "" end
    for i = 1, #lines do
        theme.label(card, 28, 74 + (i - 1) * 28, pw - 56, 26, lines[i], 17, C.ink)
    end

    theme.button(card, pw - 200, ph - 74, 172, 48, "知道了", 18, accent,
        0x05141C, function()
            theme.defer(function()
                M.close()
            end)
        end, 10)
end

return M
