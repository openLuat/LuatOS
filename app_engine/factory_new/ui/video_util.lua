--[[
@module  video_util
@summary 媒体素材工具（容器格式嗅探 / 帧尺寸读取 / HZV 音轨初始化 / 播放器创建）—— 播放类页面共用
@version 1.1
@date    2026.09.23
@author  江访

=== 为什么单独成模块 ===
idle_win（桌面播放器）与 video_win（全屏播放页）都要读素材帧尺寸，而 airui 播放器
**不支持缩放**：控件尺寸与素材帧尺寸不一致时会被强制改回素材尺寸
（components/airui/src/components/widgets/luat_airui_video.c 的
 "scaling is not supported yet ... force reset widget size"）。
也就是说，帧尺寸读错**不会**把画面拉伸，只会让控件溢出容器、把画面切掉一块 ——
同一份口径必须只有一处实现，否则两个页面的裁切行为会不一致。

（welcome_win 里还有一份历史副本。开机路径没跟着迁移，改这里时别以为全工程都干净了。）

@api video_util.guess_format(path)              容器格式："hzv" | "mjpg" | "mp4"
@api video_util.read_dimensions(path)           w, h；读不到返回 nil
@api video_util.frame_size(path, def_w, def_h)  w, h；读不到时用调用方给的兜底值
@api video_util.audio_ensure()                  幂等初始化 HZV 音轨（Audio V2），返回是否可用
@api video_util.mp4_available()                 固件是否带 mplayer（MP4 硬解）
@api video_util.fit_rect(x, y, aw, ah, w, h)    等比缩放并居中摆放的画面矩形 x, y, w, h
@api video_util.create_player(path, o)          按格式创建播放器：
                                                HZV/MJPG → airui.video，MP4 → mplayer 硬解
]]

local ok_exaudio, exaudio = pcall(require, "exaudio")
if not ok_exaudio then exaudio = nil end

--[[mplayer（MP4 硬解）是固件内置 rotable 库，直接取全局；
取不到再走 require 兜底（个别固件只注册包不挂全局）。
没有 mplayer 的固件（如部分 Air1602）上 mp4_available() 返回 false，
MP4 会走「无法播放该文件」空态，而不是像以前那样被误当 MJPG 白解一通。]]
local mplayer = rawget(_G, "mplayer")
-- if mplayer == nil then
--     -- local ok_mp, mp = pcall(require, "mplayer")
--     if ok_mp then mplayer = mp end
-- end

local M = {}

--[[判断素材用哪种容器解析：优先看魔数，其次看扩展名

魔数优先的原因：素材被改名（或从 SD 卡拷进来时后缀被改）后仍能正确解码。
MP4 的魔数是偏移 4 处的 "ftyp" box（前 4 字节是 box 长度，不能只读 4 字节）。]]
function M.guess_format(path)
    local f = io.open(path, "rb")
    if f then
        local magic = f:read(8)
        f:close()
        if magic then
            if magic:sub(1, 4) == "HZV1" then return "hzv" end
            if magic:sub(5, 8) == "ftyp" then return "mp4" end
        end
    end
    local ext = path and path:match("%.([^%.]+)$")
    if ext then
        ext = ext:lower()
        if ext == "hzv" then return "hzv" end
        if ext == "mp4" or ext == "m4v" then return "mp4" end
    end
    return "mjpg"
end

