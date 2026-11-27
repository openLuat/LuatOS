--[[
@module  video_win
@summary 视频演示页（全屏播放 HZV）
@version 1.0
@date    2026.11.23

=== 这页要解决什么 ===
视频要同时照顾 4.3 寸 480×272 与 7 寸 1024×600 两种屏，而 airui.videoplayer 不支持缩放、
控件尺寸必须等于素材帧尺寸，所以桌面不内嵌播放器，改成独立页面：左栏进「视频演示」，
按当前屏幕挑对应档的素材全屏播。

=== 分层：视频层在下，控件层在上 ===
LVGL 的 z 序等于创建顺序，后建的盖先建的。播放器是在 after_release 里异步创建的，
比标题、返回按钮、控制栏都晚 —— 如果三者平铺在同一个父容器里，视频必然盖住返回按钮，
而且按钮既看不见也点不动（点击被上层吃掉）。

所以这里固定两层，创建顺序不可调换：

    root
    ├── video_layer   先建，0..sh-BAR_H，播放器的唯一父容器
    └── ui_layer      后建，整屏透明，装标题 / 返回 / 控制栏 / 提示文字

播放器永远在 video_layer 里面，重播（销毁重建）也不会跑到 ui_layer 之上。
两层都用「颜色 + color_opacity」做透明，不能用对象级透明度 ——
LVGL 的父对象透明度会乘到子对象上，父层归零会把整棵子树一起抹掉。
（airui 的 color_opacity 只写 bg_opa，不影响子对象，这是唯一安全的写法。）

=== 两种素材，按屏宽选 ===
airui.videoplayer 不支持缩放，控件尺寸给错会被强行改回素材尺寸，所以素材按屏幕分两档，
由 tools/hzv_mini.py 的 PRESETS 生成：

    预设    画面      帧数   体积      用在哪
    small   336×224   105    1.17 MiB  4.3 寸 480×272、5 寸 800×480
    hd      828×552    68    2.04 MiB  7 / 9 / 10 寸 1024×600（铺满视频区，占屏宽 81%）

选哪一支看屏宽：>= 1024 走 hd，否则走 small（asset_names()）。两支互为兜底，
只烧了一支也能播。两份合计 + 代码约 3.65 MiB，脚本区 4 MiB 放得下。

hd 为什么不用原片 480×320：那在 1024 宽屏上只占 47%，两侧各留 272px 空白，
看上去就是中间一小块。放大到 828×552 后帧数从 145 降到 68（约 6.8 秒一循环），
这是体积上限下的取舍 —— 想更久就把 PRESETS 里 hd 的 quality/target_kb 调低再重新生成。

素材比视频区大时不会缩放、只会被裁掉右侧和下侧，日志会打一条 warn 说明实际裁了多少。

=== 素材从哪来 ===
/luadb/ → /sd/video/ → /sd/ → /
先找到哪个用哪个，路径口径收在 video_util.SEARCH_DIRS，页面不自己拼。

=== 三种「播不了」要分清楚 ===
1. 固件没编入 airui.video  —— 这是底包问题，改代码没用
2. 素材一个都没找到       —— 把搜过的目录列出来，用户自己看该往哪拷
3. 素材找到了但建播放器失败 —— 打印尺寸和堆剩余，交给 video_util 的日志
三种都在页面上直接写出来，不要只打日志（没有串口的现场只能看屏幕）。
]]

local theme = require "ui_theme"
local video_util = require "video_util"

local window_id, root
local video_layer, ui_layer     -- 视频层在下、控件层在上，创建顺序决定 z 序
local player = nil
local bar = nil
local current_path = nil
local playing, looped = false, true
local info_label = nil

local BAR_H  = 48               -- 底部控制栏高度（theme.video_bar 的默认值）
-- 顶部标题 / 返回按钮高约 30px，压在视频上沿；不参与视频区计算，视频可整块铺到顶
local TITLE_H = 30

-- 兜底帧尺寸：素材读不出尺寸时按这个建，绝不是播放尺寸的依据
local DEF_VW, DEF_VH = 336, 224

--[[按屏幕尺寸挑素材：屏宽 >= 1024 是 7/9/10 寸，用原片尺寸的 hd 版；
小于 1024 是 4.3 寸与 5 寸，用缩到视频区的 small 版。

两支互为兜底 —— 只烧了其中一支也能播，不会因为文件名对不上就黑屏。
两份素材由 tools/hzv_mini.py 生成（PRESETS 表），判据必须与那里保持一致。]]
local function asset_names()
    local sw = screen_w or 480
    if sw >= 1024 then
        return { "fruit_hd.hzv", "fruit.hzv" }
    end
    return { "fruit.hzv", "fruit_hd.hzv" }
