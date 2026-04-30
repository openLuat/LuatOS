--[[
  落子短音效：内存 PCM（与 piano 相同播放路径，PC 上 audio.play 文件不可用）
  音色：低频“笃”+ 极短高频点击感
]]

local M = {}

local SR = 22050
local AUDIO_CH = 0
local pcm_cache = nil

local function build_move_pcm()
    local dur = 0.11
    local n = math.floor(SR * dur)
    local fade = math.floor(SR * 0.018)
    local parts = {}
    for i = 0, n - 1 do
        local env = 1.0
        if i < fade then
            env = i / math.max(1, fade)
        end
        if i > n - 1 - fade then
            env = math.min(env, (n - 1 - i) / math.max(1, fade))
        end
        env = env * env
        local t = i / SR
        local s = 0
        s = s + math.sin(2 * math.pi * 280 * t) * 0.42
        s = s + math.sin(2 * math.pi * 160 * t) * 0.38
        s = s + math.sin(2 * math.pi * 2100 * t) * 0.12 * (1 - i / n)
        local v = math.floor(9200 * env * s)
        if v > 32767 then
            v = 32767
        elseif v < -32768 then
            v = -32768
        end
        parts[#parts + 1] = string.pack("<i2", v)
    end
    return table.concat(parts)
end

function M.play_drop()
    if not audio or not audio.start or not audio.write then
        return
    end
    if not pcm_cache then
        pcm_cache = build_move_pcm()
    end
    if #pcm_cache < 2 then
        return
    end
    pcall(function()
        audio.stop(AUDIO_CH)
    end)
    pcall(function()
        if not audio.start(AUDIO_CH, audio.PCM, 1, SR, 16, true) then
            return
        end
        if not audio.write(AUDIO_CH, pcm_cache) then
            return
        end
        if audio.finish then
            audio.finish(AUDIO_CH)
        end
    end)
end

return M
