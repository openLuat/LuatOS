--[[
@module  settings_titlebar
@summary 页面标题栏共享组件（TabOS 玻璃态）
@version 2.0
@date    2026.09.15
@author  江访
@usage
local titlebar = require "settings_titlebar"
local _, th = titlebar.create(main_container, "设置", screen_w, function() exwin.close(window_id) end)
]]

local theme = require "ui_theme"

local M = {}

--[[创建玻璃标题栏（实现已上收到 ui_theme.header，此处仅保留旧签名做兼容）

@param parent   父容器
@param title    标题文字
@param screen_w 屏幕（或容器）宽度
@param on_back  返回按钮回调，nil 时不显示返回按钮
@param sub      可选副标题
@param opts     可选扩展 { x, y, right, right_w }
@return 标题栏容器, 标题栏高度
]]
function M.create(parent, title, screen_w, on_back, sub, opts)
    opts = opts or {}
    return theme.header(parent, {
        x = opts.x or 0,
        y = opts.y or 0,
        --[[宽度优先取 opts.w。历史上这里写死 w = screen_w（第 3 个位置参数），
        于是「x = margin 且 w 想收窄」的调用（存储和内存页）右边缘会超出父容器
        一个页边距，父容器随即变成可滚动并画出滑动条。]]
        w = opts.w or screen_w,
        title = title,
        sub = sub,
        on_back = on_back,
        right = opts.right,
        right_w = opts.right_w,
    })
end

return M
