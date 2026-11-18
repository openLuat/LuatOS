--[[
@module app_audio
@summary 音乐播放器音频后端：Air8603 / Air1603 内置 DAC 播放 6 秒示例 MP3
@version 1.0.0
@usage
1、音频文件：audio/demo_10s.mp3（文件名沿用旧名，内容实际为官方 6 秒示例 MP3）。
2、烧录时把 demo_10s.mp3 也加进 Luatools（脚本区或资源区均可）；
   不同上传方式落点不同，代码按下面的候选路径依次探测。
3、音频后端：Air1603 固定走 exaudio.play_start（官方 Air1603 路径）；
   没有 exaudio 时才退回旧 audio，不会直调 audio_v2 导致闪退。
4、功放：AUDIOPA_EN = GPIO73，高电平使能，由 exaudio.setup 管理。
]]

local sys = require "sys"

local M = {}
local TAG = "app_audio"

local PIN_AUDIO_PA = 73
local PA_ON_LEVEL  = 1
local PA_OFF_LEVEL = 0
-- 与官方 demo/audio/Air1601&Air1603/play_file.lua 保持一致
local AUDIO_CFG = {
    model         = "dac",
    pa_ctrl       = PIN_AUDIO_PA,
    pa_on_level   = PA_ON_LEVEL,
    dac_delay     = 6,
    pa_delay      = 10,     -- DAC 稳定后再开 PA
    dac_time_delay = 600,   -- 停止时先关 PA 再关 DAC，防爆音
}

local FALLBACK_PATHS = {
    "/luadb/audio/demo_10s.mp3",
    "/luadb/demo_10s.mp3",
    "/audio/demo_10s.mp3",
    "/res/demo_10s.mp3",
    "/demo_10s.mp3",
}

local S = {
    ready    = false,
    backend  = "none",
    source   = "none",
    path     = nil,
    playing  = false,
    paused   = false,
    started  = false,
    need_stop = false,
    restart_after = 0,
    pos_ms   = 0,
    dur_ms   = 6000,
    volume   = 40,
    vol_applied = nil,
}
M.S = S

local exaudio, old_audio
local start_ms = 0
-- 官方要求 exaudio.play_start/play_stop 只能在 task 中调用；
-- UI 点击回调不属于 task，统一把命令投递到专用音频 task。
local pending_cmd = nil

function M.now_ms()
    -- 回到当初“能完整播放”的版本：只走 mcu.ticks，不调用 ticks2。
    -- Air1603 hz=50，这里的值不是毫秒，只用于音频后端内部记时；
    -- UI 进度改由 page_music 自己的 100ms 任务按 1 秒/10 拍推进。
    if mcu and mcu.ticks then
        local hz = (mcu.hz and mcu.hz()) or 1000
        local v = mcu.ticks()
        if hz > 1000 then return math.floor(v * 1000 / hz) end
        return v
    end
    return 0
end

local MP3_BR_V1 = {
    [1]=32,[2]=40,[3]=48,[4]=56,[5]=64,[6]=80,[7]=96,
    [8]=112,[9]=128,[10]=160,[11]=192,[12]=224,[13]=256,[14]=320,
}
local MP3_BR_V2 = {
    [1]=8,[2]=16,[3]=24,[4]=32,[5]=40,[6]=48,[7]=56,
    [8]=64,[9]=80,[10]=112,[11]=128,[12]=144,[13]=160,
}
local MP3_SR = {
    [3] = { 44100, 48000, 32000 },
    [2] = { 22050, 24000, 16000 },
    [0] = { 11025, 12000, 8000 },
}

