--[[
@module  mp4_loop
@summary MP4 层叠循环播放（mplayer）—— 摆到指定屏幕矩形循环播，不全屏
@version 1.0
@date    2026.10.03
@author  江访

=== 与 mp4_takeover 的分工 ===
mp4_takeover = 全屏接管、单次播放、点屏幕退出（video_win / 开机等「看片」场景）；
本模块 = 把 mplayer 的视频层摆到指定屏幕矩形、循环播放，给桌面播放器（idle_win）
当嵌入式播放器用。两边共用同一套 mplayer 约束（见下），但形态不同，
状态机拆开两个模块互不污染。

为什么 MP4 不走 airui.video：固件 C 层 H.264 解码栈溢出，嵌入路径禁播
（video_util 的 MP4_PLAYBACK_ENABLED = false，详见 video_util 文件头）。

=== mplayer 的三个硬约束（接口清单 2026-09-30）===
1. 视频层是屏幕级图层，叠在所有 LVGL UI 之上 —— 没有「嵌进容器」一说，
   只能 set_rect(x,y) 把图层**摆到**目标矩形上方，视觉上「嵌入」：
   矩形内的 UI 被盖住（矩形外不受影响）；触摸派发按 LVGL 对象树走、
   与图层遮挡无关，视频下面的控件照样点得到。
2. 无 loop API —— 循环靠轮询 is_playing，EOS 后再 play()（play 在 EOS/stop 后
   = fseek 0 从头重播）。同文件跨循环**复用同一个 player**：每次 open 要
   ~600KB 系统堆，且 close 的释放清单不含 yuv_queue（已知堆泄漏），
   反复 open/close 会把系统堆掏空（yuv_queue_alloc failed 是它的下游症状）。
3. 暂停必须 pause()/resume() —— play() 当「恢复」用会从头重播。

分辨率硬上限 480×320（s_video_rgb_buf 静态缓冲，超出缓冲区溢出），超限拒播。
声音走 mplayer 自己的 AUDIO_V2 通路：PA 按 hw.audio 手动使能，
音量暂不跟系统音量（已知限制，同 mp4_takeover）。

@api mp4_loop.start(path, o)  起播。o.x/o.y = 图层左上角（屏幕绝对坐标，
                              -1 = 该方向居中）；o.loop = 是否循环（默认 true）；
                              o.on_eos() = 单次播完（loop=false 时）或放弃循环时回调。
                              返回是否成功起播（文件不存在 / 无 mplayer / 超限 / 起播失败时 false）
@api mp4_loop.stop()          停止并释放播放器（幂等，没有会话时是空操作）
@api mp4_loop.pause()         暂停（画面停帧）
@api mp4_loop.resume()        续播：暂停恢复走 mplayer.resume；单次播完后再按 = 从头重播
@api mp4_loop.set_loop(b)     切换循环开关（不打断当前播放，切完即生效）
@api mp4_loop.is_active()     是否有会话在跑
]]

local video_util = require "video_util"
local ok_exaudio, exaudio = pcall(require, "exaudio")
if not ok_exaudio then exaudio = nil end

local M = {}

local session = nil          -- 当前会话（nil = 没有在跑）
local POLL_MS = 100          -- is_playing 轮询间隔（对齐 mp4_takeover 口径）

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
play 的 yuv_queue 都从这走）；"psram" = PSRAM。重播失败时看这里能直接定案。]]
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
        --[[先藏视频图层再停：set_layer_visible(false) 不动解码/音频、立刻露出底下的 UI，
        根治 stop/close 后画面残留（9-23 真机翻车点）。旧固件没有该 API 时防御式跳过。]]
        if mplayer.set_layer_visible then
            pcall(mplayer.set_layer_visible, p, false)
        end
        local ok_s, ret_s = pcall(mplayer.stop, p)
        local ok_c, ret_c = pcall(mplayer.close, p)
        --[[stop/close 返回 bool（接口清单）；false 或 pcall 失败意味着 C 层
        释放没做完 —— open 的 ~600KB + yuv_queue 就回不来了。绑定层 close 调完
        即把指针置 NULL、无法重试，只能记录上报（必要时重启回收）。]]
        if not (ok_s and ret_s ~= false) then
            log.warn("mp4_loop", "mplayer.stop 返回异常", tostring(ret_s), mem_info_str())
        end
        if not (ok_c and ret_c ~= false) then
            log.warn("mp4_loop", "mplayer.close 返回异常，堆资源可能泄漏", tostring(ret_c), mem_info_str())
        end
    end
    pa_off()
    -- 音频通路把触摸总线留在被重置状态，收摊时恢复一次让触摸立刻回来
    video_util.tp_bus_restore()
