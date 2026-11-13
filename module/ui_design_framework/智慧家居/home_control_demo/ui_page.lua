--[[
@module  ui_page
@summary 多页面管理器：注册 / 构建 / 显隐切换 / 定时轮询
@version 1.0.0
@note 显隐用「屏外位移」而非 hide/open/set_hidden：
      set_pos 是真机验证过的可靠手段；隐藏页整页推到 x=-SW 屏外（负方向）。
      必须用负方向（左/上）：screen 默认 scrollable，子对象探出右/下边界会出现滚动条；
      负方向 LVGL 不做负向滚动，屏外内容被裁剪、不参与命中、无滚动条。
      页面模块契约：mod.create(root) 把内容建到 root 上；可选 mod.on_show()/mod.on_hide()。
      对外接口：
        register(id, name, mod)   注册页面
        build()                   构建所有页面（首页前调用）
        show(id)                  手动切到指定页（并暂停轮询）
        next()                    下一页（轮询计时器调用）
        start_rotation(ms)        启动轮询（默认 5000ms）
        stop_rotation()           停止轮询
        set_interval(ms)          调整轮询间隔
        list()                    页面列表
        current_id()              当前页 id
]]
local T = require "ui_theme"
local M = { interval = 5000 }

local SW, SH = T.screen.w, T.screen.h
local pages = {}
local current = nil
local timer = nil

function M.register(id, name, mod)
    pages[#pages + 1] = { id = id, name = name, mod = mod, root = nil }
end

function M.build()
    for _, p in ipairs(pages) do
        local root = airui.container({ parent = airui.screen, x = 0, y = 0,
            w = SW, h = SH, color = 0x000000, color_opacity = 0, border_width = 0 })
        p.root = root
        if p.mod and p.mod.create then
            p.mod.create(root)
        end
        pcall(function() root:set_pos(-SW, 0) end)  -- 推到左侧屏外（负方向不触发滚动条），首个可见页再拉回
    end
end

local function switch_to(p)
    if current and current ~= p then
        pcall(function() current.root:set_pos(-SW, 0) end)
        if current.mod and current.mod.on_hide then pcall(current.mod.on_hide) end
    end
    current = p
    pcall(function() p.root:set_pos(0, 0) end)
    if p.mod and p.mod.on_show then pcall(p.mod.on_show) end
    log.info("ui_page", "当前页", p.name)
end

function M.show(id)                        -- 手动切到指定页，并暂停轮询
    M.stop_rotation()
    for _, p in ipairs(pages) do
        if p.id == id then switch_to(p) return end
    end
end

function M.next()
    if #pages == 0 then return end
    local idx = 1
    for i, p in ipairs(pages) do
        if current and p.id == current.id then idx = i end
    end
    switch_to(pages[idx % #pages + 1])
end

function M.start_rotation(ms)
    if ms then M.interval = ms end
    M.stop_rotation()
    timer = sys.timerLoopStart(M.next, M.interval)
end

function M.stop_rotation()
    if timer then sys.timerStop(timer) timer = nil end
end

function M.set_interval(ms)
    if ms then M.interval = ms end
end

function M.list()
    return pages
end

function M.current_id()
    return current and current.id
end

return M
