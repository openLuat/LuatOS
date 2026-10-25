--[[
@module  ui_main
@summary 音乐播放器 - 界面搭建、按键交互与逐帧动画调度（1024x600 横屏）
@version 1.0
@date    2026.10.23

=== 布局（1024x600）===
  顶栏      (0..56)            : 标题 | 音源与曲目数 | FPS
  播放列表  (14,56 252x414)    : 8 行可视 + 上下翻页 + 点行播放
  特效舞台  (278,56 452x414)   : 5 种画面风格，每个风格一个 shape 全幅铺满
  信息面板  (742,56 268x414)   : 曲名/歌手 | 进度 | 音量滑块 | 画面风格 2x3 | 歌词状态
  控制栏    (14,478 996x108)   : 播放模式 | 上一曲 播放/暂停 下一曲 | 音量 ± | 提示

=== 几个刻意的设计 ===
1. 按钮回调里只入队命令（audio.cmd），不做文件 IO：
   换曲要开文件、启动解码器、读 lrc，阻塞几十毫秒会把触摸和动画一起卡住。
2. 文字只在内容变化时才 set_text / set_color：每帧刷同一个字符串会让 LVGL 反复重排文本。
3. 画面风格懒加载 + 隐藏不销毁：切风格只 set_hidden，反复切也不涨内存。
4. 暂停时给风格传 dt=0 且不推进视觉时间，唱片/频谱/歌词滚动自然定格。
5. 列表是"虚拟列表"：只有 8 个固定槽位，翻页只换文字与底色，
   100 首歌也不会创建 100 个 LVGL 对象。
6. 所有位置参数都取整：airui 的 set_pos / set_color 在 C 层是 luaL_checkinteger，
   传小数会抛 "number has no integer representation" 并让整个 VM 重启。
]]

local theme = require "ui_theme"
local fx = require "fx_core"
local styles = require "ui_styles"
local audio = require "app_audio"

local M = {}
local C = theme.C
local F = theme.font
local L = theme.layout
local S = audio.S

local ROWS = L.list_rows
local STAGE_W = L.stage.w - L.stage_pad * 2
local STAGE_H = L.stage.h - L.stage_pad * 2
local FRAME_MS = theme.perf.frame_ms
local UI_MS = theme.perf.ui_ms

-- ==================== 按钮样式 ====================
local BTN_GHOST = {
    bg_color = C.card2, bg_opa = 255, text_color = C.text,
    radius = 10, border_width = 1, border_color = C.line,
    pressed_bg_color = C.cyan, pressed_text_color = C.ink,
}
local BTN_ON = {
    bg_color = C.cyan, bg_opa = 255, text_color = C.ink,
    radius = 10, border_width = 1, border_color = C.cyan,
    pressed_bg_color = C.cyan, pressed_text_color = C.ink,
}
local BTN_MAIN = {
    bg_color = C.violet, bg_opa = 255, text_color = 0xFFFFFF,
    radius = 10, border_width = 1, border_color = C.violet,
    pressed_bg_color = C.pink, pressed_text_color = 0xFFFFFF,
}
local BTN_PILL = {
    bg_color = C.card2, bg_opa = 255, text_color = C.dim,
    radius = 15, border_width = 1, border_color = C.line,
    pressed_bg_color = C.cyan, pressed_text_color = C.ink,
}

-- ==================== 运行时状态 ====================
local curStyle = 0
local objs, roots, styleBtns = {}, {}, {}
local rows = {}             -- 虚拟列表槽位
local top = 1               -- 列表首行对应的曲目序号
local lastIndex, lastTop, lastCount = -1, -1, -1
local volLock = false       -- 程序化改滑块值时抑制 on_change
local userPicked = false    -- 用户手动点过画面风格（点过就不再自动切）
local built = false
local TICKS_PER_MS = 1

local function now_ms()
    return audio.now_ms()
end

local function tick_diff(a, b)
    local d = a - b
    if d < 0 then d = d + 4294967296 end
    return d
end

