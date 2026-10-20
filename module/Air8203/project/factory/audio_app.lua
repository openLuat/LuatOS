--[[
@module  audio_app
@summary 音频模块（Air8203：**仅 V 系列 Air780EHV** 有音频硬件）
@version 1.1（8203 新增；改名 audio.lua → audio_app.lua）
@date    2026.09.28

=== ★ 为什么文件名是 audio_app.lua 而不是 audio.lua ===
合宙**核心库**里已经有 `audio`。固件启动时核心库会被注册进 package.loaded，
若脚本文件也叫 audio.lua，`require("audio")` 会拿到**核心库**而不是本模块
（本文件根本不会被加载）→ 表现为"音频功能静默失效、无任何报错"。
因此按项目约定给文件名加后缀：**audio → audio_app**（wdt → wdt_app 同理）。
⚠️ 改名的只有**文件名**，对外接口名一律不变（audio_app.init / set_pa / play_file / set_volume）。

=== 硬件依据 ===
· 【官网】exaudio 文档原文：「合宙仅 **Air780EHV** 内置音频编解码芯片，其他支持音频的功能需要
  外置音频编解码芯片」「目前合宙所有的型号均需要外置音频放大器(PA)才可将音频输出」
  → 8203 的四个系列里，只有 V 系列（Air780EHV）可用；H/U/N 一律不支持。
· 【图】原理图第 8 页：功放 **AW8733**，使能脚 **PA_EN = GPIO26**（board.profile.audio.pa_en_pin）
  MIC = 主控 PIN3/4，SPK = PIN5/6（模组内置 codec，无需外挂 codec 芯片）
· 支持播放的文件格式：mp3 / amr / pcm / wav（【官网】exaudio 文档）

=== 使用的 API（★ 全部取自官方《audio - Multimedia-Audio》文档，未凭记忆编写） ===
  audio.config(id, paPin, onLevel, ...)  配置 PA 自动控制（本模块**不用**，改为手动 set_pa）
  audio.on(id, func)                     注册播放事件回调（audio.DONE = 播放完成）
  audio.play(id, path, errStop)          播放文件；path 为空 = 停止播放
  audio.vol(id, value)                   音量百分比 1%~1000%，默认 100（★ 不支持 0/静音）
  audio.playStop(id) / audio.stop(id)    停止播放
  文档来源：https://wiki.luatos.org/api/audio.html

=== 设计要点 ===
1. **双保险**：config.AUDIO_CONFIG.SUPPORTED == false 或 PA_EN_PIN == nil 时，
   所有接口**空实现返回 false**，不得报错（H/U/N 系列走这条路径）。
2. **功放按需开关**：播放前开 PA、播放完成后（audio.DONE 回调）关 PA。
   省电，且避免功放常开带来的底噪。
3. ⚠️ **文件已改名为 audio_app.lua**（避开核心库同名，见文件顶部的说明）。
   但本模块的 Lua **变量名**仍叫 `audio`（对外接口名不变），因此 chunk 内部依然会遮蔽
   全局核心库 `audio` → 仍在 chunk 顶部先把核心库取到 `core`，
   所有底层调用走 `core.xxx`（并全部用 pcall 包住，缺失时只告警不崩）。

=== 【待核】/【待标定】 ===
  · PA_EN 极性：按"EN"命名取**高有效**（PA_ON_LEVEL=1）。若实测为低有效，
    只改本文件的 PA_ON_LEVEL 常量即可，不必动其它代码。
  · PA 建立延时 PA_DELAY_MS=20ms：【待标定】（功放启动时间，过短会有爆音/丢首字节）
  · 音量：audio.vol 的取值范围是 1%~1000%，**没有静音档**；
    本模块把 0 收敛到 1（最小音量），并记入 state.volume。
]]

-- ★ 先把合宙核心库 audio 取出来，再声明同名 local 遮蔽它（见头注释第 3 点）
local core = audio

local audio = {}

local config = require("config")
local CFG = config.AUDIO_CONFIG or {}

local PA_PIN      = CFG.PA_EN_PIN
local SUPPORTED   = (CFG.SUPPORTED == true) and (PA_PIN ~= nil)
local AUDIO_ID    = 0          -- 多媒体通道号（官方示例统一用 0）
local PA_ON_LEVEL = 1          -- PA 使能极性：1=高有效（【待核】实测为低有效时改这里）
local PA_DELAY_MS = 20         -- 开 PA 后延时再送数据（【待标定】）

