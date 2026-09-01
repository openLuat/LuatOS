--[[
    @module  vb7014f
    @summary 华镇 VB7014F 语音芯片 PCM+PCM 串口协议驱动
    @version 1.0.0
    @date    2026.08.31
    @author  拓毅恒
    @usage
        local vb7014f = require "vb7014f"

        -- 1) 初始化: UART1, 波特率 2M
        vb7014f.init(1, 2000000)

        -- 2) 注册回调
        vb7014f.on_audio_data(function(data)
            -- data: 每帧 512B PCM(16ms / 16kHz / 16bit / 单声道), 来自 7014 MIC 上行
        end)
        vb7014f.on_identify(function(text)
            -- text: 离线识别结果 UTF-8 文本(如 "打开灯光")
        end)

        -- 3) 下行播放(接 AI 大模型/通话下行音频)
        vb7014f.play_stream_start(20)     -- 启动流式播放, 音量 20(0~31)
        vb7014f.play_stream_write(pcm)    -- 喂入 PCM(任意长度, 内部按 320B/帧切分)
        vb7014f.play_stream_stop()        -- 停止播放

    帧结构: 55 AA + 长度(2B, 高字节在前/大端) + 命令(2B) + 数据(NB) + 和校验(1B)
    和校验: 包头 + 长度 + 命令 + 数据 逐字节累加, 取低 8 位
    命令/帧格式一览:
        20 80  7014→合宙模组  上行 MIC 录音   PCM 512B/帧 (16ms, 16kHz, 16bit, 单声道)
        01 80  7014→合宙模组  离线识别结果    N 字节 UTF-8 文本
        20 81  合宙模组→7014  下行播放 PCM   320B/帧 (10ms, 16kHz, 16bit, 单声道)
        02 01  合宙模组→7014  停止上行音频    (无数据)
        02 03  合宙模组→7014  设置播放音量    1 字节, 0~31
        02 05  合宙模组→7014  程序复位        1 字节, 00=程序复位(复位后自动恢复 MIC 上行)

    下行传输要求(强制约束):
        - 下行播放数据必须通过 命令 20 81 下发, 每帧固定 320 字节,
          即 10ms @ 16kHz / 16bit / 单声道(320B = 16kHz × 10ms × 2Byte)。
        - 必须保持 10ms/帧 连续发送, 不可长时间中断:
          数据流一断, 7014 内部 DAC 缓冲被掏空 → 瞬态爆音 / 杂音。
        - 本库内部以 10ms 时间戳(每拍取 320B 切帧)保证该节奏;
          队列空时自动补发"静音帧"(320B 全0 + 20 81)保活, 调用方只要用
          play_stream_write 持续喂数据即可, 不必自己卡 10ms 计时。
        - 若使用 play_direct 直发, 调用方须自行保证每 10ms 发送一帧 320B(否则爆音/丢帧)。
        - 注意上行 MIC(20 80)是 7014→合宙模组, 每帧 512B / 16ms, 与下行帧率不同, 不要混用。
]]

local vb7014f = {}

-- ==================== 配置 ====================
local UART_ID        = 1        -- 默认串口
local BAUD           = 2000000  -- 默认波特率
local FRAME_DOWN     = 320      -- 下行 PCM 帧字节数(10ms / 16kHz / 16bit / 单声道)
local STREAM_SILENT  = true     -- 队列空时发送静音帧保活(防爆音)
local STREAM_BURST   = 5        -- 单拍(10ms)最多连发帧数, 防 7014 接收缓存溢出丢帧
local TX_INTERVAL_US = 10000    -- 下行发送帧间隔(微秒) = 320B / 10ms
local STREAM_RAW_MAX = FRAME_DOWN * 200   -- 流式积压上限≈2s, 超出丢弃最旧帧防内存暴涨
local STREAM_BUFF_LEN = STREAM_RAW_MAX + FRAME_DOWN * 100  -- zbuff 容量

-- ==================== 命令常量(对应 PCM+PCM 串口协议) ====================
local CMD_UP_AUDIO    = string.char(0x20, 0x80)  -- 7014→合宙模组 录音 PCM(上行)
local CMD_UP_IDENTIFY = string.char(0x01, 0x80)  -- 7014→合宙模组 离线识别结果
local CMD_DOWN_AUDIO  = string.char(0x20, 0x81)  -- 合宙模组→7014 下行播放 PCM
local CMD_DOWN_STOP   = string.char(0x02, 0x01)  -- 合宙模组→7014 停止上行音频
local CMD_DOWN_VOL    = string.char(0x02, 0x03)  -- 合宙模组→7014 设置播放音量
local CMD_RESET       = string.char(0x02, 0x05)  -- 合宙模组→7014 程序复位(00=复位)