--[[tick → 毫秒 的换算系数，必须按 mcu.hz() 初始化
Air1603（Air8607 的主控）约 20ms/tick，直接当毫秒会让动画慢 20 倍、FPS 虚报。
]]
function M.init_timebase()
    local hz = mcu and mcu.hz and mcu.hz()
    if type(hz) == "number" and hz > 1 then
        TICKS_PER_MS = hz / 1000
    else
        TICKS_PER_MS = 1
    end
    log.info("ui", string.format("时间基准 mcu.hz()=%s tick/ms=%.4f", tostring(hz), TICKS_PER_MS))
end

-- ==================== 文本刷新助手 ====================
local last_txt = {}
local function st(obj, key, txt)
    if obj == nil then return end
    if last_txt[key] == txt then return end
    last_txt[key] = txt
    obj:set_text(txt)
end

-- ==================== 卡片 ====================
local function card(parent, r, radius)
    return airui.container({
        parent = parent, x = r.x, y = r.y, w = r.w, h = r.h,
        color = C.card, color_opacity = 255, radius = radius or 14,
        border_color = C.line, border_width = 1,
    })
end

-- ==================== 顶栏 ====================
local function build_hud(base)
    airui.container({
        parent = base, x = 14, y = 16, w = 5, h = 24,
        color = C.cyan, color_opacity = 255, radius = 2, border_width = 0,
    })
    airui.label({
        parent = base, x = 30, y = 8, w = 230, h = 36,
        text = "音乐播放器", font_size = F.title,
        color = C.text, align = airui.TEXT_ALIGN_LEFT,
    })
    M.lbSource = airui.label({
        parent = base, x = 252, y = 16, w = 490, h = 26,
        text = "正在扫描 SD 卡…", font_size = F.small,
        color = C.dim, align = airui.TEXT_ALIGN_LEFT,
    })
    M.lbFps = airui.label({
        parent = base, x = 780, y = 18, w = 230, h = 22,
        text = "", font_size = F.micro,
        color = C.dim2, align = airui.TEXT_ALIGN_RIGHT,
    })
    -- 顶栏与内容区之间的分隔线
    airui.container({
        parent = base, x = 14, y = 52, w = 996, h = 1,
        color = C.line, color_opacity = 255, radius = 0, border_width = 0,
    })
end

-- ==================== 播放列表 ====================
local function on_row_click(slot)
    local i = top + slot - 1
    if i >= 1 and i <= #S.tracks then
        audio.cmd("play", i)
        M.refresh()
    end
end

local function page(dir)
    local n = #S.tracks
    if n <= ROWS then return end
    top = top + dir * ROWS
    local maxTop = n - ROWS + 1
    if top > maxTop then top = maxTop end
    if top < 1 then top = 1 end
    M.refresh_list(true)
end

local function build_list(base)
    local c = card(base, L.list)
    airui.label({
        parent = c, x = 16, y = 14, w = 130, h = 22,
        text = "播放列表", font_size = F.h3, color = C.text,
        align = airui.TEXT_ALIGN_LEFT,
    })
    M.lbCount = airui.label({
        parent = c, x = 146, y = 16, w = 88, h = 20,
        text = "0 首", font_size = F.tiny, color = C.dim,
        align = airui.TEXT_ALIGN_RIGHT,
    })

    local vp = airui.container({
        parent = c, x = 10, y = 42, w = 232, h = ROWS * L.row_h,
        color = C.bg2, color_opacity = 255, radius = 10, border_width = 0,
    })

    for r = 1, ROWS do
        local box = airui.container({
            parent = vp, x = 2, y = (r - 1) * L.row_h, w = 228, h = L.row_h - L.row_gap,
            color = C.card2, color_opacity = 255, radius = 8, border_width = 0,
            on_click = function() on_row_click(r) end,
        })
        local lb = airui.label({
            parent = box, x = 10, y = 8, w = 208, h = 22,
            text = "", font_size = F.small, color = C.dim,
            align = airui.TEXT_ALIGN_LEFT,
            on_click = function() on_row_click(r) end,
        })
        rows[r] = { box = box, lb = lb, i = -1, on = false }
    end

    airui.button({
        parent = c, x = 10, y = 352, w = 108, h = 30,
        text = "上一页", font_size = F.tiny, style = BTN_PILL,
        on_click = function() page(-1) end,
    })
    airui.button({
        parent = c, x = 124, y = 352, w = 108, h = 30,
        text = "下一页", font_size = F.tiny, style = BTN_PILL,
        on_click = function() page(1) end,
    })
    airui.label({
        parent = c, x = 10, y = 386, w = 232, h = 20,
        text = "点曲目名播放 · 上下页翻动", font_size = F.micro,
        color = C.dim2, align = airui.TEXT_ALIGN_LEFT,
    })
