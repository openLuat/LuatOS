--[[
@module  mp4_loop
@summary MP4 层叠循环播放（mplayer）—— 视频层定位到指定屏幕矩形循环播放
@version 1.0
@date    2026.10.03
@author  江访

@api mp4_loop.start(path, o)  起播。o.x/o.y=图层左上角屏幕绝对坐标（-1=该方向居中）；
                              o.loop=是否循环（默认 true）；o.on_eos()=单次播完/放弃回调。
                              返回是否成功起播
@api mp4_loop.stop()          停止并释放（幂等）
@api mp4_loop.pause()         暂停
@api mp4_loop.resume()        续播（暂停恢复；单次播完后再按=从头重播）
@api mp4_loop.set_loop(b)     切换循环开关（下一次 EOS 起生效）
@api mp4_loop.is_active()     是否有会话在跑
]]

local video_util = require "video_util"
local ok_exaudio, exaudio = pcall(require, "exaudio")
if not ok_exaudio then exaudio = nil end

local M = {}

local session = nil          -- 当前会话（nil = 没有在跑）
local POLL_MS = 100          -- is_playing 轮询间隔

-- 视频分辨率上限（s_video_rgb_buf 静态缓冲）
local MP4_MAX_W = 480
local MP4_MAX_H = 320

-- PA 功放使能/关闭（引脚与电平读板级 hw.audio）
local function pa_on()
    local ac = _G.project_config and _G.project_config.hw and _G.project_config.hw.audio
    if ac and ac.pa_ctrl then
        pcall(gpio.setup, ac.pa_ctrl, ac.pa_on_level or 0)
    end
end

local function pa_off()
    local ac = _G.project_config and _G.project_config.hw and _G.project_config.hw.audio
    if ac and ac.pa_ctrl then
        pcall(gpio.setup, ac.pa_ctrl, (ac.pa_on_level == 1) and 0 or 1)
    end
end

-- 内存水位（诊断用）
local function mem_info_str()
    local function one(t)
        local ok, v
        if t then ok, v = pcall(rtos.meminfo, t) else ok, v = pcall(rtos.meminfo) end
        return ok and tostring(v) or "?"
    end
    return string.format("lua=%s sys=%s psram=%s", one(nil), one("sys"), one("psram"))
end

-- 收播放器：先藏图层再 stop/close
local function teardown_player(s)
    if s.player then
        local p = s.player
        s.player = nil
        if mplayer.set_layer_visible then
            pcall(mplayer.set_layer_visible, p, false)
        end
        local ok_s, ret_s = pcall(mplayer.stop, p)
        local ok_c, ret_c = pcall(mplayer.close, p)
        if not (ok_s and ret_s ~= false) then
            log.warn("mp4_loop", "mplayer.stop 返回异常", tostring(ret_s), mem_info_str())
        end
        if not (ok_c and ret_c ~= false) then
            log.warn("mp4_loop", "mplayer.close 返回异常", tostring(ret_c), mem_info_str())
        end
    end
    pa_off()
    video_util.tp_bus_restore()
end

--[[循环泵：轮询 is_playing，EOS 后 play() 从头重播（复用 player）
连续 2 次确认没在播才重播；重播后起播即停累计 3 次放弃循环]]
local function pump_main(s)
    local ticks = 0
    while s == session and not s.finished do
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
                        s.bad_replays = s.bad_replays + 1
                        if s.bad_replays >= 3 then
                            log.warn("mp4_loop", "重播后无法起播，放弃循环", mem_info_str())
                            s.want_play = false
                            if s.on_eos then pcall(s.on_eos) end
                        end
                    else
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

-- 起播（参数见文件头 @api）
function M.start(path, o)
    if session then return false end
    if type(path) ~= "string" or path == "" or not io.exists(path) then return false end
    if not mplayer then
        log.warn("mp4_loop", "固件没有 mplayer 绑定", path)
        return false
    end
    o = o or {}

    -- 停掉残留的 exaudio 音频
    video_util.audio_stop()
    if exaudio then pcall(exaudio.play_stop, { type = 0 }) end

    pcall(collectgarbage, "collect")
    log.info("mp4_loop", "mem before open", mem_info_str())
    pa_on()
    local ok, player = pcall(mplayer.open, path)
    local s = {
        path = path,
        player = (ok and player) or nil,
        x = o.x or -1,
        y = o.y or -1,
        loop = (o.loop ~= false),
        on_eos = o.on_eos,
        want_play = true,
        paused = false,
        finished = false,
        fail_streak = 0,
        bad_replays = 0,
        good_since_replay = true,
    }
    if not s.player then
        log.warn("mp4_loop", "mplayer.open failed", path, mem_info_str())
        pa_off()
        return false
    end

    -- 分辨率预检
    local ok_i, inf = pcall(mplayer.info, s.player)
    if ok_i and type(inf) == "table" and inf.width and inf.height
        and (inf.width > MP4_MAX_W or inf.height > MP4_MAX_H) then
        log.warn("mp4_loop", "分辨率超限", inf.width, inf.height, path)
        teardown_player(s)
        return false
    end

    -- set_rect 传图层左上角坐标，-1=该方向居中
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

-- 停止并释放（幂等）
function M.stop()
    local s = session
    if not s then return end
    session = nil
    s.finished = true
    teardown_player(s)
    log.info("mp4_loop", "stop")
end

-- 暂停
function M.pause()
    local s = session
    if not s then return end
    s.paused = true
    s.want_play = false
    pcall(mplayer.pause, s.player)
end

-- 续播：暂停态走 resume，其余（EOS/未播）走 play 从头
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
        pcall(mplayer.play, s.player)
    end
end

-- 切换循环开关
function M.set_loop(v)
    if session then session.loop = (v and true or false) end
end

-- 是否有会话在跑
function M.is_active()
    return session ~= nil
end

return M
