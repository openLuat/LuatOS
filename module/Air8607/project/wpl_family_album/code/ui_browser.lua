--[[
@module  ui_browser
@summary 相册目录页：每页 2x2 共 4 个大卡片，带真缩略图
@version 1.2
@date    2026.10.22

=== 缩略图怎么来的 ===
直接 airui.image 显示 JPEG 原图，fit="cover" 由 LVGL 绘制时缩放。
HW JPEG 硬解激活后单张解码缓冲 1.23MB（RGB565），airui 解码器在缓存满时
会自动 lv_image_cache_drop 清缓存重试，4 张卡片逐张解码上屏、不写 SD。
]]
local conf = require "conf"
local theme = require "theme"
local sd = require "sd_card"
local photo_cache = require "photo_cache"
local thumb = require "thumb"

local M = {}
local C = theme.C
local SW, SH = conf.W, conf.H

local root = nil
local app_ref = nil
local cur_dir = conf.sd.mount
local page = 1
local listing = nil
local page_count = 1

-- ==================== 小工具 ====================
local function short_name(name, max_chars)
    local i, cnt = 1, 0
    while i <= #name do
        local b = name:byte(i)
        local step = 1
        if b >= 0xF0 then step = 4
        elseif b >= 0xE0 then step = 3
        elseif b >= 0xC0 then step = 2 end
        i = i + step
        cnt = cnt + 1
        if cnt > max_chars then
            return name:sub(1, i - step - 1) .. "..."
        end
    end
    return name
end

local function folder_icon(parent, x, y, size)
    local k = size / 64
    theme.shape({
        parent = parent, x = x, y = y, w = size, h = size,
        items = {
            { type = "rect", x = 8 * k, y = 12 * k, w = 24 * k, h = 16 * k, radius = 5 * k,
              fill = true, fill_color = 0xF3B968 },
            { type = "rect", x = 8 * k, y = 22 * k, w = 46 * k, h = 32 * k, radius = 7 * k,
              fill = true, fill_color = 0xF6C77A },
            { type = "rect", x = 8 * k, y = 22 * k, w = 46 * k, h = 8 * k, radius = 4 * k,
              fill = true, fill_color = 0xFBD79B },
        },
    })
end

local function photo_icon(parent, x, y, size)
    local k = size / 64
    theme.shape({
        parent = parent, x = x, y = y, w = size, h = size,
        items = {
            { type = "rect", x = 4 * k, y = 10 * k, w = 54 * k, h = 44 * k, radius = 7 * k,
              color = 0xE9C9A8, width = 2,
              fill = true, fill_color = 0xFFF1DF },
            { type = "circle", cx = 19 * k, cy = 24 * k, r = 6 * k,
              fill = true, fill_color = C.sun },
            { type = "ellipse", cx = 36 * k, cy = 46 * k, rx = 22 * k, ry = 10 * k,
              fill = true, fill_color = 0xBFD3A6 },
            { type = "ellipse", cx = 22 * k, cy = 47 * k, rx = 16 * k, ry = 8 * k,
              fill = true, fill_color = 0xA9C48E },
        },
    })
end

-- ==================== 顶栏 ====================
local function build_topbar()
    theme.box(root, 0, 0, SW, 88, 0xFFF1E4, 0)
    theme.shape({
        parent = root, x = 0, y = 86, w = SW, h = 2,
        items = { { type = "rect", x = 0, y = 0, w = SW, h = 2, fill = true, fill_color = C.line } },
    })

    theme.button(root, 16, 16, 104, 56, "返回", 20, 0xEFD9C2, C.ink, function()
        theme.defer(function()
            if app_ref then app_ref.browser_back() end
        end)
    end, 18)

    local at_root = (cur_dir == conf.sd.mount)
    theme.button(root, 128, 16, 104, 56, "上一级", 20,
        at_root and 0xF3E3D2 or 0xEFD9C2,
        at_root and C.ink3 or C.ink,
        function()
            if at_root then return end
            theme.defer(function()
                if app_ref then app_ref.browser_up() end
            end)
        end, 18)

    theme.label(root, 248, 12, 430, 30, short_name(sd.pretty_path(cur_dir), 20), 20, C.ink)
    local count_txt = string.format("共 %d 项%s", (listing and listing.total) or 0,
        (listing and listing.truncated) and "（仅显示前 " .. conf.sd.scan_max .. " 项）" or "")
    theme.label(root, 248, 46, 430, 22, count_txt, 15, C.ink3)

    theme.label(root, 676, 16, 116, 56, string.format("第 %d/%d 页", page, page_count),
        17, C.ink2, airui.TEXT_ALIGN_CENTER)

    local prev_ok = page > 1
    local next_ok = page < page_count
    theme.button(root, 800, 16, 96, 56, "上页", 19,
        prev_ok and 0xEFD9C2 or 0xF3E3D2,
        prev_ok and C.ink or C.ink3,
        function()
            if not prev_ok then return end
            theme.defer(function()
                page = page - 1
                M.rebuild()
            end)
        end, 18)
    theme.button(root, 908, 16, 100, 56, "下页", 19,
        next_ok and 0xEFD9C2 or 0xF3E3D2,
        next_ok and C.ink or C.ink3,
        function()
            if not next_ok then return end
            theme.defer(function()
                page = page + 1
                M.rebuild()
            end)
        end, 18)
end

-- ==================== 卡片 ====================
local PX, PY, PW, PH = 18, 44, 204, 120     -- 预览区和缩略图 1:1，避免再缩放一次变糊

