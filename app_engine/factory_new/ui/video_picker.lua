--[[
@module  video_picker
@summary 视频文件选择弹窗（桌面播放器 / 全屏播放页共用）
@version 1.0
@date    2026.09.18
@author  江访

=== 为什么单独成模块 ===
两个入口都要「选文件」：桌面播放器（竖屏小播放器，控制栏的 "..." 按钮）与
全屏播放页。弹窗内容完全一致（存储设备快捷行 + 返回上一级 + 文件列表），
复制一份意味着以后修 bug 要改两处、而且容易只改一处。
这里把整套弹窗收拢成一个模块，调用方只提供「弹窗按多大屏算、选完干什么」。

=== 本模块不持有播放状态 ===
选中文件后回调 on_pick(path)，由宿主决定怎么播（桌面上重建成小播放器、
全屏页上重建成大画面）。本模块也不知道当前正在播什么。

=== 尺寸必须由调用方传进来 ===
全屏播放页会把 airui 旋转成横屏（airui.set_rotation），而 screen_w / screen_h
这两个全局量只在 lcd_drv.init() 时算过一次、**不会跟着运行时旋转变**。
所以弹窗尺寸一律走入参 sw/sh（模块内部只在调用方漏传时，才把全局量当最后的兜底）。

=== 纯函数（无 UI 依赖，可离线断言）===
video_picker.parent_path(path)   当前目录 -> 上一级；根目录返回 nil
video_picker.storage_index(path) 当前路径 -> 存储设备序号（1 内置 / 2 SD卡 / 3 Flash）
video_picker.list_items(dir)     目录 -> 可播放文件与子目录清单（已排序）

@usage
local video_picker = require "video_picker"
video_picker.open({
    start_path = "/",
    sw = screen_w, sh = screen_h,          -- 弹窗按这个尺寸定位与定大小
    on_pick = function(path) ... end,      -- 用户选中了某个视频文件
})
]]

local theme = require "ui_theme"

local M = {}

local function clamp(v, lo, hi)
    if v < lo then return lo end
    if v > hi then return hi end
    return v
end

--[[弹窗里的存储设备分段选择

三个快捷入口共用这一份清单：渲染时用它建按钮，重开弹窗时用 storage_index()
反查当前落在哪个设备上，好把那一项点亮。没有这个回显，点完「SD卡」之后三个按钮
长得一模一样，看不出此刻到底停在哪个设备里。
]]
M.STORAGE_ITEMS = {
    { text = "内置存储", path = "/" },
    { text = "SD卡",     path = "/sd/" },
    { text = "Flash",    path = "/little_flash/" },
}

-- 可播放的容器后缀（渲染前先按后缀筛，避免把整目录的图片/音频都列出来）
local VIDEO_EXTS = { hzv = true, mjpg = true, mp4 = true }

-- 弹窗运行态。同一时刻只会有一个弹窗，用文件级局部量即可。
local overlay = nil      -- airui.win 实例
local content_w = 0      -- 弹窗内容宽度（列表行宽按它算，不再依赖页面的 right_w）
local cur_sw, cur_sh = 480, 854
local cur_on_pick = nil

