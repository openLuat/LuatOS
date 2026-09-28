--[[
@module  welcome_win
@summary 开机欢迎页 —— 先亮静态 logo，初始化完成后播 HZV 开机动画
@version 4.0
@date    2026.09.26
@author  江访
@usage
订阅: OPEN_WELCOME_WIN  → 创建欢迎页，进入 LOGO 阶段（黑底 + logo 图）
订阅: BOOT_INIT_DONE    → 初始化完成，进入 VIDEO 阶段播放 /luatos_boot.hzv
发布: OPEN_IDLE_WIN     → 动画播完或超时后发布，触发桌面窗口

=== 两阶段状态机 ===

  LOGO 阶段（on_create）：
    黑底 + 居中 logo（/luadb/logo.png，128×128 1:1）。两个条件都满足才开播：
      1. 最短停留 BOOT_LOGO_MIN_MS 展满（防止初始化过快 logo 一闪而过）；
      2. BOOT_INIT_DONE 到达（或 BOOT_LOGO_MAX_WAIT_MS 兜底超时，防初始化卡死）。

  VIDEO 阶段（try_start_video）：
    hzv_audio_ensure → airui.video 单次播放。收尾两条路径共用同一个 finish()，
    先到者生效、后到者被 finished 标志挡住：
      1. on_complete —— videoplayer 解码到 EOF 时触发（素材播完）；
      2. BOOT_MAX_WAIT_MS —— 兜底上限（素材比这更长，或 on_complete 没来）。

之所以必须留超时这条路：早期 MJPG 素材走的是软件解码路径，
on_complete 未必会触发；且素材损坏、解码器起不来时，没有超时就会永久停在黑屏。

HZV 容器自带 MP3 音轨与逐帧时长，由 videoplayer 后端统一驱动，
Lua 侧不再手填 interval，也不再单独起一路「同名 MP3」。

LOGO 阶段零主题依赖（黑底用字面量 0x000000，不 require ui_theme），
使 welcome_win 可被 boot_ui 最早加载；logo 资源缺失时只显示黑底，流程不中断。
]]

local ok_exaudio, exaudio = pcall(require, "exaudio")
if not ok_exaudio then exaudio = nil end

local BOOT_VIDEO   = "/luadb/luatos_boot.hzv"
local BOOT_VW      = 480
local BOOT_VH      = 270
local LOGO_SIZE    = 128
-- 兜底上限：素材比这长就按此时间入场；素材更短则由 on_complete 提前入场
local BOOT_MAX_WAIT_MS = 5400
-- logo 最短停留：防止初始化过快导致 logo 一闪而过
local BOOT_LOGO_MIN_MS = 500
-- logo 兜底：初始化卡死（如某模块 require 挂起）也强制开播，防止永久停在 logo
local BOOT_LOGO_MAX_WAIT_MS = 3000

local window_id = nil
local bg_shape
local logo_img
local video_obj

--[[收尾标记与定时器句柄

finished 是「只走一次」的闸门：on_complete 与超时是两条独立路径，
必须保证无论哪条先到，进入桌面这件事都只发生一次 —— 重复 publish
OPEN_IDLE_WIN 会让 exwin 重复创建桌面。
]]
local finished = false
local wait_timer = nil

--[[LOGO→VIDEO 转换条件：最短停留展满(min_ok) 且 初始化完成(boot_ok) 才开播。
boot_ok 有两条来路：BOOT_INIT_DONE 事件、logo 兜底超时；粘性标记
_G.__boot_init_done 供 on_create 补查（防事件早于订阅丢失）。]]
local min_ok = false
local boot_ok = false
local video_started = false
local min_timer = nil
local logo_wait_timer = nil

--- 判断素材用哪种容器解析：优先看魔数，其次看扩展名
--- @return "hzv" | "mjpg" | "mp4"
local function media_guess_format(path)
    local f = io.open(path, "rb")
    if f then
        local magic = f:read(4)
        f:close()
        if magic == "HZV1" then return "hzv" end
    end
    local ext = path:match("%.([^%.]+)$")
    if ext then
        ext = ext:lower()
        if ext == "hzv" then return "hzv" end
        if ext == "mp4" then return "mp4" end
    end
    return "mjpg"
end

--- HZV 的音轨由 Audio V2 播放，视频时钟跟随 DAC DMA sample counter：
--- 音频框架没起来时既不响、也不会走帧，所以这里做一次幂等初始化。
--- 首次真 setup，之后只 RESUME；失败不阻断画面创建。
local function hzv_audio_ensure()
    if not exaudio then return false end
    if not (_G.project_config and _G.project_config.hw and _G.project_config.hw.audio) then
        return false
    end
    if _G.__hzv_audio_ready then
        pcall(exaudio.pm, exaudio.RESUME)
        return true
    end
    local ac = _G.project_config.hw.audio
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
    log.warn("welcome_win", "hzv: exaudio.setup 失败，音轨与播放时钟可能不可用")
    return false