local function probe_duration(path)
    local f = io.open(path, "rb")
    if not f then return 0 end
    local size = f:seek("end") or 0
    f:seek("set", 0)
    local head = f:read(4096) or ""
    f:close()
    if #head < 32 then return 0 end

    local base = 0
    if head:sub(1, 3) == "ID3" then
        -- ID3v2 尺寸是字节 7~10（Lua 1-based，0-based 的 6~9）
        local a, b, c, d = head:byte(7, 10)
        base = 10 + ((a or 0) * 2097152 + (b or 0) * 16384
            + (c or 0) * 128 + (d or 0))
    end
    local pos
    for i = base + 1, math.min(#head - 3, base + 3000) do
        local b1, b2 = head:byte(i, i + 1)
        if b1 == 0xFF and b2 and b2 >= 224 then
            local ver = math.floor(b2 / 8) % 4
            local layer = math.floor(b2 / 2) % 4
            if ver ~= 1 and (layer == 1 or layer == 2) then
                pos = i
                break
            end
        end
    end
    if not pos then return 0 end

    local b2, b3 = head:byte(pos + 1, pos + 2)
    local ver = math.floor(b2 / 8) % 4
    local bri = math.floor(b3 / 16) % 16
    local sri = math.floor(b3 / 4) % 4
    local br = (ver == 3) and MP3_BR_V1[bri] or MP3_BR_V2[bri]
    local srtab = MP3_SR[ver]
    if not br or not srtab or sri > 2 or not srtab[sri + 1] then return 0 end
    local audio_bytes = size - (pos - 1)
    if audio_bytes <= 0 then return 0 end
    local ms = math.floor(audio_bytes * 8 * 1000 / (br * 1000))
    if ms <= 0 or ms > 3600000 then return 0 end
    return ms
end

local function find_fallback()
    for _, p in ipairs(FALLBACK_PATHS) do
        if io.exists and io.exists(p) then return p end
    end
    return nil
end

local function audio_init()
    local lib = rawget(_G, "exaudio")
    if not lib then
        local ok, r = pcall(require, "exaudio")
        if ok then lib = r end
    end

    if lib then
        exaudio = lib
        if lib.version then pcall(function() log.info(TAG, "exaudio", lib.version()) end) end
        local ok2, ret = pcall(lib.setup, AUDIO_CFG)
        if ok2 and ret ~= false and lib.play_start and lib.play_stop then
            pcall(lib.vol, S.volume)
            sys.wait(100)
            -- 关键：按官方 Air1603 demo 走 exaudio.play_start，
            -- 不直接调 audio_v2.play/get_play_clock，避免播放后闪退。
            S.backend = "exaudio"
            log.info(TAG, "后端 exaudio.play_start（官方 Air1603 路径）")
            return true
        else
            log.warn(TAG, "exaudio.setup 失败，尝试旧 audio 框架", ok2, ret)
        end
    else
        log.warn(TAG, "exaudio 不可用，尝试旧 audio 框架")
    end

    local au = rawget(_G, "audio")
    if au and au.play and au.config then
        old_audio = au
        S.backend = "audio"
        pcall(au.config, 0, PIN_AUDIO_PA, 1, 6, 10)
        pcall(au.setVolume and au.setVolume or au.vol, S.volume)
        log.info(TAG, "后端 audio（旧框架，暂停近似停止）")
        return true
    end
    log.error(TAG, "没有可用音频后端：exaudio / audio 均不可用")
    return false
end

local function play_done(event)
    if exaudio and event == exaudio.PLAY_DONE then
        S.playing = false
        S.pos_ms = S.dur_ms
        S.need_stop = true
        sys.publish("APP_AUDIO_DONE")
        log.info(TAG, "播放完成回调，等待关闭 DAC/PA")
    end
end

function M.init()
    local p = find_fallback()
    if p then
        S.path = p
        S.source = "flash"
        -- 官方 sample-6s.mp3 内容就是 6 秒；探测值受 VBR 影响会偏大，
        -- 这里直接用实际时长，避免 UI 进度和播放结束对不上。
        S.dur_ms = 6000
    else
        log.error(TAG, "未找到 demo_10s.mp3，请检查烧录资源")
    end

    S.ready = audio_init()
    if S.ready then M.set_volume(S.volume) end
    log.info(TAG, "初始化完成", "backend=" .. S.backend,
        "path=" .. tostring(S.path), "dur=" .. tostring(S.dur_ms))
    return S.ready
end

-- 真正的起播：只在专用音频 task 里执行
local function do_play()
    if not S.ready or not S.path then return false end

    -- 已经在 300ms 收尾窗口里，重复点击/切歌直接忽略，不要重置计时
    if S.restart_after > 0 then
        if M.now_ms() < S.restart_after then return true end
        S.restart_after = 0
    end

    -- 旧播放未结束就再次 play_start，约 2 秒后会整机复位；先停再等 300ms
    if S.playing or S.started then
        if S.backend == "exaudio" then
            pcall(exaudio.play_stop, { type = 0 })
            pcall(gpio.setup, PIN_AUDIO_PA, PA_OFF_LEVEL)
        elseif S.backend == "audio" then
            pcall(old_audio.play, 0)
        end
        S.playing = false
        S.started = false
        S.paused = false
        S.need_stop = false
        S.restart_after = M.now_ms() + 300
        log.info(TAG, "上一首未结束，先停止，300ms 后重播")
        return true
    end

    local ok = false
    if S.backend == "exaudio" then
        local called, ret = pcall(exaudio.play_start, {
            type = 0, content = S.path, cbfnc = play_done,
        })
        ok = called and ret ~= false
        log.info(TAG, "exaudio.play_start", called, ret)
    elseif S.backend == "audio" then
        ok = old_audio.play(0, S.path) and true or false
        log.info(TAG, "audio.play", ok)
    end
    S.playing = ok
    S.paused = false
    S.started = ok
    S.need_stop = false
    S.restart_after = 0
    S.pos_ms = 0
    start_ms = M.now_ms()
    log.info(TAG, ok and "起播" or "起播失败", S.path)
    return ok
end

-- UI 点击回调不是 task，不能直接调 play_start；投递给专用 task
function M.play()
    if not S.ready or not S.path then return false end
    pending_cmd = "play"
    return true
end

function M.resume_or_play()
    if S.playing then return true end
    if S.paused and S.backend == "audio" then
        pcall(old_audio.pause, 0, false)
        S.paused = false
        S.playing = true
        return true
    end
    -- exaudio 没有真暂停，继续播放按官方方式重新起播
    return M.play()
end

-- 真正的停止：同样只在音频 task 里执行
local function do_stop(paused)
    if S.backend == "exaudio" then
        pcall(exaudio.play_stop, { type = 0 })
        pcall(gpio.setup, PIN_AUDIO_PA, PA_OFF_LEVEL)
    elseif S.backend == "audio" then
        if paused then pcall(old_audio.pause, 0, true)
        else pcall(old_audio.play, 0) end
    end
    S.playing = false
    S.paused = paused and true or false
    S.started = false
    S.need_stop = false
    S.restart_after = 0
    S.pos_ms = 0
end

function M.pause()
    if not S.playing then return false end
    pending_cmd = "pause"
    S.playing = false
    S.paused = true
    S.started = false
    return true
end

function M.stop()
    pending_cmd = "stop"
    S.playing = false
    S.paused = false
    S.started = false
    S.need_stop = false
    S.restart_after = 0
    S.pos_ms = 0
end

-- 专用音频 task：官方文档明确 play_start/play_stop 只能在 task 中调用
local function audio_cmd_task()
    while true do
        if pending_cmd then
            local cmd = pending_cmd
            pending_cmd = nil
            local ok, err = pcall(function()
                if cmd == "play" then
                    do_play()
                elseif cmd == "pause" then
                    do_stop(true)
                elseif cmd == "stop" then
                    do_stop(false)
                end
            end)
            if not ok then log.error(TAG, "audio task error", err) end
        end
        sys.wait(20)
    end
end
sys.taskInit(audio_cmd_task)

function M.set_volume(v)
    v = math.floor(v or 40)
    if v < 0 then v = 0 elseif v > 100 then v = 100 end
    if S.volume == v and S.vol_applied == v then return v end
    S.volume = v
    if exaudio and exaudio.vol then
        pcall(exaudio.vol, v)
    elseif old_audio then
        if old_audio.setVolume then pcall(old_audio.setVolume, v)
        elseif old_audio.vol then pcall(old_audio.vol, v) end
    end
    S.vol_applied = v
    return v
end

function M.update()
    if not S.ready then return end

    -- 播放结束后主动关 DAC/PA，消掉尾音“吱吱”电流声
    if S.need_stop then
        S.need_stop = false
        S.started = false
        if S.backend == "exaudio" then
            pcall(exaudio.play_stop, { type = 0 })
            -- REQUEST_END 后 audio_v2_request_index 已清空，play_stop 会直接返回；
            -- 直接把 PA 拉低即可切断底噪，不用 pm(SHUTDOWN) 去 deactivate 驱动。
            pcall(gpio.setup, PIN_AUDIO_PA, PA_OFF_LEVEL)
        elseif S.backend == "audio" then
            pcall(old_audio.play, 0)
        end
        log.info(TAG, "播放结束，已关闭 DAC/PA")
    end

    -- 重叠播放被拦下后，在这里延迟起播，给音频任务留出收尾时间
    if S.restart_after > 0 and M.now_ms() >= S.restart_after then
        M.play()
        return
    end

    if not S.playing then return end
    S.pos_ms = M.now_ms() - start_ms
    if S.pos_ms < 0 then S.pos_ms = 0 end
    if S.dur_ms > 0 and S.pos_ms >= S.dur_ms then
        S.pos_ms = S.dur_ms
        S.playing = false
        S.need_stop = true
        sys.publish("APP_AUDIO_DONE")
        log.info(TAG, "播放完成（估算），等待关闭 DAC/PA")
    end
end

function M.position_ms() return S.pos_ms end
function M.duration_ms() return S.dur_ms end
function M.active() return S.playing or S.paused end
function M.started() return S.started end
function M.path() return S.path end

return M
