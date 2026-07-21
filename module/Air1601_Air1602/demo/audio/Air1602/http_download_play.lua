--[[
@module  http_download_play
@summary HTTP下载音频文件播放
@version 1.0
@date    2026.07.21
@author  拓毅恒
@usage

注意：
1. Air1602使用内置DAC输出音频，无需外部音频编解码芯片
2. 需要固件版本>=V1024才可播放音频

HTTP下载音频文件播放演示程序：
开机自动连接WiFi，连接成功后自动开始HTTP下载音频文件并播放

音量设置：
  播放音量：70

下载播放逻辑：
  自动根据URL后缀识别音频格式（PCM/MP3/AMR）
  PCM格式使用流式播放，MP3/AMR格式使用文件播放
  支持SD卡存储，文件大于200KB时必须使用SD卡（暂不支持）

工作流程：
1. 初始化：设置音频硬件参数，等待网络就绪
2. 下载：发送HTTP请求下载音频文件到SD卡或内存（暂时仅支持下载到内存播放）
3. 播放：下载完成后自动播放音频文件
]]

local exaudio = require "exaudio"
local exnetif = require "exnetif"

-- WiFi配置
local WIFI_SSID = "luatos1234"
local WIFI_PASS = "12341234"

-- 全局状态
local is_playing = false       -- 是否正在播放
local sd_mounted = false       -- SD卡挂载状态
local temp_file_dir = ""       -- 临时文件目录

-- 音量设置
local PLAY_VOLUME = 70         -- 播放音量

-- 音频文件URL（支持 .mp3/.amr /.pcm 格式，自动识别）
local AUDIO_URL = "http://airtest.openluat.com:2900/download/sample-6s.mp3"  -- MP3格式示例
-- local AUDIO_URL = "http://airtest.openluat.com:2900/download/10.amr"  -- AMR格式示例
-- local AUDIO_URL = "http://airtest.openluat.com:2900/download/test.pcm"

-- SD卡配置参数（暂不支持）
-- local sd_spi_id = nil            -- SPI接口编号
-- local sd_cs_pin = nil            -- TF卡片选引脚
-- local sd_mount_path = "/sd"    -- TF卡挂载路径

