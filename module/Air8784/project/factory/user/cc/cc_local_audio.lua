-- 普通 CC 音频后端：Air1103 MIC -> extern_source/input；record 下行 -> Air1103。
-- 不启用 SIP、setBridge 或 CC 的纯 PCM/UART 后端。
local air = require "air1103"
local exaudio = require "exaudio"
local cfg = require "cc_local_config"
local M = {}
local buffers = {} -- C 层保留裸指针：整个运行期间必须持有四个 zbuff。
local running, rate, down, up, timer
local queue, pending = {}, ""
local mic_at, tx_at, rx_at = 0, 0, 0
local tx_bytes, rx_bytes = 0, 0

function M.check()
    if rtos.bsp() == "PC" then return false, "独立 CC 仅支持真机" end
    for _, name in ipairs({"init", "dial", "accept", "hangUp", "lastNum", "record", "on", "quality", "extern_source", "input"}) do
        if not cc or type(cc[name]) ~= "function" then return false, "缺少 cc." .. name end
    end
    if not audio_v2 or not audio_v2.DATA_CODEC_TYPE_RAW then return false, "缺少 Audio V2 RAW" end
    if not voip or type(voip.pcmResampler) ~= "function" then return false, "缺少 voip.pcmResampler" end
    return true
end

function M.stop()
    if not running then return end -- 空闲时播放流可能属于 TTS，不可停止它。
    running = false
    if timer then sys.timerStop(timer); timer = nil end
    queue, pending = {}, ""
    cc.extern_source(nil)
    air.play_stream_stop(true)
end

local function fail(reason)
    M.stop()
    sys.publish("CC_LOCAL_AUDIO_ERROR", reason)
end

local function tick()
    if not running then return end
    local q = cc.quality()
    local current_rate = q == 1 and 8000 or (q == 2 and 16000 or q)
    if current_rate ~= rate then fail("通话采样率改变或音频已停止"); return end
    if #pending == 0 and #queue > 0 then
        pending = table.remove(queue, 1)
        if rate == 8000 then pending = down:process(pending) end
    end
    if #pending > 0 then
        local ok, written = cc.input(true, pending, false)
        -- 老固件若不返回写入长度，不能猜测已消费量，否则会重复/丢失 PCM。
        if type(written) ~= "number" or written < 0 or written > #pending or written % 2 ~= 0 then
            fail("cc.input 未返回有效 PCM 写入长度"); return
        end
        if ok and written > 0 then
            pending = pending:sub(written + 1)
            tx_at, tx_bytes = os.time(), tx_bytes + written
        end
    end
    local now = os.time()
    if now - mic_at >= 4 then fail("Air1103 MIC 无数据"); return end
    if now - tx_at >= 4 then fail("CC 上行持续阻塞"); return end
    if now - rx_at >= 5 then fail("CC 下行录音无数据，请检查固件音频能力"); return end
    timer = sys.timerStart(tick, 5)
end

function M.start()
    if running then return true end
    local q = cc.quality()
    rate = q == 1 and 8000 or (q == 2 and 16000 or q)
    if rate ~= 8000 and rate ~= 16000 then return false, "CC 音频尚未就绪" end
    down:reset(); up:reset()
    queue, pending = {}, ""
    cc.extern_source(nil)
    if not cc.extern_source(true, true, audio_v2.DATA_CODEC_TYPE_RAW, true, rate, 16, 1, true) then
        return false, "cc.extern_source 流模式启动失败"
    end
    if not air.play_stream_start(cfg.volume) then
        cc.extern_source(nil)
        return false, "Air1103 播放启动失败"
    end
    tx_bytes, rx_bytes = 0, 0
    mic_at, tx_at, rx_at = os.time(), os.time(), os.time()
    running = true
    timer = sys.timerStart(tick, 5)
    log.info("cc_local_audio", "PCM_START", rate)
    return true
end

function M.init()
    local ok, err = M.check()
    if not ok then return false, err end
    gpio.setup(cfg.power_gpio, 1)
    sys.wait(cfg.boot_ms)
    if not exaudio.setup({model="air1103", uart_id=cfg.uart_id, audio_mode="new", bits_per_sample=16, channels=1}) then
        return false, "exaudio.setup 失败"
    end
    down = voip.pcmResampler(16000, 8000)
    up = voip.pcmResampler(8000, 16000)
    if not down or not up then return false, "重采样器创建失败" end
    for i = 1, 4 do
        buffers[i] = zbuff.create(640, 0, zbuff.HEAP_AUTO)
        if not buffers[i] then return false, "CC 双缓冲分配失败" end
    end
    cc.on("record", function(is_dl, index)
        if not running or not is_dl or (index ~= 0 and index ~= 1) then return end
        -- 立即复制；C 层切换双缓冲时自行重置 used，Lua 不修改它。
        local data = buffers[index + 3]:toStr(0, 640)
        rx_at, rx_bytes = os.time(), rx_bytes + #data
        if rate == 8000 then data = up:process(data) end
        if air.get_pending() < 3200 then air.play_stream_write(data) end
    end)
    if not cc.init(0) then return false, "cc.init 失败" end
    if not cc.record(true, buffers[1], buffers[2], buffers[3], buffers[4]) then
        return false, "cc.record 失败"
    end
    local received = false
    air.on_audio_data(function(data)
        if type(data) ~= "string" or #data ~= 512 then return end
        received, mic_at = true, os.time()
        if running then
            if #queue >= 8 then table.remove(queue, 1) end
            queue[#queue + 1] = data
        end
    end)
    air.set_rx_enable(true)
    if not air.reset() then return false, "Air1103 reset 失败" end
    for _ = 1, 100 do
        if received then return true end
        sys.wait(100)
    end
    return false, "Air1103 MIC 启动超时"
end

function M.stats() return tx_bytes, rx_bytes end
return M
