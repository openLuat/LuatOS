--[[
@module  video_win
@summary 全屏播放页 —— 竖屏面板自动旋转成横屏，任意尺寸素材居中播放
@version 1.1
@date    2026.09.20
@author  江访

=== 消息协议（订阅/发布）===
订阅: OPEN_VIDEO_WIN(file)      → 打开全屏播放页；file 为初始播放文件（可省略）
发布: VIDEO_FILE_CHANGED(path)  → 在本页里换了文件，通知桌面同步「当前文件」
退出: 控制栏最右「窗口」→ exwin.close(window_id)（回到窗口态）

=== 关键约束（改这个文件前必读）===

1. **airui 播放器不支持缩放**
   components/airui/src/components/widgets/luat_airui_video.c：
   "scaling is not supported yet ... force reset widget size" —— 传进去的 w/h 与素材帧
   尺寸不一致时，控件会被强制改回素材尺寸。所以「居中」只能靠摆放，不能靠缩放；
   素材比可用区域大时按**中心裁切**（我们只负责把控件摆到居中位置）。

2. **硬解链路是单实例资源**
   进入本页时桌面（idle_win）会在自己的 on_lose_focus 里停掉并销毁它的播放器，
   退出时再由 on_get_focus 重新起播。exwin.open 的顺序是「先让当前窗口 lose_focus、
   再 create 新窗口」，所以两个播放器不会同时存在 —— 不要试图让两边一起播。

3. **旋转只改 airui 的显示旋转，不改面板方向**
   airui.set_rotation 会更新 airui 的逻辑宽高，但 screen_w / screen_h 这两个全局量
   只在 lcd_drv.init() 时算过一次、**不会跟着运行时旋转变**。
   本页一律用 lcd.getSize()（面板物理尺寸）+ airui.status()（旋转后的逻辑尺寸），
   绝不读那两个全局量。

4. **播放器控件的父容器不能用 airui.container**
   LVGL 容器默认 SCROLLABLE + scrollbar_mode = AUTO，子控件只要超出 1px 就画滚动条。
   本页的舞台层用 airui.shape（C 端显式 remove_flag(SCROLLABLE)，且不吃点击）。
   注意：父对象不可点击**不影响**子对象 —— LVGL 的 lv_indev_search_obj 会无视父对象的
   CLICKABLE 标志去遍历子对象，所以控制栏挂在黑底 shape 下照样点得到。

5. **层级靠「创建顺序」定，且换文件不能打乱它**（同一父对象内 LVGL 按创建顺序绘制）
   后建的压住先建的，所以本页的真实顺序是：

       黑底 bg → 舞台层 stage → 视频 play(file) → 底部控制栏

   少了这条，素材比屏幕大时画面会盖住控制栏。
   而「视频为什么挂在 stage 上」正是为了保住这条：换文件时是**在 stage 内部**重建视频对象，
   若没有 stage（视频直接挂 bg），重建出来的视频在 bg 里会排到**最后**，
   反过来压住控制栏 —— 层级就被「换文件」这个动作破坏了。

6. **控制栏与桌面播放器共用一份实现**（2026-09-20）
   底部那排按钮走 theme.video_bar（ui_theme.lua），与 idle_win 的播放器控制栏是
   同一段代码 —— 排列、尺寸、间距、配色策略结构性一致，不会再各自漂移。
   差别只有最右一格的文案：桌面是「全屏」（进来），本页是「窗口」（回去）。
   按钮的底色与文字色都由 video_bar 按主题令牌 + 当前状态算，本页不自己写颜色。
]]

local theme = require "ui_theme"
local video_picker = require "video_picker"
local video_util = require "video_util"
local ok_exaudio, exaudio = pcall(require, "exaudio")
if not ok_exaudio then exaudio = nil end

-- 读不到容器头时的兜底帧尺寸：与工程里唯一的开机素材 luatos_boot.hzv 一致
local DEFAULT_FILE = "/luatos_boot.hzv"
local DEFAULT_VW, DEFAULT_VH = 480, 320

