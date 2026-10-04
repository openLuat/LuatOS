--[[
@module  welcome_win
@summary 开机欢迎页 —— 先亮静态 logo，初始化完成后播开机动画（mp4/hzv/mjpg 自动识别）
@version 4.1
@date    2026.10.03
@author  江访
@usage
订阅: OPEN_WELCOME_WIN  → 创建欢迎页，进入 LOGO 阶段（黑底 + logo 图）
订阅: BOOT_INIT_DONE    → 初始化完成，进入 VIDEO 阶段播放 BOOT_VIDEO
发布: OPEN_IDLE_WIN     → 动画播完或超时后发布，触发桌面窗口

=== 换开机动画素材只改一个常量 ===

BOOT_VIDEO 指向哪个文件就播哪个，容器格式自动识别（video_util.guess_format）：

  MP4（.mp4/.m4v 或 ftyp 魔数）→ mplayer 全屏接管（mp4_takeover）：
      单次播放、点屏幕可跳过、EOS 自动收尾；声音走 mplayer 自己的音频通路
      （功放脚按 hw.audio 手动使能，音量暂不跟系统音量）。
      ⚠ 素材分辨率硬上限 480×320（mplayer 静态 RGB 缓冲），超限会被预检
      拒播、直接跳桌面 —— 制作素材时务必压在上限以内。
  HZV（"HZV1" 魔数 / .hzv）    → airui.video 嵌入式播放（videoplayer 后端，
      容器自带 MP3 音轨与逐帧时长）。
  MJPG（其它）                 → airui.video 嵌入式播放，interval 33ms 逐帧喂。

MP4 不能走 airui.video 嵌入式路径：固件 C 层把 H.264 解码同步跑在调用方任务栈上，
真机一播即 "luatos stack over flow" 断言死机（详见 video_util 文件头「MP4 嵌入式
播放禁用」一节）；mp4_takeover 的 mplayer 配了 24KB 专用解码线程，是已真机验证的
替代路径。所以格式差异只在 try_start_video 一处分流，探测统一用 video_util。

=== 两阶段状态机 ===

  LOGO 阶段（on_create）：
    黑底 + 居中 logo（/luadb/logo.png，128×128 1:1）。两个条件都满足才开播：
      1. 最短停留 BOOT_LOGO_MIN_MS 展满（防止初始化过快 logo 一闪而过）；
      2. BOOT_INIT_DONE 到达（或 BOOT_LOGO_MAX_WAIT_MS 兜底超时，防初始化卡死）。

  VIDEO 阶段（try_start_video）：
    按容器格式分流两条路径，收尾都汇入同一个 finish()：
      1. HZV/MJPG —— airui.video 单次播放，on_complete（videoplayer 解码到 EOF）
         触发收尾；
      2. MP4 —— mp4_takeover.start 全屏接管，on_done（eos 播完 / touch 点屏 /
         error / oversize）触发收尾。
    另有一条独立的 BOOT_MAX_WAIT_MS 兜底上限（分格式两档），与正常收尾
    先到者生效、后到者被 finished 标志挡住。

之所以必须留超时这条路：早期 MJPG 素材走的是软件解码路径，on_complete 未必会
触发；且素材损坏、解码器起不来时，没有超时就会永久停在黑屏。

LOGO 阶段零主题依赖（黑底用字面量 0x000000，不 require ui_theme），
使 welcome_win 可被 boot_ui 最早加载；video_util 也只轻量依赖 exaudio。
mp4_takeover 顶部 require ui_theme，**必须懒加载**（takeover_mod，首次用到才
require），否则会把主题依赖提前到 LOGO 阶段。logo 资源缺失时只显示黑底，流程不中断。
]]

local video_util = require "video_util"
local ok_exaudio, exaudio = pcall(require, "exaudio")
if not ok_exaudio then exaudio = nil end

-- 换开机动画素材只改这一行（mp4/hzv/mjpg 自动识别，勿改代码）
-- local BOOT_VIDEO   = "/luadb/fruit.mp4"
local BOOT_VIDEO   = "/luadb/luatos_boot.hzv"
local BOOT_VW      = 480
local BOOT_VH      = 270
local LOGO_SIZE    = 128
-- 兜底上限（HZV/MJPG）：素材比这长就按此时间入场；素材更短则由 on_complete 提前入场
local BOOT_MAX_WAIT_MS = 5400
-- 兜底上限（MP4）：mp4 时长随内容走，给更宽裕的窗口（mplayer 自己轮询到 EOS，
-- 这条只兜「is_playing 卡死 / 起播后异常」）
local BOOT_MAX_WAIT_MS_MP4 = 15000
-- logo 最短停留：防止初始化过快导致 logo 一闪而过
local BOOT_LOGO_MIN_MS = 500
-- logo 兜底：初始化卡死（如某模块 require 挂起）也强制开播，防止永久停在 logo
local BOOT_LOGO_MAX_WAIT_MS = 3000

local window_id = nil
local bg_shape
local logo_img
local video_obj
-- mp4_takeover 懒加载缓存（见文件头：它会 require ui_theme，LOGO 阶段不能提前引入）
local mp4_takeover

