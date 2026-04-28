--[[
@module  http_download_play
@summary HTTP下载音频文件播放
@version 1.0
@date    2026.04.24
@author  拓毅恒
@usage

注意：
如果搭配AirAUDIO_1000 音频板测试，需将AirAUDIO_1000 音频板中PA开关拨到OFF，让软件控制PA，避免pop音

HTTP下载音频文件播放演示程序，按键功能：
1. Power键：开始HTTP下载并播放，停止播放
   - 空闲时按Power键开始下载并播放音频
   - 播放中按Power键停止播放
2. Boot键：停止播放
   - 播放中按Boot键停止播放

音量设置：
  播放音量：70

下载播放逻辑：
  自动根据URL后缀识别音频格式（PCM/MP3/AMR）
  PCM格式使用流式播放，MP3/AMR格式使用文件播放
  支持SD卡存储，文件大于200KB时必须使用SD卡

工作流程：
1. 初始化：挂载SD卡，设置音频硬件参数，等待网络就绪
2. 下载：发送HTTP请求下载音频文件到SD卡或内存
3. 播放：下载完成后自动播放音频文件
4. 状态管理：互斥控制下载/播放状态
]]

local exaudio = require "exaudio"

-- 根据版本号自适应设置dac_delay
local set_dac_delay = 0
local version = rtos.version()
local version_num = 0
if version then
    -- 从版本号字符串中提取数字部分
    local num_str = version:match("V(%d+)")
    if num_str then
        version_num = tonumber(num_str)
    end
end

if version_num and version_num >= 2026 then
    -- 固件版本≥V2026，dac_delay单位为100ms
    set_dac_delay = 6
else
    -- 固件版本＜V2026，dac_delay单位为1ms
    set_dac_delay = 600
end

-- 全局状态
local is_playing = false       -- 是否正在播放
local is_downloading = false   -- 是否正在下载
local download_task_handle = nil -- 下载任务句柄
local sd_mounted = false       -- SD卡挂载状态
local temp_file_dir = ""       -- 临时文件目录

-- 音量设置
local PLAY_VOLUME = 70         -- 播放音量

-- 音频文件URL（支持 .mp3/.amr /.pcm 格式，自动识别）
local AUDIO_URL = "http://airtest.openluat.com:2900/download/sample-6s.mp3"  -- MP3格式示例
-- local AUDIO_URL = "http://airtest.openluat.com:2900/download/10.amr"  -- AMR格式示例
-- local AUDIO_URL = "http://airtest.openluat.com:2900/download/test.pcm"

-- SD卡配置参数
local sd_spi_id = 0            -- SPI接口编号
local sd_cs_pin = 16           -- 片选引脚 核心板cs为8 开发板cs为16 按照自己的硬件选择
local sd_mount_path = "/sd"    -- SD卡挂载路径

-- 硬件配置参数
local audio_setup_param = {
    model = "es8311",          -- 音频编解码芯片类型
    i2c_id = 0,                -- I2C接口编号
    pa_ctrl = gpio.AUDIOPA_EN, -- 音频放大器控制引脚
    dac_ctrl = 20,             -- 音频编解码芯片控制引脚

    -- 【注意：固件版本＜V2026，这里单位为1ms，这里填600，否则可能第一个字播不出来】
    dac_delay = set_dac_delay, -- DAC启动前冗余时间

    i2s_sample = 16000,         -- I2S采样率
    bits_per_sample = 16,       -- I2S录音位深
    i2s_framebit = 16           -- I2S通道位宽
}

-- ========== 工具函数 ==========

-- 根据URL获取音频格式
local function get_audio_format(url)
    if not url then return "pcm" end
    -- 提取URL中的文件扩展名
    local ext = url:match("%.([^.]+)$")
    if ext then
        ext = ext:lower()
        if ext == "mp3" then
            return "mp3"
        elseif ext == "amr" then
            return "amr"
        elseif ext == "pcm" then
            return "pcm"
        end
    end
    -- 默认返回pcm
    return "pcm"
end

-- 根据格式获取临时文件扩展名
local function get_temp_file_ext(format)
    if format == "mp3" then
        return ".mp3"
    elseif format == "amr" then
        return ".amr"
    else
        return ".pcm"
    end
end

-- ========== 播放相关函数 ==========

-- 播放完成回调函数
local function play_end_callback(event)
    if event == exaudio.PLAY_DONE then
        log.info("http_pcm_stream_play", "播放完成")
        is_playing = false
        is_downloading = false
    end
end

-- 停止播放
local function stop_playback()
    if is_playing then
        log.info("http_pcm_stream_play", "停止播放")
        -- 根据当前音频格式选择停止方式
        local audio_format = get_audio_format(AUDIO_URL)
        if audio_format == "pcm" then
            exaudio.play_stop({type = 2})  -- 停止流式播放
        else
            exaudio.play_stop({type = 0})  -- 停止文件播放
        end
        is_playing = false
        is_downloading = false
    end

    -- 如果有正在进行的下载任务，等待其结束
    if download_task_handle then
        -- 给下载任务一点时间清理
        sys.wait(100)
        download_task_handle = nil
    end