local window_id = nil
local bg = nil                -- 全屏黑底（airui.shape，不可滚动、不吃点击）
local stage = nil             -- 舞台层：视频的父对象（换文件不影响它，因此不影响层级）
local video_obj = nil         -- airui.video 实例
local ctrl_bar = nil          -- 底部控制栏句柄（theme.video_bar 的返回值，不是 LVGL 对象）
local empty_label = nil       -- 素材放不出来时的提示

local is_playing = true
local is_loop = true
local current_file = nil

local W, H = 0, 0             -- 旋转后的逻辑屏幕尺寸
local geo = nil               -- calc_layout 的结果（只用于摆画面，控件与它无关）

-- 旋转记账：进入时若把显示转了，退出必须转回去
local prev_rotation = 0
local rotated = false

local function clamp(v, lo, hi)
    if v < lo then return lo end
    if v > hi then return hi end
    return v
end

--[[全屏播放页几何（纯函数，便于离线复算）

控制栏独占屏幕底部一条带子，画面在它**之上**的剩余区域里居中。
左上角原先还有一个返回键、画面要给它让出顶部一条带子；该按钮已并进控制栏
（本页最右一格「窗口」），所以顶部只留页边距，画面的可用高度随之变大。

只有当素材**放不进**中间那一段时才退化成「整屏居中 + 控制栏浮在画面上」——
此时靠创建顺序保证控制栏在画面之上（见文件头第 5 条）。

@param sw,sh 旋转后的逻辑屏幕尺寸
@param vw,vh 素材原生帧尺寸
@return table 各控件的像素矩形 + overlay 标志（是否退化成了控件叠在画面上）
]]
local function calc_layout(sw, sh, vw, vh)
    local d = _G.density_scale or 1.0
    local short = math.min(sw, sh)

    local pad     = clamp(math.floor(short * 0.021), 6, 18)
    local ctrl_h  = clamp(math.floor(sh * 0.10), 48, 56)

    local top_h = pad
    local bot_h = pad + ctrl_h + pad
    local avail_h = sh - top_h - bot_h
    local avail_w = sw - 2 * pad

    local vx, vy, overlay
    if vw <= avail_w and vh <= avail_h then
        -- 常规：画面落在页边距与控制栏之间，居中
        vx = math.floor((sw - vw) / 2)
        vy = top_h + math.floor((avail_h - vh) / 2)
        overlay = false
    else
        -- 超大素材：整屏居中（左右/上下可能等量超出，由父容器边界裁掉）
        vx = math.floor((sw - vw) / 2)
        vy = math.floor((sh - vh) / 2)
        overlay = true
    end

    return {
        pad = pad, ctrl_h = ctrl_h, overlay = overlay,
        bar_x = pad, bar_y = sh - pad - ctrl_h, bar_w = sw - 2 * pad, bar_h = ctrl_h,
        video_x = vx, video_y = vy, video_w = vw, video_h = vh,
        top_h = top_h, bottom_h = bot_h,
        density = d,
    }
end

--[[面板物理尺寸（不受旋转影响）

screen_w / screen_h 是 lcd_drv.init() 一次性算出来的，运行时旋转不会更新，
所以物理尺寸只能问驱动。]]
local function panel_size()
    if lcd and lcd.getSize then
        local ok, w, h = pcall(lcd.getSize)
        if ok and w and h and w > 0 and h > 0 then return w, h end
    end
    return screen_w or 480, screen_h or 854
end

--[[逻辑屏幕尺寸（旋转之后）

airui.status() 读的是 airui 自己维护的 width/height，set_rotation 会同步更新它，
是唯一可靠来源。取不到时按「转了 90/270 就宽高互换」自行推导。]]
local function logical_size(phys_w, phys_h, swapped)
    if airui.status then
        local ok, st = pcall(airui.status)
        if ok and type(st) == "table" and st.w and st.h and st.w > 0 and st.h > 0 then
            return st.w, st.h
        end
    end
    if swapped then return phys_h, phys_w end
    return phys_w, phys_h