--[[收尾标记与定时器句柄

finished 是「只走一次」的闸门：on_complete/on_done 与超时是多条独立路径，
必须保证无论哪条先到，进入桌面这件事都只发生一次 —— 重复 publish
OPEN_IDLE_WIN 会让 exwin 重复创建桌面。]]
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

--- 懒加载 mp4_takeover：首次用到时才 require（它顶部拉 ui_theme，不能提前）
--- @return table|nil
local function takeover_mod()
    if not mp4_takeover then
        local ok, m = pcall(require, "mp4_takeover")
        if ok then mp4_takeover = m end
    end
    return mp4_takeover
end

--[[收尾：进入桌面（播完 / 点屏 / 超时 / 起播失败共用，只生效一次）

@param reason string 仅用于日志，标明是哪条路径先到

顺序上必须先停掉开机视频（释放文件句柄与解码器），再 publish OPEN_IDLE_WIN ——
桌面播放器会打开同一个启动素材：hzv 的 videoplayer 句柄、mp4 的 mplayer 句柄
没释放都会打不开（mplayer 的 open 还要 ~600KB 系统堆，不 close 就回不来）。]]
local function finish(reason)
    if finished or not window_id then return end
    finished = true

    if wait_timer then
        sys.timerStop(wait_timer)
        wait_timer = nil
    end

    log.info("welcome_win", "开机动画结束(", reason, ")，进入桌面")
    -- mplayer 接管（MP4 路径）：stop 幂等，没有接管在跑时是空操作
    if mp4_takeover then
        pcall(mp4_takeover.stop)
    end
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

--[[素材播完（videoplayer 解码到 EOF，仅 loop = false 时触发，HZV/MJPG 路径）

这个回调是在 LVGL 的播放定时器里同步调进来的：此刻销毁视频控件，会把
「正在执行的那个定时器」一起删掉。所以推后一个 tick 再收尾，
让销毁发生在定时器回调之外。]]
local function on_video_done()
    sys.timerStart(function() finish("播放完毕") end, 1)
end

--[[MP4 接管收尾回调（mp4_takeover 的 on_done）

reason: "eos" 播完 | "touch" 点屏幕跳过 | "error" 起播失败 |
        "oversize" 超 480×320 上限 | "stop" 外部停止
全部直接入场，开机不被素材问题卡死。同样推后一个 tick，与 on_video_done 同理。]]
local function on_mp4_done(reason)
    sys.timerStart(function() finish("mp4:" .. tostring(reason)) end, 1)
end

--[[VIDEO 阶段入口：按容器格式分流开播（LOGO→VIDEO 转换唯一路径，只走一次）

转换条件 try_start_video 每次调用都检查：min_ok（最短停留展满）与
boot_ok（BOOT_INIT_DONE 或 logo 兜底超时）同时满足才真正开播，
两个条件哪条后到都由它自己触发开播，无需关心先后顺序。]]
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
        local base = BOOT_VIDEO:match("([^/]+)$") or BOOT_VIDEO
        for _, p in ipairs({ "/luadb/" .. base, "/" .. base }) do
            if io.exists(p) then
                video_path = p
                break
            end
        end
    end

    local fmt = video_util.guess_format(video_path)

    --[[MP4：走 mplayer 全屏接管（mp4_takeover 自己开窗、点屏可跳过、EOS 自动收尾）。
    禁走 airui.video —— 固件 H.264 解码栈溢出一播即死机（见文件头）。]]
    if fmt == "mp4" then
        local mpt = takeover_mod()
        local started = false
        if mpt then
            started = mpt.start(video_path, { on_done = on_mp4_done })
        end
        if started then
            log.info("welcome_win", "开机动画(mplayer 接管单次播放)", video_path)
        else
            -- mplayer 不可用 / 文件不存在：直接入场，不等超时
            log.warn("welcome_win", "开机动画不可用", video_path)
            sys.timerStart(function() finish("mp4不可用") end, 1)
        end
        wait_timer = sys.timerStart(on_timeout, BOOT_MAX_WAIT_MS_MP4)
        return
    end

    --[[HZV / MJPG：嵌入式 airui.video。从容器头读取实际帧尺寸，居中播放
    （airui.video 不支持缩放，尺寸不符只会溢出裁切，见 video_util 文件头）。]]
    local vw, vh = video_util.read_dimensions(video_path)
    if not vw or not vh then vw, vh = BOOT_VW, BOOT_VH end
    local vx = math.floor((screen_w - vw) / 2)
    local vy = math.floor((screen_h - vh) / 2)

    -- HZV 的音轨由 Audio V2 播放，视频时钟跟随 DAC DMA sample counter：
    -- 音频框架没起来时画面同样不会走帧，所以先确保一次音频初始化。
    video_util.audio_ensure()

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
开播时机由 on_create 查粘性标记 _G.__boot_init_done 补上（双保险）。]]
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

    -- logo 资源落点容错（对齐视频素材策略）；缺失只显示黑底，流程不中断
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
    -- 先落闸，避免 close 之后残留的 on_complete / on_done 再触发一次收尾
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

    -- 停掉可能还在跑的 mplayer 接管（MP4 路径）；stop 幂等
    if mp4_takeover then
        pcall(mp4_takeover.stop)
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
