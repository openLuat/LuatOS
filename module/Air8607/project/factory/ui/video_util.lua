--[[
@module  video_util
@summary 媒体素材工具（容器格式嗅探 / 帧尺寸读取 / HZV 音轨初始化 / 播放器创建）—— 播放类页面共用
@version 1.9
@date    2026.10.20
@author  江访

=== 为什么单独成模块 ===
idle_win（桌面播放器）与 video_win（全屏播放页）都要读素材帧尺寸，而 airui 播放器
**不支持缩放**：控件尺寸与素材帧尺寸不一致时会被强制改回素材尺寸
（components/airui/src/components/widgets/luat_airui_video.c 的
 "scaling is not supported yet ... force reset widget size"）。
也就是说，帧尺寸读错**不会**把画面拉伸，只会让控件溢出容器、把画面切掉一块 ——
同一份口径必须只有一处实现，否则两个页面的裁切行为会不一致。

（welcome_win 里还有一份历史副本。开机路径没跟着迁移，改这里时别以为全工程都干净了。）

=== MP4 / HZV / MJPG 统一走 airui.video（2026-10-09 起）===
airui.video 已支持 HZV 与 MP4：MJPG / HZV 走 videoplayer 后端（控件内拉 RGB565 帧），
MP4 按 format 自动路由到 mplayer 后端（自带音频通路、硬件图层送显、组件内部
循环重播与 EOS 回调 on_complete）。桌面播放器（idle_win）与全屏播放页
（video_win）三种格式的播放全部收口到 create_player 一个入口。
MP4 的两个会话副作用（功放使能、触摸总线守护）也在这里收口，见「MP4 会话副作用」。

@api video_util.guess_format(path)              容器格式："hzv" | "mjpg" | "mp4"
@api video_util.read_dimensions(path)           w, h；读不到返回 nil
@api video_util.frame_size(path, def_w, def_h)  w, h；读不到时用调用方给的兜底值
@api video_util.audio_ensure()                  幂等初始化配套音频框架（MJPG 的同名 MP3 用，
                                                HZV 不走 exaudio），返回是否可用
@api video_util.create_player(path, o)          按格式创建**嵌入式**播放器（airui.video，
                                                HZV/MJPG/MP4 统一；o.on_complete=单次播完回调）
@api video_util.tp_bus_restore()                恢复触摸 I2C 总线配置（音频通路会重置总线）
]]

local ok_exaudio, exaudio = pcall(require, "exaudio")
if not ok_exaudio then exaudio = nil end

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