end

--[[竖屏面板 -> 转 90° 变横屏；已经是横屏则不动

只动 airui 的显示旋转，面板本身不变。退出时按 prev_rotation 原样转回去
（见 on_destroy）—— 桌面还压在下面，它的一套控件是按原来的方向摆的。]]
local function enter_landscape()
    local phys_w, phys_h = panel_size()

    prev_rotation = 0
    if airui.get_rotation then
        local ok, r = pcall(airui.get_rotation)
        if ok and type(r) == "number" then prev_rotation = r % 360 end
    end

    rotated = false
    local target = prev_rotation
    -- 竖屏面板：0/180 都不是横屏，统一转到 90（90/270 本身已是横屏，保持原样）
    if phys_h > phys_w and prev_rotation ~= 90 and prev_rotation ~= 270 then
        target = 90
    end

    if target ~= prev_rotation and airui.set_rotation then
        local ok, r = pcall(airui.set_rotation, target)
        if ok and r then rotated = true end
    end

    local swapped = rotated or (target == 90 or target == 270)
    return logical_size(phys_w, phys_h, swapped)
end

--[[把显示转回去

必须在窗口销毁时做：桌面（idle_win）此刻还压在窗口栈下面，
它那套控件的坐标全是按旋转前的方向算好的 —— 不转回去，回到桌面就是歪的。
airui_display_set_rotation 内部会 invalidate 当前屏幕，不需要额外触发重绘。]]
local function leave_landscape()
    if not rotated then return end
    rotated = false
    if airui.set_rotation then
        pcall(airui.set_rotation, prev_rotation)
        log.info("video_win", "display rotation restored ->", prev_rotation)
    end
end

--- 按当前 current_file / geo 重建视频控件（换文件、切循环都走这里）
local function rebuild_video()
    if video_obj then
        pcall(function() video_obj:stop() end)
        pcall(function() video_obj:destroy() end)
        video_obj = nil
    end
    if empty_label then
        pcall(function() empty_label:destroy() end)
        empty_label = nil
    end
    if not stage then return end

    video_util.audio_ensure()

    local fmt = video_util.guess_format(current_file)
    local vcfg = {
        parent = stage,
        x = geo.video_x, y = geo.video_y,
        w = geo.video_w, h = geo.video_h,          -- 必须等于素材帧尺寸（不支持缩放）
        src = current_file, format = fmt,
        decode_mode = "hw",
        loop = is_loop, auto_play = true,
    }
    if fmt == "hzv" then
        -- HZV 容器自带逐帧时长与 MP3 音轨，Lua 不填 interval
        vcfg.backend = "videoplayer"
    else
        vcfg.interval = 33   -- 30fps（调大即慢放，看着像卡住）
    end

    local ok, v = pcall(airui.video, vcfg)
    video_obj = (ok and v) and v or nil
    is_playing = (video_obj ~= nil)

    if not video_obj then
        local d = geo.density
        empty_label = theme.label(stage, {
            x = 0, y = math.floor(H / 2) - math.floor(20 * d),
            w = W, h = math.floor(34 * d),
            text = "无法播放该文件",
            px_size = math.floor(18 * d),
            color = theme.C.t3, align = airui.TEXT_ALIGN_CENTER,
        })
        log.warn("video_win", "video create failed", current_file)
    end
end

--[[刷新控制栏：文件名 + 「播放」「循环」两个按钮的文案与状态色

文案与颜色必须一起刷：状态切了只改文案不改色，看起来就是「按钮没反应」。
颜色本身由 theme.video_bar 按「主题令牌 + 当前状态」算，本页只负责把状态喂进去。]]
local function sync_labels()
    if not ctrl_bar then return end
    if current_file then
        ctrl_bar:set_file(current_file:match("([^/]+)$") or current_file)
    end
    ctrl_bar:sync(is_playing, is_loop)
end