local function build_tile(item, idx, x, y, w, h)
    local is_dir = item.dir
    local tile = theme.card(root, x, y, w, h, is_dir and 0xFFF8EA or C.card, 18, C.line, 1)

    -- 左上角序号
    theme.label(tile, 14, 10, 60, 22, string.format("%02d", idx), 15, C.ink3)

    -- 占位图标：缩略图生成好之后会被盖在下面（图片控件后创建，画在上层）
    if is_dir then
        folder_icon(tile, PX + (PW - 96) / 2, PY + (PH - 96) / 2, 96)
    else
        photo_icon(tile, PX + (PW - 96) / 2, PY + (PH - 96) / 2, 96)
    end

    local tx = 240
    theme.label(tile, tx, 46, w - tx - 16, 34, short_name(item.name, 12), 21, C.ink)
    theme.label(tile, tx, 88, w - tx - 16, 24,
        is_dir and "文件夹" or theme.size_text(item.size), 16, C.ink3)
    theme.label(tile, tx, 122, w - tx - 16, 24,
        is_dir and "点开进入文件夹" or "点击查看大图", 15, 0xC9A98C)

    return tile
end

-- ==================== 缩略图填充 ====================
local gen_token = 0

--[[后台逐张生成缩略图并贴到卡片上
卡片先出来，图片再一张张补上，所以第一眼不会等整页。
进查看器时自动暂停（避免和 4.19MB 的帧缓冲抢内存），回到目录页继续。
]]
local function fill_previews(placed)
    if conf.photo.preview == false then
        log.info("browser", "conf.photo.preview = false，只显示图标")
        return
    end
    if #placed == 0 then return end
    -- 注意：LuatOS 的 videoplayer 是 userdata，不是 table
    if not videoplayer or not videoplayer.open then
        log.warn("browser", "固件没有 videoplayer 的 Lua 库，缩略图只能用图标代替")
        return
    end

    gen_token = gen_token + 1
    local token = gen_token

    sys.taskInit(function()
        for i = 1, #placed do
            local it = placed[i]
            -- 页面已重建 / 已销毁：放弃
            if token ~= gen_token or not root then return end
            -- 不在目录页（进了查看器/首页）：等回来再继续
            while token == gen_token and root and app_ref
                and app_ref.state_name() ~= "browser" do
                sys.wait(200)
            end
            if token ~= gen_token or not root then return end

            local bin = thumb.build(it.item)
            if token ~= gen_token or not root then return end
            if bin then
                pcall(function()
                    airui.image({
                        parent = it.tile, x = PX, y = PY, w = PW, h = PH,
                        src = bin, fit = "cover",
                    })
                end)
            end

            sys.wait(20)       -- 让 LVGL 有机会刷一帧再解下一张
        end
    end)
end

-- ==================== 页面 ====================
local function rebuild_inner()
    local P = conf.photo
    local cols, rows = P.grid_cols, P.grid_rows
    local gap = 20
    local x0, y0 = 20, 104
    local tw = math.floor((SW - x0 * 2 - gap * (cols - 1)) / cols)
    local th = math.floor((SH - y0 - 20 - gap * (rows - 1)) / rows)
    local per_page = cols * rows

    local items = {}
    if listing then
        for _, it in ipairs(listing.dirs) do items[#items + 1] = it end
        local pi = 0
        for _, it in ipairs(listing.photos) do
            pi = pi + 1
            items[#items + 1] = { name = it.name, path = it.path, size = it.size,
                                  dir = false, photo_idx = pi }
        end
    end

    page_count = math.max(1, math.ceil(#items / per_page))
    if page > page_count then page = page_count end

    if #items == 0 then
        theme.label(root, 0, 250, SW, 40, "这个文件夹里还没有照片", 26, C.ink2, airui.TEXT_ALIGN_CENTER)
        theme.label(root, 0, 300, SW, 28, "把照片拷进 SD 卡，或在首页点刷新", 18, C.ink3, airui.TEXT_ALIGN_CENTER)
        return
    end

    local first = (page - 1) * per_page
    local placed = {}
    for i = 1, per_page do
        local item = items[first + i]
        if item then
            local col = (i - 1) % cols
            local row = math.floor((i - 1) / cols)
            local x = x0 + col * (tw + gap)
            local y = y0 + row * (th + gap)
            local tile = build_tile(item, first + i, x, y, tw, th)
            tile:set_on_click(function()
                if not app_ref then return end
                local is_dir, path, pidx = item.dir, item.path, item.photo_idx or 1
                local list = listing.photos
                theme.defer(function()
                    if not app_ref then return end
                    if is_dir then
                        app_ref.open_dir(path)
                    else
                        app_ref.open_photo(list, pidx)
                    end
                end)
            end)
            if not item.dir then
                placed[#placed + 1] = { item = item, tile = tile }
            end
        end
    end

    fill_previews(placed)
end

local function build_page()
    root = airui.container({
        parent = nil, x = 0, y = 0, w = SW, h = SH,
        color = C.bg1, radius = 0, border_width = 0,
    })
    theme.gradient(root, 0, 0, SW, SH, C.bg1, 0xFFEBD9, 8)

    listing = sd.list(cur_dir)

    -- 先算页数（rebuild_inner 里更新 page_count），再画顶栏，
    -- 否则顶栏用旧值显示“第 1/1 页”、下页按钮被置灰（5 张只看得到 4 张）
    rebuild_inner()
    build_topbar()
end

-- ==================== 对外接口 ====================
function M.build(app, dir)
    M.destroy()
    app_ref = app
    cur_dir = dir or conf.sd.mount
    page = 1
    photo_cache.reset()
    build_page()
end

function M.rebuild()
    if not root then return end
    M.destroy()
    build_page()
end

function M.dir()
    if not root then return nil end
    return cur_dir
end

function M.destroy()
    gen_token = gen_token + 1      -- 让后台缩略图任务立刻退出
    if root then
        pcall(function() root:destroy() end)
        root = nil
    end
    listing = nil
end

return M