--[[MP4 容器盒解析拿编码宽高（纯 Lua，不碰解码器）

只为读两个整数就 open 解码器太重（会初始化 FFmpeg / 硬解并喂 SPS/PPS），
纯 Lua 解析 moov 盒足够：优先 stsd 里 avc1/hev1/hvc1/mp4v 的
VisualSampleEntry 宽高（载荷偏移 +24/+26），找不到再用 tkhd 尾部 16.16
定点显示宽高兜底。moov 超 2MB 放弃（正常素材远小于此）。
盒结构：[size(4) type(4) payload...]，size==1 时 64 位盒长跟在头后。]]
local function mp4_box_dimensions(path)
    local f = io.open(path, "rb")
    if not f then return nil end

    local function be32(s, o)
        local a, b, c, d = s:byte(o, o + 3)
        return a * 16777216 + b * 65536 + c * 256 + d
    end
    local function be16(s, o)
        local a, b = s:byte(o, o + 1)
        return a * 256 + b
    end

    -- 顶层盒遍历找 moov（只读盒头跳过 mdat 等大盒，不整文件读入）
    local moov = nil
    local fsize = io.fileSize(path) or 0
    local pos = 0
    while pos + 8 <= fsize do
        f:seek("set", pos)
        local hdr = f:read(8)
        if not hdr or #hdr < 8 then break end
        local size = be32(hdr, 1)
        if size == 1 then
            local ext = f:read(8)
            if not ext or #ext < 8 then break end
            size = be32(ext, 1) * 4294967296 + be32(ext, 5)
        elseif size == 0 then
            size = fsize - pos
        end
        if size < 8 then break end
        if hdr:sub(5, 8) == "moov" then
            local msize = size - 8
            if msize > 2 * 1024 * 1024 then break end
            f:seek("set", pos + 8)
            moov = f:read(msize)
            break
        end
        pos = pos + size
    end
    f:close()
    if not moov or #moov < 32 then return nil end

    -- VisualSampleEntry：SampleEntry 头 8 字节 + 预留 16 字节后是 width/height
    for _, tag in ipairs({ "avc1", "hvc1", "hev1", "mp4v" }) do
        local i = moov:find(tag, 1, true)
        while i do
            local p = i + 4
            if p + 27 <= #moov then
                local w, h = be16(moov, p + 24), be16(moov, p + 26)
                if w >= 16 and w <= 8192 and h >= 16 and h <= 8192 then return w, h end
            end
            i = moov:find(tag, i + 1, true)
        end
    end

    -- tkhd 兜底：显示宽高是 16.16 定点在载荷尾部（v0 载荷 84 字节宽偏移 76，v1 为 96/88）
    local i = moov:find("tkhd", 1, true)
    while i do
        local p = i + 4
        if p + 4 <= #moov then
            local woff = (moov:byte(p) == 1) and 88 or 76
            if p + woff + 8 <= #moov then
                local w = math.floor(be32(moov, p + woff) / 65536)
                local h = math.floor(be32(moov, p + woff + 4) / 65536)
                if w >= 16 and w <= 8192 and h >= 16 and h <= 8192 then return w, h end
            end
        end
        i = moov:find("tkhd", i + 1, true)
    end
    return nil
end

