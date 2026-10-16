--[[
@module  audio_record
@summary AirCAMERA_1032 摄像头麦克风录音+TF卡存储+板载DAC播放
@version 1.2
@date    2026.08.20
@author  王城钧
@usage

注意：
1. AirCAMERA_1032 摄像头自带麦克风，为标准 USB Audio Class（UAC）声卡，
   采样率固定 8000Hz/16bit/单声道
2. 播放使用 Air1601 板载 DAC0 输出，需在开发板 DAC 输出口接喇叭/功放
3. 本demo需要使用Air1601-V1.2开发板 + AirCAMERA_1032摄像头测试

录音+播放演示程序：
开机初始化USB摄像头，摄像头连接成功后自动开始录音，
录音文件保存到TF卡（/sd/record.wav，挂载失败自动回退/ram），
录音结束后自动通过板载DAC0播放录音。

工作流程：
1. 初始化：USB主机模式上电，等待摄像头连接，设置音频驱动
2. 录音：挂载TF卡，通过USB声卡麦克风录音 record_seconds 秒
3. 播放：录音结束后等待 playback_delay 秒，通过板载DAC0播放录音文件

本文件没有对外接口，直接在main.lua中require "audio_record"就可以加载运行。
]]

-- ==================== 用户配置区 ====================
local record_seconds = 10             -- 录音时长（秒），0=无限录音
local record_codec = audio_v2.DATA_CODEC_TYPE_WAV  -- 编码格式: WAV/AMR_NB/AMR_WB/RAW
local sample_rate = 8000              -- 采样率(Hz)，AirCAMERA_1032 麦克风只支持 8000
local sample_bits = 16                -- 位深(bit)，麦克风固定 16
local channels = 1                    -- 声道数，麦克风固定单声道
local save_path = "/sd/record.wav"    -- 录音文件保存路径
local loop_record = false             -- true=录完一次自动开始下一次（循环录音）
-- 固件兼容：audio_v2 计算录音总字节数时同一份数据累加两次，导致实际录音时长减半。
-- 向框架传入 record_seconds * record_fw_bug_factor，以得到真实时长。若固件已修复，请改为 1
local record_fw_bug_factor = 2
local auto_playback = true            -- true=录完音后自动播放录音
local playback_delay = 3              -- 录音结束后等待多少秒再开始播放
local play_volume = 300               -- 播放音量（软件增益 0~1000，100=1倍，1000=10倍）

--   功放(PA)使能引脚：
--   Air1601_V1.2 开发板 = 73（高电平有效）
local pa_enable_pin = nil             -- 功放(PA)使能引脚，nil=不启用
local pa_on_level = 1                 -- PA 使能电平（1=高电平，0=低电平）
local pa_on_delay_ms = 100            -- PA 上电延迟(ms)

-- ==================== TF卡配置区 ====================
local use_tf_card = true              -- true=录音保存到TF卡(/sd)，false=保存到/ram
local tf_power_pin = 56               -- TF卡供电引脚（高电平开启供电）
local tf_spi_id = 1                   -- TF卡SPI总线ID
local tf_cs_pin = 8                   -- TF卡片选引脚
local tf_spi_init_freq = 400000       -- SPI初始化频率(Hz)，挂载前用低速确保识别
local tf_spi_freq = 24000000          -- TF卡挂载后SPI工作频率(Hz)
local tf_mount_point = "/sd"          -- TF卡挂载点
local ram_fallback_path = "/ram/record.wav"  -- TF卡挂载失败时的回退保存路径

-- ==================== 全局变量 ====================
local usb_app_id = nil                -- USB摄像头应用ID
local record_req_id = nil             -- audio_v2录音请求索引
local recording = false               -- 是否正在录音
local record_done = false             -- 本次录音是否已结束（供主任务判断）
local play_req_id = nil               -- audio_v2播放请求索引
local playing = false                 -- 是否正在播放录音
local tf_mounted = false              -- TF卡是否挂载成功

-- 摄像头供电（GPIO58 拉高）
gpio.setup(58, 1, gpio.PULLUP)