end

-- HTTP下载并播放任务
local function http_download_and_play_task()
    -- 自动识别音频格式
    local audio_format = get_audio_format(AUDIO_URL)
    log.info("http_pcm_stream_play", "音频格式:", audio_format, "URL:", AUDIO_URL)

    is_downloading = true

    -- 根据SD卡挂载状态选择临时文件路径
    local temp_file_path = temp_file_dir .. "tmp_http_audio" .. get_temp_file_ext(audio_format)
    log.info("http_pcm_stream_play", "临时文件路径:", temp_file_path, sd_mounted and "(SD卡)" or "(内存)")

    -- 先发送HEAD请求获取文件大小
    log.info("http_pcm_stream_play", "获取文件大小...")
    local head_code, head_headers = http.request("HEAD", AUDIO_URL, nil, nil, {timeout = 10000}).wait()

    local file_size = 0
    if head_code == 200 and head_headers then
        -- 从响应头中获取Content-Length
        local content_length = head_headers["Content-Length"] or head_headers["content-length"]
        if content_length then
            file_size = tonumber(content_length) or 0
            log.info("http_pcm_stream_play", "文件大小:", file_size, "字节 (", string.format("%.2f", file_size / 1024), "KB)")
        end
    end

    -- 检查文件大小：大于200KB(204800字节)且SD卡未挂载时，拒绝下载
    local MAX_MEMORY_FILE_SIZE = 204800  -- 200KB
    if file_size > MAX_MEMORY_FILE_SIZE and not sd_mounted then
        log.error("http_pcm_stream_play", "文件过大，请用SD卡下载")
        log.error("http_pcm_stream_play", "文件大小:", string.format("%.2f", file_size / 1024), "KB, 最大支持:", MAX_MEMORY_FILE_SIZE / 1024, "KB (内存)")
        is_downloading = false
        download_task_handle = nil
        return
    end

    -- HTTP下载回调函数
    local function download_callback(content_len, body_len, userdata)
        log.info("http_pcm_stream_play", "下载进度:", body_len, "/", content_len or "unknown")
    end

    -- 发送HTTP请求，将数据保存到文件
    local code, headers, body_size = http.request("GET", AUDIO_URL, nil, nil, {
        timeout = 60000,
        dst = temp_file_path,  -- 保存到文件
        callback = download_callback,
        userdata = "http_audio_download"
    }).wait()

    if code == 200 then
        log.info("http_pcm_stream_play", "HTTP下载完成，文件大小:", body_size)

        -- 根据音频格式选择播放方式
        local play_param

        if audio_format == "pcm" then
            -- PCM格式：使用流式播放
            play_param = {
                type = 2,                   -- 2=流式播放
                sampling_rate = 16000,      -- 采样率
                sampling_depth = 16,        -- 采样位深
                signed_or_unsigned = true,  -- PCM数据是否有符号
                cbfnc = play_end_callback,  -- 播放完毕回调
                priority = 1                -- 播放优先级
            }
            log.info("http_pcm_stream_play", "PCM使用流式播放")
        else
            -- MP3/AMR格式：使用文件播放
            play_param = {
                type = 0,                   -- 0=文件播放
                content = temp_file_path,   -- 音频文件路径
                cbfnc = play_end_callback,  -- 播放完毕回调
                priority = 1                -- 播放优先级
            }
            log.info("http_pcm_stream_play", audio_format:upper(), "使用文件播放")
        end

        -- 启动播放
        local play_result = exaudio.play_start(play_param)
        if not play_result then
            log.error("http_pcm_stream_play", "播放启动失败")
            is_downloading = false
            os.remove(temp_file_path)
            return
        end

        is_playing = true
        log.info("http_pcm_stream_play", "播放已启动")

        -- PCM格式：读取文件数据并写入流式播放队列
        if audio_format == "pcm" then
            local f = io.open(temp_file_path, "rb")
            if f then
                local chunk_size = 2048  -- 每次读取2KB
                while true do
                    local chunk = f:read(chunk_size)
                    if not chunk or #chunk == 0 then
                        break
                    end
                    -- 写入流式播放队列
                    exaudio.play_stream_write(chunk)
                    -- 控制写入速度，避免缓冲区溢出
                    sys.wait(10)
                end
                f:close()
                -- 通知流式播放数据已结束
                exaudio.finish()
                log.info("http_pcm_stream_play", "PCM数据写入完成")
            else
                log.error("http_pcm_stream_play", "无法打开PCM文件")
                exaudio.play_stop({type = 2})
                is_playing = false
                is_downloading = false
                os.remove(temp_file_path)
                return
            end
        end

        -- 等待播放完成
        while is_playing do
            sys.wait(100)
        end

        -- 删除临时文件
        os.remove(temp_file_path)
        log.info("http_pcm_stream_play", "临时文件已删除")
    else
        log.error("http_pcm_stream_play", "HTTP下载失败，状态码:", code)
    end

    is_downloading = false
    download_task_handle = nil
end