--[[读媒体容器头拿回 (width, height)

HZV v1: 前 4 字节为 "HZV1"，0x44 / 0x46 处各一个 uint16 宽、高
        （Lua 下标从 1 起，所以是 byte(69)/byte(70) 与 byte(71)/byte(72)）
MP4 :   借 mplayer 解析一次拿宽高（box 结构在 Lua 里逐层解析不划算）
其它  : 按 MJPG/JPEG 扫 SOF0/SOF2 标记

@return width, height 或 nil（调用方必须给兜底值）]]
function M.read_dimensions(path)
    local f = io.open(path, "rb")
    if not f then return nil end
    local data = f:read(512)  -- HZV 头部 0x48 以内 / JPEG 的 SOF 标记一般在 512 字节内
    f:close()
    if not data or #data < 8 then return nil end

    if data:sub(1, 4) == "HZV1" then
        local hw = data:byte(69) + data:byte(70) * 256
        local hh = data:byte(71) + data:byte(72) * 256
        if hw > 0 and hh > 0 then return hw, hh end
        return nil
    end

    -- MP4（魔数 = 偏移 4 处的 "ftyp" box）：mplayer.open 只解析容器头，
    -- 解码线程要到 play 才起，这里开一次拿 info 就关掉，开销很小
    if data:sub(5, 8) == "ftyp" then
        if M.mp4_available() then
            local p = mplayer.open(path)
            if p then
                local info = mplayer.info(p)
                mplayer.close(p)
                if info and info.width and info.width > 0
                    and info.height and info.height > 0 then
                    return info.width, info.height
                end
            end
        end
        return nil
    end

    -- 扫描 SOI (FF D8) 之后的标记，找 SOF0 (FF C0) / SOF2 (FF C2)
    local i = 1
    while i <= #data - 1 do
        if data:byte(i) == 0xFF then
            local marker = data:byte(i + 1)
            if marker == 0xC0 or marker == 0xC2 then
                if i + 9 <= #data then
                    local h = data:byte(i + 5) * 256 + data:byte(i + 6)
                    local w = data:byte(i + 7) * 256 + data:byte(i + 8)
                    return w, h
                end
                return nil
            end
            -- 跳过非 SOF 标记（读取段长度并跳过）
            if marker ~= 0xD8 and marker ~= 0xD9 and (marker < 0xD0 or marker > 0xD7) then
                if i + 3 <= #data then
                    local seg_len = data:byte(i + 2) * 256 + data:byte(i + 3)
                    i = i + 2 + seg_len
                else
                    break
                end
            else
                i = i + 2
            end
        else
            i = i + 1
        end
    end
    return nil
end

--[[读素材帧尺寸，读不到时回退到调用方给的兜底值

兜底值必须与该页面的**布局基准**一致：给定错了不会「拉伸画面」，
只会让控件溢出容器、把画面切掉一块。]]
function M.frame_size(path, def_w, def_h)
    local w, h = M.read_dimensions(path)
    if w and h then return w, h end
    return def_w, def_h
end

--[[HZV 音轨初始化（幂等）

HZV 的音轨由 Audio V2 播放，视频时钟跟随 DAC DMA sample counter ——
音频框架没起来时既不响、也不会走帧。所以创建 HZV 播放器前必须先确保一次；
首次真 setup，之后只 RESUME。失败不阻断画面创建（只是没声音、可能不走帧）。

用全局标志 _G.__hzv_audio_ready 记账：桌面播放器与全屏播放页共用同一套音频框架，
各自 setup 一次会互相打断，标志位必须跨模块共享。]]
function M.audio_ensure()
    if not exaudio then return false end
    local pc = _G.project_config
    if not (pc and pc.hw and pc.hw.audio) then return false end
    if _G.__hzv_audio_ready then
        pcall(exaudio.pm, exaudio.RESUME)
        return true
    end
    local ac = pc.hw.audio
    local ok = pcall(exaudio.setup, {
        model       = ac.model or "dac",
        pa_ctrl     = ac.pa_ctrl,
        pa_on_level = ac.pa_on_level or 0,
        dac_delay   = ac.dac_delay,
    })
    if ok then
        pcall(exaudio.vol, ac.play_vol or 100)
        _G.__hzv_audio_ready = true
        return true
    end
    log.warn("video_util", "exaudio.setup 失败，音轨与播放时钟可能不可用")
    return false
end

-- ==================== 配套音频（同名 MP3） ====================
--[[只有 MJPG 素材需要：HZV 的音轨在容器内、由 videoplayer 统一驱动，无需另外一路。
两个页面（桌面播放器 / 全屏播放页）共用一份播放状态，而不是各记一份 ——
同一时刻只会有一个页面在放视频（进入全屏时桌面会先释放自己的播放器），
共用状态顺带避免了「两边同时出声」。]]

local audio_mp3 = nil       -- 当前配套音频路径（非 nil 表示这一路在放）
local audio_playing = false
local exaudio_inited = false

local function has_audio()
    return exaudio ~= nil
        and _G.project_config ~= nil and _G.project_config.hw ~= nil
        and _G.project_config.hw.audio ~= nil
end

