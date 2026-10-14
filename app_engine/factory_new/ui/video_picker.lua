--[[
@module  video_picker
@summary 视频文件选择弹窗（桌面播放器 / 全屏播放页共用）
@version 1.1
@date    2026.10.13
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
video_picker.storage_index(path) 当前路径 -> 存储设备序号（1 内置 / 2 SD卡 / 3 外置存储）
video_picker.list_items(dir)     目录 -> 可播放文件与子目录清单（已排序）

@usage
local video_picker = require "video_picker"
video_picker.open({
    start_path = "/",
    sw = screen_w, sh = screen_h,          -- 弹窗按这个尺寸定位与定大小
    avoid = { x=, y=, w=, h= },            -- 可选：避让矩形，弹窗不与其相交
    on_pick = function(path) ... end,      -- 用户选中了某个视频文件
    on_cancel = function() ... end,        -- 可选：用户关掉弹窗且未选文件时回调
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
    { text = "外置存储", path = "/little_flash/" },
}

-- 可播放的容器后缀（渲染前先按后缀筛，避免把整目录的图片/音频都列出来）
local VIDEO_EXTS = { hzv = true, mjpg = true, mp4 = true }

-- 弹窗运行态。同一时刻只会有一个弹窗，用文件级局部量即可。
local overlay = nil      -- airui.win 实例
local content_w = 0      -- 弹窗内容宽度（列表行宽按它算，不再依赖页面的 right_w）
local cur_sw, cur_sh = 480, 854
local cur_on_pick = nil
local cur_on_cancel = nil   -- 关掉弹窗且未选文件时的回调（程序性关闭不触发）
local in_programmatic_close = false  -- 程序性关闭标记：M.close/重建/宿主销毁都不触发 on_cancel
local cur_avoid = nil     -- 避让矩形 {x,y,w,h}（屏幕坐标）

--[[由当前路径反查存储设备序号（1 内置 / 2 SD卡 / 3 外置存储）

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

-- 分页读全目录（io.lsdir 单次条数有上限，按 offset 翻页取全）
local function lsdir_all(dir_path)
    local files, offset = {}, 0
    while offset < 1000 do
        local ok, page = io.lsdir(dir_path, 50, offset)
        if type(ok) == "table" and page == nil then page = ok; ok = true end
        if not ok or type(page) ~= "table" or #page == 0 then break end
        for _, f in ipairs(page) do files[#files + 1] = f end
        offset = offset + #page
    end
    return files
end

--[[列出目录下的子目录与可播放视频（目录在前、按名字排序）
luadb 平铺名按当前目录前缀归位，剩余首段合成子目录；根目录补 luadb 目录项
@return table items, number 原始条目数]]
function M.list_items(dir_path)
    local files = lsdir_all(dir_path)
    -- 尾斜杠兜底重试
    if (not files or #files == 0) and #dir_path > 1 and dir_path:sub(-1) == "/" then
        files = lsdir_all((dir_path:gsub("/+$", "")))
    end

    -- 平铺名归位：前缀过滤后取剩余首段，有后续段则合成子目录
    local sub_prefix = ""
    if dir_path:sub(1, 7) == "/luadb/" then
        sub_prefix = dir_path:sub(8)
    end

    local items, seen = {}, {}
    for _, f in ipairs(files or {}) do
        local name = (type(f) == "string") and f or f.name
        local is_dir = (type(f) == "table" and f.type == 1)
        if name then name = name:gsub("^/+", "") end
        if name and (sub_prefix ~= "" or name:find("/", 1, true)) then
            if name:sub(1, #sub_prefix) == sub_prefix then
                local rest = name:sub(#sub_prefix + 1)
                if rest:sub(-1) == "/" then
                    rest = rest:sub(1, -2)
                    is_dir = true
                end
                local seg, more = rest:match("^([^/]+)/?(.*)$")
                if rest == "" then
                    name = nil
                elseif more ~= "" then
                    is_dir = true
                    name = seg
                else
                    name = rest
                end
            else
                name = nil
            end
        end
        if name and name ~= "" and not seen[name] then
            seen[name] = true
            items[#items + 1] = {
                name = name, is_dir = is_dir,
                path = dir_path .. name .. (is_dir and "/" or ""),
            }
        end
    end

    -- 根目录补 luadb 目录项（挂载点不进 flash 根的 lsdir）
    if dir_path == "/" and not seen["luadb"] then
        items[#items + 1] = { name = "luadb", is_dir = true, path = "/luadb/" }
    end

    -- 过滤：目录全保留，文件只留可播视频
    local out = {}
    for _, it in ipairs(items) do
        if it.is_dir then
            it.playable = true
            out[#out + 1] = it
        else
            local ext = it.name:match("%.([^%.]+)$")
            if ext then ext = ext:lower() end
            it.playable = (ext ~= nil and VIDEO_EXTS[ext] == true)
            if it.playable then
                out[#out + 1] = it
            end
        end
    end
    if #out == 0 then
        -- 带原始计数便于排查
        log.warn("video_picker", "无可播内容", dir_path, "raw_n=", files and #files or 0)
    end
    table.sort(out, function(a, b)
        local ra = a.is_dir and 0 or (a.playable and 1 or 2)
        local rb = b.is_dir and 0 or (b.playable and 1 or 2)
        if ra ~= rb then return ra < rb end
        return a.name < b.name
    end)
    return out, (files and #files or 0)
end

function M.close()
    if overlay then
        in_programmatic_close = true
        pcall(function() overlay:destroy() end)
        in_programmatic_close = false
        overlay = nil
    end
end

-- 前向声明：进入子目录 / 返回上一级都要重建整套弹窗
local open_at

local function render(dir_path, scroll_container)
    if not scroll_container then return end
    local items, raw_n = M.list_items(dir_path)
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
                    M.open({ start_path = item.path, sw = cur_sw, sh = cur_sh, avoid = cur_avoid, on_pick = cur_on_pick, on_cancel = cur_on_cancel })
                elseif item.playable then
                    M.close()
                    if cur_on_pick then pcall(cur_on_pick, item.path) end
                end
            end,
        })
        -- 目录琥珀、视频青色、非视频灰色
        theme.label(row, {
            x = px, y = 0, w = math.floor(18 * d), h = row_h,
            text = ">", px_size = math.floor(13 * d),
            color = item.is_dir and theme.C.amber or (item.playable and theme.C.cyan or theme.C.t3),
            align = airui.TEXT_ALIGN_CENTER,
        })
        theme.label(row, {
            x = px + math.floor(20 * d), y = 0,
            w = list_w - 2 * px - math.floor(24 * d), h = row_h,
            text = item.name, px_size = math.floor(12 * d),
            color = item.playable and theme.C.t1 or theme.C.t3, align = airui.TEXT_ALIGN_LEFT,
        })
        y = y + row_h + math.floor(2 * d)
    end
    if #items == 0 then
        theme.label(scroll_container, {
            x = 0, y = math.floor(20 * d), w = list_w, h = row_h,
            text = (raw_n and raw_n > 0) and ("无视频文件（目录共 " .. raw_n .. " 项）")
                or "目录为空或读取失败",
            px_size = math.floor(12 * d),
            color = theme.C.t3, align = airui.TEXT_ALIGN_CENTER,
        })
    end
end

--[[弹窗避让定位：取不与 avoid 相交的最大空闲区居中，空间不足则缩小弹窗
@return table|nil { x, y, w, h } 无处可放返回 nil]]
local function place_avoiding(pw, ph, avoid, sw, sh)
    local m = math.floor(8 * (_G.density_scale or 1.0))
    local ax0, ay0 = avoid.x, avoid.y
    local ax1, ay1 = avoid.x + avoid.w, avoid.y + avoid.h
    local rects = {
        { x = ax1 + m, y = m, w = sw - m - (ax1 + m), h = sh - 2 * m },   -- 右
        { x = m, y = m, w = ax0 - m - m, h = sh - 2 * m },                -- 左
        { x = m, y = ay1 + m, w = sw - 2 * m, h = sh - m - (ay1 + m) },   -- 下
        { x = m, y = m, w = sw - 2 * m, h = ay0 - m - m },                -- 上
    }
    local best, best_area = nil, 0
    for _, r in ipairs(rects) do
        if r.w > 0 and r.h > 0 then
            local area = r.w * r.h
            if area > best_area then best, best_area = r, area end
        end
    end
    if not best then return nil end
    local w = math.min(pw, best.w)
    local h = math.min(ph, best.h)
    return {
        x = best.x + math.floor((best.w - w) / 2),
        y = best.y + math.floor((best.h - h) / 2),
        w = w, h = h,
    }
end

open_at = function(start_path)
    local d = _G.density_scale or 1.0

    -- 弹窗尺寸：宽屏取半屏（≤460），窄屏取 0.72 屏宽
    local picker_w = (cur_sw <= 560) and math.min(math.floor(cur_sw * 0.72), 460)
        or math.min(math.floor(cur_sw * 0.50), 460)
    local picker_h = math.floor(cur_sh * 0.70)
    local pad_in = math.floor(12 * d)

    -- 有避让矩形时定位到空闲区，否则居中
    local place = cur_avoid and place_avoiding(picker_w, picker_h, cur_avoid, cur_sw, cur_sh)
    if place then
        picker_w, picker_h = place.w, place.h
    end
    content_w = picker_w

    -- auto_center 居中；避让定位时用显式 x/y
    overlay = airui.win({
        parent = airui.screen, title = "选择视频文件",
        x = place and place.x or 0, y = place and place.y or 0,
        w = picker_w, h = picker_h, close_btn = true,
        auto_center = (place == nil),
        style = {
            bg_color = theme.C.dialog, header_bg_color = theme.C.dialog,
            content_bg_color = theme.C.dialog,
            title_text_color = theme.C.t1, radius = theme.R.lg,
            title_align = airui.TEXT_ALIGN_CENTER,
            header_height = math.floor(40 * d), content_pad = 0,
        },
        on_close = function()
            overlay = nil
            if not in_programmatic_close and cur_on_cancel then pcall(cur_on_cancel) end
        end,
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
                M.open({ start_path = q.path, sw = cur_sw, sh = cur_sh, avoid = cur_avoid, on_pick = cur_on_pick, on_cancel = cur_on_cancel })
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
                M.open({ start_path = parent_path, sw = cur_sw, sh = cur_sh, avoid = cur_avoid, on_pick = cur_on_pick, on_cancel = cur_on_cancel })
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
  @table o.avoid    可选：避让矩形 {x,y,w,h}（如桌面视频区），弹窗不与它相交
  @function o.on_pick  选中文件后的回调，参数为完整路径
]]
function M.open(o)
    o = o or {}
    M.close()
    cur_sw = o.sw or screen_w or 480
    cur_sh = o.sh or screen_h or 854
    cur_on_pick = o.on_pick
    cur_on_cancel = o.on_cancel
    cur_avoid = o.avoid
    open_at(o.start_path or "/")
end

return M