--[[由当前路径反查存储设备序号（1 内置 / 2 SD卡 / 3 Flash）

从第 2 项开始比前缀：内置存储的 "/" 是所有路径的前缀，先比它会把一切都判成内置。
子目录（/sd/xxx/）仍归属同一个设备，所以用前缀匹配而不是全等。]]
function M.storage_index(path)
    if type(path) ~= "string" then return 1 end
    for i = 2, #M.STORAGE_ITEMS do
        local prefix = M.STORAGE_ITEMS[i].path
        if path:sub(1, #prefix) == prefix then return i end
    end
    return 1    -- 根目录 / luadb 等内置路径
end

--[[由当前目录推出上一级目录

根目录（"/"）没有上一级，返回 nil —— 调用方据此隐藏「返回上一级」按钮，
而不是给一个点了没反应的死按钮。
文件路径也兼容（先补上结尾的 "/" 再取父目录），免得从文件列表里误用时算出怪结果。

  /sd/          -> /
  /sd/video/    -> /sd/
  /luadb/       -> /
  /             -> nil
]]
function M.parent_path(path)
    if type(path) ~= "string" or path == "" then return nil end
    if path == "/" then return nil end
    local p = path
    if p:sub(-1) ~= "/" then p = p .. "/" end
    p = p:gsub("/+$", "/")                      -- 收掉结尾重复斜杠
    local parent = p:match("^(.*/)[^/]+/$")     -- 贪婪匹配：吃掉最后一段目录名
    if not parent or parent == "" then return nil end
    return parent
end

--[[列出一个目录下的子目录与可播放视频（目录在前、各自按名字排序）

@return table { { name=, is_dir=, path= }, ... }  读取失败时返回空表
]]
function M.list_items(dir_path)
    local items = {}
    local ok, files = io.lsdir(dir_path, 200, 0)
    if ok and files then
        for _, f in ipairs(files) do
            if f.type == 1 then
                items[#items + 1] = { name = f.name, is_dir = true, path = dir_path .. f.name .. "/" }
            elseif f.type == 0 then
                local ext = f.name:match("%.([^%.]+)$")
                if ext then ext = ext:lower() end
                if ext and VIDEO_EXTS[ext] then
                    items[#items + 1] = { name = f.name, is_dir = false, path = dir_path .. f.name }
                end
            end
        end
    end
    table.sort(items, function(a, b)
        if a.is_dir ~= b.is_dir then return a.is_dir end
        return a.name < b.name
    end)
    return items
end

function M.close()
    if overlay then
        pcall(function() overlay:destroy() end)
        overlay = nil
    end
end

-- 前向声明：进入子目录 / 返回上一级都要重建整套弹窗
local open_at

local function render(dir_path, scroll_container)
    if not scroll_container then return end
    local items = M.list_items(dir_path)
    local d = _G.density_scale or 1.0
    local row_h = math.floor(32 * d)
    local px = math.floor(8 * d)
    local list_w = content_w
    local y = 0
    for _, item in ipairs(items) do
        local row = theme.card(scroll_container, {
            x = px, y = y, w = list_w - 2 * px, h = row_h,
            radius = theme.R.sm, opa = 0,
            on_click = function()
                if item.is_dir then
                    -- 进子目录：重建选择器（顺带刷新设备高亮与「返回上一级」）
                    M.open({ start_path = item.path, sw = cur_sw, sh = cur_sh, on_pick = cur_on_pick })
                else
                    M.close()
                    if cur_on_pick then pcall(cur_on_pick, item.path) end
                end
            end,
        })
        -- 目录用琥珀、文件用青色：靠颜色区分，不额外占一行说明
        theme.label(row, {
            x = px, y = 0, w = math.floor(18 * d), h = row_h,
            text = ">", px_size = math.floor(13 * d),
            color = item.is_dir and theme.C.amber or theme.C.cyan,
            align = airui.TEXT_ALIGN_CENTER,
        })
        theme.label(row, {
            x = px + math.floor(20 * d), y = 0,
            w = list_w - 2 * px - math.floor(24 * d), h = row_h,
            text = item.name, px_size = math.floor(12 * d),
            color = theme.C.t1, align = airui.TEXT_ALIGN_LEFT,
        })
        y = y + row_h + math.floor(2 * d)
    end
    if #items == 0 then
        theme.label(scroll_container, {
            x = 0, y = math.floor(20 * d), w = list_w, h = row_h,
            text = "无视频文件", px_size = math.floor(12 * d),
            color = theme.C.t3, align = airui.TEXT_ALIGN_CENTER,
        })
    end
end

open_at = function(start_path)
    local d = _G.density_scale or 1.0

    -- 弹窗尺寸：宽屏半屏（≤460，保持原观感）；窄屏放宽到 0.72 屏宽，
    -- 否则 480 宽的面板上弹窗只有 240，文件名几乎看不见
    local picker_w = (cur_sw <= 560) and math.min(math.floor(cur_sw * 0.72), 460)
        or math.min(math.floor(cur_sw * 0.50), 460)
    local picker_h = math.floor(cur_sh * 0.70)
    content_w = picker_w
    local pad_in = math.floor(12 * d)

    -- 使用 airui.win 创建独立弹窗，不影响底层布局。
    -- auto_center 走 lv_obj_center，按父对象（当前屏幕）**实时**尺寸居中 ——
    -- 旋转后的横屏也能正确居中，不需要额外补偿。
    overlay = airui.win({
        parent = airui.screen, title = "选择视频文件",
        w = picker_w, h = picker_h, close_btn = true, auto_center = true,
        style = {
            bg_color = theme.C.dialog, header_bg_color = theme.C.dialog,
            content_bg_color = theme.C.dialog,
            title_text_color = theme.C.t1, radius = theme.R.lg,
            title_align = airui.TEXT_ALIGN_CENTER,
            header_height = math.floor(40 * d), content_pad = 0,
        },
        on_close = function() overlay = nil end,
    })

    --[[快捷跳转行：当前所在设备用强调色点亮

    只把当前项换成「琥珀底块 + 琥珀描边 + 亮琥珀文字」，其余保持原来的
    「描边透明底 + 青色文字」—— 差异只出现在选中项上，不会让整行变花。
    选中态走 button（文字自绘、垂直居中），不用 theme.pills：
    pills 里的 label 铺满胶囊高，而 AirUI 的 label 没有垂直居中，文字会贴盒顶。]]
    local quick_h = math.floor(28 * d)
    local quick_w = math.floor((picker_w - pad_in * 2 - math.floor(8 * d)) / 3)
    local quick_gap = math.floor(4 * d)
    local active_storage = M.storage_index(start_path)
    for qi, q in ipairs(M.STORAGE_ITEMS) do
        local on = (qi == active_storage)
        theme.ghost_button(overlay, {
            x = pad_in + (qi - 1) * (quick_w + quick_gap), y = pad_in,
            w = quick_w, h = quick_h,
            text = q.text, size = theme.F.tiny,
            fg = on and theme.C.amber_light or theme.C.cyan,
            bg = on and theme.C.amber or nil,
            bg_opa = on and theme.OPA.rail_active or nil,
            border = on and theme.C.amber or nil,
            -- 按压态：只把色调压深一档，不透明度不变（默认 fill_hi=30 会比常态 48 更淡）
            pressed_bg = on and theme.C.amber_deep or nil,
            pressed_bg_opa = on and theme.OPA.rail_active or nil,
            on_click = function()
                M.open({ start_path = q.path, sw = cur_sw, sh = cur_sh, on_pick = cur_on_pick })
            end,
        })
    end

    --[[「返回上一级」按钮

    摆在快捷设备行的下面、文件列表的上面，独占一行而不是挤进设备行
    （设备行三格已经各占 1/3，再塞一个会把「内置存储」这四字挤到换行）。
    特意不把按钮浮在列表上方：列表滚动时它跟着一起滚走就点不到了。

    根目录没有上一级，此时不建按钮、列表也不留空档 —— 位置与改动前完全一致。]]
    local back_gap = math.floor(6 * d)
    local back_h = quick_h
    local parent_path = M.parent_path(start_path)
    if parent_path then
        local back_w = clamp(math.floor(120 * d), 100, picker_w - pad_in * 2)
        theme.ghost_button(overlay, {
            x = pad_in, y = pad_in + quick_h + back_gap,
            w = back_w, h = back_h,
            text = "< 返回上一级", size = theme.F.tiny,
            fg = theme.C.cyan,
            on_click = function()
                -- 与进入子目录同款：重建选择器，顺带刷新设备高亮
                M.open({ start_path = parent_path, sw = cur_sw, sh = cur_sh, on_pick = cur_on_pick })
            end,
        })
    end

    -- 文件列表滚动区域（有返回按钮时整体下移一行）
    local back_row_h = parent_path and (back_gap + back_h) or 0
    local list_y = pad_in + quick_h + back_row_h + pad_in
    local scroll = airui.container({
        parent = overlay,
        x = 0, y = list_y, w = picker_w, h = picker_h - list_y - pad_in,
        color = theme.C.bg, color_opacity = 0, scrollable = true,
    })
    render(start_path, scroll)
end

--[[打开选择器

@table o
  @string o.start_path 初始目录，默认 "/"
  @number o.sw,o.sh    按哪个逻辑屏尺寸算弹窗大小（旋转后的尺寸由调用方给）
  @function o.on_pick  选中文件后的回调，参数为完整路径
]]
function M.open(o)
    o = o or {}
    M.close()
    cur_sw = o.sw or screen_w or 480
    cur_sh = o.sh or screen_h or 854
    cur_on_pick = o.on_pick
    open_at(o.start_path or "/")
end

return M