-- 挂载SD卡函数
local function mount_sd_card()
    log.info("http_pcm_stream_play", "开始挂载SD卡")

    -- 打开ch390供电脚（使用开发板需要打开此注释）
    gpio.setup(20, 1, gpio.PULLUP)
    -- 上拉ch390使用spi的cs引脚避免干扰（使用开发板需要打开此注释）
    gpio.setup(8, 1)

    -- 初始化SPI接口
    spi.setup(sd_spi_id, nil, 0, 0, 400 * 1000)
    -- 设置片选引脚为高电平
    gpio.setup(sd_cs_pin, 1)

    -- 挂载SD卡，挂载失败时自动格式化
    local mount_ok, mount_err = fatfs.mount(fatfs.SPI, sd_mount_path, sd_spi_id, sd_cs_pin, 24 * 1000 * 1000)

    if mount_ok then
        log.info("http_pcm_stream_play", "SD卡挂载成功", "挂载路径:", sd_mount_path)
        sd_mounted = true
        temp_file_dir = sd_mount_path .. "/"

        -- 获取SD卡空间信息
        local data, err = fatfs.getfree(sd_mount_path)
        if data then
            log.info("http_pcm_stream_play", "SD卡空间信息", json.encode(data))
        else
            log.warn("http_pcm_stream_play", "获取SD卡空间信息失败", err)
        end
        return true
    else
        log.error("http_pcm_stream_play", "SD卡挂载失败", mount_err)
        sd_mounted = false
        temp_file_dir = "/"
        return false
    end
end

-- 开始HTTP下载并播放
local function start_http_play()
    if is_playing or is_downloading then
        log.info("http_pcm_stream_play", "正在播放或下载中，请先停止")
        return
    end

    -- 检查网络是否就绪
    if not socket.adapter(socket.dft()) then
        log.error("http_pcm_stream_play", "网络未就绪，请检查网络连接")
        return
    end

    -- 启动下载播放任务
    log.info("http_pcm_stream_play", "启动HTTP下载播放任务")
    download_task_handle = sys.taskInit(http_download_and_play_task)
end

-- ========== 按键处理函数 ==========

-- POWERKEY键：开始HTTP下载并播放
local function powerkey_handler()
    log.info("http_pcm_stream_play", "按下POWERKEY键")

    if is_playing or is_downloading then
        -- 如果正在播放，则停止
        log.info("http_pcm_stream_play", "停止当前播放")
        stop_playback()
    else
        -- 空闲状态：开始HTTP下载并播放
        local audio_format = get_audio_format(AUDIO_URL)
        log.info("http_pcm_stream_play", "开始HTTP下载并播放", audio_format)
        start_http_play()
    end
end

-- BOOT键：停止播放
local function boot_key_handler()
    log.info("http_pcm_stream_play", "按下BOOT键")

    if is_playing or is_downloading then
        log.info("http_pcm_stream_play", "停止播放")
        stop_playback()
    else
        log.info("http_pcm_stream_play", "当前未在播放")
    end
end

-- ========== 音频主任务 ==========

local function main_audio_task()
    log.info("http_pcm_stream_play", "音频系统初始化")

    -- 尝试挂载SD卡
    mount_sd_card()

    -- 等待网络就绪
    log.info("http_pcm_stream_play", "等待网络就绪...")
    while not socket.adapter(socket.dft()) do
        log.info("http_pcm_stream_play", "网络未就绪，等待中...")
        sys.wait(1000)
    end
    log.info("http_pcm_stream_play", "网络已就绪")

    -- 获取音频格式
    local audio_format = get_audio_format(AUDIO_URL)

    -- 初始化音频硬件
    if exaudio.setup(audio_setup_param) then
        -- 设置音量
        exaudio.vol(PLAY_VOLUME)

        log.info("http_pcm_stream_play", "音量设置:", PLAY_VOLUME)
        log.info("http_pcm_stream_play", "音频硬件初始化成功")

        log.info("http_pcm_stream_play", "存储路径:", sd_mounted and (sd_mount_path .. " (SD卡)") or "/ (内存)")
        log.info("http_pcm_stream_play", "按键功能说明：")
        log.info("http_pcm_stream_play", "1. Power键: 开始HTTP下载并播放音频")
        log.info("http_pcm_stream_play", "2. Boot键: 停止播放")
        log.info("http_pcm_stream_play", "3. 音频URL:", AUDIO_URL)
        log.info("http_pcm_stream_play", "4. 音频格式:", audio_format)
        if audio_format == "pcm" then
            log.info("http_pcm_stream_play", "5. PCM参数: 16kHz, 16bit, 有符号")
        end
    else
        log.error("http_pcm_stream_play", "音频硬件初始化失败")
    end
end

-- ========== 初始化设置 ==========

-- 设置POWERKEY键（开始/停止播放）
gpio.setup(gpio.PWR_KEY, powerkey_handler, gpio.PULLUP, gpio.FALLING)
gpio.debounce(gpio.PWR_KEY, 200, 1)

-- 设置BOOT键（停止播放）
gpio.setup(0, boot_key_handler, gpio.PULLDOWN, gpio.RISING)
gpio.debounce(0, 200, 1)

-- 启动音频主任务
sys.taskInit(main_audio_task)