end

-- ==================== 舞台 ====================
local function build_stage(base)
    card(base, L.stage)
    -- 内容区单独一层并开 clip_corner，图元不会溢出圆角
    M.stage = airui.container({
        parent = base,
        x = L.stage.x + L.stage_pad, y = L.stage.y + L.stage_pad,
        w = STAGE_W, h = STAGE_H,
        color = C.bg2, color_opacity = 255, radius = 11,
        border_width = 0,
    })
end

-- ==================== 信息面板 ====================
local function build_panel(base)
    local p = card(base, L.panel)

    M.lbTitle = airui.label({
        parent = p, x = 16, y = 12, w = 236, h = 30,
        text = "正在载入…", font_size = F.h1, color = C.text,
        align = airui.TEXT_ALIGN_LEFT,
    })
    M.lbArtist = airui.label({
        parent = p, x = 16, y = 46, w = 236, h = 20,
        text = "", font_size = F.tiny, color = C.dim,
        align = airui.TEXT_ALIGN_LEFT,
    })

    -- 进度条：airui.bar 的 value 是整数，用 0~100 表示百分比
    M.bar = airui.bar({
        parent = p, x = 16, y = 76, w = 236, h = 8,
        min = 0, max = 100, value = 0, radius = 4,
        bg_color = 0x16233A, indicator_color = C.cyan, border_width = 0,
    })
    M.lbTime = airui.label({
        parent = p, x = 16, y = 90, w = 236, h = 18,
        text = "--:-- / --:--", font_size = F.micro, color = C.dim2,
        align = airui.TEXT_ALIGN_LEFT,
    })

    -- 音量
    M.lbVol = airui.label({
        parent = p, x = 16, y = 116, w = 150, h = 20,
        text = "音量 70", font_size = F.tiny, color = C.dim,
        align = airui.TEXT_ALIGN_LEFT,
    })
    M.slider = airui.slider({
        parent = p, x = 16, y = 140, w = 236, h = 18,
        min = 0, max = 100, value = S.volume,
        style = {
            bg_color = 0x16233A, bg_opa = 255,
            indicator_color = C.cyan, knob_color = 0xE8EFFC,
            radius = 9, pad = 2,
        },
        on_change = function(self)
            if volLock then return end
            audio.set_volume(self:get_value())
            M.refresh()
        end,
    })

    -- 画面风格
    airui.label({
        parent = p, x = 16, y = 176, w = 200, h = 18,
        text = "画面风格", font_size = F.tiny, color = C.dim,
        align = airui.TEXT_ALIGN_LEFT,
    })
    for i, d in ipairs(styles.defs) do
        local col = (i - 1) % 2
        local row = math.floor((i - 1) / 2)
        styleBtns[i] = airui.button({
            parent = p,
            x = 16 + col * 122, y = 198 + row * 36,
            w = 114, h = 32,
            text = d.name, font_size = F.tiny, style = BTN_GHOST,
            on_click = function()
                userPicked = true
                M.select_style(i)
            end,
        })
    end

    M.lbLyric = airui.label({
        parent = p, x = 16, y = 312, w = 236, h = 52,
        text = "", font_size = F.micro, color = C.dim2,
        align = airui.TEXT_ALIGN_LEFT,
    })
    M.lbWarn = airui.label({
        parent = p, x = 16, y = 366, w = 236, h = 40,
        text = "", font_size = F.micro, color = C.gold,
        align = airui.TEXT_ALIGN_LEFT,
    })
