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
4. 录音文件仅支持SD卡存储

功能说明：
- 来电自动接听：响铃2声后自动接听来电
- 通话录音：自动开始录音，对方挂断后停止录音
- AMR转码（可选）：默认关闭，如需AMR格式请取消注释相关代码

录音功能特性：
- 录音文件保存为PCM格式：/sd/record_call.pcm
- 可选AMR转码：/sd/record_call.amr（需手动开启）
- 只保存上行数据（包含本地声音和网络回声）
- 下行数据自动跳过，避免重复存储
- 支持SD卡自动挂载和空间检测
- 根据通话质量自动选择AMR-NB（8KHz）或AMR-WB（16KHz）

使用方法：
1. 默认只生成PCM文件：/sd/record_call.pcm
2. 如需AMR格式，找到 stop_call_recording() 函数，取消 convert_pcm_to_amr() 的注释

注意事项：
1. 本模块仅支持呼入自动接听功能
2. 录音文件仅支持SD卡存储，必须插入SD卡才能使用录音功能
3. PCM文件为原始音频格式，可用Audacity等工具播放
4. AMR文件为通用格式，手机播放器可直接播放
]]

-- 引入音频设备模块
local audio_drv = require "audio_drv"
local exaudio = require "exaudio"

-- ====================== 配置区域 ======================

-- 全局状态变量
local call_counter = 0                 -- 响铃计数器
local caller_number = ""               -- 来电号码

-- SD卡挂载路径和录音文件保存路径
local SD_MOUNT_PATH = "/sd"
local RECORD_FILE_PATH = SD_MOUNT_PATH .. "/record_call.pcm"  -- 录音文件路径（PCM原始格式）
local RECORD_AMR_FILE_PATH = SD_MOUNT_PATH .. "/record_call.amr"  -- 转码后的AMR文件路径
-- 整机开发板上TF卡的的pin_cs为gpio16，spi_id为0.请根据实际硬件修改
local spi_id = 0
local pin_cs = 16
-- 核心板CS为IO8
-- local pin_cs = 8

-- 录音功能相关函数
local is_recording_to_file = false  -- 录音状态标志：true表示正在录音到文件
local record_file = nil                -- 录音文件句柄
local record_start_time = 0            -- 录音开始时间戳（毫秒）
local record_duration = 0              -- 录音时长（秒）
local record_sample_rate = 8000        -- 录音采样率

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

-- ====================== sd卡挂载函数 ======================

-- 挂载SD卡
local function mount_sd_card()
    log.info("SD卡", "开始挂载SD卡")
    
    -- 检查SD卡是否已挂载
    if io.exists(SD_MOUNT_PATH) then
        log.info("SD卡", "SD卡已挂载:", SD_MOUNT_PATH)
        return true
    end
    
    -- 初始化SPI接口
    -- 打开ch390供电脚（使用开发板需要打开此注释）
    gpio.setup(20, 1, gpio.PULLUP) 
    --上拉ch390使用spi的cs引脚避免干扰（使用开发板需要打开此注释）
    gpio.setup(8,1)
    
    -- 初始化SPI接口
    spi.setup(spi_id, nil, 0, 0, 8, 2000000)
    -- 设置片选引脚为高电平
    gpio.setup(pin_cs, 1)
    
    -- 尝试挂载SD卡
    local mount_ok, mount_err = fatfs.mount(fatfs.SPI, SD_MOUNT_PATH, spi_id, pin_cs, 24 * 1000 * 1000)
    
    if mount_ok then
        log.info("SD卡", "SD卡挂载成功:", SD_MOUNT_PATH)
        
        -- 获取SD卡空间信息
        local data, err = fatfs.getfree(SD_MOUNT_PATH)
        if data then
            log.info("SD卡空间信息", json.encode(data))
        else
            log.warn("获取SD卡空间信息失败", err)
        end
        
        return true
    else
        log.error("SD卡", "SD卡挂载失败:", mount_err)
        return false
    end
end

-- ====================== 录音功能 ======================

-- 创建音频数据缓冲区
local up1 = zbuff.create(BUFFER_SIZE,0)      -- 上行数据保存区1
local up2 = zbuff.create(BUFFER_SIZE,0)      -- 上行数据保存区2
local down1 = zbuff.create(BUFFER_SIZE,0)    -- 下行数据保存区1
local down2 = zbuff.create(BUFFER_SIZE,0)    -- 下行数据保存区2