-- ==================== TF卡初始化 ====================
-- 挂载成功：save_path 指向 TF 卡；挂载失败：回退到 /ram，保证录音功能可用
local function init_tf_card()
    if not use_tf_card then
        save_path = ram_fallback_path
        log.info("audio_record", "TF卡存储已关闭，录音保存到", save_path)
        return false
    end
    -- 1. 开启 TF 卡供电
    gpio.setup(tf_power_pin, 1, gpio.PULLUP)
    sys.wait(300)  -- 等待供电稳定（大容量卡需更长时间）
    -- 2. SPI 初始化（低速），片选拉高，防止与其他 SPI 从设备互相干扰
    spi.setup(tf_spi_id, nil, 0, 0, 8, tf_spi_init_freq)
    gpio.setup(tf_cs_pin, 1)
    -- 3. 挂载 fatfs（挂载失败默认自动格式化），失败则断电重启卡并重试
    for retry = 1, 3 do
        local mount_ok, mount_err = fatfs.mount(fatfs.SPI, tf_mount_point, tf_spi_id, tf_cs_pin, tf_spi_freq)
        if mount_ok then
            tf_mounted = true
            save_path = tf_mount_point .. "/record.wav"
            log.info("audio_record", "TF卡挂载成功，录音保存到", save_path)
            return true
        end
        log.warn("audio_record", "TF卡挂载失败(第", retry, "次):", mount_err)
        if retry < 3 then
            -- 断电重启 TF 卡：拉低供电脚 → 等待 → 重新上电 → 等待
            log.info("audio_record", "断电重启TF卡...")
            gpio.setup(tf_power_pin, 0)
            sys.wait(200)  -- 断电保持，确保TF卡完全掉电复位
            gpio.setup(tf_power_pin, 1, gpio.PULLUP)
            sys.wait(300)  -- 重新上电后等待供电稳定
        end
    end
    tf_mounted = false
    save_path = ram_fallback_path
    log.error("audio_record", "TF卡挂载失败，回退到", save_path)
    return false
end

-- 卸载 TF 卡并关闭 SPI
local function deinit_tf_card()
    if tf_mounted then
        if fatfs.unmount(tf_mount_point) then
            log.info("audio_record", "TF卡卸载成功")
        else
            log.error("audio_record", "TF卡卸载失败")
        end
        tf_mounted = false
    end
    spi.close(tf_spi_id)
    log.info("audio_record", "SPI接口已关闭")
end

-- ==================== 音频驱动设置 ====================
-- 录音走 USB 声卡（摄像头麦克风），播放走板载 DAC0
local function setup_default_driver()
    -- 设置默认驱动：tx=DAC0(播放), rx=USB0(录音)
    local probe_id = audio_v2.make_probe_id(audio_v2.DRIVER_TYPE_DAC, 0, audio_v2.DRIVER_TYPE_USB, 0)
    local ok = audio_v2.set_default_driver(probe_id)
    if not ok then
        log.error("audio_record", "默认音频驱动设置失败，请确认USB摄像头(麦克风)已连接且固件支持UAC")
        return false
    end
    log.info("audio_record", "默认音频驱动设置成功: 录音USB声卡0/播放DAC0")

    -- 配置功放(PA)电源控制：DAC 播放时 PA 放大输出，音量显著提升
    if pa_enable_pin then
        local pa_ok = audio_v2.config_pa_power_ctrl(true, pa_enable_pin, pa_on_level, pa_on_delay_ms)
        if pa_ok then
            log.info("audio_record", "PA功放已使能: GPIO" .. pa_enable_pin .. " 电平" .. pa_on_level)
        else
            log.warn("audio_record", "PA功放配置失败，音量可能偏小")
        end
    end

    -- 配置 codec 电源/就绪时序：电源不控制，播放前预留 200ms 空白音。
    audio_v2.config_codec_power_ctrl(false, nil, nil, 200, 10)

    -- 设置软件音量增益（作用于默认驱动/播放通道）
    audio_v2.soft_volume(play_volume)
    return true
end

-- ==================== audio_v2 事件回调 ====================
-- 仅处理 REQUEST_END：录音/播放结束时更新状态标志，
-- 主任务（record_done）和播放等待（playing）都依赖此回调
local function audio_v2_cb(request_index, event, param)
    if event == audio_v2.REQUEST_END then
        -- 播放结束：清理播放状态
        if request_index == play_req_id then
            play_req_id = nil
            playing = false
        -- 录音结束：清理录音状态，标记录音完成
        elseif request_index == record_req_id then
            record_req_id = nil
            recording = false
            record_done = true
        end
    end
end
audio_v2.on(audio_v2_cb)  -- 注册audio_v2事件回调

-- ==================== 开始/停止录音 ====================
local function start_record()
    if recording then
        log.warn("audio_record", "正在录音中，请勿重复启动")
        return false
    end
    record_done = false
    -- 录音到文件：第2个参数为录音时长（秒），时长到后自动停止。
    -- 因固件 bug 实际时长减半，这里乘上 record_fw_bug_factor 补偿
    local result, req_id = audio_v2.record(
        save_path,                          -- 保存路径
        record_seconds * record_fw_bug_factor, -- 传给框架的时长（补偿后为真实时长）
        record_codec,                       -- 编码器ID
        0,                                  -- 优先级
        sample_rate,                        -- 采样率
        sample_bits,                        -- 位深
        channels                            -- 声道数
    )
    if result then
        record_req_id = req_id
        recording = true
        log.info("audio_record", "录音已开始, req_id", req_id)
        return true
    else
        log.error("audio_record", "录音启动失败")
        return false
    end
end

local function stop_record()
    if recording and record_req_id then
        audio_v2.stop(record_req_id)
        log.info("audio_record", "已请求停止录音")
    end
end