-- ==================== 状态 ====================
local is_inited     = false    -- 是否已初始化
local rxstr         = ""       -- 接收缓冲(跨 uart 回调累积, 用于帧解析)
local rx_enabled    = true     -- 是否解析接收数据
local cb_identify   = nil      -- function(text)   识别结果回调
local cb_audio_data = nil      -- function(data)   上行 PCM 数据(512B/帧)回调

-- 下行流式播放缓冲(zbuff 增量写入)
local stream_running = false
local stream_timer   = nil
local stream_buff   = nil      -- 防止大缓冲拷贝
local stream_wr     = 0        -- 已写入字节
local stream_rd     = 0        -- 已读取字节
local silent_frame  = nil      -- 预打包静音保活帧(320B 全0 + 20 81 + 校验)

-- ==================== 工具函数 ====================
-- 微秒级时间戳(mcu.ticks2, 64bit 计数不溢出), 用于下行 10ms 节拍基准
local function us_now()
    local h, l = mcu.ticks2(0)
    return h * 1000000 + l
end

-- 构造协议帧
-- @param cmd     命令(2B, 见上方命令常量)
-- @param payload 数据(可为 nil)
-- @return string 完整帧: 包头(55 AA) + 长度(2B 大端) + 命令(2B) + 数据 + 校验(1B)
-- @remark 和校验 = 包头+长度+命令+数据 逐字节累加取低 8 位
local function pack(cmd, payload)
    local ln = payload and #payload or 0
    local body = string.char(0x55, 0xAA, math.floor(ln / 256), ln % 256)
        .. cmd .. (payload or "")
    local sum = 0
    local tbl = { body:byte(1, -1) }
    for i = 1, #tbl do sum = sum + tbl[i] end
    return body .. string.char(sum % 256)
end

-- ==================== 串口接收回调 ====================
-- UART receive 事件: 读出数据 → 喂给帧解析器
local function on_uart_receive()
    local data = uart.read(UART_ID, 1024)
    -- 非通话时直接丢弃, 不做字符串拼接/解析
    if not rx_enabled then return end
    while data and #data > 0 do
        vb7014f.feed(data)
        data = uart.read(UART_ID, 1024)
    end
end

-- ==================== 初始化 ====================
-- 初始化串口并注册接收回调
-- @param id   串口 ID, 默认 1
-- @param baud 波特率, 默认 2000000(固定 2M)
-- @return boolean true=成功 false=失败
function vb7014f.init(id, baud)
    if is_inited then return true end
    UART_ID = id or 1
    BAUD = baud or 2000000
    local ok = uart.setup(UART_ID, BAUD, 8, 1, uart.NONE, uart.LSB, 10240)
    if not ok then
        log.error("vb7014f", "串口初始化失败", UART_ID, BAUD)
        return false
    end
    uart.on(UART_ID, "receive", on_uart_receive)
    is_inited = true
    log.info("vb7014f", "初始化完成", UART_ID, BAUD)
    return true
end

-- ==================== 事件回调注册 ====================
-- 注册离线识别结果回调
-- @param cb function(text), text 为 7014 发来的识别文本(UTF-8)
function vb7014f.on_identify(cb)
    cb_identify = cb
end

-- 注册上行 MIC 数据回调
-- @param cb function(data), data 为每帧 512B PCM(16ms / 16kHz / 16bit / 单声道)
function vb7014f.on_audio_data(cb)
    cb_audio_data = cb
end

-- 开关接收数据解析(非通话时关闭)
-- @param flag true=解析 false=丢弃
function vb7014f.set_rx_enable(flag)
    rx_enabled = flag
    if not flag then
        rxstr = ""
    end
end