-- 打开录音文件
local function open_record_file()
    -- 先挂载SD卡
    if not mount_sd_card() then
        log.error("录音文件", "SD卡挂载失败，无法进行录音")
        return false
    end
    
    log.info("录音文件", "SD卡挂载成功，录音文件将保存到SD卡")
    
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
    -- 获取通话质量，用于后续AMR转码
    local quality = cc.quality()
    if quality then
        -- 根据通话质量确定采样率
        if quality.amr_wb and quality.amr_wb == 1 then
            record_sample_rate = 16000  -- AMR-WB模式，16KHz
        else
            record_sample_rate = 8000   -- AMR-NB模式，8KHz
        end
        log.info("通话质量", quality)
    end
end

-- 启用通话录音
local function enableRecording()
    cc.record(true, up1, up2, down1, down2)
    cc.on("record", recordCallback)
    log.info("cc_app", "通话录音已启用")
end

-- 开始通话录音到文件
local function start_call_recording()
    if open_record_file() then
        log.info("通话录音", "开始录音到文件:", RECORD_FILE_PATH)
        return true
    else
        log.error("通话录音", "无法开始录音到文件，请检查SD卡")
        return false
    end
end

-- 将PCM录音文件转码为AMR格式
-- 注意：此函数在通话结束后异步执行，避免阻塞主线程
local function convert_pcm_to_amr()
    log.info("AMR转码", "开始将PCM转码为AMR格式...")
    
    -- 检查PCM文件是否存在
    if not io.exists(RECORD_FILE_PATH) then
        log.error("AMR转码", "PCM文件不存在:", RECORD_FILE_PATH)
        return false
    end
    
    -- 删除旧的AMR文件
    if io.exists(RECORD_AMR_FILE_PATH) then
        os.remove(RECORD_AMR_FILE_PATH)
        log.info("AMR转码", "删除旧AMR文件")
    end
    
    -- 创建AMR编码器
    local amr_coder = codec.create(codec.AMR, record_sample_rate, 4)
    if not amr_coder then
        log.error("AMR转码", "创建AMR编码器失败")
        return false
    end
    
    -- 打开PCM文件
    local pcm_file = io.open(RECORD_FILE_PATH, "rb")
    if not pcm_file then
        log.error("AMR转码", "无法打开PCM文件:", RECORD_FILE_PATH)
        codec.release(amr_coder)
        return false
    end
    
    -- 创建AMR输出文件
    local amr_file = io.open(RECORD_AMR_FILE_PATH, "wb")
    if not amr_file then
        log.error("AMR转码", "无法创建AMR文件:", RECORD_AMR_FILE_PATH)
        pcm_file:close()
        codec.release(amr_coder)
        return false
    end
    
    -- 写入AMR文件头
    if record_sample_rate == 16000 then
        amr_file:write("#!AMR-WB\n")  -- AMR-WB文件头
        log.info("AMR转码", "使用AMR-WB格式(16KHz)")
    else
        amr_file:write("#!AMR\n")     -- AMR-NB文件头
        log.info("AMR转码", "使用AMR-NB格式(8KHz)")
    end
    
    -- 计算帧大小
    local frame_samples = record_sample_rate == 16000 and 640 or 320  -- AMR-WB: 640 samples, AMR-NB: 320 samples
    local frame_bytes = frame_samples * 2  -- 16bit = 2 bytes per sample
    
    -- 创建缓冲区
    local read_buff = zbuff.create(frame_bytes)
    local amr_out = zbuff.create(1024)
    
    local total_encoded = 0
    local start_time = mcu.ticks()
    local pcm_size = io.fileSize(RECORD_FILE_PATH)
    
    -- 读取并编码PCM数据
    while true do
        local data = pcm_file:read(frame_bytes)
        if not data or #data < frame_bytes then
            break  -- 文件读取完毕或数据不足一帧
        end
        
        -- 将数据复制到zbuff
        read_buff:del()
        read_buff:copy(nil, data)
        
        -- 使用pcall保护编码操作
        local ok, result = pcall(function()
            return codec.encode(amr_coder, read_buff, amr_out)
        end)
        
        if ok and result then
            -- 写入编码后的数据
            amr_file:write(amr_out:query())
            total_encoded = total_encoded + amr_out:used()
        else
            log.warn("AMR转码", "编码失败，跳过当前帧")
        end
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

-- 停止通话录音到文件
local function stop_call_recording()
    close_record_file()
    log.info("通话录音", "停止录音到文件")
    
    -- 如需AMR格式，取消下面这行的注释
    -- 转码在通话结束后异步执行，避免阻塞主线程
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
    elseif status == "HANGUP_CALL_DONE" or status == "MAKE_CALL_FAILED" or status == "DISCONNECTED" then
        exaudio.pm(audio.SHUTDOWN)   --主动进入低功耗模式
    end
end)

-- ====================== 电话系统初始化 ======================
local function init_cc()
    -- 先尝试挂载SD卡
    mount_sd_card()
    
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