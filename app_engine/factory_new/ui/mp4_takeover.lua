--[[
@module  mp4_takeover
@summary MP4 全屏接管播放（mplayer 路径）—— 单次播放、点屏幕退出、不循环
@version 1.0
@date    2026.09.30
@author  江访

=== 这个模块解决什么问题 ===
MP4 走 airui.video 的嵌入式路径已禁播（video_util 的 MP4_PLAYBACK_ENABLED = false）：
固件 C 层 components/videoplayer/src/luat_mp4_videoplayer.c 把 FFmpeg H.264 解码
（h264_decoder_init / h264_decode_nal / h264_deinit）同步跑在调用方任务栈上，
真机一播即 "luatos stack over flow" 断言死机（详见 video_util.lua 文件头）。
C 层问题只指出不改；固件把解码挪到大栈线程之前，MP4 只能换一条已验证的播放路径 ——
mplayer（它把解码放在 24KB 专用线程，components/mplayer/src/luat_mplayer.c 的
MPLAYER_DS_STACK，不解调用方的栈，所以不炸）。

播放流程照搬真机验证过的 mp4_test 工程
（C:\luatools_v1\userprojs\mp4_test\user\main.lua）：

    mplayer.open → set_rect(-1,-1) → play → 轮询 is_playing → stop → close

=== 播放形态（2026-09-30 拍板）===
全屏接管单次播放：mplayer 的视频层叠在整个 UI 之上，播放中不显示任何控制栏
（显示了也会被画面盖住），点屏幕任意处退出；EOS 自动收尾。**不循环**。
桌面播放器（idle_win）与全屏播放页（video_win）都从这里进：选中 MP4 即触发。

=== 已知限制 / 真机验证点 ===
1. mplayer 无 loop API：MP4 不循环，播完即停；要重播由调用方的「播放」键再 start。
2. 视频层叠 UI 之上（9-23 真机结论）：触摸捕获层被画面盖住**看不见但点得到** ——
   LVGL 的 lv_indev 按对象树派发触摸，与视频层遮挡无关。
3. **视频分辨率上限 480×320**（mplayer 接口清单 2026-09-30）：s_video_rgb_buf 是
   固定静态缓冲，超出会缓冲区溢出。本模块在 open 后用 info() 宽高预检拦截
   （reason="oversize"），超限素材不起播。
4. 画面残留用 set_layer_visible(player,false) 根治（接口清单确认有该 API，
   9-23 时缺的就是它）：收尾一律先藏图层再 stop。set_rect(player,x,y) 传的是
   **图层坐标**、-1 = 该方向居中（mp4_test 传 -1,-1 即全屏居中）；接口清单
   （2026-09-30，按绑定注册表整理）确认绑定有 set_rect/set_layer_visible，
   旧固件可能没有 —— 防御式调用，取不到就跳过。
5. MP4 音频由 mplayer 自己的 AUDIO_V2 通路输出，不经 exaudio 的音量/功放管理 ——
   PA 功放按 hw.audio 配置手动使能（同 mp4_test 里 gpio 拉功放脚的做法），
   音量暂时跟不了系统音量（真机验证点）。

@api mp4_takeover.start(path, o)  开始一次全屏接管播放；o.on_done(reason) 结束时回调
                                 reason: "eos" 播完 | "touch" 点屏幕退出 |
                                         "error" 起播失败 | "oversize" 超 480×320 上限 |
                                         "stop" 外部停止
                                 返回是否成功进入接管（mplayer 不可用/文件不存在时 false）
@api mp4_takeover.stop()          安全结束当前接管（没有接管时是空操作）
@api mp4_takeover.is_active()     是否有接管正在跑
]]

local theme = require "ui_theme"
local video_util = require "video_util"
local ok_exaudio, exaudio = pcall(require, "exaudio")
if not ok_exaudio then exaudio = nil end

local M = {}

local session = nil          -- 当前接管会话（nil = 没有接管在跑）
local window_id = nil
local bg = nil               -- 全屏黑底（兼触摸捕获层）
local hint = nil             -- 提示文案（起播前可见；播放中被视频层盖住）

local POLL_MS = 100          -- is_playing 轮询间隔（mp4_test 同款口径）

--[[视频分辨率上限（mplayer 接口清单 2026-09-30）：s_video_rgb_buf 是固定静态缓冲，
超出会缓冲区溢出 —— 起播前必须拦住超限素材。]]
local MP4_MAX_W = 480
local MP4_MAX_H = 320

-- ==================== PA 功放 ====================
--[[mplayer 的音频不经 exaudio，功放脚只能自己拉（mp4_test 里就是直接 gpio 使能）。
电平与引脚从板级配置 hw.audio 读（pa_ctrl / pa_on_level），各板不写死。]]
local function pa_on()
    local ac = _G.project_config and _G.project_config.hw and _G.project_config.hw.audio
    if ac and ac.pa_ctrl then
        pcall(gpio.setup, ac.pa_ctrl, ac.pa_on_level or 0)
    end
