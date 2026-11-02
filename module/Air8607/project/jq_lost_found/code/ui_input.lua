--[[
@module  ui_input
@summary 通用文本输入浮层：遮罩 + 输入框 + 拼音候选 + 软键盘
@version 1.0
@date    2026.10.30
@usage
local I = require "ui_input"
I.open({
    title    = "物品名称",
    initial  = "",
    on_done  = function(text) ... end,
    on_cancel= function() ... end,
})

说明：
- 中文由 pinyin 模块的候选词行上屏（固件未开 LUAT_USE_PINYIN 时 airui 的 IME 候选为空）。
- 键盘是全局单例，必须最后创建（z 序最高）；本模块由 main 统一预构建保证顺序。
]]

local conf = require "conf"
local theme = require "theme"
local pinyin = require "pinyin"

local M = {}

local SW, SH = conf.W, conf.H
local C = theme.C

local root, panel, lb_title, ta, cands
local kb
local st = { on_done = nil, on_cancel = nil, suppress = false, cand_py = "", opened = false }

-- ==================== 候选词 ====================
local function hide_cands()
    if not cands then return end
    for i = 1, #cands do
        cands[i].word = ""
        cands[i].box:set_hidden(true)
    end
end

local function update_candidates()
    if not (ta and cands) then return end
    local txt = ta:get_text() or ""
    local py = txt:lower():match("([a-z]+)$") or ""
    if #py > 18 then py = py:sub(-18) end
    st.cand_py = py
    hide_cands()
    if py == "" then return end
    local words = pinyin.lookup(py, #cands)
    for i = 1, #words do
        local slot = cands[i]
        if slot then
            slot.word = words[i]
            slot.lb:set_text(words[i])
            slot.box:set_hidden(false)
        end
    end
end

local function pick_candidate(idx)
    local slot = cands and cands[idx]
    if not slot or slot.word == "" then return end
    local py = st.cand_py or ""
    if py == "" then return end
    local cur = ta:get_text() or ""
    if #cur < #py then return end
    local new = cur:sub(1, #cur - #py) .. slot.word
    st.suppress = true
    ta:set_text(new)      -- set_text 后 LVGL 光标自动落在末尾
    st.suppress = false
    st.cand_py = ""
    hide_cands()
end

-- ==================== 构建 ====================
local function build_kb()
    if kb then return end
    local ok, k = pcall(airui.keyboard, {
        w = SW, h = 220, mode = "text",
        auto_hide = false, preview = false,
        bg_color = C.card2, font_size = 18,
        on_commit = function() M.finish(true) end,
    })
    if ok and k then
        kb = k
        kb:hide()
    else
        log.warn("ui_input", "airui.keyboard 不可用，无法输入文本")
    end
end

function M.build()
    if root then return end

    root = airui.container({
        parent = nil, x = 0, y = 0, w = SW, h = SH,
        color = 0x000000, color_opacity = 150, radius = 0, border_width = 0,
        on_click = function() M.finish(false) end,
    })
    root:set_hidden(true)

    panel = theme.card(root, math.floor((SW - 560) / 2), 140, 560, 210, C.panel, 14, C.line2, 1)

    lb_title = theme.label(panel, 24, 12, 300, 26, "输入", 18, C.ink)
    theme.label(panel, 320, 14, 216, 22, "打拼音，点候选词上屏", 14, C.ink3, airui.TEXT_ALIGN_RIGHT)

    ta = airui.textarea({
        parent = panel, x = 24, y = 44, w = 512, h = 56,
        text = "", placeholder = "输入拼音后点候选词，或直接输入英文数字",
        font = "hzfont", font_size = 16,
        style = { bg_color = C.card2, text_color = C.ink, radius = 8, font_size = 16 },
    })
    ta:set_on_text_change(function()
        if st.suppress then return end
        update_candidates()
    end)

    cands = {}
    for i = 1, 6 do
        local c = airui.container({
            parent = panel, x = 24 + (i - 1) * 86, y = 108, w = 80, h = 30,
            color = C.card2, radius = 6, border_color = C.accent, border_width = 1,
            on_click = function() pick_candidate(i) end,
        })
        c:set_hidden(true)
        cands[i] = {
            box = c,
            lb = theme.label(c, 0, 4, 80, 22, "", 16, C.accent, airui.TEXT_ALIGN_CENTER),
            word = "",
        }
    end

    theme.button(panel, 24, 152, 110, 42, "取消", 18, function() M.finish(false) end, "ghost")
    theme.button(panel, 150, 152, 110, 42, "清空", 18, function()
        ta:set_text("")
        hide_cands()
    end, "ghost")
    theme.button(panel, 420, 152, 116, 42, "确定", 18, function() M.finish(true) end, "primary")

    build_kb()
end

-- ==================== 对外 ====================
function M.open(cfg)
    cfg = cfg or {}
    M.build()
    st.on_done = cfg.on_done
    st.on_cancel = cfg.on_cancel
    st.opened = true

    lb_title:set_text(cfg.title or "输入")
    st.suppress = true
    ta:set_text(cfg.initial or "")
    st.suppress = false
    st.cand_py = ""
    hide_cands()

    root:set_hidden(false)
    if kb then
        kb:set_target(ta)
        kb:show()
    end
end

function M.finish(commit)
    if not root or not st.opened then return end
    st.opened = false

    local text = ta and ta:get_text() or ""
    root:set_hidden(true)
    if kb then kb:hide() end
    hide_cands()

    local fn = commit and st.on_done or st.on_cancel
    st.on_done, st.on_cancel = nil, nil
    if fn then
        local ok, err = pcall(fn, text)
        if not ok then log.error("ui_input", "回调异常", err) end
    end
end

function M.close() M.finish(false) end

return M