--[[在同目录下搜索与视频同名的 .mp3 文件（只认 .mjpg 后缀，HZV 天然返回 nil）]]
function M.find_companion_mp3(mjpg_path)
    if not has_audio() or type(mjpg_path) ~= "string" then return nil end
    if not mjpg_path:lower():match("%.mjpg$") then return nil end
    local dir = mjpg_path:match("^(.+/)") or "/"
    local base = mjpg_path:match("([^/]+)%.[mM][jJ][pP][gG]$")
    if not base then return nil end
    local mp3_path = dir .. base .. ".mp3"
    if io.exists(mp3_path) then return mp3_path end
    mp3_path = dir .. base .. ".MP3"
    if io.exists(mp3_path) then return mp3_path end
    return nil
end

--[[开始播放一路配套音频

@param mp3_path string 音频文件路径
@param should_loop function|nil 一首播完后是否续播：返回 true 则重放。
       由调用方决定（要同时看「循环开关」与「是否还在播」两个状态）
@return boolean 是否起播成功
]]
function M.audio_play(mp3_path, should_loop)
    if not has_audio() or not mp3_path then return false end
    if not exaudio_inited then
        pcall(exaudio.pm, exaudio.RESUME)
        exaudio_inited = true
    end
    M.audio_stop()                 -- 必须先停再记：stop 会清空 audio_mp3
    audio_mp3 = mp3_path
    local function play_loop(path)
        return pcall(exaudio.play_start, {
            type = 0, content = path,
            cbfnc = function(event)
                if event == exaudio.PLAY_DONE then
                    if (should_loop and should_loop()) and audio_mp3 then
                        play_loop(path)
                    else
                        audio_playing = false
                    end
                end
            end
        })
    end
    audio_playing = play_loop(mp3_path)
    log.info("video_util", "companion audio start", mp3_path, "ok=", audio_playing)
    return audio_playing
end

--[[停掉配套音频（没有在放时是空操作）]]
function M.audio_stop()
    if exaudio == nil then return end
    if audio_mp3 then
        pcall(exaudio.play_stop, { type = 0 })
        audio_mp3 = nil
        audio_playing = false
    end
end

--[[播放/暂停切换配套音频（暂停后再点会从头重放：exaudio 没有 seek/续播接口）]]
function M.audio_toggle(should_loop)
    if not audio_mp3 then return end
    if audio_playing then
        pcall(exaudio.play_stop, { type = 0 })
        audio_playing = false
    else
        M.audio_play(audio_mp3, should_loop)
    end
end

-- ==================== MP4（mplayer 硬解，参考 mp4_test） ====================
--[[MP4 与 HZV/MJPG 的播放链路完全不同：

HZV/MJPG → airui.video（lv_image 逐帧刷新，不支持缩放）；
MP4      → mplayer 硬解：解码线程把 H.264 帧（YUV→RGB565）挂到 LCDC 视频层
           （layer 1）直接扫描显示，音轨由 C 层同步，Lua 不碰帧数据。

两条链路的差异收在 create_player 一个入口后面，播放页面只面对统一的
:play/:pause/:stop/:destroy 接口。关键差异与对策：

1. 画面坐标：视频层叠在 LVGL UI **之上**，矩形必须避开控制栏，否则按钮被
   画面盖住（点得到但看不见）；且 set_rect 收的是**面板物理坐标**，airui
   运行时旋转（set_rotation 只转显示不动面板）要按 lv_display_rotate_area
   的口径换算（见 to_panel_rect）。
2. 缩放语义：airui 路径「不支持缩放、大素材裁切」；视频层没有裁切容器，
   大素材不缩就会盖住控制栏，所以 MP4 一律用 fit_rect 等比收进可用区。
3. 循环：mplayer 没有 loop 参数，靠轮询 is_playing、EOS 后重开实现。
4. set_rect 在部分固件的 Lua 绑定里还没有（LuatOS 主干 binding 只有
   open/close/play/pause/resume/stop/is_playing/is_paused/info），
   取不到时不报错，按 C 层默认全屏居中播放。]]

--- 固件是否带 mplayer（MP4 硬解）；没有则 MP4 走「无法播放」空态
function M.mp4_available()
    return mplayer ~= nil and type(mplayer.open) == "function"
end