end

--- 读媒体容器头拿回 (width, height)
--- HZV v1: 前 4 字节为 "HZV1"，0x44 / 0x46 处各一个 uint16 宽、高
--- 其它  : 按 MJPG/JPEG 扫 SOF0/SOF2 标记
--- 取不到返回 nil，由调用方回退默认尺寸
local function media_read_dimensions(path)
    local f = io.open(path, "rb")
    if not f then return nil end
    local data = f:read(512)  -- HZV 头部 0x48 以内 / JPEG 的 SOF 标记一般在 512 字节内
    f:close()
    if not data or #data < 8 then return nil end

    -- HZV 容器：帧尺寸直接写在头里（Lua 下标从 1 起，0x44 → 69）
    if data:sub(1, 4) == "HZV1" then
        local hw = data:byte(69) + data:byte(70) * 256
        local hh = data:byte(71) + data:byte(72) * 256
        if hw > 0 and hh > 0 then return hw, hh end
        return nil
    end

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

--[[收尾：进入桌面（播完 / 超时共用，只生效一次）

@param reason string 仅用于日志，标明是哪条路径先到

顺序上必须先停掉开机视频（释放文件句柄与解码器），再 publish OPEN_IDLE_WIN ——
桌面播放器要打开同一个 /luatos_boot.hzv，句柄没释放会打不开。
]]
local function finish(reason)
    if finished or not window_id then return end
    finished = true

    if wait_timer then
        sys.timerStop(wait_timer)
        wait_timer = nil
    end

    log.info("welcome_win", "开机动画结束(", reason, ")，进入桌面")
    if video_obj then
        pcall(video_obj.stop, video_obj)
        pcall(video_obj.destroy, video_obj)
        video_obj = nil
    end
    sys.publish("OPEN_IDLE_WIN")
    exwin.close(window_id)
end

local function on_timeout()
    finish("超时")
end

--[[素材播完（videoplayer 解码到 EOF，仅 loop = false 时触发）

这个回调是在 LVGL 的播放定时器里同步调进来的：此刻销毁视频控件，会把
「正在执行的那个定时器」一起删掉。所以推后一个 tick 再收尾，
让销毁发生在定时器回调之外。
]]
local function on_video_done()
    sys.timerStart(function() finish("播放完毕") end, 1)
end

--[[VIDEO 阶段入口：音频预热 + 播放 hzv（LOGO→VIDEO 转换唯一路径，只走一次）

转换条件 try_start_video 每次调用都检查：min_ok（最短停留展满）与
boot_ok（BOOT_INIT_DONE 或 logo 兜底超时）同时满足才真正开播，
两个条件哪条后到都由它自己触发开播，无需关心先后顺序。
]]
local function try_start_video()
    if not (min_ok and boot_ok) then return end
    if video_started or finished or not window_id then return end
    video_started = true

    if min_timer then
        sys.timerStop(min_timer)
        min_timer = nil
    end
    if logo_wait_timer then
        sys.timerStop(logo_wait_timer)
        logo_wait_timer = nil
    end

    -- logo 让位给视频（同为居中矩形，视频不透明会盖住 logo；销毁后也省一块解码缓存）
    if logo_img then
        pcall(logo_img.destroy, logo_img)
        logo_img = nil
    end

    -- 资源落点随烧录方式而变（/luadb/ 或根目录），先挑实际存在的那个
    local video_path = BOOT_VIDEO
    if not io.exists(video_path) then
        -- .hzv 优先（真机硬解）；素材还没换成 hzv 时回落同名 .mjpg，避免开机黑屏
        for _, p in ipairs({
            "/luadb/luatos_boot.hzv","/luatos_boot.hzv",
        }) do
            if io.exists(p) then
                video_path = p
                break
            end
        end
    end

    -- 从容器头读取实际帧尺寸，居中播放
    local vw, vh = media_read_dimensions(video_path)
    if not vw or not vh then vw, vh = BOOT_VW, BOOT_VH end
    local vx = math.floor((screen_w - vw) / 2)
    local vy = math.floor((screen_h - vh) / 2)

    -- HZV 的音轨由 Audio V2 播放，视频时钟跟随 DAC DMA sample counter：
    -- 音频框架没起来时画面同样不会走帧，所以先确保一次音频初始化。
    hzv_audio_ensure()

    local fmt = media_guess_format(video_path)
    local vcfg = {
        x = vx, y = vy, w = vw, h = vh,
        src = video_path,
        format = fmt,
        decode_mode = "hw",
        loop = false,              -- 单次播放：播完由 on_complete 收尾
        auto_play = true,
        on_complete = on_video_done,
    }
    if fmt == "hzv" then
        -- HZV 容器自带 MP3 音轨与逐帧时长，Lua 不填 interval，交给 videoplayer 后端统一驱动
        vcfg.backend = "videoplayer"
    else
        -- 兼容早期 MJPG 素材：帧间隔只能由 Lua 指定
        vcfg.interval = 33
    end

    local ok, v = pcall(airui.video, vcfg)

    if ok and v then
        video_obj = v
        log.info("welcome_win", "开机动画单次播放", video_path, fmt)
    else
        log.warn("welcome_win", "开机动画不可用", video_path)
    end

    -- 兜底上限：素材更长 / on_complete 没来 / 素材不可用时，都由它收尾
    wait_timer = sys.timerStart(on_timeout, BOOT_MAX_WAIT_MS)