--[[读媒体容器头拿回 (width, height)

HZV v1: 前 4 字节为 "HZV1"，0x44 / 0x46 处各一个 uint16 宽、高
        （Lua 下标从 1 起，所以是 byte(69)/byte(70) 与 byte(71)/byte(72)）
MP4 :   纯 Lua 解析容器盒拿宽高（见 mp4_box_dimensions，不碰解码器）
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

    -- MP4（魔数 = 偏移 4 处的 "ftyp" box）：纯 Lua 解析容器盒，不碰 H.264 解码器
    if data:sub(5, 8) == "ftyp" then
        return mp4_box_dimensions(path)
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

--[[配套音频框架初始化（幂等，MJPG 的同名 MP3 用）

首次真 setup，之后只 RESUME 并重新对齐 ac.play_vol（设置页「亮度和声音」会改
ac.play_vol，回到播放路径时对齐一次）。失败不阻断画面创建（只是没声音）。

HZV **不走这里**：它的音轨由 videoplayer 自己调用 luat_audio_request_play_stream，
测试工程不碰 exaudio 一切正常；而 exaudio.setup 的 DAC 收尾会 audio_v2.shutdown
关掉 codec 和功放 —— MP4 的 mplayer 刚把上一路请求标成结束、音频任务还没释放完，
紧接着 shutdown 会让下一次 play_stream 没声音（真机踩过：MP4→HZV 切换后静音）。

用全局标志 _G.__hzv_audio_ready 记账：桌面播放器与全屏播放页共用同一套音频框架，
各自 setup 一次会互相打断，标志位必须跨模块共享。]]
function M.audio_ensure()
    if not exaudio then return false end
    local pc = _G.project_config
    if not (pc and pc.hw and pc.hw.audio) then return false end
    local ac = pc.hw.audio
    if _G.__hzv_audio_ready then
        pcall(exaudio.pm, exaudio.RESUME)
        --[[RESUME 后重新对齐一次当前音量：设置页「亮度和声音」会改 ac.play_vol，
        回到播放路径时对齐一次，保证桌面 HZV 音轨跟着用户音量走；
        也兜住增益状态在休眠中丢失的个别平台。]]
        pcall(exaudio.vol, ac.play_vol or 100)
        return true
    end
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

-- ==================== 触摸总线守护 ====================
--[[恢复触摸 I2C 总线配置（音频通路会重置总线）
@return boolean 是否有可恢复的触摸驱动]]
function M.tp_bus_restore()
    if _G.tp_drv and _G.tp_drv.i2c_restore then
        pcall(_G.tp_drv.i2c_restore)
        return true
    end
    return false
end

--[[触摸硬恢复：i2c.setup 之上再补一层 —— 重新初始化 GT911（复位 + tp.init + 重新绑定）

为什么光 i2c.setup 不够：音频通路重配 I2C1 若正好落在 tp 的读事务中间，
GT911 会停在半事务状态，之后所有读都不应答 —— 速率改回来也没用，
现象就是「屏幕亮、日志正常、整块屏点不动」。
延时执行（默认 300ms）是为了避开 mplayer / 音频收尾那一刻，别在同一时刻抢总线。

@param number delay_ms 延迟毫秒数，缺省 300
@return boolean 是否排上了（没有可用的触摸驱动时返回 false）
]]
local tp_recover_t = nil
function M.tp_recover(delay_ms)
    if not (_G.tp_drv and _G.tp_drv.reinit) then return false end
    if tp_recover_t then
        sys.timerStop(tp_recover_t)
        tp_recover_t = nil
    end
    tp_recover_t = sys.timerStart(function()
        tp_recover_t = nil
        local ok, r = pcall(_G.tp_drv.reinit)
        if ok and r then
            log.info("video_util", "触摸重新初始化完成")
        else
            log.error("video_util", "触摸重新初始化失败", tostring(r))
        end
    end, delay_ms or 300)
    return true
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

-- ==================== MP4 会话副作用（功放 / 触摸总线守护） ====================
--[[mplayer 的音频通路启动时会把触摸 I2C 总线配置重置（真机踩过：GT911 读超时、
触摸失灵），功放引脚也要手动使能（mplayer 自己不拉 PA）。airui.video 的 MP4
后端内部同样走 mplayer，这两个副作用原样存在 —— 在创建/销毁播放器时统一收口
（见 wrap_mp4_player）；跨格式切换丢功放由 pa_reassert 补（见 create_player）。

触摸总线恢复是事件驱动的：重置只发生在音频通路启动（起播 / 续播 / 循环重播 /
异步初始化），每个事件点恢复一次再补两发延迟恢复即覆盖全程，不做周期泵
（500ms 守护泵会在整个会话期无条件 i2c.setup，一直刷 i2c change_br 日志）。
组件内部循环重播走不到包装层 play，故 MP4 的 loop 改为应用层续播
（EOF 回调里 play() 从头重播，见 create_player），每轮重播都精确恢复一次。

恢复定时器必须**按播放器实例**归属（见 wrap_mp4_player 的 sess）：桌面播放器与
全屏播放页各有一份，谁收尾只停谁的；共用一份时切换页面会互相 cancel，
最终把触摸总线留在音频通路改过的配置上（整屏无响应）。
HZV/MJPG 没有会话对象，起播后用 tp_bus_settle_once 打两发即止（发射即忘）。
exaudio 路径的 I2C 守护在 boot_ui.guard_audio_init（setup 仅首次 + 入口恢复）。

MP4 源分辨率上限 480×320：mplayer 的 RGB 帧缓冲是静态数组，超限直接溢出，
起播前用纯 Lua 盒解析读宽高拦截。HZV/MJPG 无此上限（HZV 支持更大分辨率）。]]
local MP4_MAX_W = 480
local MP4_MAX_H = 320

-- PA 功放使能/关闭（引脚与电平读板级 hw.audio）
local function pa_set(on)
    local ac = _G.project_config and _G.project_config.hw and _G.project_config.hw.audio
    if not (ac and ac.pa_ctrl) then return end
    if on then
        pcall(gpio.setup, ac.pa_ctrl, ac.pa_on_level or 0)
    else
        pcall(gpio.setup, ac.pa_ctrl, (ac.pa_on_level == 1) and 0 or 1)
    end
end

-- 功放补枪的世代号：会话收尾后作废尚未触发的补枪
local pa_gen = 0

-- MP4 销毁会把功放拉高；HZV 的 exaudio.setup 收尾也会 shutdown 关掉功放。
-- 切到 HZV/MJPG 后必须再打开，并在音频任务异步收尾之后补一次。
local function pa_reassert()
    pa_gen = pa_gen + 1
    local gen = pa_gen
    pa_set(true)
    sys.timerStart(function()
        if gen == pa_gen then pa_set(true) end
    end, 200)
end

--[[触摸总线恢复：立即一次 + 400/1500ms 各补一发（发射即忘，只给非 MP4 路径用）

HZV/MJPG 的音轨由 videoplayer 自己发起音频请求，起播同样可能重配 codec 总线；
这两发补枪覆盖音频通路的异步初始化（解码线程里才起音频，实测会把 Lua 调度卡住约 1s）。
MP4 会话有自己**可取消**的一份（收进实例的 sess 表，见 wrap_mp4_player），不要混用。]]
local function tp_bus_settle_once()
    M.tp_bus_restore()
    for _, delay_ms in ipairs({ 400, 1500 }) do
        sys.timerStart(function() M.tp_bus_restore() end, delay_ms)
    end
end

--[[包装 MP4 播放器：音频通路启动相关的事件点恢复触摸总线，destroy 时统一收尾

接口面与裸 airui.video 对象一致（:play/:pause/:stop/:destroy），调用方无感；
paused 字段记录用户暂停状态（应用层循环续播据此跳过，见 create_player）；
HZV/MJPG 不涉及这些副作用，create_player 仍返回裸对象。

**会话状态按实例归属（修「全屏↔窗口切换几次后 MP4 不显示 / 回到桌面点不动」）**：
触摸总线恢复定时器 settle_t 收进每个播放器自己的 sess 表，不再用模块级共享一份。
此前 idle_win 的桌面播放器与 video_win 的全屏播放器共用同一份 —— 切换页面时
上一页 destroy 的收尾会 cancel 掉下一页刚布防的恢复定时器，几次之后 mplayer 的
音频/总线会话被搅坏：GT911 停留在音频通路改过的总线配置上（整屏触摸无响应），
画面黑屏不更新。下沉到实例后，destroy 只收尾自己的会话，互不干扰。
功放补枪世代 pa_gen 仍是全局唯一（功放是全局硬件，pa_reassert 也在操控它）。]]
local function wrap_mp4_player(v)
    local sess = {
        settle_t = { nil, nil }, -- 本实例触摸总线延迟恢复句柄
    }

    -- 触摸总线恢复：立即一次 + 400/1500ms 各补一发（补枪覆盖音频通路异步初始化）
    local function tp_bus_settle()
        M.tp_bus_restore()
        local delays = { 400, 1500 }
        for i = 1, 2 do
            if sess.settle_t[i] then
                sys.timerStop(sess.settle_t[i])
                sess.settle_t[i] = nil
            end
            --[[回调里先把句柄置空：sys.timerStart 的是一次性定时器，触发后 id 即失效，
            不清空的话下一次 tp_bus_settle 会拿失效 id 去 sys.timerStop，
            日志里就是那两行 "luat_timer_get ... no find!!!"（噪音，且没必要）]]
            sess.settle_t[i] = sys.timerStart(function()
                sess.settle_t[i] = nil
                M.tp_bus_restore()
            end, delays[i])
        end
    end

    -- 停掉本实例未触发的延迟恢复（会话收尾）
    local function tp_bus_settle_cancel()
        for i = 1, 2 do
            if sess.settle_t[i] then
                sys.timerStop(sess.settle_t[i])
                sess.settle_t[i] = nil
            end
        end
    end

    -- 本实例会话收尾：只停自己的定时器；作废补枪要连全局功放世代一起翻
    local function session_end()
        tp_bus_settle_cancel()
        pa_gen = pa_gen + 1   -- 作废尚未触发的 pa_reassert 补枪，防止收尾后功放被重新打开
        pa_set(false)
        M.tp_bus_restore()
        --[[会话收尾是触摸最容易被搞坏的时机（mplayer 释放音频通路会重配一次 I2C1）：
        先 i2c.setup 把速率改回来，再延时重新初始化 GT911 兜底。
        客户现场「视频播完/退出后整块屏点不动」就是这一步缺了硬恢复。]]
        M.tp_recover(300)
    end

    -- 构造即布防初始触摸总线恢复（auto_play 起播的音频初始化在解码线程里异步进行）
    tp_bus_settle()

    return {
        paused = false,
        play = function(self, ...)
            local r = v:play(...)
            self.paused = false
            pa_set(true)             -- PA_EN 跟随播放：起播开功放
            -- 续播/循环重播会重启音频通路，再次重置总线
            tp_bus_settle()
            return r
        end,
        pause = function(self, ...)
            local r = v:pause(...)
            self.paused = true
            pa_set(false)            -- PA_EN 跟随暂停：暂停关功放
            -- 暂停不会再重配音频通路，这里不碰 I2C1：i2c.setup 本身会打断 tp 的读事务，
            -- 每多一次就多一次把 GT911 读坏的窗口（收尾时统一硬恢复，见 session_end）
            return r
        end,
        stop = function(self, ...)
            local r = v:stop(...)
            self.paused = true
            pa_set(false)            -- PA_EN 跟随停止：停止关功放
            -- 同上：停止后必然走 destroy → session_end，那里统一恢复
            return r
        end,
        destroy = function(_)
            pcall(function() v:destroy() end)
            session_end()
        end,
    }
end

-- ==================== 播放器创建 ====================
--[[按素材格式创建**嵌入式**播放器（唯一入口）

HZV / MJPG / MP4 都走 airui.video（父容器内的控件，随 UI 层级显示/隐藏）：
MJPG 逐帧按 interval 喂；HZV / MP4 自带帧时序（HZV 容器帧时长 / MP4 PTS），
单次播完（on_complete）由组件回调，循环控制栏代码无感 —— HZV/MJPG 循环
由组件统一处理，MP4 循环为应用层续播（保证每轮重播都恢复触摸总线，见下）。
两个播放页面（桌面播放器 / 全屏播放页）都走这里，格式差异只有一处实现。

@table o
  @userdata o.parent   airui 父容器
  @number   o.x,o.y    画面摆放位置（相对 parent）
  @number   o.w,o.h    画面尺寸（必须等于素材帧尺寸，不支持缩放）
  @boolean  o.loop     是否循环
  @function o.on_complete 单次播完（loop=false 读到 EOF）回调
@return userdata|nil 播放器对象（:play/:pause/:stop/:destroy），失败 nil
]]
function M.create_player(path, o)
    o = o or {}
    local fmt = M.guess_format(path)

    if fmt == "mp4" then
        -- 分辨率超限拒绝起播：调用方按「无法播放」走空态 UI
        local w, h = M.read_dimensions(path)
        if w and h and (w > MP4_MAX_W or h > MP4_MAX_H) then
            log.warn("video_util", "MP4 超 480×320 上限，拒绝起播", w, h, path)
            return nil
        end
        --[[停掉残留的配套/容器音频再起 mplayer：两路音频同开必打架。
        MP4 的声音走 mplayer 自带音频通路（组件内部自行初始化），
        不经 exaudio，也不需要 audio_ensure。]]
        M.audio_stop()
        if exaudio then pcall(exaudio.play_stop, { type = 0 }) end
        pa_set(true)
    elseif fmt == "hzv" then
        --[[HZV 音轨由 videoplayer 自己调用 luat_audio_request_play_stream。
        不能在这里 exaudio.setup：DAC 模式收尾会 audio_v2.shutdown 关掉 codec 和功放，
        而 MP4 的 mplayer 刚把上一路请求标成结束、音频任务还没释放完。
        紧接着 shutdown，下一次 play_stream 就没有声音。
        测试工程不碰 exaudio，只保持功放开，切换是正常的。]]
        pa_reassert()
    else
        -- MJPG 配套 MP3 走 exaudio，先确保音频框架
        M.audio_ensure()
        pa_reassert()
    end

    local vcfg = {
        parent = o.parent,
        x = o.x, y = o.y, w = o.w, h = o.h,
        src = path, format = fmt,
        decode_mode = "hw",
        loop = o.loop and true or false,
        auto_play = true,
    }
    if o.on_complete then
        vcfg.on_complete = o.on_complete
    end
    if fmt == "mjpg" then
        vcfg.interval = 33   -- 30fps（调大即慢放，看着像卡住）
    elseif fmt == "hzv" then
        -- HZV 自带逐帧时长，不填 interval，显式走 videoplayer 后端；
        -- MP4 不指定 backend，组件按 format 自动路由到 mplayer 后端
        vcfg.backend = "videoplayer"
    end

    --[[MP4 的 loop 改为应用层续播（EOF 回调里 play() 从头重播）：组件内部
    循环重播走不到包装层 play，每轮重启音频通路后恢复不了触摸总线。
    重播与组件内部循环同为「play 从头重播」路径，画面无差异；
    用户暂停中不续播（paused 状态由包装层维护）。]]
    local player_obj = nil
    if fmt == "mp4" then
        if o.loop then
            vcfg.loop = false
            vcfg.on_complete = function()
                -- 应用层续播：走包装层 play，PA 与触摸总线恢复自动跟上
                if player_obj and not player_obj.paused then
                    player_obj:play()
                end
                -- EOS 也是音频通路收尾的时机（mplayer 停解码/放音频会重配 I2C1）
                M.tp_recover(300)
            end
        else
            -- 单次播完（EOF）：先关功放，再回调调用方（翻播放状态 / 刷控制栏）
            local user_complete = vcfg.on_complete
            vcfg.on_complete = function()
                pa_set(false)
                if user_complete then user_complete() end
                M.tp_recover(300)
            end
        end
    elseif vcfg.on_complete then
        --[[HZV/MJPG 单次播完：组件回调用户回调后，同样补一次触摸硬恢复。
        循环模式下组件内部自己重播、不停音频通路，不会触发这里。]]
        local user_complete = vcfg.on_complete
        vcfg.on_complete = function()
            user_complete()
            M.tp_recover(300)
        end
    end

    local ok, v = pcall(airui.video, vcfg)
    if not ok or not v then
        if fmt == "mp4" then
            -- 起播失败收尾：此时还没 wrap，没有实例定时器，直接关功放 + 恢复触摸总线
            pa_set(false)
            M.tp_bus_restore()
        end
        return nil
    end
    if fmt == "mp4" then
        -- wrap 内部构造时已布防初始触摸总线恢复（auto_play 起播的音频初始化在解码线程里异步进行）
        player_obj = wrap_mp4_player(v)
        return player_obj
    end
    -- 播放器打开时音频任务可能再次把功放拉高，创建成功后再拉一次
    pa_set(true)
    --[[HZV/MJPG 的音轨由 videoplayer 自己发起音频请求，起播同样会重配 codec 总线；
    这里补两发延迟恢复（发射即忘，这类播放器没有可收尾的会话对象）。
    与桌面/全屏切换时序无关，因此不存在 MP4 那种「被对端 cancel」的问题。]]
    tp_bus_settle_once()
    return v
end

return M
