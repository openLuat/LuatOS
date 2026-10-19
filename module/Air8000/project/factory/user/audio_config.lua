--[[
@module  audio_config
@summary Air8000 系列音频封装（基于 exaudio 新框架，es8311）
@version 1.0
@date    2026.10.16
@usage
对外接口（与 Air8780 factory 保持一致，业务层无需改动）：
- audio_config.init()                        初始化音频（exaudio.setup）
- audio_config.audio_play_tts(text)          播放 TTS（入队串行播放）
- audio_config.audio_play_file(url,name,del) 下载并播放音频文件（mp3/amr/wav）

硬件依据 Air8000 开发板：es8311 挂硬件 I2C0（pin80/81），pa_ctrl=GPIO162，dac_ctrl=GPIO164
（核心板为 pa_ctrl=17 / dac_ctrl=16，如有差异在此文件修改）
注意：exaudio.play_start / play_stop 只允许在 task 中调用，本模块用单一播放任务串行处理。
]]

audio_config = {}

local exaudio = require "exaudio"
io.mkdir("/afile/")

-- ==================== 版本自适应 dac_delay ====================
-- 固件版本 ≥ V2026：dac_delay 单位为 100ms，填 6
-- 固件版本 < V2026：dac_delay 单位为 1ms，填 600（否则首字可能播不出来）
local function get_dac_delay()
    local num = tonumber(tostring(rtos.version() or ""):match("V(%d+)") or "0")
    if num >= 2026 then
        return 6
    end
    return 600
end

-- ==================== exaudio.setup 参数 ====================
local audio_setup_param = {
    model = "es8311",     -- 音频编解码型号：es8311（AirAUDIO_1020 改 tm8211 并去掉 i2c_id）
    i2c_id = 0,           -- 硬件 I2C0（pin80=SCL / pin81=SDA）
    dac_delay = get_dac_delay(),
    pa_ctrl = 162,        -- Air8000 开发板 PA 使能（核心板改为 17）
    dac_ctrl = 164,       -- Air8000 开发板 codec 电源（核心板改为 16）
    audio_mode = "auto",  -- 框架自动选择
}

-- ==================== 播放队列（单任务串行，杜绝并发抢占） ====================
local TASK_NAME = "audio_play_task"
local playQueue = {}

-- 播放结束回调：收到 PLAY_DONE 后停止本次播放并唤醒播放任务
local function play_end(event)
    if event == exaudio.PLAY_DONE then
        log.info("audio_config", "播放完成", exaudio.is_end())
        sys.publish(TASK_NAME, "DONE")
    end
end

-- 队列播放任务：所有 exaudio.play_start 都在此任务内执行
local function audio_task()
    while true do
        local item = table.remove(playQueue, 1)
        if item then
            -- 中断上一段尚未结束的播放，保证新指令立即响应
            pcall(exaudio.play_stop, { type = item.ptype })
            local ok = pcall(exaudio.play_start, {
                type = item.ptype,       -- 0=文件播放 1=TTS
                content = item.content,
                cbfnc = play_end,
            })
            if ok then
                -- 等待播放完成回调；兜底超时（TTS 60s / 文件 120s），防止异常卡死队列
                local deadline = item.ptype == 1 and 60000 or 120000
                local waited = 0
                local done = false
                while waited < deadline do
                    local res = sys.waitUntil(TASK_NAME, 500)
                    -- sys.waitUntil 返回 true 表示收到 publish（非超时）
                    if res then
                        done = true
                        break
                    end
                    waited = waited + 500
                end
                if not done then
                    log.warn("audio_config", "播放等待超时，强制停止")
                end
                pcall(exaudio.play_stop, { type = item.ptype })
            else
                log.error("audio_config", "play_start 调用失败", item.content)
            end
            -- 文件播放且要求播后删除
            if item.delete_file and item.local_path then
                os.remove(item.local_path)
            end
        else
            sys.waitUntil(TASK_NAME)
        end
    end
end

local function enqueue(item)
    table.insert(playQueue, item)
    sys.publish(TASK_NAME, "WAKE")
end

-- ==================== 对外接口：TTS 播放 ====================
function audio_config.audio_play_tts(playdata)
    if not playdata or playdata == "" then
        return false
    end
    log.info("audio_config", "TTS入队", playdata)
    enqueue({ ptype = 1, content = playdata })
    return true
end

-- ==================== 对外接口：网络音频文件下载后播放 ====================
function audio_config.audio_play_file(url, file_name, isdelete)
    log.info("audio_config", "文件播放", url, file_name, isdelete)
    sys.taskInit(function()
        if not url or url == "" then
            log.error("audio_config", "url 为空")
            return
        end
        local local_path = "/afile/" .. (file_name or tostring(os.time()) .. ".mp3")
        local code = http.request("GET", url, nil, nil, { dst = local_path }).wait()
        log.info("audio_config", "下载完成", code)
        if code ~= 200 or not io.exists(local_path) then
            log.error("audio_config", "音频下载失败", code)
            return
        end
        enqueue({
            ptype = 0,
            content = local_path,
            local_path = local_path,
            delete_file = tonumber(isdelete) == 1,
        })
    end)
    return true
end

-- ==================== 对外接口：初始化 ====================
-- 返回值：成功 true，失败 false
function audio_config.init()
    if not exaudio.setup(audio_setup_param) then
        log.error("audio_config", "音频初始化失败，检查 I2C0 / pa_ctrl / dac_ctrl")
        return false
    end
    -- 持久化音量（fskv key: vol）
    local vol = fskv.get("vol")
    if vol then
        exaudio.vol(vol)
        log.info("audio_config", "音量设置成功", vol)
    end
    sys.taskInitEx(audio_task, TASK_NAME)
    return true
end

return audio_config