end

--[[循环泵：轮询 is_playing，确认停了才动手（协程，sys.wait 让出）

两个防抖设计，都是被 mplayer 的状态过渡逼出来的：
1. 连续 2 次（约 200ms）确认没在播才重播 —— pause/resume 过渡、play 起播
   的瞬间 is_playing 可能短暂为假，立刻重播会把「暂停」变成「从头播」；
2. 重播后从未确认过在播（起播即停）连续 3 次就放弃循环 —— 坏文件会在
   「play → 立即 EOS → play」里打转，每 200ms 一轮重播风暴，必须掐掉。
单次播放（loop=false）走到 EOS 就把 want_play 落掉、回调 on_eos，泵转入空转，
等 resume（从头重播）或 stop。]]
local function pump_main(s)
    local ticks = 0
    while s == session and not s.finished do
        --[[触摸总线守护：mplayer 的 AUDIO_V2 走 C 层，启动/重播音频时无条件
        i2c.setup 把触摸总线重置回中断模式 → GT911 读超时、触摸失灵
        （i2c_failed: 从机地址5d），且播完没人恢复会一直瞎（见 video_util.tp_bus_restore）。
        每 500ms 恢复一次：音频启动是异步的（起播后约 0.4s），只在收尾恢复救不了
        播放中点控制栏；恢复本身只是一次 i2c.setup，开销可忽略。]]
        ticks = ticks + 1
        if ticks % 5 == 0 then video_util.tp_bus_restore() end
        if s.want_play and not s.paused and s.player then
            local ok, playing = pcall(mplayer.is_playing, s.player)
            if ok and playing then
                s.fail_streak = 0
                s.good_since_replay = true
            else
                s.fail_streak = s.fail_streak + 1
                if s.fail_streak >= 2 then
                    s.fail_streak = 0
                    if not s.loop then
                        log.info("mp4_loop", "单次播放完毕")
                        s.want_play = false
                        if s.on_eos then pcall(s.on_eos) end
                    elseif not s.good_since_replay then
                        -- 上一轮重播后一次都没播起来：起播即停，连续 3 次放弃
                        s.bad_replays = s.bad_replays + 1
                        if s.bad_replays >= 3 then
                            log.warn("mp4_loop", "重播后无法起播，放弃循环", mem_info_str())
                            s.want_play = false
                            if s.on_eos then pcall(s.on_eos) end
                        end
                    else
                        -- play 在 EOS 后 = fseek 0 从头重播（接口清单）；
                        -- 复用同一个 player，不 open/close（见文件头约束 2）
                        s.good_since_replay = false
                        s.bad_replays = 0
                        local pok = pcall(mplayer.play, s.player)
                        if not pok then
                            log.warn("mp4_loop", "循环重播失败", mem_info_str())
                            s.want_play = false
                            if s.on_eos then pcall(s.on_eos) end
                        end
                    end
                end
            end
        end
        sys.wait(POLL_MS)
    end
end