-- ==================== 开始/停止播放录音 ====================
local function start_playback()
    if playing then
        log.warn("audio_record", "正在播放中，请勿重复启动")
        return false
    end
    if not io.exists(save_path) or io.fileSize(save_path) <= 0 then
        log.error("audio_record", "录音文件不存在或为空，无法播放:", save_path)
        return false
    end
    -- 通过板载 DAC0 播放（默认驱动）
    local result, req_id = audio_v2.play(save_path, true, 0)
    if result then
        play_req_id = req_id
        playing = true
        log.info("audio_record", "播放已开始(DAC0), req_id", req_id)
        return true
    else
        log.error("audio_record", "播放启动失败")
        return false
    end
end

local function stop_playback()
    if playing and play_req_id then
        audio_v2.stop(play_req_id)
        log.info("audio_record", "已请求停止播放")
    end
end

-- 录音结束后自动播放：等待 playback_delay 秒后播放，并阻塞至播放结束
local function playback_after_record()
    if not auto_playback then
        return false
    end
    if not io.exists(save_path) or io.fileSize(save_path) <= 0 then
        log.error("audio_record", "录音文件不存在或为空，无法播放:", save_path)
        return false
    end
    log.info("audio_record", playback_delay .. "秒后开始播放录音...")
    sys.wait(playback_delay * 1000)  -- 等待 playback_delay 秒再开始播放
    if not start_playback() then return false end
    -- 等待播放完成
    while playing do
        sys.wait(200)  -- 轮询播放状态
    end
    log.info("audio_record", "播放完成")
    return true
end

-- ==================== 摄像头事件回调（标准UVC接口） ====================
-- 摄像头断开/异常时统一停止播放和录音
local function stop_audio_on_camera_gone()
    usb_app_id = nil
    stop_playback()
    stop_record()
end

local function camera_cb(app_id, event, param)
    -- USB 摄像头连接：枚举完成后，USB 音频(麦克风)驱动应已注册
    if event == usb.EV_CONNECT then
        log.info("audio_record", "USB摄像头已连接, app id", app_id)
        usb_app_id = app_id
        sys.publish("USB_AUDIO_READY")
        return
    end

    -- USB 摄像头断开
    if event == usb.EV_DISCONNECT then
        log.warn("audio_record", "USB摄像头已断开, app id", app_id)
        stop_audio_on_camera_gone()
        return
    end

    -- USB 摄像头接收数据异常并已停止工作
    if event == usb.EV_ERR_STOP then
        log.warn("audio_record", "USB摄像头接收数据异常，已停止工作")
        usb.reset_device(0, app_id)
        stop_audio_on_camera_gone()
    end
end

-- ==================== 主任务 ====================
local function main_task()
    log.info("audio_record", "初始化USB摄像头（标准UVC接口）...")

    -- 注册摄像头事件回调
    camera.on(camera.USB, "usb_raw", camera_cb)

    -- USB 主机模式上电
    pm.power(pm.USB, false)
    usb.mode(0, usb.HOST)
    pm.power(pm.USB, true)

    -- 等待 USB 摄像头连接（标准 UVC 接口枚举完成，含 USB 麦克风/UAC 声卡）
    sys.waitUntil("USB_AUDIO_READY", 30000)
    if not usb_app_id then
        log.error("audio_record", "等待USB摄像头连接超时")
        return
    end

    -- 设置音频驱动（失败自动重试，间隔500ms，无需额外延时等待驱动注册）
    local ok = false
    for i = 1, 5 do
        ok = setup_default_driver()
        if ok then break end
        sys.wait(500)  -- 必要延时：驱动未就绪时的重试间隔，给UAC声卡驱动注册留出时间
    end
    if not ok then
        log.error("audio_record", "USB声卡驱动不可用，录音功能退出")
        return
    end

    -- 初始化 TF 卡（挂载成功则保存到 TF 卡/sd，失败回退到/ram）
    init_tf_card()

    -- 开始录音
    if not start_record() then return end

    if loop_record then
        -- ====== 循环录音：录完一次→播放→再开始下一次 ======
        while true do
            sys.wait(200)  -- 轮询录音完成状态
            if record_done and not recording then
                record_done = false
                -- 录音完成后自动播放（播放结束后再间隔1秒开始下一次录音）
                playback_after_record()
                sys.wait(1000)  -- 间隔1秒再开始下一次
                start_record()
            end
        end
    else
        -- ====== 单次录音 ======
        if record_seconds == 0 then
            log.info("audio_record", "无限录音中，如需停止请调用 stop_record() 或断电复位")
        end
        while true do
            sys.wait(200)  -- 轮询录音状态，录音结束后退出
            if not recording then
                break
            end
        end
        log.info("audio_record", "本次录音完成, 文件", save_path)
        -- 录音完成后自动播放
        playback_after_record()
        -- 单次录音流程结束，卸载 TF 卡并关闭 SPI（循环录音模式下不卸载）
        deinit_tf_card()
    end
end

sys.taskInit(main_task)
