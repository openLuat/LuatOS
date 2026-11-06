--[[
@module  cc_record_save
@summary 通话录音功能模块（PCM格式，可选AMR转码）
@version 1.1
@date    2026.5.15
@author  拓毅恒
@usage
本模块提供以下功能：
1. 实现呼入自动接听功能（响2声后自动接听）
2. 支持通话录音功能，保存为PCM格式
3. 可选：通话结束后将PCM转码为AMR格式（需手动开启）

录音功能特性：
- 录音文件保存到内部 flash：/record_call.pcm
- 可选AMR转码：/record_call.amr（需手动开启）
- 只保存上行数据（包含本地声音和网络回声）
- 下行数据自动跳过，避免重复存储
- 根据通话质量自动选择AMR-NB（8KHz）或AMR-WB（16KHz）

注意事项：
1. 8780V 板上没有 TF 卡座，录音直接写内部 flash，不要再挂 SPI/SD 卡
2. 内部 lfs 分区实测只有 768KB，由 FLASH_MAX_RECORD_KB 封顶
3. 本模块仅支持呼入自动接听功能
4. PCM文件为原始音频格式，可用Audacity等工具播放
]]

-- 引入音频设备模块
local audio_drv = require "audio_drv"
local exaudio = require "exaudio"

-- ====================== 配置区域 ======================

-- 全局状态变量
local call_counter = 0                 -- 响铃计数器
local caller_number = ""               -- 来电号码

-- 录音存储：内部 flash
local RECORD_FILE_PATH = "/record_call.pcm"        -- 录音文件（PCM原始格式）
local RECORD_AMR_FILE_PATH = "/record_call.amr"    -- 转码后的AMR文件
-- 内部 lfs 分区实测 768KB，不封顶会写满分区影响脚本和参数存储
local FLASH_MAX_RECORD_KB = 400

-- 录音功能相关函数
local is_recording_to_file = false  -- 录音状态标志：true表示正在录音到文件
local record_file = nil                -- 录音文件句柄
local record_start_time = 0            -- 录音开始时间戳（毫秒）
local record_duration = 0              -- 录音时长（秒）
local record_sample_rate = 8000        -- 录音采样率（从cc.quality获取，用于后续AMR转码）
local record_bytes = 0                 -- 本次已写入的字节数（内部 flash 用来封顶）

-- 注意：缓冲区大小必须是640的倍数
-- 原因：VoLTE通话音频数据以20ms为帧单位，8KHz采样率每帧320字节，16KHz采样率每帧640字节
-- 640是两者的最小公倍数，确保缓冲区能整除存放整数个音频帧
-- 
-- 当前配置计算：
-- BUFFER_SIZE = 48000 字节
-- 16KHz模式：48000 / 640 = 75 帧 = 75 * 20ms = 1500ms = 1.5 秒
-- 8KHz模式：48000 / 320 = 150 帧 = 150 * 20ms = 3000ms = 3 秒
-- 
-- 双缓冲机制：满时触发回调，处理完用:del()清空
local BUFFER_SIZE = 48000  -- 缓冲区大小不能太小，否则保存过程中有可能会溢出造成死机

-- ====================== 录音功能 ======================

-- 创建音频数据缓冲区
local up1 = zbuff.create(BUFFER_SIZE,0)      -- 上行数据保存区1
local up2 = zbuff.create(BUFFER_SIZE,0)      -- 上行数据保存区2
local down1 = zbuff.create(BUFFER_SIZE,0)    -- 下行数据保存区1
local down2 = zbuff.create(BUFFER_SIZE,0)    -- 下行数据保存区2

-- 打开录音文件
local function open_record_file()
    -- 8780V 板上没有 TF 卡座，直接写内部 flash。
    -- 不要 gpio.setup(20)：GPIO20 是 Codec 电源使能，误拉高会干扰音频。
    log.info("录音文件", "录音写入内部 flash:", RECORD_FILE_PATH)
    
    -- 关闭已打开的文件
    if record_file then
        record_file:close()
        record_file = nil
    end
    
    -- 删除旧录音文件
    if io.exists(RECORD_FILE_PATH) then
        os.remove(RECORD_FILE_PATH)
        log.info("录音文件", "删除旧录音文件:", RECORD_FILE_PATH)
    end
    
    -- 创建录音文件
    record_file = io.open(RECORD_FILE_PATH, "wb")
    
    if record_file then
        log.info("录音文件", "创建录音文件成功:", RECORD_FILE_PATH)
        record_start_time = mcu.ticks()
        record_bytes = 0
        is_recording_to_file = true
        return true
    else
        log.error("录音文件", "创建录音文件失败:", RECORD_FILE_PATH)
        return false
    end