-- ==================== 帧解析 ====================
-- 喂入串口接收数据
-- @param data string 从 UART 读出的原始字节
-- @remark 按 55 AA 帧头切分; 长度大端; 校验失败则丢弃整缓冲
function vb7014f.feed(data)
    if not data or #data == 0 then return end
    rxstr = rxstr .. data
    while #rxstr >= 6 do
        local pos = rxstr:find("\x55\xAA", 1, true)
        if not pos then
            rxstr = ""
            break
        end
        if pos > 1 then rxstr = rxstr:sub(pos) end
        -- 长度(2B, 大端): byte3=高字节, byte4=低字节
        local ln = rxstr:byte(3) * 256 + rxstr:byte(4)
        local total = 6 + ln + 1   -- 头(2)+长(2)+命(2)+数据(ln)+校验(1)
        if #rxstr < total then break end
        local frame = rxstr:sub(1, total)
        rxstr = rxstr:sub(total + 1)
        -- 和校验: 前面所有字节累加取低 8 位
        local sum = 0
        local tbl = { frame:byte(1, total - 1) }
        for i = 1, #tbl do sum = sum + tbl[i] end
        if (sum % 256) ~= frame:byte(total) then
            rxstr = ""
            break
        end
        local cmd = frame:sub(5, 6)
        local payload = frame:sub(7, 6 + ln)
        if cmd == CMD_UP_IDENTIFY then
            if cb_identify then cb_identify(payload) end
        elseif cmd == CMD_UP_AUDIO then
            if cb_audio_data then cb_audio_data(payload) end
        end
    end
end

-- ==================== 控制指令 ====================
-- 停止 7014 发送上行音频(命令 02 01, 无数据)
-- @return boolean
function vb7014f.stop_audio()
    if not is_inited then return false end
    uart.write(UART_ID, pack(CMD_DOWN_STOP, nil))
    return true
end

-- 程序复位 7014(命令 02 05, 数据 00=程序复位)
-- @remark 协议无"开始上行"指令; 复位后 7014 重新初始化会自动开始发送 MIC 上行
-- @return boolean
function vb7014f.reset()
    if not is_inited then return false end
    uart.write(UART_ID, pack(CMD_RESET, string.char(0x00)))
    log.info("vb7014f", "发送程序复位 02 05 00, 等待重新初始化后自动恢复上行")
    return true
end

-- 设置播放音量(命令 02 03, 数据 0~31)
-- @param vol 音量值 0~31
-- @return boolean
function vb7014f.set_volume(vol)
    if not is_inited then return false end
    vol = math.max(0, math.min(31, vol or 20))
    uart.write(UART_ID, pack(CMD_DOWN_VOL, string.char(vol)))
    return true
end

-- ==================== 流式播放(下行) ====================
-- 启动流式播放发送任务(接 AI 大模型 / 通话下行音频)
-- @param vol 音量(0~31), 可省; 非 nil 时先设置音量
-- @return boolean
-- @remark 传输要求: 以 10ms/帧 从缓冲取 320B 切帧(命令 20 81)发送;
--         队列空时自动补发静音帧(全0)保活, 保证数据流连续不断;
--         每次唤醒最多连发 STREAM_BURST 帧, 防 7014 接收缓存(约2KB)溢出丢帧。
function vb7014f.play_stream_start(vol)
    if not is_inited then return false end
    if vol then vb7014f.set_volume(vol) end
    if not stream_buff then
        stream_buff = zbuff.create(STREAM_BUFF_LEN, 0, zbuff.HEAP_AUTO)
    end
    stream_buff:clear(0)   -- 内存清零
    stream_buff:used(0)    -- used 归零(否则 del/avail 判断错位)
    stream_wr = 0
    stream_rd = 0
    stream_running = true
    if not silent_frame then
        -- 预打包一帧静音(320B 全0 + 20 81 命令头 + 校验)
        silent_frame = pack(CMD_DOWN_AUDIO, string.rep(string.char(0), FRAME_DOWN))
    end
    -- 流式发送节拍: 以绝对时间戳 next_tx 为 10ms 基准
    local STREAM_TICK_MS  = 10            -- 定时器节拍(ms)
    local MAX_BURST       = STREAM_BURST  -- 单拍最多连发帧数(追赶上限)
    local CLEANUP_THRESHOLD = FRAME_DOWN * 10  -- 每读出 10 帧即压缩, 限制写偏移防 zbuff 越界
    local next_tx = us_now()              -- 下次发送绝对时间戳(us), 启动即置当前→首拍即发
    local function stream_play_tick()
        if not stream_running then
            if stream_timer then sys.timerStop(stream_timer); stream_timer = nil end  -- 任务结束自动停定时器, 防空转
            return
        end
        if not stream_buff then
            if stream_timer then sys.timerStop(stream_timer); stream_timer = nil end
            return
        end
        local now = us_now()
        local burst = 0
        while stream_running and burst < MAX_BURST and now >= next_tx do
            local avail = stream_wr - stream_rd
            if avail >= FRAME_DOWN then
                -- 逐帧切+打包(每帧≈3ms)
                local body = stream_buff:toStr(stream_rd, FRAME_DOWN)
                local f = pack(CMD_DOWN_AUDIO, body)
                local wr = uart.write(UART_ID, f)
                if wr and wr > 0 then
                    stream_rd = stream_rd + FRAME_DOWN
                    -- 逐帧压缩: 读游标超阈值即回收已读部分, 限制写偏移≤容量, 杜绝 zbuff 越界
                    if stream_rd >= CLEANUP_THRESHOLD then
                        stream_buff:del(0, stream_rd)
                        stream_wr = stream_wr - stream_rd
                        stream_rd = 0
                    end
                end
            else
                -- 队列空: 发静音帧保活(数据流永不断→7014 DAC 连续输出→消除爆音)
                if STREAM_SILENT then
                    uart.write(UART_ID, silent_frame)
                end
            end
            next_tx = next_tx + TX_INTERVAL_US  -- 基准前进 10ms/帧(落后则下轮继续补发)
            burst = burst + 1
            now = us_now()
        end
    end
    -- 启动循环定时器: 每 STREAM_TICK_MS 触发一拍(替代 sys.wait 轮询)
    stream_timer = sys.timerLoopStart(stream_play_tick, STREAM_TICK_MS)
    return true
