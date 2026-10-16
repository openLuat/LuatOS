--[[
@module  settings_display_app
@summary 亮度与声音业务逻辑层
@version 1.3
@date    2026.10.15
@author  江访
@usage
本模块为亮度与声音业务逻辑层，管理PWM背光亮度调节与喇叭媒体音量。
提供亮度增减、设置、查询接口，以及媒体音量设置、查询、试听接口。

媒体音量（hw.audio 存在时默认启用，无需配置开关）：
起播方（llm_chat / factory_rec / video_util）每次都读
project_config.hw.audio.play_vol，本模块把用户音量写回该字段，
新起的播放即用新音量；正在播放的用 exaudio.vol 立即生效。

媒体音量与背光亮度经 fskv 持久化（media_volume / display_brightness），
设置即保存；restore() 从 fskv 恢复两者并写回 hw.audio.play_vol /
hw.lcd.backlight.level，供起播方与 backlight_on 开机点亮使用。
boot_ui 开机第 0 步先 fskv.init 再调 restore()；fskv 挂载是异步的，
未就绪时模块内后台短轮询重试，SETTINGS_APP_INIT 再对齐一次。

消息协议（订阅/发布）:
订阅: DISPLAY_BRIGHTNESS_INCREASE    → 亮度 +10
订阅: DISPLAY_BRIGHTNESS_DECREASE    → 亮度 -10
订阅: DISPLAY_BRIGHTNESS_SET(level)  → 设置亮度值 (10-100)
订阅: DISPLAY_BRIGHTNESS_GET         → 查询当前亮度
发布: DISPLAY_BRIGHTNESS_CHANGED(level) → 亮度变化通知
发布: DISPLAY_BRIGHTNESS_VALUE(level)   → 亮度查询返回值
订阅: AUDIO_VOLUME_SET(level)        → 设置媒体音量 (0-100)
订阅: AUDIO_VOLUME_GET               → 查询当前媒体音量
订阅: AUDIO_PLAY_TEST                → 播放一段试听语音
发布: AUDIO_VOLUME_CHANGED(level)    → 媒体音量变化通知
发布: AUDIO_VOLUME_VALUE(level)      → 媒体音量查询返回值
]]
-- ==================== 局部变量 ====================
local pwm_initialized = false  -- PWM 初始化标志

-- 从配置文件读取背光 PWM 参数（hw.lcd.backlight）
local cfg = _G.project_config
local pwm_channel, pwm_freq = 0, 1000
local bl_cfg = cfg and cfg.hw and cfg.hw.lcd and cfg.hw.lcd.backlight
if bl_cfg then
    pwm_channel = bl_cfg.pwm_ch or 0
    pwm_freq = bl_cfg.pwm_freq or 1000
end

local current_brightness = (bl_cfg and bl_cfg.level) or 100  -- 当前亮度值 (10-100)

-- ==================== 媒体音量 ====================
-- exaudio 是固件扩展库，须 require 绑定（video_util / llm_chat 同款拿法），
-- 裸用全局 exaudio 在 LuatOS 里恒为 nil；无音频固件上取不到则为 nil，下面全部判空。
-- 懒加载：顶层 require 会在开机关键路径提前拉入 exaudio（≈100ms），
-- 首次真正用到时才加载（音量设置/试听/音量恢复，均在显示完成之后）
local exaudio = nil
local exaudio_loaded = false
local function get_exaudio()
    if not exaudio_loaded then
        exaudio_loaded = true
        local ok, m = pcall(require, "exaudio")
        exaudio = ok and m or nil
    end
    return exaudio
end

-- 支持 audio 功能（hw.audio 已配置）即默认开启音量调节，不设配置开关
local FSKV_VOLUME = "media_volume"            -- 媒体音量 fskv 持久化键
local FSKV_BRIGHTNESS = "display_brightness"  -- 背光亮度 fskv 持久化键
local DEFAULT_VOLUME = 70            -- 默认媒体音量 (0-100)

local ac = cfg and cfg.hw and cfg.hw.audio
local has_audio = ac ~= nil
local current_volume = (ac and ac.play_vol) or DEFAULT_VOLUME
local restored_brightness = false  -- 亮度恢复完成标志（幂等）
local restored_volume = false      -- 音量恢复完成标志（幂等）

--[[
@function save_fskv
@summary 写 fskv 持久化（fskv 挂载是异步的，先 init 确保就绪）
@param key fskv 键
@param val fskv 值
]]
local function save_fskv(key, val)
    pcall(fskv.init)
    pcall(fskv.set, key, val)
end

--[[
@function set_volume
@summary 设置媒体音量：写回 play_vol + 立即生效 + 持久化，并上报变更事件
@param level 音量值 (0-100)
]]
local function set_volume(level)
    local exaudio = get_exaudio()
    level = tonumber(level) or current_volume
    if level < 0 then
        level = 0
    elseif level > 100 then
        level = 100
    end
    current_volume = level
    -- 写回配置表：llm_chat / factory_rec / video_util
    -- 每次起播都读 ac.play_vol，新起的播放自动用上用户音量
    if ac then ac.play_vol = level end
    -- exaudio.vol 是驱动级全局增益，正在播放的音轨立即生效；
    -- exaudio 在无音频固件上不存在，须判空后再 pcall
    if exaudio and exaudio.vol then pcall(exaudio.vol, level) end
    save_fskv(FSKV_VOLUME, level)
    log.info("settings_display", "媒体音量设置为: " .. level .. "%")
    -- 上报媒体音量变化事件
    sys.publish("AUDIO_VOLUME_CHANGED", current_volume)
