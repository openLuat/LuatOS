--[[
@module  audio.player
@summary 音频播放模块
@version 4.0
@date    2026.07.31
@usage
参考 Air8201 demo play_file.lua 架构：
- 一个永久音频 task，通过消息队列控制播放
]]

local audio_player = {}
local exaudio = require("exaudio")
local TASK_NAME = "task_audio"
local MSG_PLAY = 1

-- 音频电源控制引脚
local DAC_CTRL_PIN = 2
local PA_CTRL_PIN = 25

-- 根据版本号自适应设置dac_delay
local set_dac_delay = 0
local version = rtos.version()
local version_num = 0
if version then
    local num_str = version:match("V(%d+)")
    if num_str then
        version_num = tonumber(num_str)
    end
end
if version_num and version_num >= 2026 then
    set_dac_delay = 6
else
    set_dac_delay = 600
end

-- 音频初始化参数
local audio_setup_param = {
    model = "es8311",
    i2c_id = 0,
    pa_ctrl = PA_CTRL_PIN,
    dac_ctrl = DAC_CTRL_PIN,
    dac_delay = set_dac_delay,
    audio_mode = "new",
    codec_voltage = 1,
}

-- 播放结束回调
local function play_end(event)
    if event == exaudio.PLAY_DONE then
        log.info("audio_player", "播放完成")
    end
end

-- 音频播放参数模板
local audio_play_param = {
    type = 0,
    content = "",
    cbfnc = play_end,
}

-- 永久音频 task
local function audio_task()
    log.info("audio_player", "音频task启动")
    gpio.setup(DAC_CTRL_PIN, 1)
    gpio.setup(PA_CTRL_PIN, 1)
    sys.wait(20)
    if not exaudio.setup(audio_setup_param) then
        log.error("audio_player", "音频硬件初始化失败")
        gpio.setup(DAC_CTRL_PIN, 0)
        gpio.setup(PA_CTRL_PIN, 0)
        return
    end
    exaudio.vol(80)
    log.info("audio_player", "音频初始化成功，等待播放指令")

    while true do
        local msg = sys.waitMsg(TASK_NAME, MSG_PLAY)
        if msg and msg[2] then
            local file_path = msg[2]
            log.info("audio_player", "播放音频:", file_path)
            audio_play_param.content = file_path
            if exaudio.play_start(audio_play_param) then
                log.info("audio_player", "音频播放开始")
            else
                log.error("audio_player", "音频播放失败:", file_path)
            end
        end
    end
end

-- 启动音频 task
sys.taskInitEx(audio_task, TASK_NAME)

-- 播放本地音频文件
-- @param string file_path 音频文件路径
function audio_player.play_file(file_path)
    log.info("audio_player", "请求播放本地音频:", file_path)
    sys.sendMsg(TASK_NAME, MSG_PLAY, file_path)
end

-- 播放在线音频文件，下载后播放
-- @param string url 音频文件URL
function audio_player.play_url(url)
    log.info("audio_player", "请求播放在线音频:", url)
    sys.taskInit(function()
        local temp_path = "/tmp_audio.mp3"
        if io.exists(temp_path) then os.remove(temp_path) end
        local code = http.request("GET", url, {}, "", {
            dst = temp_path,
            timeout = 60000
        }).wait()
        if code == 200 and io.exists(temp_path) then
            audio_player.play_file(temp_path)
        else
            log.error("audio_player", "在线音频下载失败, code:", code)
        end
    end)
end

-- 设置音量
function audio_player.set_volume(volume)
    exaudio.vol(volume)
end

-- 停止播放
function audio_player.stop()
    exaudio.play_stop({type = 0})
end

return audio_player