end

-- ==================== 控制栏 ====================
local function build_bar(base)
    local b = card(base, L.bar)

    M.btnMode = airui.button({
        parent = b, x = 16, y = 26, w = 140, h = 52,
        text = "顺序播放", font_size = F.h2, style = BTN_GHOST,
        on_click = function()
            audio.cycle_mode()
            M.refresh()
        end,
    })
    airui.button({
        parent = b, x = 172, y = 26, w = 116, h = 52,
        text = "上一曲", font_size = F.h2, style = BTN_GHOST,
        on_click = function()
            audio.cmd("prev")
            M.refresh()
        end,
    })
    M.btnPlay = airui.button({
        parent = b, x = 300, y = 26, w = 152, h = 52,
        text = "播放", font_size = F.title, style = BTN_MAIN,
        on_click = function()
            audio.toggle()
            M.refresh()
        end,
    })
    airui.button({
        parent = b, x = 464, y = 26, w = 116, h = 52,
        text = "下一曲", font_size = F.h2, style = BTN_GHOST,
        on_click = function()
            audio.cmd("next")
            M.refresh()
        end,
    })
    airui.button({
        parent = b, x = 600, y = 26, w = 56, h = 52,
        text = "-", font_size = F.title, style = BTN_GHOST,
        on_click = function()
            audio.volume_step(-5)
            M.refresh()
        end,
    })
    airui.button({
        parent = b, x = 664, y = 26, w = 56, h = 52,
        text = "+", font_size = F.title, style = BTN_GHOST,
        on_click = function()
            audio.volume_step(5)
            M.refresh()
        end,
    })

    M.lbHint = airui.label({
        parent = b, x = 740, y = 30, w = 240, h = 44,
        text = "", font_size = F.micro, color = C.dim2,
        align = airui.TEXT_ALIGN_RIGHT,
    })
end

-- ==================== 画面风格切换 ====================
--[[切换中间画面风格（懒加载 + 隐藏旧容器）
@param number i 1..#styles.defs
]]
function M.select_style(i)
    if i < 1 or i > #styles.defs then return end
    if curStyle == i then return end

    if roots[curStyle] then roots[curStyle]:set_hidden(true) end

    local d = styles.defs[i]
    if not objs[i] then
        local root = airui.container({
            parent = M.stage, x = 0, y = 0, w = STAGE_W, h = STAGE_H,
            radius = 0, border_width = 0,
        })
        roots[i] = root
        objs[i] = styles.build(d.id, root, STAGE_W, STAGE_H)
    else
        roots[i]:set_hidden(false)
    end

    for k, btn in ipairs(styleBtns) do
        btn:set_style((k == i) and BTN_ON or BTN_GHOST)
    end

    curStyle = i
    st(M.lbHint, "hint", d.desc)
    log.info("ui", "画面风格", d.id, d.name)
end

--[[音频初始化完成后调用：第一首有歌词就直接进歌词模式
界面是先于音频起来的（SD 卡挂载要几百毫秒），所以 build 时还不知道有没有歌词，
这里补一次判断。用户已经手动点过风格就不抢了。]]
function M.auto_style()
    if userPicked then return end
    if S.lyric and curStyle ~= 2 then M.select_style(2) end
end