end

--[[
@function play_volume_test
@summary 播放一段试听语音（llm_chat TTS 同款 exaudio 配方，勿走旧框架 audio.tts）
]]
local function play_volume_test()
    local exaudio = get_exaudio()
    if not has_audio then
        log.warn("settings_display", "未配置 hw.audio，无法试听")
        return
    end
    if not exaudio then
        log.warn("settings_display", "exaudio 扩展库不可用，无法试听")
        return
    end
    if not exaudio.play_start then
        log.warn("settings_display", "exaudio.play_start 不存在，无法试听")
        return
    end
    -- exaudio.setup 幂等，每次完整组装（与 llm_chat tts_init 一致）
    local sp = { model = ac.model or "es8311", pa_ctrl = ac.pa_ctrl,
                 pa_on_level = ac.pa_on_level or 1, dac_delay = ac.dac_delay }
    if ac.dac_ctrl then sp.dac_ctrl = ac.dac_ctrl end
    if ac.i2c_id then sp.i2c_id = ac.i2c_id end
    if ac.i2s_sample then sp.i2s_sample = ac.i2s_sample end
    if ac.bits_per_sample then sp.bits_per_sample = ac.bits_per_sample end
    if ac.i2s_framebit then sp.i2s_framebit = ac.i2s_framebit end
    if ac.channels then sp.channels = ac.channels end
    if ac.pa_delay then sp.pa_delay = ac.pa_delay end
    if ac.tx_bus_type and ac.rx_bus_type then
        sp.tx_bus_type = ac.tx_bus_type; sp.tx_bus_id = ac.tx_bus_id or 0
        sp.rx_bus_type = ac.rx_bus_type; sp.rx_bus_id = ac.rx_bus_id or 0
    end
    if ac.audio_mode then sp.audio_mode = ac.audio_mode end
    pcall(exaudio.setup, sp)
    if exaudio.vol then pcall(exaudio.vol, current_volume) end
    pcall(exaudio.play_stop, { type = 1 })
    pcall(exaudio.play_start, { type = 1, content = "音量测试" })
end

-- ==================== 内部函数 ====================
--[[
@function write_back_brightness
@summary 背光亮度写回配置表 hw.lcd.backlight.level（backlight_on 开机点亮取该值作占空比）
@param level 亮度值 (10-100)
]]
local function write_back_brightness(level)
    local lcd = cfg and cfg.hw and cfg.hw.lcd
    if lcd then
        lcd.backlight = lcd.backlight or {}
        lcd.backlight.level = level
    end
end

--[[
@function init_pwm
@summary 初始化背光 PWM
]]
local function init_pwm()
    if not pwm_initialized then
        local ok, err = pcall(pwm.setup, pwm_channel, pwm_freq, current_brightness)
        if not ok then
            log.error("settings_display", "PWM setup 失败:", err)
            return
        end
        ok, err = pcall(pwm.start, pwm_channel)
        if not ok then
            log.error("settings_display", "PWM start 失败:", err)
            return
        end
        pwm_initialized = true
        log.info("settings_display", "PWM 初始化完成，初始亮度: " .. current_brightness)
    end
end

--[[
@function set_brightness
@summary 设置背光亮度：写回配置表 + fskv 持久化，并上报变更事件
@param level 亮度值 (10-100)
]]
local function set_brightness(level)
    if not pwm_initialized then
        init_pwm()
    end
    if level < 10 then
        level = 10
    elseif level > 100 then
        level = 100
    end
    current_brightness = level
    -- 写回配置表：backlight_on 开机点亮读 backlight.level 作占空比
    write_back_brightness(level)
    local ok, err = pcall(pwm.setDuty, pwm_channel, level)
    if not ok then
        log.error("settings_display", "PWM setDuty 失败:", err)
    end
    save_fskv(FSKV_BRIGHTNESS, level)
    log.info("settings_display", "亮度设置为: " .. level .. "%")
    -- 上报亮度变化事件
    sys.publish("DISPLAY_BRIGHTNESS_CHANGED", current_brightness)
end

-- ==================== 初始化 ====================
--[[
@function fskv_ready
@summary fskv 挂载就绪探测（挂载是异步的，init 成功才算就绪）
@return boolean true=就绪
]]
local function fskv_ready()
    -- 未就绪时 fskv.get 返回 nil，与「无记录」区分不了，调用方返回 false 等重试
    local ok, inited = pcall(fskv.init)
    return (ok and inited) and true or false
end