end

-- 流式喂入 PCM 数据(追加原始字节, 不在本函数切帧/打包)
-- @param data PCM 数据块(任意长度, 内部按 320B/帧 对齐切分后逐帧 10ms 发送;
--             数据须为 16kHz / 16bit / 单声道, 与 XLS 下行帧格式一致)
-- @remark 积压超 STREAM_RAW_MAX 时丢弃最旧整帧(对齐 320B, 保序), 防内存无限增长
function vb7014f.play_stream_write(data)
    if not stream_running then return end
    if not stream_buff then return end
    if not data or #data == 0 then return end
    -- 积压限流: 用"未读原始字节"判断, 超过阈值丢最旧整帧(对齐 320B, 保序)
    local avail = stream_wr - stream_rd
    if avail + #data > STREAM_RAW_MAX then
        local drop = (avail + #data) - STREAM_RAW_MAX
        drop = drop - (drop % FRAME_DOWN)
        stream_rd = stream_rd + drop
    end
    -- 防御性兜底: 写前若逼近容量上限, 先物理回收已读部分, 仍放不下则丢最旧整帧, 绝不允许越界
    if stream_wr + #data > STREAM_BUFF_LEN - FRAME_DOWN * 10 then
        if stream_rd > 0 then
            stream_buff:del(0, stream_rd)
            stream_wr = stream_wr - stream_rd
            stream_rd = 0
        end
        while stream_wr + #data > STREAM_BUFF_LEN - FRAME_DOWN * 10 do
            local d = FRAME_DOWN
            stream_buff:del(0, d)
            stream_wr = stream_wr - d
        end
    end
    -- zbuff 增量写入(O(1) memcpy), 写前 seek 到 stream_wr, 写后手动同步 used
    stream_buff:seek(stream_wr)
    stream_buff:write(data)
    stream_wr = stream_wr + #data
    stream_buff:used(stream_wr)
end

-- 结束流式播放(播完队列剩余后停止)
function vb7014f.play_stream_stop()
    stream_running = false
    if stream_timer then sys.timerStop(stream_timer); stream_timer = nil end  -- 停循环定时器, 防空转
    vb7014f.stop_audio()   -- 停止下行(同时发 02 01 停上行惯例, 由调用方按需恢复)
    -- 清空残留原始缓冲+游标, 防内存残留到下一次通话
    if stream_buff then
        stream_buff:clear(0)
        stream_buff:used(0)
    end
    stream_wr = 0
    stream_rd = 0
end

-- ==================== 直接播放(下行, 绕过流式队列) ====================
-- 直接发送一帧下行 PCM(命令 20 81), 不经过流式缓冲/定时器
-- @param data 单帧 PCM(必须 320B / 10ms; 不足补0, 超出截断)
-- @return boolean true=已发送
-- @remark 适合隔离测试"780EHM→7014 纯传输链路"时逐帧直发
function vb7014f.play_direct(data)
    if not is_inited then return false end
    if not data or #data == 0 then return false end
    local payload = data
    if #payload < FRAME_DOWN then
        payload = payload .. string.rep(string.char(0), FRAME_DOWN - #payload)
    elseif #payload > FRAME_DOWN then
        payload = payload:sub(1, FRAME_DOWN)
    end
    uart.write(UART_ID, pack(CMD_DOWN_AUDIO, payload))
    return true
end

return vb7014f