end

local function pa_off()
    local ac = _G.project_config and _G.project_config.hw and _G.project_config.hw.audio
    if ac and ac.pa_ctrl then
        -- 与使能反相；exaudio 下次播放会按自己的时序重新管理这只脚
        pcall(gpio.setup, ac.pa_ctrl, (ac.pa_on_level == 1) and 0 or 1)
    end
end

--[[内存水位（诊断用）

rtos.meminfo() = Lua 虚拟机堆；"sys" = 系统堆（mplayer 的 open ~600KB 与
play 的 yuv_queue 都从这走）；"psram" = PSRAM。
卡死会话释放不干净时 sys 水位会一路走低 —— yuv_queue_alloc failed /
image malloc fail(-6) 都是它见底的下游症状，看这里能直接定案。]]
local function mem_info_str()
    local function one(t)
        local ok, v
        if t then ok, v = pcall(rtos.meminfo, t) else ok, v = pcall(rtos.meminfo) end
        return ok and tostring(v) or "?"
    end
    return string.format("lua=%s sys=%s psram=%s", one(nil), one("sys"), one("psram"))
end

-- ==================== 会话收尾 ====================
local function teardown_player(s)
    if s.player then
        local p = s.player
        s.player = nil
        --[[先藏视频图层再停：set_layer_visible(false) 不动解码/音频、立刻露出 UI，
        根治 stop/close 后画面残留（9-23 真机翻车点，当时绑定没这个 API）。
        旧固件没有该 API 时防御式跳过。]]
        if mplayer.set_layer_visible then
            pcall(mplayer.set_layer_visible, p, false)
        end
        local ok_s, ret_s = pcall(mplayer.stop, p)
        local ok_c, ret_c = pcall(mplayer.close, p)
        --[[stop/close 返回 bool（接口清单）；false 或 pcall 失败意味着 C 层
        释放没做完 —— open 的 ~600KB + yuv_queue 就回不来了，之后所有 malloc
        都会挂（mp4 的 yuv_queue_alloc failed / hzv 的 image malloc fail -6）。
        绑定层 close 调完即把指针置 NULL、无法重试，只能记录上报 + 重启回收。]]
        if not (ok_s and ret_s ~= false) then
            log.warn("mp4_takeover", "mplayer.stop 返回异常", tostring(ret_s), mem_info_str())
        end
        if not (ok_c and ret_c ~= false) then
            log.warn("mp4_takeover", "mplayer.close 返回异常，堆资源可能泄漏", tostring(ret_c), mem_info_str())
        end
    end
    pa_off()
end

--[[结束一次接管：收播放器、关窗、回调

幂等是必须的：EOS 轮询、点屏幕、宿主清子树关窗、外部 stop 都可能撞到一起。
reason 取值见文件头 @api。]]
local function finish(reason)
    local s = session
    if not s or s.finished then return end
    s.finished = true
    teardown_player(s)
    local wid = window_id
    window_id = nil
    session = nil
    if wid then pcall(exwin.close, wid) end   -- 触发 on_destroy 清 UI
    log.info("mp4_takeover", "finish", reason)
    if s.on_done then pcall(s.on_done, reason) end
end

local function on_destroy()
    --[[外部关窗（宿主清自己的子树时连带把本窗收掉）：没走 finish 的话
    在这里兜底收播放器并回调 —— 否则 mplayer 的解码线程会一直跑。]]
    local s = session
    if s then
        session = nil
        s.finished = true
        teardown_player(s)
        if s.on_done then pcall(s.on_done, "stop") end
    end
    if bg then pcall(function() bg:destroy() end); bg = nil end
    hint = nil
    window_id = nil
end

-- ==================== 窗口构建 ====================
local function on_touch()
    finish("touch")
end

local function on_create(path)
    --[[逻辑屏幕尺寸（旋转后的）：本窗不改旋转 —— 宿主是什么方向就是什么方向，
    退出后不用做任何还原（video_win 的横屏是它自己 enter_landscape 的事）。]]
    local w, h
    if airui.status then
        local ok, st = pcall(airui.status)
        if ok and type(st) == "table" and st.w and st.h and st.w > 0 and st.h > 0 then
            w, h = st.w, st.h
        end
    end
    if not w and display and display.getSize then
        local ok, dw, dh = pcall(display.getSize)
        if ok and dw and dh and dw > 0 and dh > 0 then w, h = dw, dh end
    end
    w = w or 480
    h = h or 854

    --[[全屏黑底兼触摸捕获层：先于视频起播存在，点任意处结束接管。
    theme.card 底下是 airui.container（可点击），视频层盖在它上面**不影响
    触摸派发** —— LVGL 按对象树找可点击对象，与显示遮挡无关。]]
    bg = theme.card(airui.screen, {
        x = 0, y = 0, w = w, h = h,
        color = theme.C.black, opa = 255, border_w = 0, radius = 0,
        on_click = on_touch,
    })
    hint = theme.label(bg, {
        x = 0, y = math.floor(h / 2) - 13, w = w, h = 28,
        text = "点击屏幕退出播放",
        px_size = 20, color = theme.C.t3,
        align = airui.TEXT_ALIGN_CENTER,
        on_click = on_touch,
    })