--[[
@function restore_brightness
@summary 从 fskv 恢复背光亮度，写回 hw.lcd.backlight.level（backlight_on 点亮取该值作占空比）
@return boolean true=已恢复，false=fskv 未就绪（后台重试）
]]
local function restore_brightness()
    if restored_brightness then return true end
    if not fskv_ready() then return false end
    local ok_b, val_b = pcall(fskv.get, FSKV_BRIGHTNESS)
    if ok_b and type(val_b) == "number" then
        current_brightness = val_b
        if current_brightness < 10 then current_brightness = 10 end
        if current_brightness > 100 then current_brightness = 100 end
    end
    write_back_brightness(current_brightness)
    -- 背光已由 backlight_on 配置 PWM 时才热应用新亮度；pwm 未 setup 前
    -- setDuty 会刷 C 层 error（值已写回配置表，点亮时自然生效，无需提前调）
    if bl_cfg and pwm_initialized then
        pcall(pwm.setDuty, pwm_channel, current_brightness)
    end
    restored_brightness = true
    log.info("settings_display", "背光亮度恢复: " .. current_brightness .. "%")
    return true
end

--[[
@function restore_volume
@summary 从 fskv 恢复媒体音量，写回 hw.audio.play_vol（含 exaudio 懒加载，显示之后调用）
@return boolean true=已恢复，false=fskv 未就绪（等后续重试）
]]
local function restore_volume()
    if restored_volume then return true end
    if not has_audio then return true end
    if not fskv_ready() then return false end
    -- 媒体音量：无论是否有 fskv 记录都写回，顺带归一 play_vol 的兜底值，
    -- 免得各起播方的 or 70 / or 100 兜底不一致
    local ok, val = pcall(fskv.get, FSKV_VOLUME)
    if ok and type(val) == "number" then
        current_volume = val
        if current_volume < 0 then current_volume = 0 end
        if current_volume > 100 then current_volume = 100 end
    end
    if ac then ac.play_vol = current_volume end
    -- 正在播放的音轨立即对齐（未起播时是空操作）
    local exaudio = get_exaudio()
    if exaudio and exaudio.vol then pcall(exaudio.vol, current_volume) end
    restored_volume = true
    log.info("settings_display", "媒体音量恢复: " .. current_volume .. "%")
    return true
end

--[[
@function restore
@summary 恢复背光亮度 + 媒体音量（兼容合口；开机路径分别调 restore_brightness / restore_volume）
@return boolean true=both 就绪
]]
local function restore()
    local ok_b = restore_brightness()
    local ok_v = restore_volume()
    return ok_b and ok_v
end

sys.subscribe("SETTINGS_APP_INIT", restore)

-- fskv 挂载是异步的：开机首次亮度恢复未就绪时后台短轮询重试，就绪即停。
-- 只重试亮度（点亮前关键路径）；音量由 restore_volume 在显示之后的批里补
-- （可选批调用 + SETTINGS_APP_INIT 各一次，幂等）
local function restore_retry_task()
    for _ = 1, 30 do
        sys.wait(100)
        if restore_brightness() then return end
    end
    log.warn("settings_display", "fskv 长时间未就绪，亮度使用默认值")
end
sys.taskInit(restore_retry_task)

-- ==================== 事件订阅 ====================
-- 订阅亮度增加事件
sys.subscribe("DISPLAY_BRIGHTNESS_INCREASE", function()
    local new_level = current_brightness + 10
    if new_level > 100 then
        new_level = 100
    end
    set_brightness(new_level)
end)

-- 订阅亮度减少事件
sys.subscribe("DISPLAY_BRIGHTNESS_DECREASE", function()
    local new_level = current_brightness - 10
    if new_level < 10 then
        new_level = 10
    end
    set_brightness(new_level)
end)

-- 订阅亮度设置事件（直接设置指定值）
sys.subscribe("DISPLAY_BRIGHTNESS_SET", function(level)
    if type(level) == "number" then
        set_brightness(level)
    end
end)

-- 订阅亮度查询事件（业务层上报当前值；查询前对齐一次 fskv 恢复）
sys.subscribe("DISPLAY_BRIGHTNESS_GET", function()
    restore()
    sys.publish("DISPLAY_BRIGHTNESS_VALUE", current_brightness)
end)

if has_audio then
    -- 订阅媒体音量设置事件（滑块拖动直接给绝对值）
    sys.subscribe("AUDIO_VOLUME_SET", function(level)
        set_volume(level)
    end)

    -- 订阅媒体音量查询事件（业务层上报当前值；查询前对齐一次 fskv 恢复）
    sys.subscribe("AUDIO_VOLUME_GET", function()
        restore()
        sys.publish("AUDIO_VOLUME_VALUE", current_volume)
    end)

    -- 订阅试听事件（设置页音量滑块旁的「测试」）
    sys.subscribe("AUDIO_PLAY_TEST", play_volume_test)
end

-- ==================== 模块导出 ====================
-- boot_ui 开机路径：fskv.init → 显示完成后 restore_brightness()（背光点亮取该值）、
-- 可选批里 restore_volume()（音频域，含 exaudio 懒加载）；restore() 为兼容合口
local M = {}
M.restore = restore
M.restore_brightness = restore_brightness
M.restore_volume = restore_volume
return M