--- 播放配套音频（同名 MP3）：只有 MJPG 素材有；HZV 的音轨在容器内
local function start_companion_audio()
    video_util.audio_stop()
    local mp3 = video_util.find_companion_mp3(current_file)
    if mp3 then
        video_util.audio_play(mp3, function() return is_loop and is_playing end)
    end
end

--- 切换到某个文件：重算几何 -> 重建画面 -> 刷新文案
local function play(path)
    if type(path) ~= "string" or path == "" then return end
    current_file = path
    local vw, vh = video_util.frame_size(path, DEFAULT_VW, DEFAULT_VH)
    geo = calc_layout(W, H, vw, vh)
    rebuild_video()
    sync_labels()
    start_companion_audio()
    log.info("video_win", "play", path, "frame", vw, "x", vh, "overlay=", geo.overlay)
end

local function toggle_play()
    if not video_obj then return end
    if is_playing then
        pcall(function() video_obj:pause() end)
        is_playing = false
        video_util.audio_toggle(function() return is_loop and is_playing end)
    else
        pcall(function() video_obj:play() end)
        is_playing = true
        video_util.audio_toggle(function() return is_loop and is_playing end)
    end
    sync_labels()
end

-- loop 只在创建组件时生效，所以切完标志位整组重建一次
local function toggle_loop()
    is_loop = not is_loop
    sync_labels()
    if current_file then play(current_file) end
end

local function restart()
    if current_file then play(current_file) end
end

--- 打开文件选择器（弹窗按旋转后的逻辑尺寸算大小）
local function open_picker()
    local start = (current_file and current_file:match("^(.+/)")) or "/"
    video_picker.open({
        start_path = start,
        sw = W, sh = H,
        on_pick = function(path)
            --[[换文件要通知桌面

            桌面此刻已失焦（它的 on_lose_focus 已经释放了自己的播放器），
            收到通知只更新「当前文件」、不起播；等回到桌面时它按新文件起播
            （idle_win 的 on_get_focus -> VP.start_play(VP.resume_file)）。
            所以这里用 publish（延迟到下一轮派发）而不是直接改桌面的状态。]]
            if path ~= current_file then
                sys.publish("VIDEO_FILE_CHANGED", path)
            end
            play(path)
        end,
    })
end

--- 退回窗口态：关窗（关窗会触发 on_destroy，其中负责停播、同步与还原旋转）
--- 控制栏最右那一格就是这个动作，与桌面上的「全屏」键位置/样式一一对应
local function request_close()
    if not window_id then return end
    exwin.close(window_id)
end

--[[底部控制栏

必须在视频创建之后调用：同一父对象内 LVGL 按创建顺序绘制，
后建的控件才压得住画面（素材比屏幕大时会与画面重叠）。

整条控制栏交给 theme.video_bar 构建 —— 与 idle_win 的桌面播放器控制栏共用同一段代码，
所以「播放 | 循环 | 选择 | 全屏/窗口」的排列、按钮尺寸、间距、配色策略完全一致，
两处不会各自漂移。最右一格本页传 "窗口"（退回窗口态），桌面传 "全屏"（进入本页）。]]
local function build_controls()
    ctrl_bar = theme.video_bar(bg, {
        x = geo.bar_x, y = geo.bar_y, w = geo.bar_w, h = geo.bar_h,
        radius = theme.R.md,
        playing = is_playing,
        loop = is_loop,
        file_text = current_file and (current_file:match("([^/]+)$") or current_file) or "",
        mode_text = "窗口",
        on_play = toggle_play,
        on_loop = toggle_loop,
        on_pick = open_picker,
        on_mode = request_close,
    })
    sync_labels()
end

-- ==================== 窗口生命周期 ====================