end

--[[接管主流程（协程）

先 sys.wait(1) 让宿主的调用栈（窗口 on_create / 选择器 on_pick）跑完再开窗，
避免在宿主窗口创建过程中嵌套 exwin.open 打乱焦点簿记。]]
local function session_main(s)
    sys.wait(1)
    if s ~= session or s.finished then return end

    window_id = exwin.open({
        on_create = function() on_create(s.path) end,
        on_destroy = on_destroy,
        on_get_focus = function() end,
        on_lose_focus = function() end,
    })
    if not window_id then
        session = nil
        log.warn("mp4_takeover", "exwin.open failed", s.path)
        if s.on_done then pcall(s.on_done, "error") end
        return
    end

    --[[mplayer 流程（mp4_test 验证过的顺序）：PA 使能 → open → 宽高预检 →
    set_rect → play。set_rect(player,x,y) 传图层坐标，-1 = 该方向居中
    （mp4_test 传 -1,-1 即全屏居中）；旧固件没有该 API 时防御式跳过。]]
    --[[先强制 GC 再 open：上个会话的 player userdata 若还滞留，__gc 会兜底
    close（绑定挂了 __gc）把系统堆还回来；open 一次就是 ~600KB+。
    起播前留一条内存水位：卡死重播失败时前后对比能直接看出堆去哪了。]]
    pcall(collectgarbage, "collect")
    log.info("mp4_takeover", "mem before open", mem_info_str())
    pa_on()
    local ok, player = pcall(mplayer.open, s.path)
    s.player = (ok and player) or nil
    if not s.player then
        log.warn("mp4_takeover", "mplayer.open failed", s.path, mem_info_str())
        finish("error")
        return
    end
    --[[分辨率预检（接口清单：超过 480×320 会溢出静态缓冲）：
    info() 的宽高在 open 阶段就从 demux 填好了，不用等解码。]]
    local ok_i, inf = pcall(mplayer.info, s.player)
    if ok_i and type(inf) == "table" and inf.width and inf.height
        and (inf.width > MP4_MAX_W or inf.height > MP4_MAX_H) then
        log.warn("mp4_takeover", "分辨率超限，拒绝起播", inf.width, inf.height,
            "上限", MP4_MAX_W, "x", MP4_MAX_H, s.path)
        finish("oversize")
        return
    end
    if mplayer.set_rect then
        pcall(mplayer.set_rect, s.player, -1, -1)
    end
    local pok, pret = pcall(mplayer.play, s.player)
    if not (pok and pret) then
        log.warn("mp4_takeover", "mplayer.play failed", s.path, mem_info_str())
        finish("error")
        return
    end

    --[[轮询到 EOS（is_playing 变 false 就是播完了 —— 本形态没有暂停）。
    整段 pcall 包住：轮询里出错也必须走到 finish，否则会话悬死、player
    不 close，那 ~1MB 系统堆就再也回不来（接口清单要点 1：不 close 必漏）。]]
    local ok_poll = pcall(function()
        while s.player and not s.finished and mplayer.is_playing(s.player) do
            sys.wait(POLL_MS)
        end
    end)
    if not ok_poll then
        log.warn("mp4_takeover", "轮询异常，强制收尾", mem_info_str())
    end
    if not s.finished then
        finish(ok_poll and "eos" or "error")
    end
end

-- ==================== 对外接口 ====================
--[[开始一次全屏接管播放

@string path  MP4 文件路径
@table  o     { on_done = function(reason) }
@return boolean 是否成功进入接管（已在接管 / 文件不存在 / 固件无 mplayer 时 false，
                不回调 on_done —— 调用方按「无法播放」处理）]]
function M.start(path, o)
    if session then return false end
    if type(path) ~= "string" or path == "" or not io.exists(path) then return false end
    if not mplayer then
        log.warn("mp4_takeover", "固件没有 mplayer 绑定，MP4 无法播放", path)
        return false
    end

    --[[先把宿主残留的音频停掉：桌面/全屏页的 HZV 音轨、同名 MP3 都走 exaudio，
    不停会和 mplayer 的声音叠着响。]]
    video_util.audio_stop()
    if exaudio then pcall(exaudio.play_stop, { type = 0 }) end

    o = o or {}
    session = {
        path = path,
        on_done = o.on_done,
        finished = false,
    }
    log.info("mp4_takeover", "start", path)
    sys.taskInit(session_main, session)
    return true
end

--- 安全结束当前接管（没有接管时是空操作）
function M.stop()
    if session then finish("stop") end
end

--- 是否有接管正在跑
function M.is_active()
    return session ~= nil
end

return M