end

-- 计算时间差（毫秒）
local function calc_time_diff_ms(start_tick, end_tick)
    -- 检查溢出：Lua中超过0x7fffffff会变成负数
    if (start_tick > 0 and end_tick < 0) or (start_tick < 0 and end_tick > 0) then
        log.warn("时间计算", "mcu.ticks()溢出，无法准确计算时长")
        return nil
    end
    
    local diff_ticks = end_tick - start_tick
    local hz = mcu.hz()
    if hz == 0 then
        hz = 1000  -- 默认1ms一个tick
    end
    
    return (diff_ticks * 1000) / hz
end

-- 关闭录音文件
local function close_record_file()
    if record_file then
        record_file:close()
        record_file = nil
        
        local file_size = io.fileSize(RECORD_FILE_PATH)
        local duration_ms = calc_time_diff_ms(record_start_time, mcu.ticks())
        
        if duration_ms then
            record_duration = duration_ms / 1000  -- 转换为秒
            log.info("录音文件", "录音完成", "文件大小:", file_size, "字节", "录音时长:", string.format("%.1f", record_duration), "秒", "路径:", RECORD_FILE_PATH)
        else
            log.info("录音文件", "录音完成", "文件大小:", file_size, "字节", "录音时长: 溢出无法计算", "路径:", RECORD_FILE_PATH)
        end
        
        is_recording_to_file = false
        record_start_time = 0
        record_duration = 0
    end
end

-- 写入录音数据到文件
local function write_record_data(buff, is_downlink)
    if not record_file or not is_recording_to_file then
        return false
    end
    
    -- 保存数据
    if not is_downlink then
        local data_size = buff:used()
        if data_size > 0 then
            local start_time = mcu.ticks()
            
            -- 写入数据到文件
            record_file:write(buff:query())

            -- 内部 flash 分区只有 768KB，写到上限就主动停，
            -- 避免写满分区影响脚本和参数存储
            record_bytes = record_bytes + data_size
            if record_bytes >= FLASH_MAX_RECORD_KB * 1024 then
                log.warn("录音文件", "内部 flash 录音已达上限", FLASH_MAX_RECORD_KB, "KB，自动停止")
                close_record_file()
                return true
            end
            
            local end_time = mcu.ticks()
            local write_time_ms = calc_time_diff_ms(start_time, end_time)
            
            if write_time_ms and write_time_ms > 0 then
                local write_speed = data_size / (write_time_ms / 1000)  -- 字节/秒
                log.info("录音写入", 
                        "数据大小:", data_size, "字节,", 
                        "写入耗时:", string.format("%.2f", write_time_ms), "ms,",
                        "写入速度:", string.format("%.2f", write_speed / 1024), "KB/s")
            else
                log.info("录音写入", 
                        "数据大小:", data_size, "字节,", 
                        "写入耗时: 溢出无法计算")
            end
            
            return true
        end
    else
        -- 下行数据不保存，只记录日志
        -- 写入下行数据会导致文件内有回声
        local data_size = buff:used()
        if data_size > 0 then
            log.info("录音写入", "下行数据跳过", "数据大小:", data_size, "字节")
        end
    end
    return false
end

-- 音频数据回调函数
local function recordCallback(is_dl, point)
    if is_dl then
        log.info("录音", "下行数据，位于缓存", point+1, "缓存1数据量", down1:used(), "缓存2数据量", down2:used())
        
        -- 处理下行数据
        if point == 0 then
            write_record_data(down1, true)
            down1:del()  -- 清空缓冲区
        else
            write_record_data(down2, true)
            down2:del()  -- 清空缓冲区
        end
    else
        log.info("录音", "上行数据，位于缓存", point+1, "缓存1数据量", up1:used(), "缓存2数据量", up2:used())
        
        -- 处理上行数据
        if point == 0 then
            write_record_data(up1, false)
            up1:del()  -- 清空缓冲区
        else
            write_record_data(up2, false)
            up2:del()  -- 清空缓冲区
        end
    end
    log.info("通话质量", cc.quality())
end

