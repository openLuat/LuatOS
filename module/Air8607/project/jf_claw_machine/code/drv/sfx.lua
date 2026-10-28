--[[
@module sfx
@summary 抓娃娃音效：Lua 合成 PCM + exaudio 流式播放
@ver 1.0.0
@author cqd
@note 不依赖任何音频资源文件：所有音效用正弦滑频+指数包络在初始化时
      合成 16kHz/16bit/单声道 PCM，一次性写入播放队列。
      无 exaudio 后端（PC 模拟器 / 固件未带扩展库）时静默降级，不影响游戏。
      音效名：press(按键) / drop(下探) / grab(闭爪) / ok(抓中) / fail(滑落)
@usage
local sfx = require "sfx"
sfx.init(config)
sfx.play("ok")
sfx.toggle()   -- 切换静音，返回当前是否启用
]]

local M = { ready = false, enabled = true }

local RATE = 16000
local ex = nil

-- 16bit 小端打包
local function i2le(v)
    if v > 32767 then v = 32767 elseif v < -32768 then v = -32768 end
    if v < 0 then v = v + 65536 end
    return string.char(v % 256, math.floor(v / 256) % 256)
end

-- 单音调合成：freq0->freq1 线性滑频，指数衰减包络
-- @tparam number freq0 起始频率 Hz
-- @tparam number freq1 结束频率 Hz
-- @tparam number dur_ms 时长 ms
-- @tparam number vol 音量 0~1
local function tone(freq0, freq1, dur_ms, vol)
    local n = math.floor(RATE * dur_ms / 1000)
    if n <= 0 then return "" end
    local buf = {}
    local phase = 0
    for i = 0, n - 1 do
        local k = i / n
        local f = freq0 + (freq1 - freq0) * k
        phase = phase + 2 * math.pi * f / RATE
        local env = (1 - k) ^ 1.4 * vol
        buf[i + 1] = i2le(math.floor(math.sin(phase) * env * 32767))
    end
    return table.concat(buf)
end

-- 音效片段（惰性生成，首次播放才合成）
local CLIPS = {
    press = function() return tone(1100, 880, 60, 0.30) end,
    drop  = function() return tone(320, 150, 160, 0.34) end,
    grab  = function() return tone(520, 660, 110, 0.32) end,
    ok    = function() return tone(660, 660, 80, 0.30)
                          .. tone(880, 880, 80, 0.30)
                          .. tone(1100, 1320, 200, 0.28) end,
    fail  = function() return tone(300, 210, 240, 0.28) end,
}
local clips = {}

-- 初始化音频后端（功放 GPIO/音量见 config），失败保持静默
-- @tparam table config 配置表
function M.init(config)
    local ok, lib = pcall(require, "exaudio")
    if not ok or type(lib) ~= "table" then
        M.ready = false
        return false
    end
    ex = lib
    pcall(function()
        ex.setup({
            model = "dac",
            pa_ctrl = config and config.pa_ctrl or 73,
            pa_on_level = config and config.pa_on_level or 1,
            dac_delay = config and config.dac_delay or 6,
        })
        ex.vol(config and config.sfx_vol or 30)
    end)
    M.ready = true
    return true
end

-- 播放一个音效（忙时丢弃，不阻塞游戏）
-- @tparam string name 音效名 press/drop/grab/ok/fail
function M.play(name)
    if not (M.ready and M.enabled) then return false end
    if not clips[name] then
        local gen = CLIPS[name]
        if not gen then return false end
        clips[name] = gen()
    end
    local clip = clips[name]
    if #clip == 0 then return false end
    local ok = pcall(function()
        assert(ex.play_start({
            codec_id = 0,
            type = 2,
            sampling_rate = RATE,
            sampling_depth = 16,
            signed_or_unsigned = true,
            stream_buffer_size = 2048,
        }), "play_start busy")
        for pos = 1, #clip, 2048 do
            ex.play_stream_write(clip:sub(pos, pos + 2047))
        end
        if ex.finish then ex.finish() end
    end)
    return ok
end

-- 切换静音开关，返回当前是否启用
function M.toggle()
    M.enabled = not M.enabled
    return M.enabled
end

return M
