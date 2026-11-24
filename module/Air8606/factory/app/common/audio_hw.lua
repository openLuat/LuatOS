--[[
@module  audio_hw
@summary exaudio.setup 入参统一组装（hw.audio → exaudio.setup / 音量）+ 音频占用租约
@version 1.1
@date    2026.11.13
@author  江访

=== 设计要点 ===

1. 全固件只此一处组装 exaudio.setup 的入参。tts_app / llm_chat / factory_rec /
   settings_display_app / periph_audio 五个消费方一律调用本模块，
   不再各自复制一份字段白名单（字段漏传只会让全局音频失效，且现象离因很远）。

2. **uart_id 与 audio_mode 必传**：exaudio 内部 uart_id 缺省取 1，
   而 Air1103（model="air1103"）实际接在 UART6（Air8605W / Air8605M），
   漏传会把语音芯片绑到 UART1（那一路是隔离 RS485），
   录音采不到数据、播放也没声音。本模块把 exaudio.setup 收口成只执行首次，
   air1103.init 也不换串口，
   所以第一次 setup 的入参决定全局，任何一处漏传后续全部补不回来。

3. air1103 模式补 bits_per_sample=16、channels=1（芯片固定 16kHz/16bit/单声道，
   与 module/Air8784/project/factory 参考工程的 exaudio.setup 入参一致）。

4. tx_bus_type / rx_bus_type 只有成对给出才透传，单侧不传（分总线播放/录音
   必须两侧一起配，只配一侧底层会得到半截驱动）。

5. setup 成功后立即套用 ac.play_vol（「亮度和声音」页 set_volume 的统一写回点）；
   setup 幂等记账后，重复调用仍会重新套音量。

6. es8311 板的 I2C1 与触摸共用，故 hw.audio 另有 i2c_shared / codec_init_on_play /
   i2c_speed 三个可选键（只对 model="es8311" 板生效，不填即 exaudio 旧行为）。
   exaudio 对未知表字段是静默忽略的，只传不验会退回「每次播放重配 I2C、触摸随之
   失灵」的旧行为且一个字节都不报错，所以 setup 成功后必须读 exaudio.bus_policy()
   对账，对不上就告警（见 check_bus_policy）。

7. 【单通路】hw.audio.model 决定整条音频通路，只在开机 setup 一次，运行期不再切。
   Air8605M/W、Air8603M1/W1 这类接了 Air1103 的板子写 model="air1103" 即可：
   录音走 Air1103 的 UART MIC，播放走 Air1103 下行（type=1 TTS / type=2 流式 PCM；
   type=0 文件播放在这条通路上不成立）。
   视频素材（HZV）的音轨不经 exaudio，仍由 videoplayer 送进内置 DAC 那一路。

8. 【音频占用】SIP 通话会长时间独占语音芯片，TTS / 语音聊天 / 录音 / 音量试听这些
   短任务要先问一句能不能用。acquire / release 记租约，guard 包住会 yield 的起播与
   暖机过程，register_busy_probe 让底层把「还在出声 / 还在收音」也报进来。
   这四个入口都不 yield，检查与占有之间没有抢占窗口。

=== 对外接口 ===

  audio_hw.cfg()          -> table|nil      hw.audio 配置（nil = 本板无音频能力）
  audio_hw.is_air1103()   -> boolean        是否 Air1103 UART 语音芯片
  audio_hw.params(extra)  -> table          exaudio.setup 入参（extra 同名字段覆盖）
  audio_hw.setup(extra, owner) -> ok, err   pcall(exaudio.setup, params) + 套用音量
  audio_hw.vol(level, owner)   -> ok        套用媒体音量（level 为 nil 取 ac.play_vol）
  audio_hw.record_start(cfg) -> ok, ret, reason  等价 pcall(exaudio.record_start, cfg)
  audio_hw.play_start(cfg)   -> ok, ret, reason  等价 pcall(exaudio.play_start, cfg)
  audio_hw.sync(vol, mute)   -> ok          下发音量/静音并广播 AUDIO_CFG_SYNC
  audio_hw.apply(vol, mute)  -> ok          AUDIO_CFG_SYNC 的生效点
  audio_hw.shutdown()     -> ok             停机（非 Air1103 直接返回 true）
  audio_hw.exaudio()      -> table|nil      require 到的 exaudio（无音频固件上为 nil）

  audio_hw.acquire(owner) -> ok, why       占用音频；owner 是会话标识
  audio_hw.release(owner) -> ok            归还
  audio_hw.busy(owner)    -> boolean       是否被别人占用（owner 传自己的标识可豁免）
  audio_hw.guard(fn)      -> function      包住会 yield 的音频操作，期间阻止抢占
  audio_hw.register_busy_probe(name, fn)   登记「底层还在出声 / 收音」探针
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
    "i2c_shared", "codec_init_on_play", "i2c_speed",
}

-- 需要向 exaudio.bus_policy() 对账的新语义键，只核对实际传入的字段（见 check_bus_policy）
local BUS_POLICY_KEYS = { "i2c_shared", "codec_init_on_play", "i2c_speed" }

--[[
@function cfg
@summary 取板级音频配置（hw.audio），nil 即本板无音频能力
@return table|nil
]]
function M.cfg()
    local c = _G.project_config
    return c and c.hw and c.hw.audio
end

function M.has_mic()
    local features = (_G.project_config or {}).features or {}
    return M.cfg() ~= nil and features.mic ~= false
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
    -- Air8606 GPIO73 兼作 Air1103 供电与 PA 使能。自动 PA 关断绝不能碰这条共用轨，
    -- 板级上电序列保持它常开：pa_ctrl 置 nil = 交给 exaudio 的自动 PA 控制不用该脚
    -- （文档口径「不传 = 不使用」；参考实现是 >0 才用，写 0 同义但 nil 更可移植）
    if ac.pa_power_hold then sp.pa_ctrl = nil end
    return sp
end

-- ==================== 音频占用租约 ====================

local lease_owner
local busy_probes = {}
local operations = 0

--[[
@function guard
@summary 把一个会 yield 的音频操作包起来：执行期间别的任务抢不进音频
@param function fn 被包的函数
@return function  形态与 fn 一致；音频被占用时直接返回 false, "audio_busy"
]]
function M.guard(fn)
    return function(...)
        if M.busy() then return false, "audio_busy" end
        operations = operations + 1
        local result = table.pack(pcall(fn, ...))
        operations = operations - 1
        if not result[1] then error(result[2], 0) end
        return table.unpack(result, 2, result.n)
    end
end

--[[
@function register_busy_probe
@summary 登记「底层还在出声 / 收音」探针，acquire 前逐个问一遍
@param string name 探针名（占用失败的原因里带上它）
@param function probe 只读状态且不得 yield
]]
function M.register_busy_probe(name, probe)
    assert(type(name) == "string" and type(probe) == "function")
    busy_probes[name] = probe
end

--[[
@function busy
@summary 音频是否正被别人占用
@param any owner 自己的会话标识，传了可以豁免自己的占用
@return boolean
]]
function M.busy(owner)
    return lease_owner ~= nil and lease_owner ~= owner
end

--[[
@function acquire
@summary 占用音频
@param any owner 会话标识
@return boolean, string|nil
]]
function M.acquire(owner)
    if owner == nil then return false, "audio_owner_required" end
    if lease_owner == owner then return true end
    if lease_owner ~= nil then return false, "audio_busy" end
    if operations > 0 then return false, "audio_busy:operation" end
    for name, probe in pairs(busy_probes) do
        local ok, busy = pcall(probe)
        if not ok or busy then return false, "audio_busy:" .. name end
    end
    -- 检查到占有之间不 yield，避免录音 / 暖机中途被抢占
    lease_owner = owner
    return true
end

--[[
@function release
@summary 归还音频
@param any owner 占用时用的会话标识
@return boolean
]]
function M.release(owner)
    if owner == nil or lease_owner ~= owner then return false end
    lease_owner = nil
    return true
end

-- 全局消息：音频设置（音量 0-100）与开关（true = 静音）同步
M.SYNC_MSG = "AUDIO_CFG_SYNC"

--[[
@function vol
@summary 套用媒体音量（settings_display_app 的统一写回点，AUDIO_CFG_SYNC 的生效点）
@param number|nil level 音量 0-100，nil 取 hw.audio.play_vol
@param any owner 会话标识；音频被别人占用时不动音量
@return boolean
]]
function M.vol(level, owner)
    if M.busy(owner) then return false end
    local ex = get_exaudio()
    if not ex or not ex.vol then return false end
    local ac = M.cfg() or {}
    local v = level or ac.play_vol or 70
    pcall(ex.vol, v)
    -- Air1103 机型：exaudio.vol 只写语音芯片的音量寄存器，够不着 audio_v2 的数字增益，
    -- 内置 DAC 那一路（视频素材的音轨）音量在此单独下发。
    -- audio_v2 是固件扩展库，以全局形式存在，无音频固件上为 nil，须判空
    if M.is_air1103() and audio_v2 then
        pcall(audio_v2.soft_volume, v)
    end
    return true
end

-- ==================== PA 功放供电 ====================

-- PA 使用者登记：pa_off 前逐个问一遍，还有人在用（如桌面 HZV 在播）就不拉低。
-- 与 busy_probes 的区别：占用租约管「音频任务能不能开」，这里只管「能不能关 PA」——
-- 视频走 videoplayer 的 luat_audio_request_play_stream，不占租约但要用 PA。
local pa_blockers = {}

--[[
@function register_pa_blocker
@summary 登记「PA 还有人用」探针（video_util 按播放态登记），pa_off 逐个问
@param string name   探针名
@param function probe 只读状态且不得 yield，返回 true 表示此刻不能关 PA
]]
function M.register_pa_blocker(name, probe)
    assert(type(name) == "string" and type(probe) == "function")
    pa_blockers[name] = probe
end

--[[
@function pa_set
@summary 打开/关闭 PA 功放供电（hw.audio.pa_ctrl）
pa_power_hold 板（如 Air8606：GPIO73 兼作语音芯片供电）由板级上电常供电，这里绝不动它；
pa_ctrl 未配的板（8605M/W 三键接线）直接返回 false。
@param on boolean true=开 / false=关
@return boolean 是否驱动了该脚
]]
function M.pa_set(on)
    local ac = M.cfg()
    if not (ac and ac.pa_ctrl) or ac.pa_power_hold then return false end
    local on_lv = ac.pa_on_level or 1
    pcall(gpio.setup, ac.pa_ctrl, on and on_lv or ((on_lv == 1) and 0 or 1))
    return true
end

--[[
@function pa_off
@summary 关闭 PA 功放供电（没人用了才真关）
音频任务在跑（busy）或有 PA 使用者登记（如桌面视频在播）时放弃，
否则会把别人正在用的功放掐掉（音量测试收尾 vs 桌面视频并发就是这条路）。
@return boolean 是否真的关了
]]
function M.pa_off()
    if M.busy() then return false end
    for _, probe in pairs(pa_blockers) do
        local ok, on = pcall(probe)
        if ok and on then return false end
    end
    return M.pa_set(false)
end

-- 新语义字段的生效对账：setup 成功后读 exaudio.bus_policy() 与实际传入的字段核对。
-- 旧版 exaudio 对未知表字段静默忽略，只传不验会退回「每次播放重配 I2C」的旧行为且
-- 不报任何错。对不上只告警不补救：那层「播完恢复触摸总线」的补救本身就是 i2c.setup，
-- 是把一次冲突放大成整个会话冲突的元凶，删掉就不该再长回来。
-- 没请求新语义时不告警，保持旧行为
local function check_bus_policy(ex, sp)
    local asked = false
    for i = 1, #BUS_POLICY_KEYS do
        if sp[BUS_POLICY_KEYS[i]] ~= nil then asked = true end
    end
    if not asked then return end

    local pol = nil
    if type(ex.bus_policy) == "function" then
        local ok, r = pcall(ex.bus_policy)
        if ok and type(r) == "table" then pol = r end
    end

    local bad = nil
    if not pol then
        bad = "库无 bus_policy"
    else
        for i = 1, #BUS_POLICY_KEYS do
            local k = BUS_POLICY_KEYS[i]
            if sp[k] ~= nil and pol[k] ~= sp[k] then
                bad = k .. "=" .. tostring(pol[k]) .. "，期望 " .. tostring(sp[k])
                break
            end
        end
    end
    if not bad then return end

    log.warn("audio_hw", "exaudio 新语义未生效:", bad, "，需同步升级 exaudio 后触摸才不被音频打断")
end

-- exaudio.setup 幂等记账：只执行首次。重复初始化会反复 i2c.setup 并整套重配 ES8311，
-- 是触摸失灵的直接原因，所以五个消费方都调用本模块也只有第一次真正下到 exaudio
local setup_done = false

local function setup_impl(extra, owner)
    local ac = M.cfg()
    if not ac then return false, "未配置 hw.audio" end
    local ex = get_exaudio()
    if not ex or not ex.setup then return false, "缺少 exaudio 扩展库" end
    local sp = M.params(extra)
    -- pa_power_hold 板（Air8606）：把 PA 控制脚钉在使能电平，并让 audio_v2 放弃
    -- 自动 PA 控制（config_pa_power_ctrl 不存在的固件静默跳过，只留钉脚）
    if ac.pa_power_hold and ac.pa_ctrl then
        pcall(gpio.setup, ac.pa_ctrl, ac.pa_on_level or 1)
        if audio_v2 and type(audio_v2.config_pa_power_ctrl) == "function" then
            pcall(audio_v2.config_pa_power_ctrl, false, 0, 1, 0)
        end
    end
    if not setup_done then
        local ok, ret = pcall(ex.setup, sp)
        if not ok then return false, "exaudio.setup 异常: " .. tostring(ret) end
        if not ret then return false, "音频初始化失败" end
        setup_done = true
        check_bus_policy(ex, sp)
    end
    -- 重复调用只重新套音量（「亮度和声音」页 set_volume 的统一写回点）
    M.vol(nil, owner)
    return true
end

--[[
@function setup
@summary 初始化音频：组装入参 → exaudio.setup（仅首次） → 套用音量
@param extra table|nil 同名字段覆盖
@param any owner 会话标识；音频被别人占用时不初始化
@return boolean, string|nil
]]
function M.setup(extra, owner)
    if M.busy(owner) then return false, "audio_busy" end
    operations = operations + 1
    local ok, result, reason = pcall(setup_impl, extra, owner)
    operations = operations - 1
    if not ok then return false, "audio_setup_failed:" .. tostring(result) end
    return result, reason
end

--[[
@function exaudio
@summary 取 exaudio 扩展库实例（无音频固件上为 nil）
@return table|nil
]]
function M.exaudio()
    return get_exaudio()
end

--[[
@function record_start
@summary 录音起播：转发 exaudio.record_start
@param table cfg exaudio.record_start 入参
@return boolean, any  形态与 pcall(exaudio.record_start, cfg) 一致
]]
function M.record_start(cfg)
    local ex = get_exaudio()
    if not ex or not ex.record_start then return false, "缺少 exaudio 扩展库" end
    return pcall(ex.record_start, cfg)
end

--[[
@function play_start
@summary 播放起播：转发 exaudio.play_start
@param table cfg exaudio.play_start 入参
@return boolean, any, any  ok=pcall 结果，ret=起播是否成立，reason=拒绝原因（形态同 pcall(exaudio.play_start, cfg)）
]]
function M.play_start(cfg)
    local ex = get_exaudio()
    if not ex or not ex.play_start then return false, "缺少 exaudio 扩展库" end
    return pcall(ex.play_start, cfg)
end

--[[
@function shutdown
@summary 停机：停掉 Air1103 上的录音 / 播放并反初始化（非 Air1103 直接返回 true）
@return boolean
]]
function M.shutdown()
    if not M.is_air1103() then return true end
    local ex = get_exaudio()
    if ex then
        if ex.record_stop then ex.record_stop() end
        if ex.play_stop then ex.play_stop({type=0}) end
    end
    local chip = require "air1103"
    chip.stop_audio()
    chip.play_stream_stop()
    chip.set_rx_enable(false)
    -- 停机命令先走出串口，再关它的驱动
    sys.wait(30)
    assert(chip.uninit(), "Air1103 uninit failed")
    setup_done = false
    return true
end

--[[
@function apply
@summary AUDIO_CFG_SYNC 生效点：音量与静音开关一起下发
@param number|nil vol  音量 0-100，nil 取 hw.audio.play_vol
@param boolean|nil mute  true = 静音
@return boolean
]]
function M.apply(vol, mute)
    if not M.cfg() then return false end
    local level = (mute == true) and 0 or (vol or (M.cfg().play_vol) or 70)
    M.vol(level)
    return true
end

--[[
@function sync
@summary 同步音频设置与开关：立即生效并广播 AUDIO_CFG_SYNC
@param number|nil vol  音量 0-100
@param boolean|nil mute  true = 静音
@return boolean
]]
function M.sync(vol, mute)
    M.apply(vol, mute)
    sys.publish(M.SYNC_MSG, vol, mute)
    return true
end

-- 其它模块也可 sys.publish(AUDIO_CFG_SYNC, vol, mute) 驱动同一套生效逻辑
sys.subscribe(M.SYNC_MSG, M.apply)

return M