-- 将PCM录音文件转码为AMR格式
local function convert_pcm_to_amr()
    -- 检查PCM文件是否存在
    if not io.exists(RECORD_FILE_PATH) then
        log.warn("AMR转码", "PCM文件不存在，跳过转码:", RECORD_FILE_PATH)
        return false
    end
    
    local pcm_size = io.fileSize(RECORD_FILE_PATH)
    if pcm_size == 0 then
        log.warn("AMR转码", "PCM文件为空，跳过转码")
        return false
    end
    
    log.info("AMR转码", "开始转码，PCM文件大小:", pcm_size, "字节", "采样率:", record_sample_rate)
    
    -- 打开PCM文件读取
    local pcm_file = io.open(RECORD_FILE_PATH, "rb")
    if not pcm_file then
        log.error("AMR转码", "无法打开PCM文件:", RECORD_FILE_PATH)
        return false
    end
    
    -- 删除旧的AMR文件
    if io.exists(RECORD_AMR_FILE_PATH) then
        os.remove(RECORD_AMR_FILE_PATH)
    end
    
    -- 创建AMR文件
    local amr_file = io.open(RECORD_AMR_FILE_PATH, "wb")
    if not amr_file then
        log.error("AMR转码", "无法创建AMR文件:", RECORD_AMR_FILE_PATH)
        pcm_file:close()
        return false
    end
    
    -- 根据采样率选择AMR格式
    local amr_coder
    local is_wb = false
    if record_sample_rate == 16000 then
        -- 16KHz → AMR-WB
        is_wb = true
        amr_coder = codec.create(codec.AMR_WB, false, 8)
        amr_file:write("#!AMR-WB\n")
        log.info("AMR转码", "使用AMR-WB格式，16KHz")
    else
        -- 8KHz → AMR-NB
        amr_coder = codec.create(codec.AMR, false, 7)
        amr_file:write("#!AMR\n")
        log.info("AMR转码", "使用AMR-NB格式，8KHz")
    end
    
    if not amr_coder then
        log.error("AMR转码", "创建AMR编码器失败")
        pcm_file:close()
        amr_file:close()
        return false
    end
    
    -- 创建编码输出缓冲区和读取缓冲区
    local amr_out = zbuff.create(4096)
    local read_buff = zbuff.create(4096)
    local total_encoded = 0
    local frame_count = 0
    local start_time = mcu.ticks()
    
    -- 分块读取PCM数据并编码
    while true do
        -- 从PCM文件读取数据到zbuff
        local data = pcm_file:read(4096)
        if not data or #data == 0 then
            break  -- 文件读取完毕
        end
        
        -- 写入zbuff
        read_buff:write(data)
        local read_size = read_buff:used()
        
        -- 清空输出缓冲区
        amr_out:del()
        
        -- 编码为AMR
        local ok, result = pcall(codec.encode, amr_coder, read_buff, amr_out, 7)
        if not ok then
            log.error("AMR转码", "编码异常:", result)
            break
        end
        
        if result then
            local encoded_size = amr_out:used()
            if encoded_size > 0 then
                local encoded_data = amr_out:query()
                amr_file:write(encoded_data)
                total_encoded = total_encoded + encoded_size
                frame_count = frame_count + 1
            end
        end
        
        -- 清空读取缓冲区，准备下一块
        read_buff:del()
    end
    
    -- 清理资源
    read_buff:del()
    amr_out:del()
    codec.release(amr_coder)
    pcm_file:close()
    amr_file:close()
    
    local end_time = mcu.ticks()
    local cost_time_ms = calc_time_diff_ms(start_time, end_time)
    
    if cost_time_ms then
        local cost_time_sec = cost_time_ms / 1000
        log.info("AMR转码", "转码完成",
                 "AMR大小:", total_encoded, "字节,",
                 "压缩比:", string.format("%.1f%%", total_encoded / pcm_size * 100), ",",
                 "耗时:", string.format("%.1f", cost_time_sec), "秒,",
                 "路径:", RECORD_AMR_FILE_PATH)
    else
        log.info("AMR转码", "转码完成",
                 "AMR大小:", total_encoded, "字节,",
                 "压缩比:", string.format("%.1f%%", total_encoded / pcm_size * 100), ",",
                 "耗时: 溢出无法计算",
                 "路径:", RECORD_AMR_FILE_PATH)
    end
    
    return true
end

-- 启用通话录音
local function enableRecording()
    cc.record(true, up1, up2, down1, down2)
    cc.on("record", recordCallback)
    log.info("cc_app", "通话录音已启用")
