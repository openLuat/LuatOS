--[[
@module  music
@summary 开机曲目演奏模块（有源蜂鸣器节奏版《铃儿响叮当》）
@version 1.0
@date    2026.10.08
@author  江访
@usage
本模块只负责曲谱数据与演奏节拍，声音输出全部由 buzzer_drv 完成。

曲目说明：
受硬件限制（本机为有源蜂鸣器，无音高概念），曲目为"同一音高 + 长短节奏"的节奏版，
结构 A-B-A，共 48 拍，BPM=160（每拍 375ms）→ 整曲约 18 秒。

对外接口：
1、music.play()        ：演奏一遍（含扬声器占用互斥，扬声器忙则拒绝本次播放）
2、music.duration_ms() ：返回整曲时长(ms)，供上层做日志/超时判断

节拍精度：
sys.wait 存在调度误差，几十个音符后会累积成明显走样；本模块以演奏起始时刻
（mcu.ticks()，开机至今毫秒数）为基准，逐音符按"目标时刻 - 当前时刻"做误差补偿，
因此整曲时长不随系统负载漂移。
]]

local buzzer_drv = require "buzzer_drv"

local music = {}

-- ==================== 演奏参数 ====================
local BPM        = 160              -- 每分钟拍数
local BEAT_MS    = math.floor(60000 / BPM)  -- 每拍时长(ms，必须为整数)，160BPM → 375ms
local GAP_MS     = 40               -- 音符之间的静音间隔(ms)，用于区分连音
local MIN_ON_MS  = 40               -- 最短发声时长(ms)，避免极短音符听不见
local LOCK_TAG   = "music"          -- 扬声器占用标记
local LOCK_WAIT  = 1000             -- 申请占用权的最大等待时长(ms)，覆盖按键音等短占用
local MAX_TICK   = 0x100000000      -- mcu.ticks() 为 32 位无符号，用于回绕计算

-- ==================== 曲谱 ====================
-- 记谱格式：数字=拍数（0.5 为八分音符），0=休止符，逗号分隔音符，竖线分隔小节（仅便于阅读）
-- 《铃儿响叮当》节奏版：A 段（叮 叮 叮—）+ B 段（哦 什么 乐趣…）+ A 段，共 48 拍
local SCORE = "1,1,2|1,1,2|1,1,1,1|2,2|"                 -- A 段 16 拍
           .. "1,0.5,0.5,1,1|1,0.5,0.5,1,1|1,1,1,1|2,2|"  -- B 段 16 拍
           .. "1,1,2|1,1,2|1,1,1,1|2,2"                   -- A 段 16 拍

-- 加载时一次性解析为拍数数组，运行时无解析开销
local steps = {}
for token in SCORE:gmatch("[^,|]+") do
    local beats = tonumber(token)
    if beats then
        steps[#steps + 1] = beats
    end
end

-- 整曲理论时长（各音符时长之和）
local total_ms = 0
for _, beats in ipairs(steps) do
    total_ms = total_ms + beats * BEAT_MS
end

--[[
返回整曲时长（理论值，ms）

@api music.duration_ms
@return number 整曲时长(ms)
]]
function music.duration_ms()
    return math.floor(total_ms + 0.5)
end

--[[
等待到相对基准时刻的指定时间点。
分片等待（每片不超过 20ms）以便及时纠正调度误差，保证节拍不累积漂移。

@local
@function wait_until
@param number base_ms    演奏起始时刻（mcu.ticks()）
@param number target_ms  目标时刻（相对起始时刻的毫秒数）
]]
local function wait_until(base_ms, target_ms)
    while true do
        -- 注意：sys.wait 只接受整数毫秒，浮点参数会直接抛错并导致 Lua VM 重启，
        -- 因此这里所有参与等待的时间都必须向下取整后再传入。
        local elapsed = math.floor((mcu.ticks() - base_ms) % MAX_TICK)
        local remain = math.floor(target_ms - elapsed)
        if remain <= 0 then return end
        local slice = remain > 20 and 20 or remain
        if slice < 1 then slice = 1 end
        sys.wait(slice)
    end
end

--[[
演奏一遍曲目（协程内调用，含扬声器占用互斥）
每个音符拆成"发声段 + 静音段"：发声段时长 = 音符时长 - 间隔，静音段 = 间隔，
从而使相邻音符之间有干净的分隔，避免连音糊在一起。

@api music.play
@return boolean true=演奏完成；false=扬声器忙，本次未演奏
]]
function music.play()
    if not buzzer_drv.lock(LOCK_TAG, LOCK_WAIT) then
        log.warn("music", "speaker busy, skip playing")
        return false
    end

    log.info("music", "start playing, notes", #steps, "duration", music.duration_ms() .. "ms")

    local base_ms = mcu.ticks()
    local target_ms = 0

    -- 演奏主体单独封装：配合 pcall 使用，保证任何异常（例如时间参数非法）都能走到
    -- 下面的收尾静音，避免 PWM 停留在 50% 占空比造成蜂鸣器长鸣。
    local function play_steps()
        for _, beats in ipairs(steps) do
            -- 音符时长取整（0.5 拍等会出现小数，必须转为整数毫秒）
            local dur_ms = math.floor(beats * BEAT_MS + 0.5)
            if beats > 0 then
                -- 发声段
                local on_ms = dur_ms - GAP_MS
                if on_ms < MIN_ON_MS then on_ms = MIN_ON_MS end
                buzzer_drv.tone_on()
                target_ms = target_ms + on_ms
                wait_until(base_ms, target_ms)
                -- 静音段（区分相邻音符）
                buzzer_drv.tone_off()
                target_ms = target_ms + (dur_ms - on_ms)
                wait_until(base_ms, target_ms)
            else
                -- 休止符：整段静音
                buzzer_drv.tone_off()
                target_ms = target_ms + dur_ms
                wait_until(base_ms, target_ms)
            end
        end
    end

    local ok, err = pcall(play_steps)

    -- 收尾静音并释放占用权，确保任何情况下（含异常中断）都不会长鸣
    buzzer_drv.tone_off()
    buzzer_drv.unlock(LOCK_TAG)

    if ok then
        log.info("music", "play finished")
    else
        log.error("music", "play aborted", err)
    end
    return ok
end

return music