-- ==================== 对外接口 ====================
--[[起播一次层叠循环播放

@string path 素材路径（MP4）
@table  o    { x, y, loop, on_eos }，见文件头 @api
@return boolean 是否成功起播]]
function M.start(path, o)
    if session then return false end
    if type(path) ~= "string" or path == "" or not io.exists(path) then return false end
    if not mplayer then
        log.warn("mp4_loop", "固件没有 mplayer 绑定，MP4 无法播放", path)
        return false
    end
    o = o or {}

    --[[先把宿主残留的音频停掉：HZV 音轨、同名 MP3 都走 exaudio，
    不停会和 mplayer 的声音叠着响。]]
    video_util.audio_stop()
    if exaudio then pcall(exaudio.play_stop, { type = 0 }) end

    --[[强制 GC 再 open：上个会话的 player userdata 若还滞留，__gc 会兜底
    close 把系统堆还回来；open 一次就是 ~600KB+。起播前留一条内存水位。]]
    pcall(collectgarbage, "collect")
    log.info("mp4_loop", "mem before open", mem_info_str())
    pa_on()
    local ok, player = pcall(mplayer.open, path)
    local s = {
        path = path,
        player = (ok and player) or nil,
        x = o.x or -1,
        y = o.y or -1,
        loop = (o.loop ~= false),   -- 默认循环
        on_eos = o.on_eos,
        want_play = true,
        paused = false,
        finished = false,
        fail_streak = 0,
        bad_replays = 0,
        good_since_replay = true,   -- 首播不算「重播后没播起来」
    }
    if not s.player then
        log.warn("mp4_loop", "mplayer.open failed", path, mem_info_str())
        pa_off()
        return false
    end

    --[[分辨率预检（接口清单：超过 480×320 会溢出静态缓冲）：
    info() 的宽高在 open 阶段就从 demux 填好了，不用等解码。]]
    local ok_i, inf = pcall(mplayer.info, s.player)
    if ok_i and type(inf) == "table" and inf.width and inf.height
        and (inf.width > MP4_MAX_W or inf.height > MP4_MAX_H) then
        log.warn("mp4_loop", "分辨率超限，拒绝起播", inf.width, inf.height,
            "上限", MP4_MAX_W, "x", MP4_MAX_H, path)
        teardown_player(s)
        return false
    end

    --[[set_rect 传图层左上角的屏幕绝对坐标，-1 = 该方向居中。
    旧固件没有该 API 时防御式跳过（画面会落在默认位置，不再是「嵌入」观感）。]]
    if mplayer.set_rect then
        pcall(mplayer.set_rect, s.player, s.x, s.y)
    end
    local pok, pret = pcall(mplayer.play, s.player)
    if not (pok and pret) then
        log.warn("mp4_loop", "mplayer.play failed", path, mem_info_str())
        teardown_player(s)
        return false
    end

    session = s
    log.info("mp4_loop", "playing", path, s.x, s.y, "loop=", s.loop)
    sys.taskInit(pump_main, s)
    return true
end

--- 停止并释放播放器（幂等；没有会话时是空操作）
function M.stop()
    local s = session
    if not s then return end
    session = nil
    s.finished = true
    teardown_player(s)
    log.info("mp4_loop", "stop")
end

--- 暂停（画面停帧）。没有会话时是空操作
function M.pause()
    local s = session
    if not s then return end
    s.paused = true
    s.want_play = false
    pcall(mplayer.pause, s.player)
end

--[[续播

暂停恢复走 mplayer.resume（接口清单：play 当「恢复」用会从头重播）；
单次播完 / 暂停态之外的「没在播」则用 play —— EOS 后 play 就是从头重播。]]
function M.resume()
    local s = session
    if not s then return end
    s.paused = false
    s.want_play = true
    s.fail_streak = 0
    s.good_since_replay = true
    s.bad_replays = 0
    local ok_p, paused = pcall(mplayer.is_paused, s.player)
    if ok_p and paused then
        pcall(mplayer.resume, s.player)
    else
        pcall(mplayer.play, s.player)   -- EOS 后从头
    end
end

--- 切换循环开关（不打断当前播放，下一次 EOS 起生效）
function M.set_loop(v)
    if session then session.loop = (v and true or false) end
end

--- 是否有会话在跑
function M.is_active()
    return session ~= nil
end

return M