local state = {
    inited  = false,
    playing = false,
    volume  = CFG.VOLUME or 80,
}

-- ==================== 对外接口 ====================

--[[
初始化音频模块（仅 V 系列真正初始化）。

@return boolean true=已启用；false=本板无音频硬件 / PA 脚未确认 / 核心库不可用
]]
function audio.init()
    if state.inited then return true end

    if not SUPPORTED then
        log.info("audio", string.format(
            "本板无音频硬件（SUPPORTED=%s PA_EN=%s），音频模块不启用（仅 V 系列 Air780EHV 有音频）",
            tostring(CFG.SUPPORTED), tostring(PA_PIN)))
        return false
    end

    if not core or type(core) ~= "table" then
        log.warn("audio", "合宙核心库 audio 不可用（固件未包含音频功能），音频模块不启用")
        return false
    end

    -- PA 使能脚：上电先关功放（省电 + 防底噪）
    gpio.setup(PA_PIN, 1 - PA_ON_LEVEL)
    audio.set_pa(false)

    -- 播放完成回调：自动关闭功放（避免功放常开）
    if core.on then
        local ok, err = pcall(core.on, AUDIO_ID, function(id, msg)
            if msg == core.DONE then
                log.info("audio", "播放完成（通道", id, "），关闭功放")
                audio.set_pa(false)
                state.playing = false
            end
        end)
        if not ok then
            log.warn("audio", "audio.on 注册失败:", tostring(err))
        end
    end

    state.inited = true
    log.info("audio", string.format("音频模块初始化完成（PA_EN=GPIO%s，%s有效，音量=%d%%）",
        tostring(PA_PIN), PA_ON_LEVEL == 1 and "高电平" or "低电平", state.volume))
    return true
end

--[[
控制功放使能脚 PA_EN（播放前开、播放后关）。

@param boolean onoff true=开功放 / false=关功放
@return boolean false=本板无 PA 脚可控制
]]
function audio.set_pa(onoff)
    if not PA_PIN then return false end
    gpio.set(PA_PIN, onoff and PA_ON_LEVEL or (1 - PA_ON_LEVEL))
    return true
end

--[[
播放音频文件。

@param string path 文件路径（mp3 / amr / pcm / wav）
@return boolean, string 成功 true；失败 false + 原因
]]
function audio.play_file(path)
    if not state.inited then
        return false, "音频未初始化（非 V 系列，或 PA_EN 未确认）"
    end
    if type(path) ~= "string" or path == "" then
        return false, "参数错误: path 为空"
    end
    if not core or not core.play then
        return false, "核心库 audio.play 不可用"
    end

    -- ★ 先开功放，等它建立完成再送数据（否则首字节丢失 / 爆音）
    audio.set_pa(true)
    sys.wait(PA_DELAY_MS)

    local ok, res = pcall(core.play, AUDIO_ID, path)
    if not ok or not res then
        audio.set_pa(false)
        return false, "播放失败: " .. tostring(res)
    end

    state.playing = true
    log.info("audio", "开始播放:", path)
    return true
end

--[[
设置音量（0~100）。

★【官网】audio.vol 的入参是百分比 1%~1000%（默认 100），**没有静音档**；
  因此 0 收敛到 1（最小音量），其余按 1:1 映射。
  音量值同时记入本模块状态，未启用音频时也能返回"已记录但下发失败"。

@param number v 0~100
@return boolean, string
]]
function audio.set_volume(v)
    v = tonumber(v)
    if not v or v < 0 or v > 100 then
        return false, "参数错误: volume=" .. tostring(v)
    end
    state.volume = v

    if not state.inited or not core or not core.vol then
        return false, "音量已记录，但未下发（音频不可用）"
    end

    local pct = math.floor(v + 0.5)
    if pct < 1 then pct = 1 end   -- 无静音档，0 → 最小音量 1%
    local ok, res = pcall(core.vol, AUDIO_ID, pct)
    if not ok then
        return false, "音量下发失败: " .. tostring(res)
    end

    log.info("audio", "音量设置为:", pct, "%")
    return true
end

return audio