local function on_create(init_file)
    -- 1) 竖屏转横屏；顺手拿到旋转后的逻辑尺寸
    W, H = enter_landscape()

    -- 2) 黑底铺满整个（旋转后的）屏幕：桌面还压在下面，必须完全不透光
    bg = airui.shape({
        parent = airui.screen, x = 0, y = 0, w = W, h = H,
        items = {
            { type = "rect", x = 0, y = 0, w = W, h = H,
              fill = true, fill_color = theme.C.black, color = theme.C.black },
        },
    })

    --[[3) 舞台层：视频的父对象

    单独一层的原因：换文件时要重建视频控件，而重建出来的控件在**同一个父对象里
    会排到最后**（压住控制栏）。把视频统一挂在舞台层下，舞台层本身在控制栏之前创建，
    于是「画面在下、控件在上」这条层级与「什么时候重建视频」彻底解耦。
    用 airui.shape 而不是 container：C 端显式去掉了 SCROLLABLE 与 CLICKABLE，
    画面超出舞台时不会画出滚动条，也不抢点击。]]
    stage = airui.shape({ parent = bg, x = 0, y = 0, w = W, h = H })

    -- 4) 定素材：优先用桌面传进来的那个
    local file = init_file
    if type(file) ~= "string" or file == "" or not io.exists(file) then
        file = nil
        for _, p in ipairs({
            DEFAULT_FILE, "/luadb/luatos_boot.hzv",
            "/luatos_boot.hzv", "/luadb/luatos_boot.mjpg",
        }) do
            if io.exists(p) then
                file = p
                break
            end
        end
        file = file or DEFAULT_FILE
    end

    -- 5) 画面（先建，处于最底层）
    play(file)

    -- 6) 控制栏（后建，压在画面之上）
    build_controls()

    log.info("video_win", string.format("fullscreen %dx%d rot=%s file=%s overlay=%s",
        W, H, tostring(rotated and 90 or prev_rotation), tostring(current_file),
        tostring(geo and geo.overlay)))
end

local function on_destroy()
    log.info("video_win", "on_destroy")
    video_util.audio_stop()
    if video_obj then
        pcall(function() video_obj:stop() end)
        pcall(function() video_obj:destroy() end)
        video_obj = nil
    end
    -- 容器音轨（HZV 自带的那一路）兜底停掉
    if exaudio then pcall(exaudio.play_stop, { type = 0 }) end

    video_picker.close()

    if bg then pcall(function() bg:destroy() end); bg = nil end
    stage = nil
    ctrl_bar = nil
    empty_label = nil
    current_file = nil
    is_playing = true
    geo = nil

    -- 最后再把显示转回去：桌面马上要拿回焦点，它的坐标是按旋转前的方向算的
    leave_landscape()
    window_id = nil
end

--- 主题切换时重建控制栏（按钮底色是主题令牌，不重建就还是旧皮肤的颜色）
local function on_theme_changed()
    if not window_id then return end
    -- 只销毁控制栏本身：它挂在 bg 下，destroy 会连带清掉里面的按钮与文件名标签
    if ctrl_bar then
        pcall(function() ctrl_bar.ctrl:destroy() end)
        ctrl_bar = nil
    end
    -- 重新构建控件（geo 里缓存的密度/尺寸不会因换肤变化，可复用）
    if bg and geo then build_controls() end
end
sys.subscribe("UI_THEME_CHANGED", on_theme_changed)

local function open_handler(file)
    -- 本页是全屏的，正常情况下不会被叠开第二次；真收到重复请求就忽略
    if window_id then return end

    window_id = exwin.open({
        -- 归属者交给默认值（谁开的我，我就归谁 = 桌面）。这样切一级菜单时
        -- 桌面清自己的子树会顺带把这页收掉，不留孤儿窗口。
        on_create = function() on_create(file) end,
        on_destroy = on_destroy,
        -- 全屏页不会被压住（选择器弹窗直接建在屏幕上，不占窗口栈），
        -- 所以不在这里做「失焦停播」—— 多余的状态机会跟桌面那套打架。
        on_get_focus = function() end,
        on_lose_focus = function() end,
    })
    log.info("video_win", "open id=", window_id)
end

sys.subscribe("OPEN_VIDEO_WIN", open_handler)
