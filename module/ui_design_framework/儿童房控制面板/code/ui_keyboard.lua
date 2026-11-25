--[[
@module  ui_keyboard
@summary 改名弹层：半透明遮罩 + 离屏 textarea + airui.keyboard 底部键盘
@version 1.0.0
@note 效果稿里名字是 HTML <input>，设备没有输入法宿主，改成：
        点名字 → 全屏 110 透明遮罩（顺手吞掉误触）→ 底部弹出 AirUI 键盘；
        textarea 放在遮罩里 y=-400 的离屏位置，只借它的文本缓冲与 IME 预览；
        点键盘上的确认键 = 提交，点遮罩空白 = 取消。

      两个关键取舍：
        1) 遮罩与键盘「建一次、反复用」，关闭只是把遮罩推到 -2048 并 hide 键盘。
           如果关闭时销毁，W.press 的 90ms 回弹定时器会落到已销毁控件上报错；
           而用 W.bump_epoch() 作废定时器会把工程里所有热区一起作废（epoch 是全局的）。
        2) 键盘创建失败（固件没编 IME）时返回 false，调用方退化成「点名字循环预设名」。
]]
local W = require "ui_widget"
local T = require "ui_theme"
local C = T.c

local M = {}

local SW, SH = 1024, 600
local HIDDEN_X = -2048

local overlay, ta, kb = nil, nil, nil
local on_done = nil
local cur_value = "小星星"

M.available = nil          -- nil=未知 / true / false

--- 一次性建层（失败返回 false 并记住不可用）
local function ensure_layer(parent)
    if overlay then return true end

    local ok, err = pcall(function()
        overlay = W.box(parent, HIDDEN_X, 0, SW, SH, 0x000000, 0)
        W.glass(overlay, 0x000000, 110)

        -- 键盘开着 preview 时会占住 600-344 以上，提示必须落在 y<250，否则被压住
        W.text_mid(overlay, { text = "给房间起个名字吧", x = 0, y = 168, w = SW, h = 32,
            size = T.f.h3, color = 0xFFFFFF, align = airui.TEXT_ALIGN_CENTER })
        W.text_mid(overlay, { text = "点键盘上的确认键保存，点空白处取消", x = 0, y = 208, w = SW, h = 24,
            size = T.f.sub, color = 0xFFFFFF, align = airui.TEXT_ALIGN_CENTER })

        -- 离屏 textarea：只要文本缓冲 + IME 预览，不显示在画面上
        local tok, obj = pcall(airui.textarea, {
            parent = overlay, x = -400, y = -400, w = 240, h = 44,
            text = cur_value, max_len = 6,
            font = "hzfont", font_size = T.f.body,
            align = airui.TEXT_ALIGN_CENTER,
            style = { radius = 12, font_size = T.f.body,
                      bg_color = C.card, text_color = C.ink },
        })
        if not (tok and obj) then error("textarea 创建失败: " .. tostring(obj)) end
        ta = obj

        local tries = { "pinyin_26", "text" }
        for _, mode in ipairs(tries) do
            local kok, kob = pcall(airui.keyboard, {
                w = SW, h = 250, mode = mode,
                -- preview：键盘顶部显示「当前 textarea 文本」。
                -- textarea 本身是离屏的（只借文本缓冲），没有这行字孩子就是盲打。
                preview = true, preview_height = 44,
                style = { radius = 12 },
            })
            if kok and kob then
                kb = kob
                log.info("ui_keyboard", "键盘已创建", mode)
                break
            end
            log.warn("ui_keyboard", "键盘创建失败，换模式重试", mode, tostring(kob))
        end
        if not kb then error("keyboard 创建失败") end

        pcall(function() ta:attach_keyboard(kb) end)
        pcall(function() kb:set_target(ta) end)
        pcall(function() kb:set_on_commit(function() M.commit() end) end)

        -- 遮罩热区最后建，保证吃掉空白处的点击（键盘在更上层，不受影响）
        W.press(overlay, { x = 0, y = 0, w = SW, h = 340, radius = 0,
            on_click = function() M.close() end })
    end)

    if not ok then
        log.error("ui_keyboard", "改名弹层创建失败，退化为预设名循环", tostring(err))
        overlay, ta, kb = nil, nil, nil
        M.available = false
        return false
    end
    M.available = true
    return true
end

--- 打开改名弹层
--- @param cfg table { parent=遮罩父容器, value=当前名字, on_done=function(name) }
--- @return boolean 是否成功打开
function M.open(cfg)
    if M.available == false then return false end
    if not ensure_layer(cfg.parent) then return false end
    if overlay then pcall(function() overlay:set_pos(0, 0) end) end
    cur_value = cfg.value or "小星星"
    if ta then pcall(function()
        ta:set_text(cur_value)
        ta:set_cursor(cur_value:len())
    end) end
    pcall(function() kb:show() end)
    on_done = cfg.on_done
    log.info("ui_keyboard", "打开改名弹层", cur_value)
    return true
end

--- 关闭（不提交）
function M.close()
    if not overlay then return end
    pcall(function() if kb then kb:hide() end end)
    pcall(function() overlay:set_pos(HIDDEN_X, 0) end)
    on_done = nil
end

--- 提交当前文本
function M.commit()
    local text = nil
    if ta then
        local ok, v = pcall(function() return ta:get_text() end)
        if ok then text = v end
    end
    local cb = on_done
    M.close()
    if cb then
        local ok, err = pcall(cb, text)
        if not ok then log.error("ui_keyboard", "提交回调异常", tostring(err)) end
    end
end

--- 主题重建时整层销毁（重建流程会 bump_epoch，不存在悬挂定时器问题）
function M.destroy()
    if kb then
        pcall(function() kb:hide() end)
        pcall(function() kb:destroy() end)
    end
    if ta then pcall(function() ta:destroy() end) end
    if overlay then pcall(function() overlay:destroy() end) end
    overlay, ta, kb = nil, nil, nil
    on_done = nil
end

return M