-- 硬件配置参数
local audio_setup_param ={
    model = "dac",            -- 音频编解码类型: "dac" 表示使用内置DAC
    
    pa_ctrl = 45,             -- 音频放大器电源控制管脚，Air1602畅玩版-IO45，Air1602_V1.2开发板-IO73
    pa_on_level = 1,          -- PA打开电平，0=低电平使能，1=高电平使能
    dac_delay = 6,            -- DAC启动前冗余时间，单位为100ms
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
        log.info("http_download_play", "播放完成")
        is_playing = false
    end
end

-- 挂载SD卡函数
local function mount_sd_card()
    log.info("http_download_play", "开始挂载SD卡")

    -- 拉高CS脚避免干扰
    gpio.setup(sd_cs_pin, 1, gpio.PULLUP)

    -- 初始化SPI接口（先用低速400kHz挂载）
    spi.setup(sd_spi_id, nil, 0, 0, 8, 400 * 1000)
    -- 设置片选引脚为高电平
    gpio.setup(sd_cs_pin, 1)

    -- 挂载SD卡，挂载失败时自动格式化
    local mount_ok, mount_err = fatfs.mount(fatfs.SPI, sd_mount_path, sd_spi_id, sd_cs_pin, 24 * 1000 * 1000)

    if mount_ok then
        log.info("http_download_play", "SD卡挂载成功", "挂载路径:", sd_mount_path)
        sd_mounted = true
        temp_file_dir = sd_mount_path .. "/"

        -- 获取SD卡空间信息
        local data, err = fatfs.getfree(sd_mount_path)
        if data then
            log.info("http_download_play", "SD卡空间信息", json.encode(data))
        else
            log.warn("http_download_play", "获取SD卡空间信息失败", err)
        end
        return true
    else
        log.info("http_download_play", "SD卡挂载失败", mount_err)
        sd_mounted = false
        temp_file_dir = "/"
        return false
    end
end

-- 下载并播放音频文件
local function download_and_play()
    -- 自动识别音频格式
    local audio_format = get_audio_format(AUDIO_URL)
    log.info("http_download_play", "音频格式:", audio_format, "URL:", AUDIO_URL)

    -- 根据SD卡挂载状态选择临时文件路径
    local temp_file_path = temp_file_dir .. "tmp_http_audio" .. get_temp_file_ext(audio_format)
    log.info("http_download_play", "临时文件路径:", temp_file_path, sd_mounted and "(SD卡)" or "(内存)")

    -- 先发送HEAD请求获取文件大小
    log.info("http_download_play", "获取文件大小...")
    local head_code, head_headers = http.request("HEAD", AUDIO_URL, nil, nil, {timeout = 10000}).wait()

    local file_size = 0
    if head_code == 200 and head_headers then
        -- 从响应头中获取Content-Length
        local content_length = head_headers["Content-Length"] or head_headers["content-length"]
        if content_length then
            file_size = tonumber(content_length) or 0
            log.info("http_download_play", "文件大小:", file_size, "字节 (", string.format("%.2f", file_size / 1024), "KB)")
        end
    end

    -- 检查文件大小：大于200KB(204800字节)且SD卡未挂载时，拒绝下载
    local MAX_MEMORY_FILE_SIZE = 204800  -- 200KB
    if file_size > MAX_MEMORY_FILE_SIZE and not sd_mounted then
        log.error("http_download_play", "文件过大，请用SD卡下载")
        log.error("http_download_play", "文件大小:", string.format("%.2f", file_size / 1024), "KB, 最大支持:", MAX_MEMORY_FILE_SIZE / 1024, "KB (内存)")
        return
    end

    -- HTTP下载回调函数
    local function download_callback(content_len, body_len, userdata)
        log.info("http_download_play", "下载进度:", body_len, "/", content_len or "unknown")
    end

    -- 发送HTTP请求，将数据保存到文件
    local code, headers, body_size = http.request("GET", AUDIO_URL, nil, nil, {
        timeout = 60000,
        dst = temp_file_path,  -- 保存到文件
        callback = download_callback,
        userdata = "http_audio_download"
    }).wait()

    if code == 200 then
        log.info("http_download_play", "HTTP下载完成，文件大小:", body_size)

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
            log.info("http_download_play", "PCM使用流式播放")
        else
            -- MP3/AMR格式：使用文件播放
            play_param = {
                type = 0,                   -- 0=文件播放
                content = temp_file_path,   -- 音频文件路径
                cbfnc = play_end_callback,  -- 播放完毕回调
                priority = 1                -- 播放优先级
            }
            log.info("http_download_play", audio_format:upper(), "使用文件播放")
        end

        -- 启动播放
        local play_result = exaudio.play_start(play_param)
        if not play_result then
            log.error("http_download_play", "播放启动失败")
            os.remove(temp_file_path)
            return
        end

        is_playing = true
        log.info("http_download_play", "播放已启动")

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
                log.info("http_download_play", "PCM数据写入完成")
            else
                log.error("http_download_play", "无法打开PCM文件")
                exaudio.play_stop({type = 2})
                is_playing = false
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
        log.info("http_download_play", "临时文件已删除")
    else
        log.error("http_download_play", "HTTP下载失败，状态码:", code)
    end
end

-- ========== 网络连接 ==========

local function wait_network_ready()
    log.info("wifi", "开始连接WiFi", WIFI_SSID)
    sys.subscribe("WLAN_STA_INC", function(evt, data) log.info("wifi", "STA事件:", evt, data) end)
    sys.subscribe("IP_READY", function(ip, adapter)
        if adapter == socket.LWIP_STA then
            socket.setDNS(adapter, 1, "223.5.5.5")
            socket.setDNS(adapter, 2, "114.114.114.114")
            log.info("wifi", "IP_READY", socket.localIP(socket.LWIP_STA))
        end
    end)
    exnetif.set_priority_order({
        {
            airlink_wifi = {
                auto_socket_switch = false,
                airlink_type = airlink.MODE_SPI_MASTER,
                airlink_spi_id = 1,
                airlink_cs_pin = 8,
                airlink_rdy_pin = 14,
                ssid = WIFI_SSID,
                password = WIFI_PASS
            }
        }
    })
    log.info("wifi", "等待IP获取...")
    local r = sys.waitUntil("IP_READY", 30000)
    if r then
        log.info("wifi", "WiFi连接成功"); return true
    else
        log.error("wifi", "WiFi连接超时"); return false
    end
end

-- ========== 音频主任务 ==========

local function main_audio_task()
    log.info("http_download_play", "音频系统初始化")

    -- 尝试挂载SD卡（暂不支持）
    -- mount_sd_card()

    -- 初始化音频硬件
    if exaudio.setup(audio_setup_param) then
        -- 设置音量
        exaudio.vol(PLAY_VOLUME)
        log.info("http_download_play", "音量设置:", PLAY_VOLUME)
        log.info("http_download_play", "音频硬件初始化成功")
    else
        log.error("http_download_play", "音频硬件初始化失败")
        return
    end

    -- 连接WiFi
    if not wait_network_ready() then
        return
    end

    -- WiFi连接成功后，自动开始下载并播放
    log.info("http_download_play", "WiFi已连接，开始下载并播放音频")
    log.info("http_download_play", "音频URL:", AUDIO_URL)
    log.info("http_download_play", "音频格式:", get_audio_format(AUDIO_URL))
    log.info("http_download_play", "存储路径:", sd_mounted and (sd_mount_path .. " (SD卡)") or "/ (内存)")

    download_and_play()
end

-- 启动音频主任务
sys.taskInit(main_audio_task)