end

-- 开始通话录音到文件
local function start_call_recording()
    -- 保存当前通话质量（采样率）
    local quality = cc.quality()
    if quality == 2 then
        record_sample_rate = 16000
    else
        record_sample_rate = 8000
    end
    log.info("通话录音", "通话质量:", quality, "采样率:", record_sample_rate)

    -- 内部 flash 只有 768KB，开录前把"最长能录多久"打出来，
    -- 省得事后看到只录了十几秒以为是 bug
    local ok, total, used, bsize = io.fsstat("/")
    if ok and total then
        local free_kb = math.floor((total - used) * (bsize or 0) / 1024)
        local allow_kb = free_kb < FLASH_MAX_RECORD_KB and free_kb or FLASH_MAX_RECORD_KB
        local bps = record_sample_rate * 2      -- 16bit 单声道
        if allow_kb > 0 and bps > 0 then
            log.info("通话录音", "内部 flash 剩余", free_kb, "KB, 预计最长可录",
                math.floor(allow_kb * 1024 / bps), "秒")
        end
    end

    if open_record_file() then
        log.info("通话录音", "开始录音到文件:", RECORD_FILE_PATH)
        return true
    else
        log.error("通话录音", "无法开始录音到文件")
        return false
    end
end

-- 停止通话录音到文件
local function stop_call_recording()
    close_record_file()
    log.info("通话录音", "停止录音到文件")
    
    -- 通话结束后，将PCM文件离线转码为AMR
    -- 如需AMR格式，取消下面这行的注释
    -- convert_pcm_to_amr()
end

-- 获取所有缓冲区
local function getRecordingBuffers()
    return {
        up1 = up1,
        up2 = up2,
        down1 = down1,
        down2 = down2
    }
end

-- 获取录音文件信息
local function get_record_file_info()
    if io.exists(RECORD_FILE_PATH) then
        local file_size = io.fileSize(RECORD_FILE_PATH)
        return {
            path = RECORD_FILE_PATH,
            size = file_size,
            duration = record_duration,
            exists = true
        }
    else
        return {
            path = RECORD_FILE_PATH,
            size = 0,
            duration = 0,
            exists = false
        }
    end
end

-- 呼入自动接听，等待对方挂断
local function handle_scenario(status)
    if status == "INCOMINGCALL" then
        -- 获取来电号码
        caller_number = cc.lastNum() or "未知号码"
        call_counter = call_counter + 1
        
        log.info("收到来电，号码:", caller_number, "响铃次数:", call_counter)
        
        -- 响铃2声后自动接听
        if call_counter >= 2 then
            log.info("自动接听来电")
            cc.accept(0)
            call_counter = 0  -- 重置计数器
        end
    elseif status == "SPEECH_START" then
        -- 语音通话真正开始
        log.info("电话已接通，电话号码:", caller_number)
        
        -- 开始通话录音到文件
        start_call_recording()
    elseif status == "DISCONNECTED" then
        -- 对方挂断通话
        log.info("通话结束对方挂断")
        
        -- 停止通话录音到文件
        stop_call_recording()
        
        call_counter = 0  -- 重置计数器
    end
end

-- ====================== 主事件处理器 ======================
sys.subscribe("CC_IND", function(status)
    log.info("CC状态", status)
    handle_scenario(status)
    
    -- 需要处理的通用状态
    if status == "READY" then
        sys.publish("CC_READY")  -- 发布系统就绪事件
    elseif status == "PLAY" then
        -- 开始有音频输出后，播放文件会由exaudio.play_start自动唤醒，无需手动设置
        -- exaudio.pm(exaudio.RESUME)
    elseif status == "HANGUP_CALL_DONE" or status == "MAKE_CALL_FAILED" or status == "DISCONNECTED" then
        -- 通话结束，主动进入低功耗模式
        exaudio.pm(exaudio.SHUTDOWN)
    end
end)

-- ====================== 电话系统初始化 ======================
local function init_cc()
    -- 初始化音频设备
    audio_drv.initAudioDevice()
    
    -- 等待电话系统就绪
    sys.waitUntil("CC_READY")
    
    -- 初始化电话功能
    cc.init(audio_drv.getMultimediaId())
    
    -- 启用通话录音（录音功能在cc_app中）
    enableRecording()
    
    log.info("cc_app", "电话系统初始化完成")
end

-- 启动初始化任务
sys.taskInit(init_cc)