end

--[[初始化完成（boot_ui 在分批加载完业务与 UI 模块、主题恢复后发布）

只置位并尝试开播；窗口尚未创建时 try_start_video 会被 window_id 挡住，
开播时机由 on_create 查粘性标记 _G.__boot_init_done 补上（双保险）。
]]
local function on_boot_init_done()
    boot_ok = true
    if logo_wait_timer then
        sys.timerStop(logo_wait_timer)
        logo_wait_timer = nil
    end
    try_start_video()
end

local function on_create()
    finished = false
    wait_timer = nil
    min_ok = false
    boot_ok = false
    video_started = false

    -- 黑色全屏背景（0x000000 字面量：LOGO 阶段零主题依赖，可被 boot_ui 最早加载）
    bg_shape = airui.shape({
        x = 0, y = 0, w = screen_w, h = screen_h,
        items = {
            { type = "rect", x = 0, y = 0, w = screen_w, h = screen_h,
              fill = true, fill_color = 0x000000, color = 0x000000 },
        },
    })

    -- logo 资源落点容错（对齐 hzv 策略）；缺失只显示黑底，流程不中断
    local logo_path = nil
    for _, p in ipairs({ "/luadb/logo.png", "/logo.png" }) do
        if io.exists(p) then
            logo_path = p
            break
        end
    end
    if logo_path then
        -- 128×128 居中 1:1 显示，不缩放
        logo_img = airui.image({
            x = math.floor((screen_w - LOGO_SIZE) / 2),
            y = math.floor((screen_h - LOGO_SIZE) / 2),
            w = LOGO_SIZE, h = LOGO_SIZE,
            src = logo_path,
        })
        log.info("welcome_win", "LOGO 阶段", logo_path)
    else
        log.warn("welcome_win", "logo 资源缺失，LOGO 阶段仅显示黑底")
    end

    -- 最短停留：展满后放行开播（若 boot_ok 已就绪）
    min_timer = sys.timerStart(function()
        min_timer = nil
        min_ok = true
        try_start_video()
    end, BOOT_LOGO_MIN_MS)

    -- 兜底：初始化卡死也强制开播，防止永久停在 logo
    logo_wait_timer = sys.timerStart(function()
        logo_wait_timer = nil
        log.warn("welcome_win", "初始化未在", BOOT_LOGO_MAX_WAIT_MS, "ms 内完成，兜底开播")
        boot_ok = true
        try_start_video()
    end, BOOT_LOGO_MAX_WAIT_MS)

    -- 粘性标记补查：BOOT_INIT_DONE 可能早于窗口创建（事件丢不了，见 on_boot_init_done 注释）
    if _G.__boot_init_done then
        boot_ok = true
    end
    try_start_video()
end

local function on_destroy()
    -- 先落闸，避免 close 之后残留的 on_complete 再触发一次收尾
    finished = true
    if wait_timer then
        sys.timerStop(wait_timer)
        wait_timer = nil
    end
    if min_timer then
        sys.timerStop(min_timer)
        min_timer = nil
    end
    if logo_wait_timer then
        sys.timerStop(logo_wait_timer)
        logo_wait_timer = nil
    end

    -- 兜底：停掉可能还在跑的容器音轨
    -- 注意 exaudio 是容错加载的（可能为 nil），取字段必须在 pcall 之外先判空，
    -- 否则 exaudio.play_stop 本身就会抛 "attempt to index a nil value"
    if exaudio then
        pcall(exaudio.play_stop, { type = 0 })
    end
    if video_obj then
        pcall(video_obj.stop, video_obj)
        pcall(video_obj.destroy, video_obj)
        video_obj = nil
    end
    if logo_img then
        pcall(logo_img.destroy, logo_img)
        logo_img = nil
    end
    if bg_shape then
        bg_shape:destroy()
        bg_shape = nil
    end
    window_id = nil
end

local function on_get_focus() end
local function on_lose_focus() end

local function open_handler()
    window_id = exwin.open({
        on_create = on_create,
        on_destroy = on_destroy,
        on_get_focus = on_get_focus,
        on_lose_focus = on_lose_focus,
    })
end

sys.subscribe("OPEN_WELCOME_WIN", open_handler)
sys.subscribe("BOOT_INIT_DONE", on_boot_init_done)