-- ==================== 面板刷新 ====================
local function source_text()
    if S.source == "sd" then
        return string.format("音源 SD 卡 · %d 首 · %s", #S.tracks, S.scan_dir)
    elseif S.source == "flash" then
        return "未检测到 SD 卡 · 播放内置示例音频"
    elseif S.source == "none" then
        return "未找到音频 · 请插入 SD 卡"
    end
    return "正在扫描 SD 卡…"
end

function M.refresh()
    local n = #S.tracks
    local tk = S.tracks[S.index]

    if n == 0 then
        st(M.lbTitle, "title", "未找到音频")
        st(M.lbArtist, "artist", "SD 卡与内置示例都不可用")
    else
        local title = (S.title ~= nil and S.title ~= "") and S.title or (tk and tk.name) or ""
        st(M.lbTitle, "title", fx.fit(title, 228, F.h1))
        local sub = (S.artist ~= "") and S.artist or string.format("第 %d / %d 首", S.index, n)
        st(M.lbArtist, "artist", fx.fit(sub, 228, F.tiny))
    end

    local total = (S.dur_ms and S.dur_ms > 0) and fx.fmt_time(S.dur_ms) or "--:--"
    st(M.lbTime, "time", fx.fmt_time(S.pos_ms) .. " / " .. total)

    if M.bar then
        local v = 0
        if S.dur_ms and S.dur_ms > 0 then
            v = math.floor(S.pos_ms * 100 / S.dur_ms)
        end
        if v < 0 then v = 0 elseif v > 100 then v = 100 end
        if last_txt.pbar ~= v then
            last_txt.pbar = v
            M.bar:set_value(v)
        end
    end

    st(M.lbVol, "vol", "音量 " .. S.volume)
    if M.slider and not volLock and M.slider:get_value() ~= S.volume then
        volLock = true
        M.slider:set_value(S.volume, false)
        volLock = false
    end

    st(M.btnPlay, "play", S.paused and "继续" or (S.playing and "暂停" or "播放"))
    st(M.btnMode, "mode", audio.mode_name())
    st(M.lbCount, "cnt", n .. " 首")
    st(M.lbSource, "src", source_text())

    if S.lyric and S.lyric.lines then
        st(M.lbLyric, "lyr", string.format("歌词就绪 · %d 行", #S.lyric.lines))
    elseif S.index > 0 then
        st(M.lbLyric, "lyr", "没有找到同名 .lrc 歌词文件")
    else
        st(M.lbLyric, "lyr", "")
    end

    if S.source == "none" then
        st(M.lbWarn, "warn", "把音乐和歌词放进 SD 卡：/sd/music/")
    elseif S.lyric and S.lyric.gbk then
        st(M.lbWarn, "warn", "歌词不是 UTF-8 编码，请转码后再用")
    elseif not S.ready then
        st(M.lbWarn, "warn", "音频后端不可用（固件缺 exaudio）")
    elseif S.backend == "exaudio" then
        st(M.lbWarn, "warn", "旧音频框架：继续播放会从头开始")
    else
        st(M.lbWarn, "warn", "")
    end

    M.refresh_list(false)
end

--[[刷新虚拟列表（只在当前曲目/首行/曲目数变化时真正改控件）]]
function M.refresh_list(force)
    local n = #S.tracks
    local cur = S.index

    -- 自动跟随当前播放的曲目（切歌后列表滚到能看见它的位置）
    if cur >= 1 and n > ROWS then
        if cur < top then
            top = cur
        elseif cur > top + ROWS - 1 then
            top = cur - ROWS + 1
        end
    end
    local maxTop = math.max(1, n - ROWS + 1)
    if top > maxTop then top = maxTop end
    if top < 1 then top = 1 end

    if not force and cur == lastIndex and top == lastTop and n == lastCount then return end
    lastIndex, lastTop, lastCount = cur, top, n

    for r = 1, ROWS do
        local i = top + r - 1
        local tk = S.tracks[i]
        local row = rows[r]
        if tk then
            local on = (i == cur)
            if row.i ~= i or row.on ~= on then
                row.i, row.on = i, on
                row.box:set_color(on and C.card3 or C.card2, 255)
                row.lb:set_color(on and C.cyan or C.dim)
            end
            local txt = fx.fit(string.format("%02d  %s", i, tk.title or tk.name), 202, F.small)
            if row.txt ~= txt then
                row.txt = txt
                row.lb:set_text(txt)
            end
        else
            if row.i ~= -1 then
                row.i, row.on, row.txt = -1, false, ""
                row.box:set_color(C.card2, 255)
                row.lb:set_text("")
            end
        end
    end
end

-- ==================== 界面搭建 ====================
--[[搭建整屏界面（必须在 airui.init + font_load 之后调用）]]
function M.build(SW, SH)
    if built then return end
    built = true

    local base = airui.container({
        parent = nil, x = 0, y = 0, w = SW, h = SH,
        color = C.bg, color_opacity = 255, radius = 0, border_width = 0,
    })
    build_hud(base)
    build_list(base)
    build_stage(base)
    build_panel(base)
    build_bar(base)

    -- 有歌词就直接进歌词模式，否则从唱片模式开始
    M.select_style(S.lyric and 2 or 1)
    M.refresh()
end

-- ==================== 逐帧动画 ====================
--[[逐帧驱动当前画面风格（阻塞，请在独立 task 里调用）
时间轴只在"正在播放"时推进：暂停时 dt 传 0，唱片停转、频谱定格、歌词不再滚动。
]]
function M.run()
    M.init_timebase()

    local t = 0                 -- 视觉时间（秒）
    local prev = now_ms()
    local waitMs = FRAME_MS
    local acc = 0
    local info = { playing = false, progress = 0, pos_ms = 0 }
    local frames, fsum = 0, 0

    while true do
        sys.wait(waitMs)

        local now = now_ms()
        local realMs = tick_diff(now, prev) / TICKS_PER_MS
        prev = now

        --[[步长：正常情况下用固定值
        Air1603 的 tick 分辨率约 20ms，比 FRAME_MS(33ms) 粗，
        直接拿 tick 差当 dt 会让动画一顿一顿；只有真的挂起过才按真实时间补跳。]]
        local dt
        if realMs > FRAME_MS * 3 or realMs <= 0 then
            dt = realMs / 1000
            if dt <= 0 or dt > 0.25 then dt = FRAME_MS / 1000 end
        else
            dt = FRAME_MS / 1000
        end

        -- 播放状态推进（读进度 + 判断播完）
        local okUpd, errUpd = pcall(audio.update)
        if not okUpd then log.error("ui", "音频状态更新失败", errUpd) end

        local playing = S.playing and not S.paused
        if playing then t = t + dt end

        info.playing = playing
        info.pos_ms = S.pos_ms or 0
        info.dur_ms = S.dur_ms or 0
        info.progress = (S.dur_ms and S.dur_ms > 0) and fx.clamp(info.pos_ms / S.dur_ms, 0, 1) or 0
        info.lyric = S.lyric
        info.title = S.title
        info.index = S.index
        info.count = #S.tracks

        -- 只对"画一帧"单独计时：这个数字才是决定帧率的耗时
        local t0 = now_ms()
        local o = objs[curStyle]
        if o then
            local ok, err = pcall(styles.update, o, t, playing and dt or 0, info)
            if not ok then
                log.error("ui", "画面更新失败", o.kind, err)
                sys.wait(500)     -- 出错别在死循环里刷日志
            end
        end
        local cost = tick_diff(now_ms(), t0) / TICKS_PER_MS       -- 毫秒

        -- 面板文字与进度条（低频刷新即可，每帧刷会白吃帧预算）
        acc = acc + realMs / 1000
        if acc >= UI_MS / 1000 then
            acc = 0
            M.refresh()
        end

        -- FPS（每秒刷一次，定位性能用）
        frames = frames + 1
        fsum = fsum + realMs / 1000
        if fsum >= 1 then
            local lvFps = 0
            local dbg = airui.debug and airui.debug()
            if type(dbg) == "table" then lvFps = dbg.fps or 0 end
            st(M.lbFps, "fps", string.format("FPS %d / LV %s",
                math.floor(frames / fsum + 0.5), (lvFps > 0) and tostring(lvFps) or "--"))
            frames, fsum = 0, 0
        end

        --[[补偿式节拍
        sys.wait(n) 是"至少睡 n 毫秒"，实际周期 = 睡眠 + 本帧工作耗时，
        不补偿的话工作越重帧率越低、自我恶化。这里按实测耗时把睡眠补回来。
        必须取整：rtos.timer_start 在 C 层是 luaL_checkinteger，
        TICKS_PER_MS = 0.02 这种不精确浮点会让 ms 变成 24.999999999，直接抛错重启 VM。]]
        local w = FRAME_MS - cost
        if w < 4 then w = 4 end
        waitMs = math.floor(w)
    end
end

return M
