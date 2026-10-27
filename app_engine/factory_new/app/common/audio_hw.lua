--[[
@module  audio_hw
@summary exaudio.setup 入参统一组装（hw.audio → exaudio.setup / 音量）
@version 1.0
@date    2026.10.27
@author  江访

=== 设计要点 ===

1. 全固件只此一处组装 exaudio.setup 的入参。tts_app / llm_chat / factory_rec /
   settings_display_app / video_util / periph_audio 六个消费方一律调用本模块，
   不再各自复制一份字段白名单（字段漏传只会让全局音频失效，且现象离因很远）。

2. **uart_id 与 audio_mode 必传**：exaudio 内部 uart_id 缺省取 1，
   而 Air1103（model="air1103"）实际接在 UART6（Air8605W / Air8605M），
   漏传会把语音芯片绑到 UART1（那一路是隔离 RS485），
   录音采不到数据、播放也没声音。boot_ui.guard_audio_init 把 exaudio.setup
   收口成只执行首次，air1103.init 也不换串口，
   所以第一次 setup 的入参决定全局，任何一处漏传后续全部补不回来。

3. air1103 模式补 bits_per_sample=16、channels=1（芯片固定 16kHz/16bit/单声道，
   与 module/Air8784/project/factory 参考工程的 exaudio.setup 入参一致）。

4. tx_bus_type / rx_bus_type 只有成对给出才透传，单侧不传（分总线播放/录音
   必须两侧一起配，只配一侧底层会得到半截驱动）。

5. setup 成功后立即套用 ac.play_vol（「亮度和声音」页 set_volume 的统一写回点）；
   boot_ui 把 setup 记忆化后，重复调用仍会重新套音量。

=== 对外接口 ===

  audio_hw.cfg()          -> table|nil      hw.audio 配置（nil = 本板无音频能力）
  audio_hw.is_air1103()   -> boolean        是否 Air1103 UART 语音芯片
  audio_hw.params(extra)  -> table          exaudio.setup 入参（extra 同名字段覆盖）
  audio_hw.setup(extra)   -> ok, err        pcall(exaudio.setup, params) + 套用音量
  audio_hw.vol()          -> ok             单独套用 ac.play_vol
  audio_hw.exaudio()      -> table|nil      require 到的 exaudio（无音频固件上为 nil）
]]

local M = {}

-- exaudio 是固件扩展库，须 require 绑定；顶层引用 i2s 常量，无音频固件上 require 会报错。
-- 懒加载：顶层 require 会把 exaudio 提前进开机关键路径（≈100ms），
-- 本模块可能被 settings_display_app 在显示完成前 require，故只在调用时加载
local exaudio_mod = nil
local exaudio_loaded = false

-- 编译系统按 require "exaudio" 的字面文本决定打包范围，故这里保持字面写法；
-- 函数体内才调用，保留上面的懒加载语义
local function load_exaudio()
    return require "exaudio"
end

local function get_exaudio()
    if not exaudio_loaded then
        exaudio_loaded = true
        local ok, m = pcall(load_exaudio)
        exaudio_mod = ok and type(m) == "table" and m or nil
    end
    return exaudio_mod
end

-- hw.audio 里需要逐字段透传的键（成对总线键单独处理，见 params）
local PASSTHROUGH_KEYS = {
    "dac_ctrl", "i2c_id", "i2s_sample", "bits_per_sample", "i2s_framebit", "channels",
    "pa_delay", "tx_bus_type", "tx_bus_id", "rx_bus_type", "rx_bus_id",
    "audio_mode", "uart_id",
}

--[[
@function cfg
@summary 取板级音频配置（hw.audio），nil 即本板无音频能力
@return table|nil
]]
function M.cfg()
    local c = _G.project_config
    return c and c.hw and c.hw.audio
end

--[[
@function is_air1103
@summary 是否 Air1103 UART 语音芯片（MIC + 喇叭 + AEC 单芯片方案）
@return boolean
]]
function M.is_air1103()
    local ac = M.cfg()
    return ac ~= nil and ac.model == "air1103"
end

--[[
@function params
@summary 组装 exaudio.setup 入参
@param extra table|nil 同名字段覆盖（一般传 nil）
@return table
]]
function M.params(extra)
    local ac = M.cfg() or {}
    local sp = {
        model = ac.model or "es8311",
        pa_ctrl = ac.pa_ctrl,
        pa_on_level = ac.pa_on_level or 1,
        dac_delay = ac.dac_delay,
    }
    for i = 1, #PASSTHROUGH_KEYS do
        local k = PASSTHROUGH_KEYS[i]
        if ac[k] ~= nil then sp[k] = ac[k] end
    end
    if not (ac.tx_bus_type and ac.rx_bus_type) then
        sp.tx_bus_type, sp.tx_bus_id = nil, nil
        sp.rx_bus_type, sp.rx_bus_id = nil, nil
    end
    -- Air1103 走 UART，固定 16kHz/16bit/单声道
    if sp.model == "air1103" then
        sp.bits_per_sample = 16
        sp.channels = 1
    end
    if type(extra) == "table" then
        for k, v in pairs(extra) do sp[k] = v end
    end
    return sp
end

--[[
@function vol
@summary 套用媒体音量（读 hw.audio.play_vol，settings_display_app 的统一写回点）
@return boolean
]]
function M.vol()
    local ex = get_exaudio()
    if not ex or not ex.vol then return false end
    local ac = M.cfg() or {}
    pcall(ex.vol, ac.play_vol or 70)
    return true
end

--[[
@function setup
@summary 初始化音频：组装入参 → exaudio.setup → 套用音量
@param extra table|nil 同名字段覆盖
@return boolean, string|nil
]]
function M.setup(extra)
    local ac = M.cfg()
    if not ac then return false, "未配置 hw.audio" end
    local ex = get_exaudio()
    if not ex or not ex.setup then return false, "缺少 exaudio 扩展库" end
    local sp = M.params(extra)
    local ok, ret = pcall(ex.setup, sp)
    if not ok then return false, "exaudio.setup 异常: " .. tostring(ret) end
    if not ret then return false, "音频初始化失败" end
    M.vol()
    return true
end

--[[
@function exaudio
@summary 取 exaudio 扩展库实例（无音频固件上为 nil）
@return table|nil
]]
function M.exaudio()
    return get_exaudio()
end

return M