--[[打开功放（不初始化音频框架）

mplayer 自管音轨，不需要 exaudio.setup；但功放使能脚是板级的，固件不会
替你拉（参考 mp4_test 里手拉 AUDIOPA_EN）。参数取 project_config.hw.audio。]]
local function pa_enable()
    local ac = _G.project_config and _G.project_config.hw and _G.project_config.hw.audio
    if not ac or not ac.pa_ctrl then return end
    pcall(gpio.setup, ac.pa_ctrl, ac.pa_on_level or 0)
end

--[[把 w×h 的画面等比收进 (aw × ah) 并居中，返回 x, y, w, h

放得下时保持原尺寸居中 —— 与 airui「不支持缩放」路径的摆放结果一致；
放不下时等比缩小（视频层叠在 UI 之上，超出可用区就会盖住控制栏）。]]
function M.fit_rect(ax, ay, aw, ah, w, h)
    if not (w and h and w > 0 and h > 0) then return ax, ay, aw, ah end
    local rw, rh = w, h
    if rw > aw then
        rh = math.floor(h * aw / w)
        rw = aw
    end
    if rh > ah then
        rw = math.floor(w * ah / h)
        rh = ah
    end
    return ax + math.floor((aw - rw) / 2), ay + math.floor((ah - rh) / 2), rw, rh
end

--[[逻辑屏矩形 -> 面板物理矩形（airui 运行时旋转补偿）

mplayer 的视频层挂在 LCDC 上，坐标永远是面板物理坐标；播放页布局却按
airui 旋转后的逻辑屏算。换算口径直接照抄 LVGL 的 lv_display_rotate_area
（lvgl9/src/display/lv_display.c）—— 那是所有 UI 控件坐标落面板的唯一权威
实现。rot=0 时是恒等变换（横屏机型永远走这条路，未做换算实测的只有
竖屏机型的 90/270 分支）。]]
local function to_panel_rect(x, y, w, h)
    local rot = 0
    if airui.get_rotation then
        local ok, r = pcall(airui.get_rotation)
        if ok and type(r) == "number" then rot = r % 360 end
    end
    if rot == 0 then return x, y, w, h end

    -- 面板物理尺寸（不受旋转影响）；取不到时按工厂默认竖屏兜底
    local pw, ph = 480, 854
    if display and display.getSize then
        local ok, dw, dh = pcall(display.getSize)
        if ok and dw and dh and dw > 0 and dh > 0 then pw, ph = dw, dh end
    end

    if rot == 90 then
        return y, ph - x - w, h, w
    elseif rot == 180 then
        return pw - x - w, ph - y - h, w, h
    elseif rot == 270 then
        return pw - y - h, x, h, w
    end
    return x, y, w, h
end