end

local function stop_player()
    if player then
        pcall(function() player:stop() end)
        pcall(function() player:destroy() end)
        player = nil
    end
    playing = false
    video_util.cancel_pending()
end

--[[视频区几何：屏宽 × (屏高 - 控制栏)

播放器的父容器与摆放都以这里为准，两处各算一遍迟早对不上。
返回值是相对 root 的 x/y/w/h。]]
local function video_area()
    local sw, sh = screen_w or 480, screen_h or 272
    local h = sh - BAR_H
    if h < 1 then h = sh end          -- 屏太矮时先保正高度，控制栏另做兜底
    return 0, 0, sw, h
end

--[[把「为什么播不了」写到页面上
三个原因分开写，现场没有串口时只能靠这行字判断。
ttl_ms 给了就在到点后自己消失，避免故障字常驻挡住画面。
父容器是 ui_layer，保证提示压在视频之上。]]
local reason_timer = nil

local function clear_reason()
    if reason_timer then sys.timerStop(reason_timer); reason_timer = nil end
    if info_label then info_label:destroy(); info_label = nil end
end

local function show_reason(line1, line2, ttl_ms)
    local host = ui_layer or root
    if not host then return end
    clear_reason()
    local w = screen_w or 480
    local h = 72
    local lx, ly, lw, lh = video_area()
    local y = math.max(ly, ly + (lh - h) // 2)
    info_label = theme.label(host, {
        x = 16, y = y, w = w - 32, h = h,
        text = line1 .. "\n" .. (line2 or ""),
        px_size = theme.fs("caption"), color = theme.C.t2,
        align = airui.TEXT_ALIGN_CENTER,
    })
    if ttl_ms then
        reason_timer = sys.timerStart(function()
            reason_timer = nil
            clear_reason()
        end, ttl_ms)
    end
end

local function sync_bar()
    if bar then bar:sync(playing, looped) end
end

--[[建播放器：画面按素材帧尺寸摆放（组件不支持缩放，尺寸给错会被强行改回去）

父容器必须是 video_layer，不能是 root ——
挂在 root 下就会盖住 ui_layer 里的返回按钮，点击也会被视频吃掉。]]
local function start_play(path)
    stop_player()
    clear_reason()
    if not path then return end
    current_path = path

    local vw, vh = video_util.frame_size(path, DEF_VW, DEF_VH)
    local lx, ly, lw, lh = video_area()

    -- 素材大于视频区：不缩放，居中后右侧/下侧被裁。把裁掉多少写清楚，别让人以为是花屏。
    if vw > lw or vh > lh then
        log.warn("video_win", "素材超出视频区，将被裁剪",
            vw .. "×" .. vh, "视频区", lw .. "×" .. lh,
            "建议用 hzv_mini.py --fit-to " .. lw .. "x" .. lh .. " 重新生成")
    end
    local px = lx + math.max(0, (lw - vw) // 2)
    -- 高度放得进「标题行以下」就在那块干净区里居中，避免画面被标题和返回按钮压住；
    -- 放不进就贴顶（否则底部会被控制栏切掉更多）
    local py
    if vh <= lh - TITLE_H then
        py = ly + TITLE_H + (lh - TITLE_H - vh) // 2
    else
        py = ly
    end

    if bar then bar:set_file(path) end

    video_util.after_release(function()
        if not video_layer then return end
        player = video_util.create_player(path, {
            parent = video_layer, x = px - lx, y = py - ly, w = vw, h = vh,
            loop = looped,
            on_complete = function()
                playing = false
                sync_bar()
            end,
        })
        if player then
            playing = true
            pcall(function() player:play() end)
            log.info("video_win", "起播", path, vw .. "×" .. vh)
        else
            playing = false
            show_reason("素材无法播放：" .. path,
                "分辨率上限 1024×600，或固件/内存不足；详见日志 video_util")
        end
        sync_bar()
    end)
end

-- 找素材：按屏幕尺寸决定优先名，找不到就扫所有落点的 .hzv，用第一个
local function pick_asset()
    for _, name in ipairs(asset_names()) do
        local p = video_util.find_asset(name)
        if p then return p, name end
    end
    local all = video_util.scan_assets()
    if #all > 0 then return all[1].path end
    return nil
end

-- 「选择」：在扫到的素材里轮换（8801 没做文件夹浏览器，先按顺序切）
local function next_asset()
    local all = video_util.scan_assets()
    -- 没得切就静默返回：页面上正在播的那一支就是唯一素材，不该弹「没有找到」
    if #all == 0 then
        if not current_path then
            local only = pick_asset()
            if only then start_play(only) end
        end
        return
    end
    if #all == 1 then
        if all[1].path ~= current_path then start_play(all[1].path) end
        return
    end
    local idx = 0
    for i, item in ipairs(all) do
        if item.path == current_path then idx = i break end
    end
    local nxt = all[(idx % #all) + 1]
    start_play(nxt.path)
end

local function build()
    local sw, sh = screen_w or 480, screen_h or 272
    root = theme.page_bg(airui.screen, sw, sh, 0, 0)
    theme.bind_root(root, { keep_visible = true })

    --[[两层，创建顺序就是 z 序，不能交换

    video_layer 先建：它是播放器唯一的父容器，占屏高减去控制栏那一块。
    ui_layer 后建：整屏透明，标题 / 返回 / 控制栏 / 提示都挂在它下面。

    透明用「颜色 + color_opacity = 0」，不能用原值 0 的 opa ——
    LVGL 父对象透明度会乘到子对象上，父层归零等于把整棵子树一起隐藏。]]
    local lx, ly, lw, lh = video_area()
    video_layer = theme.box(root, {
        x = lx, y = ly, w = lw, h = lh,
        color = theme.C.bg, radius = 0,
    })
    ui_layer = theme.box(root, {
        x = 0, y = 0, w = sw, h = sh,
        color = theme.C.bg, opa = 0, radius = 0,
    })

    -- 顶部标题 + 返回：压在视频之上，底板给接近实色，画面再亮也读得清
    theme.label(ui_layer, {
        x = 12, y = 6, w = sw - 96, h = 24, text = "视频演示",
        px_size = theme.fs("h2"), color = theme.C.t1,
    })
    theme.ghost_button(ui_layer, {
        x = sw - 76, y = 4, w = 64, h = 26, text = "返回",
        bg = theme.C.panel, bg_opa = 235, border_w = 0,
        on_click = function() exwin.close(window_id) end,
    })

    -- 底部控制栏（theme.video_bar 是桌面/全屏页共用的唯一实现）
    bar = theme.video_bar(ui_layer, {
        x = 0, y = sh - BAR_H, w = sw, h = BAR_H, radius = 0,
        playing = false, loop = looped,
        file_text = "—",
        mode_text = "返回",
        on_play = function()
            if not player then start_play(current_path or pick_asset()); return end
            if playing then
                pcall(function() player:pause() end)
                playing = false
            else
                pcall(function() player:play() end)
                playing = true
            end
            sync_bar()
        end,
        on_loop = function()
            looped = not looped
            -- loop 只在创建组件时生效，切完标志位整组重建一次
            if current_path then start_play(current_path) else sync_bar() end
        end,
        on_pick = next_asset,
        on_mode = function() exwin.close(window_id) end,
    })

    -- ==================== 开局三问 ====================
    if not video_util.available() then
        show_reason("本固件未编入 airui.video",
            "底包缺 videoplayer 组件，改 Lua 代码无效，需要换固件")
        return
    end

    local path = pick_asset()
    if not path then
        local dirs = table.concat(video_util.SEARCH_DIRS, "  ")
        -- 提示只留几秒，不常驻：页面本身有底部控制栏，空着也不至于让人以为死机
        show_reason("没有找到 .hzv 素材",
            "已查：" .. dirs .. "；拷一个 fruit.hzv 进去即可", 6000)
        log.warn("video_win", "无素材", dirs)
        return
    end

    start_play(path)
end

local function destroy()
    stop_player()
    clear_reason()      -- 同时停掉自动清除定时器
    if bar then bar = nil end
    video_layer, ui_layer = nil, nil
    if root then root:destroy() end
    root, current_path = nil, nil
end

local function open()
    if window_id then return end
    window_id = exwin.open({
        owner = false,
        on_create = function() build() end,
        on_get_focus = function()
            -- 回来后不自动重播：播放器在失焦时已经销毁，重播交给用户点
            playing = false
            sync_bar()
        end,
        on_destroy = function()
            destroy()
            window_id = nil
            theme.shell.host_id = nil
        end,
    })
    theme.shell.host_id = window_id
end

sys.subscribe("OPEN_VIDEO_WIN", open)