--[[创建 MP4 播放器（mplayer 硬解），返回与 airui.video 同用法的对象

接口对齐播放页面现有的调用方式（全部经 pcall 以 : 方式调用）：
  obj:play()    起播；暂停后续播走 resume；停止/EOS 后重播会重开
  obj:pause()   暂停
  obj:stop()    停止（回收解码线程，保留句柄）
  obj:destroy() 彻底关闭（stop + close，幂等）

@param path string  mp4 文件路径
@param rect table|nil { x, y, w, h } 画面矩形（逻辑屏坐标，内部换算面板坐标）
@param loop boolean 播完是否重播（轮询 EOS 后重开实现）
@return table|nil 起播成功返回对象，失败返回 nil
]]
local function mp4_player(path, rect, loop)
    local h = {
        path = path,
        rect = rect,
        loop = loop and true or false,
        player = nil,
        state = nil,    -- nil | "playing" | "paused" | "eos" | "stopped"
        watch = nil,
        closed = false,
    }

    local function stop_watch()
        if h.watch then sys.timerStop(h.watch); h.watch = nil end
    end

    --[[EOS 轮询（200ms）

    mplayer 没有播完回调也没有 loop 参数，is_playing 在 EOS 时翻 false
    （参考 mp4_test 的收尾逻辑）。循环开着就重开，否则记账收尾。]]
    local function start_watch()
        if h.watch then return end
        h.watch = sys.timerLoopStart(function()
            if h.closed or h.state ~= "playing" or not h.player then return end
            if mplayer.is_playing(h.player) then return end
            if h.loop then
                h:restart()
            else
                h.state = "eos"
            end
        end, 200)
    end

    local function apply_rect()
        if not (mplayer.set_rect and h.player) then return end
        if h.rect then
            local x, y, w, hh = to_panel_rect(h.rect.x, h.rect.y, h.rect.w, h.rect.h)
            --[[多传参兼容两种绑定：set_rect 若只收 (player, x, y)，多余实参被
            Lua C 绑定忽略；若收 (player, x, y, w, h) 则四元全用上。与 mp4_test
            的 set_rect(player, -1, -1) 同语义，只是把「全屏居中」换成指定矩形。]]
            pcall(mplayer.set_rect, h.player, x, y, w, hh)
        else
            pcall(mplayer.set_rect, h.player, -1, -1)
        end
    end

    --- 重开并起播：停止/EOS 后解码线程已回收，重开最稳（不赌 play 能续）
    function h:restart()
        if self.closed then return false end
        stop_watch()
        if self.player then
            pcall(mplayer.stop, self.player)
            pcall(mplayer.close, self.player)
            self.player = nil
        end
        self.state = nil
        self.player = mplayer.open(self.path)
        if not self.player then return false end
        apply_rect()
        local ok = mplayer.play(self.player)
        self.state = ok and "playing" or nil
        if ok then start_watch() end
        return ok and true or false
    end

    function h:play()
        if self.closed then return false end
        if self.state == "paused" and self.player then
            local ok = mplayer.resume(self.player)
            if ok then
                self.state = "playing"
                start_watch()
            end
            return ok and true or false
        end
        if self.state == "playing" and self.player and mplayer.is_playing(self.player) then
            return true
        end
        return self:restart()
    end

    function h:pause()
        if self.closed or not self.player then return false end
        if self.state ~= "playing" then return true end
        local ok = mplayer.pause(self.player)
        if ok then self.state = "paused" end
        return ok and true or false
    end

    function h:stop()
        stop_watch()
        if self.player then pcall(mplayer.stop, self.player) end
        self.state = "stopped"
        return true
    end

    function h:destroy()
        if self.closed then return end
        self.closed = true
        stop_watch()
        if self.player then
            pcall(mplayer.stop, self.player)
            pcall(mplayer.close, self.player)
            self.player = nil
        end
    end

    if not h:restart() then
        h:destroy()
        return nil
    end
    return h
end

--[[按素材格式创建播放器（唯一入口）

HZV/MJPG → airui.video（父容器内的 lv_image 控件）；
MP4      → mplayer 硬解（面板视频层，矩形避开 UI）。
两个播放页面（桌面播放器 / 全屏播放页）都走这里，格式分派与差异处理
只有一处实现。

@table o
  @userdata o.parent   airui 父容器（MP4 不用：画面挂 LCDC 视频层）
  @number   o.x,o.y    画面摆放位置（相对 parent；airui 用）
  @number   o.w,o.h    画面尺寸（airui 路径必须等于素材帧尺寸，不支持缩放）
  @number   o.sx,o.sy  同一画面的逻辑屏绝对坐标（MP4 set_rect 用；缺省用 x,y）
  @boolean  o.loop     是否循环
@return userdata|table|nil 播放器对象（统一 :play/:pause/:stop/:destroy），失败 nil
]]
function M.create_player(path, o)
    o = o or {}
    local fmt = M.guess_format(path)

    if fmt == "mp4" then
        if not M.mp4_available() then
            log.warn("video_util", "固件无 mplayer，MP4 不可播", path)
            return nil
        end
        pa_enable()
        local rect
        if o.w and o.h and o.w > 0 and o.h > 0 then
            rect = { x = o.sx or o.x or 0, y = o.sy or o.y or 0, w = o.w, h = o.h }
        end
        return mp4_player(path, rect, o.loop)
    end

    -- HZV/MJPG：音频框架先起来（HZV 时钟依赖它；MJPG 的配套 MP3 也走它）
    M.audio_ensure()

    local vcfg = {
        parent = o.parent,
        x = o.x, y = o.y, w = o.w, h = o.h,
        src = path, format = fmt,
        decode_mode = "hw",
        loop = o.loop and true or false,
        auto_play = true,
    }
    if fmt == "hzv" then
        -- HZV 容器自带逐帧时长与 MP3 音轨，Lua 不填 interval
        vcfg.backend = "videoplayer"
    else
        vcfg.interval = 33   -- 30fps（调大即慢放，看着像卡住）
    end
    local ok, v = pcall(airui.video, vcfg)
    return (ok and v) and v or nil
end

return M
