--[[
@module  factory_rec
@summary 应用工厂-录音与应用生成业务层（exaudio + AI 生成 APP）
@version 4.0
@date    2026.08.13
@author  江访
@usage
本模块为"应用工厂"（语音生成 APP）提供业务逻辑：
1. 录音：按芯片/音频框架区分实现（audio_v2 zbuff 回调 / audio 文件录音），最长 30 秒
2. 应用生成：录音完成后通过 https://api.luatos.com/engine/appstore/make_app 上传
   - POST multipart/form-data，字段 file（录音文件）+ device_info（设备信息 JSON 对象）
   - device_info 自动携带当前屏幕分辨率（宽x高，含旋转）与芯片型号
   - Header 带 app-key：RSA 公钥加密 "时间戳,appid,设备ID"（appid=当前时间戳，应用市场同套鉴权）
3. 任务轮询：创建成功后按服务端下发的 interval（秒）间隔轮询
   https://api.luatos.com/engine/appstore/make_app_status
   - status=1 运行中（history 显示进度）；status=2 结束成功（value.summary 为 APP 下载地址）；status=3 结束失败

录音实现要点（沿用 v2.5）：
- Air1602 等新框架(audio_v2)：zbuff 回调录音，支持点击停止（record_stop 真正停止）
  C 层不写文件头，需自行写格式头；record_stop() 后 RECORD_DONE 不再触发，主动收尾
- Air8000 等旧框架(audio)：文件录音，record_stop 有效，序列号文件名 + RECORD_DONE 清理

录音格式（config.hw.audio.record_format）：
- "AMR_NB"：AMR 窄带（默认，与 Air1601/1602/Air8101 一致；体积小，上传省内存）
- "PCM_16000"：16kHz PCM（如需流式/大带宽场景）
- PCM 模式下 zbuff 回调直接写原始 PCM，无需文件头；上传 Content-Type=audio/pcm

硬件依赖（config.hw.audio）：
  model="es8311" 时需 i2c_id(控制总线), pa_ctrl(PA_EN), dac_ctrl(8311_EN/AUDIO_EN)
  Air1602 引擎板（DAC0 播放 + I2S2 录音接 ES8311）：需配 tx_bus_type/rx_bus_type 驱动切换

⚠️ 关键硬件约束（I2C1 总线共享）：
  8311 与触摸屏(GT911)共用 I2C1。8311 一旦断电，其引脚会把共享 I2C1 总线拉低 → 触摸失灵
  （日志 i2c 地址 0x5d 超时 + wait free timeout）。
  因此本模块【8311 保持常供电，绝不断电】：
  - setup 后禁用 C 层 codec 电源管理（audio_v2.config_codec_power_ctrl(false)），
    使 record_stop 时 C 层不拉低 8311_EN
  - 停止录音 / 退出窗口时仅保持 8311_EN 高电平并重新初始化寄存器（codec_power_restore），
    不做 exaudio.pm(SHUTDOWN) 下电

消息协议（订阅/发布）:
订阅: FACTORY_REC_SETUP        → 初始化音频驱动（进入窗口时）
订阅: FACTORY_REC_START        → 开始录音
订阅: FACTORY_REC_STOP         → 停止录音
订阅: FACTORY_REC_RESET        → 清理并下电（退出窗口时）
订阅: FACTORY_MAKE_SEND        → 发送最新录音生成应用
订阅: FACTORY_MAKE_INSTALL     → 安装已生成的 APP（携带链接）
发布: FACTORY_REC_READY(ok,msg)      → 初始化结果
发布: FACTORY_REC_STATE({state,...}) → 状态: idle/recording
发布: FACTORY_REC_STATUS(msg)        → 提示文本
发布: FACTORY_REC_DURATION(sec)      → 录音计时
发布: FACTORY_REC_DONE({path,size,seconds}) → 录音完成（含时长）
发布: FACTORY_MAKE_STATUS({status,history,link}) → 生成任务进度（status: 1运行中/2成功/3失败）
发布: FACTORY_MAKE_ERROR(msg)        → 生成失败
]]

local exaudio = require "exaudio"

-- ==================== 常量 ====================

-- 应用生成接口（前缀 https://api.luatos.com/engine/appstore/）
local MAKE_APP_URL  = "https://api.luatos.com/engine/appstore/make_app"
local MAKE_STATUS_URL = "https://api.luatos.com/engine/appstore/make_app_status"

-- ==================== 录音文件管理 ====================
-- 旧框架(audio)：序列号文件名 /ram/r1.<ext>, /ram/r2.<ext> ...
--                每段录音用新文件名，避免删除仍被写入的文件
-- 新框架(audio_v2)：zbuff 回调模式，文件句柄由本模块管理，固定路径 /ram/record.<ext>
--                扩展名随录音格式变化（AMR_NB=.amr, PCM_*=*.pcm）
local rec_seq = 0
local cur_path = nil      -- 当前正在录音的文件路径
local latest_path = nil   -- 最新一段完整录音的文件路径

-- 状态机
local state = "idle"      -- idle / recording
local inited = false      -- exaudio 是否已 setup
local is_v2 = false       -- true=新框架(audio_v2), false=旧框架(audio)
local rec_timer = nil     -- 录音计时定时器
local rec_seconds = 0     -- 录音累计秒数
local rec_fp = nil        -- audio_v2 回调录音的文件句柄
local v2_finalized = false -- audio_v2 停止后已收尾标记（防异步 RECORD_DONE 重复处理）
local make_send           -- 前向声明（应用生成上传函数，定义见下文；事件订阅在文件末尾引用）
local make_poll           -- 前向声明（任务轮询函数，make_send 内引用）
local make_appid = nil    -- appid 缓存：一次生成会话（创建+轮询）固定复用同一 appid=时间戳
                          -- 服务端用 appid 关联任务，轮询若用新时间戳会找不到任务(任务接口错误)

-- ==================== 读取配置 ====================

local function get_audio_config()
    local cfg = _G.project_config
    if cfg and cfg.hw and cfg.hw.audio then
        return cfg.hw.audio
    end
    return nil
end

-- ==================== 录音格式 ====================

-- 当前录音格式（config.hw.audio.record_format 驱动，默认 AMR_NB）
local rec_fmt = "AMR_NB"
local rec_sr = 8000      -- 采样率（AMR_NB=8k, PCM_16000=16k）

-- 解析录音格式配置："AMR_NB" / "PCM_8000" / "PCM_16000" ...
local function parse_record_format(str)
    if not str then return "AMR_NB", 8000 end
    local up = str:upper()
    if up:find("^PCM_") then
        local sr = tonumber(up:match("PCM_(%d+)")) or 16000
        return "PCM_" .. sr, sr
    end
    return "AMR_NB", 8000
end

-- 获取当前录音格式的 exaudio 常量 + 采样率
local function get_record_format()
    local ac = get_audio_config()
    if ac and ac.record_format then
        rec_fmt, rec_sr = parse_record_format(ac.record_format)
    end
    return rec_fmt, rec_sr
end

-- 当前录音文件扩展名（旧框架序列号文件名用）
local function rec_ext()
    return rec_fmt:find("^PCM_") and ".pcm" or ".amr"
end

-- 当前录音文件头内容（audio_v2 zbuff 模式需自行写头；PCM 无需头）
local function rec_file_header()
    if rec_fmt:find("^PCM_") then
        return nil
    end
    return "#!AMR\n"
end

-- 当前录音格式的 exaudio.xxx 常量
local function rec_exformat()
    if rec_fmt == "PCM_16000" then return exaudio.PCM_16000 end
    if rec_fmt == "PCM_24000" then return exaudio.PCM_24000 end
    if rec_fmt == "PCM_32000" then return exaudio.PCM_32000 end
    if rec_fmt == "PCM_48000" then return exaudio.PCM_48000 end
    if rec_fmt == "PCM_8000" then return exaudio.PCM_8000 end
    return exaudio.AMR_NB
end

-- 生成新录音文件路径（旧框架序列号）
local function next_rec_path()
    rec_seq = rec_seq + 1
    return "/ram/r" .. rec_seq .. rec_ext()
end

-- 清理旧的已完成录音文件（旧框架，只在 RECORD_DONE 后调用，此时文件已关闭）
local function cleanup_old_files()
    local keep = latest_path
    if not keep then return end
    local ext = rec_ext()
    for i = 1, rec_seq - 1 do
        local p = "/ram/r" .. i .. ext
        if p ~= keep and io.exists(p) then
            pcall(os.remove, p)
        end
    end
end

-- 保持 ES8311 供电 + 诊断（绝不断电、绝不复位芯片）
-- 8311 与触摸(GT911)共用 I2C1 总线：8311 一旦断电，其引脚会把共享 I2C1 拉低，触摸失灵。
-- 因此本函数【绝不断电】【绝不重新初始化】：仅保持 8311_EN 高电平并读取 ID 诊断。
-- 注意：不能调 es8311.init()/resume() —— init 会写复位寄存器(0x00)让 8311 短暂无应答，
-- 复位瞬间其 I2C 引脚可能拉低 SDA，把共享总线钳死，反而触发触摸(0x5d)超时。
local codec_restore_scheduled = false  -- 防重入：恢复任务是否已安排/执行中
local function codec_power_restore()
    local ac = get_audio_config()
    if not ac or not ac.dac_ctrl or ac.dac_ctrl <= 0 then return end
    -- 1. 保持 8311 供电（只拉高，不拉低断电）
    gpio.setup(ac.dac_ctrl, 1)
    gpio.set(ac.dac_ctrl, 1)
    -- 2. 诊断：读取 ES8311 芯片 ID（0xFD 应为 0x83），确认其是否正常应答
    if ac.model == "es8311" then
        local id = nil
        local ok = pcall(function()
            local data = i2c.readReg(ac.i2c_id or 0, 0x18, 0xFD, 1)
            if data and #data == 1 then id = data:byte(1) end
        end)
        log.info("factory_rec", "ES8311 供电诊断 ok:", ok,
                 "ID:", id and string.format("0x%02X", id) or "无应答")
    end
end

-- ==================== 录音计时 ====================

-- 停止录音计时（保留已计秒数，供 finalize_record 上报时长；下次录音开始时清零）
local function stop_record_timer()
    if rec_timer then
        sys.timerStop(rec_timer)
        rec_timer = nil
    end
end

-- 异步恢复任务（具名函数，防重入；供 finalize_record 统一调用）
local function codec_restore_task()
    codec_power_restore()
    codec_restore_scheduled = false
end

-- 录音完成收尾（两框架共用，防重复执行）
local function finalize_record(manual_stop)
    if v2_finalized then return end
    v2_finalized = true
    local sec = rec_seconds
    stop_record_timer()
    -- 新框架：关闭自行管理的文件句柄
    if is_v2 and rec_fp then
        pcall(rec_fp.close, rec_fp)
        rec_fp = nil
    end
    latest_path = cur_path
    local sz = 0
    if latest_path and io.exists(latest_path) then
        sz = io.fileSize(latest_path) or 0
    end
    -- 旧框架：清理更早的录音文件（已关闭，安全）
    if not is_v2 then
        cleanup_old_files()
    end
    state = "idle"
    sys.publish("FACTORY_REC_STATE", { state = "idle" })
    sys.publish("FACTORY_REC_STATUS", "录音完成")
    sys.publish("FACTORY_REC_DONE", { path = latest_path, size = sz, seconds = sec })
    log.info("factory_rec", "录音完成 路径:", latest_path, "大小:", sz, "字节 时长:", sec, "秒",
             manual_stop and "手动停止" or "到时结束")
    -- 8311 与触摸(GT911)共用 I2C1：停止录音时 C 层可能下电/异常化 8311，把总线钳位导致触摸失灵。
    -- 统一在此调度一次复位+重初始化恢复任务（防重入；回调上下文不可阻塞，故异步）。
    if not codec_restore_scheduled then
        codec_restore_scheduled = true
        sys.taskInit(codec_restore_task)
    end
end



--[[
停止录音
- 旧框架(audio)：文件录音 record_stop() 立即停止，RECORD_DONE 回调关闭文件
- 新框架(audio_v2)：record_stop() flush 剩余数据并停止 C 层，随后关闭文件
]]
local function rec_stop ()
    if state ~= "recording" then return end
    pcall(exaudio.record_stop)
    if is_v2 then
        -- 新框架：record_stop() 已 flush 剩余数据并停止，立即收尾
        -- （audio_v2 文件录音 record_stop 后可能不再触发 RECORD_DONE，此处主动收尾）
        finalize_record(true)
    else
        -- 旧框架：停止后由 RECORD_DONE 回调负责收尾
        stop_record_timer()
        state = "idle"
        sys.publish("FACTORY_REC_STATE", { state = "idle" })
        sys.publish("FACTORY_REC_STATUS", "正在结束录音...")
    end
end

local function rec_timer_cb()
    rec_seconds = rec_seconds + 1
    sys.publish("FACTORY_REC_DURATION", rec_seconds)
    -- 到时自动停止（最长录音时长）
    local ac = get_audio_config()
    local max_time = (ac and ac.max_record_time) or 30
    if rec_seconds >= max_time then
        log.info("factory_rec", "录音已达上限", max_time, "秒，自动停止")
        sys.taskInit(rec_stop)
    end
end

local function start_record_timer()
    rec_seconds = 0
    sys.publish("FACTORY_REC_DURATION", 0)
    rec_timer = sys.timerLoopStart(rec_timer_cb, 1000)
end

-- ==================== 回调 ====================

-- 录音数据回调（仅 audio_v2 新框架 zbuff 模式）
-- C 层把编码后的音频帧（AMR/PCM）写入 zbuff 后调用本函数，随后 exaudio 会 del 该 zbuff
local function rec_data_cb(buff, len)
    if rec_fp and buff and len and len > 0 then
        local data = buff:toStr(0, len)
        if #data > 0 then
            pcall(rec_fp.write, rec_fp, data)
        end
    end
end



-- 录音完成回调（time 到期 / record_stop 停止后触发，旧框架文件录音）
local function rec_done_cb(event)
    if event ~= exaudio.RECORD_DONE then return end
    finalize_record(false)
end

-- ==================== 初始化 / 清理 ====================

--[[
初始化 exaudio（进入窗口时调用）
首次进入 setup，后续进入仅 pm(RESUME) 恢复
]]
local function rec_setup()
    local ac = get_audio_config()
    if not ac then
        log.error("factory_rec", "未配置 hw.audio")
        sys.publish("FACTORY_REC_READY", false, "未配置 hw.audio")
        return
    end
    if not inited then
        -- 兜底：外部编解码芯片（如 ES8311）需先上电（dac_ctrl 高电平使能）并等待稳定
        -- config power_on 已拉高，这里再确认一次（幂等）；内置 DAC 模式无需此步骤
        if ac.dac_ctrl and ac.dac_ctrl > 0 then
            gpio.setup(ac.dac_ctrl, 1)
            gpio.set(ac.dac_ctrl, 1)
            -- 等待外部编解码上电稳定（电源启动 + 晶振起振，一般需 100~200ms）
            sys.wait(200)
        end
        log.info("factory_rec", "exaudio.setup 调用, model:", ac.model or "es8311",
                 "pa:", ac.pa_ctrl, "dac_ctrl:", ac.dac_ctrl, "i2c:", ac.i2c_id)
        -- 首次：exaudio.setup 初始化音频（用 pcall 捕获可能的异常）
        -- 参数按配置透传：DAC 模式只需 pa_ctrl/pa_on_level/dac_delay；
        -- ES8311 模式需 i2c_id/dac_ctrl/i2s_sample 等，可配合 tx_bus_type/rx_bus_type
        -- 做默认驱动切换（如 Air1602 引擎板 DAC0 播放 + I2S2 录音），8000 旧框架按需透传 audio_mode
        local setup_param = {
            model = ac.model or "es8311",
            pa_ctrl = ac.pa_ctrl,
            pa_on_level = ac.pa_on_level or 1,
            dac_delay = ac.dac_delay,
        }
        if ac.dac_ctrl then setup_param.dac_ctrl = ac.dac_ctrl end
        if ac.i2c_id then setup_param.i2c_id = ac.i2c_id end
        if ac.i2s_sample then setup_param.i2s_sample = ac.i2s_sample end
        if ac.bits_per_sample then setup_param.bits_per_sample = ac.bits_per_sample end
        if ac.i2s_framebit then setup_param.i2s_framebit = ac.i2s_framebit end
        if ac.channels then setup_param.channels = ac.channels end
        if ac.pa_delay then setup_param.pa_delay = ac.pa_delay end
        -- 默认驱动切换（exaudio v2.8）：播放/录音用不同总线时设置（DAC0播放 + I2S2录音）
        if ac.tx_bus_type and ac.rx_bus_type then
            setup_param.tx_bus_type = ac.tx_bus_type
            setup_param.tx_bus_id = ac.tx_bus_id or 0
            setup_param.rx_bus_type = ac.rx_bus_type
            setup_param.rx_bus_id = ac.rx_bus_id or 0
        end
        -- 8000 等默认旧框架型号，录音需 audio_mode="new"；1602 新框架此参数无效
        if ac.audio_mode then setup_param.audio_mode = ac.audio_mode end
        local ok, result = pcall(exaudio.setup, setup_param)
        -- ok = pcall 是否无异常; result = setup 返回值（正常为 true/false）
        if not ok then
            log.error("factory_rec", "exaudio.setup 异常:", tostring(result))
            sys.publish("FACTORY_REC_READY", false, "音频初始化异常")
            return
        end
        if not result then
            log.error("factory_rec", "exaudio.setup 返回 false（音频初始化失败）")
            sys.publish("FACTORY_REC_READY", false, "音频初始化失败")
            return
        end
        exaudio.vol(ac.play_vol or 70)
        exaudio.mic_vol(ac.mic_vol or 70)
        -- 记录当前音频框架：audio_v2(新)/audio(旧)
        is_v2 = (exaudio.get_audio_mode and exaudio.get_audio_mode() == "audio_v2")
        -- ⚠️ 8311 与触摸(GT911)共用 I2C1：禁用 C 层 codec 电源管理，
        -- 否则 record_stop 时 C 层会拉低 8311_EN(GPIO49) → 8311 掉电把共享 I2C1 钳位 → 触摸失灵。
        -- 禁用后 stop 只清驱动状态、不操作电源引脚，8311 保持常供电。
        if is_v2 and audio_v2 and audio_v2.config_codec_power_ctrl then
            pcall(audio_v2.config_codec_power_ctrl, false, 0, 0, 0, 0)
            log.info("factory_rec", "已禁用 C 层 codec 电源管理（8311 常供电，保护 I2C1 触摸总线）")
        end
        inited = true
        log.info("factory_rec", "exaudio 初始化成功 model:", ac.model, "框架:", is_v2 and "audio_v2" or "audio")
    else
        exaudio.pm(exaudio.RESUME)
    end
    state = "idle"
    sys.publish("FACTORY_REC_READY", true, "音频就绪")
end

--[[
清理并下电（退出窗口时）
录音尽力停止；关闭残留文件句柄。
注意：本型号 8311 与触摸(GT911)共用 I2C1，8311 断电会把总线拉低导致触摸失灵，
因此不做 exaudio.pm(SHUTDOWN) 下电，仅确保 8311 保持供电。
]]
local function rec_reset()
    stop_record_timer()
    if state == "recording" then
        pcall(exaudio.record_stop)
        -- 新框架：record_stop 后 RECORD_DONE 不再触发，此处主动收尾
        -- （保留本次录音文件，退出后可继续上传）
        if is_v2 then
            finalize_record(true)
        end
    end
    -- 兜底：新框架残留文件句柄关闭
    if is_v2 and rec_fp then
        pcall(rec_fp.close, rec_fp)
        rec_fp = nil
    end
    state = "idle"
    -- 8311 与触摸共用 I2C1：统一走防重入的异步恢复任务，避免双重复位重新钳位总线
    if not codec_restore_scheduled then
        codec_restore_scheduled = true
        sys.taskInit(codec_restore_task)
    end
end

-- ==================== 录音 ====================

--[[
开始录音
- 旧框架(audio)：文件录音 → /ram/r<序号>.<ext>，record_stop() 有效
- 新框架(audio_v2)：zbuff 回调录音 → /ram/record.<ext>，支持点击停止
录音格式由 config.hw.audio.record_format 驱动（AMR_NB 默认 / PCM_16000 等）
]]
local function rec_start()
    if not inited then
        sys.publish("FACTORY_REC_STATUS", "音频未初始化")
        return
    end
    if state == "recording" then return end
    local ac = get_audio_config()
    local max_time = (ac and ac.max_record_time) or 30
    v2_finalized = false
    local fmt, sr = get_record_format()

    if is_v2 then
        -- ===== 新框架(audio_v2)：zbuff 回调录音，支持点击停止 =====
        -- audio_v2 文件录音 record_stop() 不真正停止，改用回调模式：
        -- 传函数给 path，C 层每帧回调 rec_data_cb，record_stop() 时 flush 剩余并真正停止
        local rec_path = "/ram/record" .. rec_ext()
        if io.exists(rec_path) then
            pcall(os.remove, rec_path)
        end
        local fp = io.open(rec_path, "wb")
        if not fp then
            sys.publish("FACTORY_REC_STATUS", "录音文件打开失败")
            return
        end
        -- AMR_NB 需写文件头（zbuff 模式 C 层不写头）；PCM 无需头
        local header = rec_file_header()
        if header then
            fp:write(header)
        end
        cur_path = rec_path
        rec_fp = fp
        local ok = exaudio.record_start({
            format = rec_exformat(),
            time = 0,          -- 0 = 无限录音，由本模块计时器控制最长时长
            path = rec_data_cb,
            cbfnc = rec_done_cb,
        })
        if ok then
            state = "recording"
            start_record_timer()
            sys.publish("FACTORY_REC_STATE", { state = "recording" })
            sys.publish("FACTORY_REC_STATUS", "录音中...")
            log.info("factory_rec", "开始录音(audio_v2) 路径:", rec_path, "格式:", fmt, "采样率:", sr, "上限:", max_time, "秒")
        else
            pcall(fp.close, fp)
            rec_fp = nil
            v2_finalized = false
            if io.exists(rec_path) then
                pcall(os.remove, rec_path)
            end
            sys.publish("FACTORY_REC_STATUS", "录音启动失败")
        end
        return
    end

    -- ===== 旧框架(audio)：文件录音，保持原有行为 =====
    -- 若上一段录音仍在后台写入（RECORD_DONE 未触发），等待其完成
    local wait_cnt = 0
    while not exaudio.is_end() and wait_cnt < (max_time + 5) * 10 do
        sys.wait(100)
        wait_cnt = wait_cnt + 1
    end
    -- 新录音用新文件名，天然避免文件冲突
    cur_path = next_rec_path()
    local ok = exaudio.record_start({
        format = rec_exformat(),
        time = max_time,
        path = cur_path,
        cbfnc = rec_done_cb,
    })
    if ok then
        state = "recording"
        start_record_timer()
        sys.publish("FACTORY_REC_STATE", { state = "recording" })
        sys.publish("FACTORY_REC_STATUS", "录音中...")
        log.info("factory_rec", "开始录音(audio) 路径:", cur_path, "格式:", fmt, "采样率:", sr, "上限:", max_time, "秒")
    else
        sys.publish("FACTORY_REC_STATUS", "录音启动失败")
    end
end



-- ==================== 应用生成（make_app） ====================

-- 生成设备 ID（与应用市场 exapp.iot_gen_device_uid 同套逻辑）
local function make_device_id()
    local model = rtos.bsp()
    if model:find("Air1601") or model:find("Air1602") or model:find("PC") then
        return mcu.unique_id() or "PC"
    elseif model:find("Air8101") or model:find("Air6205") then
        return wlan.getMac() or ""
    elseif model:find("Air780E") or model:find("Air8000") then
        return mobile.imei() or "0"
    else
        return mcu.unique_id() or "unknown"
    end
end

-- 生成设备信息 JSON 字符串（随 make_app 上传）
-- 自动携带当前屏幕分辨率（宽x高，含旋转）与芯片型号
-- ⚠️ 返回 JSON 对象字符串（形如 {"model":"Air8101","resolution":"800x480","screen_width":800,"screen_height":480}）
--    手工构造确保是 JSON 对象而非数组，避免 json.encode 对 Lua table 的数组/对象判定歧义
-- ⚠️ model 用 rtos.bsp()：返回纯芯片型号（如 "Air8101"/"Air8000"），
--    不能用 _G.model_str（hmeta.model() 会带变体后缀，如 "Air1602_10in1"，服务端不识别）
local function make_device_info()
    local model = rtos.bsp() or ""
    local phys_w, phys_h = lcd.getSize()
    local rotation = 0
    if airui.get_rotation then
        rotation = airui.get_rotation()
    end
    local disp_w, disp_h = phys_w, phys_h
    if rotation == 90 or rotation == 270 then
        disp_w, disp_h = phys_h, phys_w
    end
    -- model 做 JSON 转义（双引号/反斜杠），其余为纯数字无需转义
    local safe_model = model:gsub("\\", "\\\\"):gsub('"', '\\"')
    return string.format('{"model":"%s","resolution":"%dx%d","screen_width":%d,"screen_height":%d}',
        safe_model, disp_w, disp_h, disp_w, disp_h)
end

--[[
生成 app-key 请求头（应用市场 9.1.3 鉴权 Headers 规范）
规则：RSA 公钥加密 "时间戳,appid,设备ID"
  时间戳 = os.time()（10 位秒级），appid = 当前时间戳（设备作为 appid），设备ID = 设备唯一标识
返回 {["app-key"]=...} 或 nil
注意：rsa 是核心库（rotable 只读表，type 为 userdata 而非 table），部分固件可能未编译。
      直接用 rsa.encrypt 在缺库固件上会崩溃重启，必须先用 pcall + 存在性检查兜底。
]]
local function make_auth_headers()
    -- ⚠️ 缺 rsa 库时不能直接调用（会导致 Lua VM 崩溃重启）。rsa 是 rotable 只读表，
    -- type() 返回 userdata 而非 table，不能用 type 判断，只检查 encrypt 方法是否存在。
    local pub_key = io.readFile("/luadb/public.pem")
    if not pub_key then
        log.error("factory_rec", "make_app 缺少公钥 /luadb/public.pem")
        return nil
    end
    local devid = make_device_id()
    -- 时间戳 = os.time()，作为 appid（header 中携带 appid 信息，设备使用当前时间戳作为 appid）
    -- ⚠️ 复用缓存的 appid：一次生成会话（创建+轮询）用同一个 appid，
    --    否则轮询重新生成时间戳 → 服务端按 appid 关联任务找不到 → "任务接口错误"(code:153)
    local ts = make_appid or tostring(os.time())
    make_appid = ts
    local raw = ts .. "," .. ts .. "," .. devid
    local ok, cipher = pcall(rsa.encrypt, pub_key, raw)
    if not ok then
        log.error("factory_rec", "make_app 鉴权失败：固件缺少 rsa 核心库（", tostring(cipher), "）")
        return nil
    end
    if not cipher then
        log.error("factory_rec", "make_app rsa.encrypt 失败")
        return nil
    end
    local app_key = string.toBase64(cipher) or ""
    if app_key == "" then
        log.error("factory_rec", "make_app app-key 生成失败（Base64 为空）")
        return nil
    end
    return { ["app-key"] = app_key }
end

--[[
上传最新录音生成应用
POST https://api.luatos.com/engine/appstore/make_app
multipart/form-data：字段 file（录音文件）+ device_info（设备信息 JSON 对象）
成功后按服务端下发 interval 秒轮询 make_app_status，发布进度/结果。
发布 FACTORY_MAKE_STATUS({status,history,link}) 或 FACTORY_MAKE_ERROR(msg)
status: 1 运行中 / 2 结束并成功（link 为安装链接） / 3 结束且失败
]]
-- 注意：用赋值而非 local function —— 顶部已有前向声明 local make_send，
-- 若用 local function 会创建新的局部变量遮蔽前向声明，导致后续引用（事件订阅）捕获的仍是 nil。
make_send = function()
    -- 每次新生成会话重置 appid：下一次录音生成用新的时间戳 appid（创建+轮询固定同一值）
    make_appid = nil
    if not latest_path or not io.exists(latest_path) then
        sys.publish("FACTORY_MAKE_ERROR", "暂无录音文件")
        return
    end
    local sz = io.fileSize(latest_path) or 0
    if sz <= 0 then
        sys.publish("FACTORY_MAKE_ERROR", "录音文件为空")
        return
    end
    if not socket.localIP() then
        sys.publish("FACTORY_MAKE_ERROR", "网络未连接")
        return
    end
    local headers = make_auth_headers()
    if not headers then
        sys.publish("FACTORY_MAKE_ERROR", "鉴权失败(固件缺rsa库或公钥缺失)")
        return
    end
    -- 录音格式决定上传的 Content-Type / 文件名
    local fmt, _ = get_record_format()
    local is_pcm = fmt:find("^PCM_") ~= nil
    local ctype = is_pcm and "audio/pcm" or "audio/amr"
    local fname = is_pcm and "record.pcm" or "record.amr"
    local boundary = "----WebKitFormBoundary" .. os.time()
    headers["Content-Type"] = "multipart/form-data; boundary=" .. boundary
    -- device_info 自动携带屏幕分辨率 + 模块型号（JSON 对象字符串）
    local device_info = make_device_info()
    local body = {}
    -- 1. file 字段（录音文件）
    table.insert(body, "--" .. boundary .. "\r\n")
    table.insert(body, "Content-Disposition: form-data; name=\"file\"; filename=\"" .. fname .. "\"\r\n")
    table.insert(body, "Content-Type: " .. ctype .. "\r\n\r\n")
    local fdata = io.readFile(latest_path)
    if not fdata then
        sys.publish("FACTORY_MAKE_ERROR", "读取录音文件失败")
        return
    end
    -- 调试：打印录音文件头 16 字节十六进制，验证 AMR 格式头（应为 "#!AMR\n" = 23 21 41 4D 52 0A）
    local head_hex = {}
    local n = math.min(#fdata, 16)
    for i = 1, n do
        head_hex[i] = string.format("%02X", fdata:byte(i))
    end
    log.info("factory_rec", "make_app >>> 录音文件头", n, "字节:", table.concat(head_hex, " "),
             " 前4字符:", fdata:sub(1, 4))
    table.insert(body, fdata)
    table.insert(body, "\r\n")
    -- 2. device_info 字段（设备信息 JSON 对象）
    -- ⚠️ 作为【普通表单字段】发送（不带 filename）：
    --   带 filename 的 part 会被 Spring 识别为文件(MultipartFile)，request.getParameter("device_info")
    --   拿不到值(null) → 服务端校验报 "device_info异常"(code:54)。
    --   无 filename → getParameter("device_info") 能拿到 JSON 字符串（等同前端
    --   formData.append('device_info', JSON.stringify(info)) 标准写法）
    table.insert(body, "--" .. boundary .. "\r\n")
    table.insert(body, "Content-Disposition: form-data; name=\"device_info\"\r\n")
    table.insert(body, "Content-Type: application/json\r\n\r\n")
    table.insert(body, device_info)
    table.insert(body, "\r\n")
    -- 结束 boundary
    table.insert(body, "--" .. boundary .. "--\r\n")
    local body_str = table.concat(body)
    local app_key = headers["app-key"] or ""
    -- 打印发送信息（分块打印，避免超长字符串被 log 截断）
    -- ⚠️ log.info 单条超长会被截断（日志只剩 tag 无内容），故每行保持短
    log.info("factory_rec", "make_app >>> URL:", MAKE_APP_URL)
    log.info("factory_rec", "make_app >>> app-key:", app_key)
    log.info("factory_rec", "make_app >>> Content-Type:", headers["Content-Type"])
    log.info("factory_rec", "make_app >>> ===== MULTIPART START =====")
    log.info("factory_rec", "--- part1 file ---")
    log.info("factory_rec", "Content-Disposition: form-data; name=\"file\"; filename=\"" .. fname .. "\"")
    log.info("factory_rec", "Content-Type: " .. ctype)
    log.info("factory_rec", "录音文件大小:", sz, "字节")
    log.info("factory_rec", "--- part2 device_info ---")
    log.info("factory_rec", "Content-Disposition: form-data; name=\"device_info\"")
    log.info("factory_rec", "Content-Type: application/json")
    log.info("factory_rec", "device_info:", device_info)
    log.info("factory_rec", "make_app >>> ===== MULTIPART END =====")
    log.info("factory_rec", "make_app >>> body 总大小:", body_str:len(), "字节")
    local code, _, resp_body = http.request("POST", MAKE_APP_URL, headers, body_str, { timeout = 30000 }).wait()
    -- 打印回复信息（HTTP code + 完整响应体）
    log.info("factory_rec", "make_app <<< 响应 code:", code)
    log.info("factory_rec", "make_app <<< 响应 body:", resp_body)
    if code < 0 or code ~= 200 then
        sys.publish("FACTORY_MAKE_ERROR", "服务器连接失败(" .. tostring(code) .. ")")
        return
    end
    local ok, resp = pcall(json.decode, resp_body)
    if not ok or type(resp) ~= "table" then
        log.warn("factory_rec", "make_app 响应解析失败:", resp_body)
        sys.publish("FACTORY_MAKE_ERROR", "响应解析失败")
        return
    end
    if resp.code ~= 0 then
        local err = ""
        if type(resp.value) == "table" then
            err = resp.value.msg or resp.value.error or ""
        else
            err = tostring(resp.value or "")
        end
        if err == "" then err = tostring(resp.msg or "创建任务失败") end
        sys.publish("FACTORY_MAKE_ERROR", err)
        return
    end
    -- 创建成功：value 含 task_id / msg / interval
    local value = resp.value
    if type(value) ~= "table" then
        sys.publish("FACTORY_MAKE_ERROR", "任务创建异常")
        return
    end
    local task_id = value.task_id
    -- 轮询间隔固定 10 秒（忽略服务端下发的 interval，避免轮询过快被限流/过慢影响体验）
    local interval = 10
    if not task_id then
        sys.publish("FACTORY_MAKE_ERROR", "任务ID缺失")
        return
    end
    sys.publish("FACTORY_MAKE_STATUS", {
        status = 1,
        history = { value.msg or "任务已创建" },
        task_id = task_id,
        interval = interval,
    })
    -- 轮询任务状态：间隔用服务端下发的 interval 秒（轮询不要太快，避免限流）
    sys.taskInit(make_poll, task_id, interval)
end

--[[
轮询应用生成任务状态
POST https://api.luatos.com/engine/appstore/make_app_status
body: { task_id = ... }
- 非 200 或 code != 0：任务异常结束，停止轮询
- code == 0 时 status: 1 运行中 / 2 结束成功（value.summary 为 APP 下载地址）/ 3 结束失败，status 为 2/3 时停止轮询
发布 FACTORY_MAKE_STATUS({status,history,link}) 或 FACTORY_MAKE_ERROR(msg)
]]
-- 注意：用赋值而非 local function —— 顶部已有前向声明 local make_poll，
-- 若用 local function 会创建新的局部变量遮蔽前向声明，导致 make_send 内引用的仍是 nil。
make_poll = function(task_id, interval)
    if not task_id then return end
    -- 轮询上限：10 秒一次，最长 10 分钟 = 60 次（60×10=600 秒）
    local max_times = 60
    local headers = make_auth_headers()
    if not headers then
        sys.publish("FACTORY_MAKE_ERROR", "鉴权失败(轮询)")
        return
    end
    -- ⚠️ make_app_status 用 JSON body + application/json：
    --   （1）multipart 不被支持 → 服务端报 951 HttpMediaTypeNotSupportedException
    --   （2）JSON body 时 task_id 原样带上（make_app 返回的完整字符串，不做任何解析/截断）
    --   （3）之前 JSON body 返回 153"任务接口错误" 是创建后立即轮询太快导致，不是 task_id 问题
    headers["Content-Type"] = "application/json"
    local body_str = json.encode({ task_id = task_id })
    for i = 1, max_times do
        -- ⚠️ 每次轮询前先等 interval 秒（含首次）：创建后立刻轮询（毫秒级）会被服务端
        --    判定任务"已结束(超时清理/异常)"(code:153)。文档明确：轮询间隔建议用 interval，不要太快
        sys.wait(interval * 1000)
        -- 打印轮询发送信息（URL + body），便于真机调试
        log.info("factory_rec", "make_app_status >>> 第", i, "次轮询 URL:", MAKE_STATUS_URL, "task_id:", tostring(task_id))
        local code, _, resp_body = http.request("POST", MAKE_STATUS_URL, headers, body_str, { timeout = 15000 }).wait()
        -- 打印轮询回复信息（HTTP code + 完整响应体）
        log.info("factory_rec", "make_app_status <<< 响应 code:", code, "body:", resp_body)
        if code < 0 or code ~= 200 then
            sys.publish("FACTORY_MAKE_ERROR", "轮询连接失败(" .. tostring(code) .. ")")
            return
        end
        local ok, resp = pcall(json.decode, resp_body)
        if not ok or type(resp) ~= "table" then
            log.warn("factory_rec", "make_app 轮询响应解析失败:", resp_body)
            sys.publish("FACTORY_MAKE_ERROR", "轮询响应解析失败")
            return
        end
        -- 非 0 code 表示任务异常结束，停止轮询
        if resp.code ~= 0 then
            local err = ""
            if type(resp.value) == "table" then
                err = resp.value.msg or resp.value.error or ""
            else
                err = tostring(resp.value or "")
            end
            if err == "" then err = tostring(resp.msg or "任务异常") end
            sys.publish("FACTORY_MAKE_ERROR", err)
            return
        end
        local value = resp.value
        if type(value) ~= "table" then
            sys.publish("FACTORY_MAKE_ERROR", "轮询数据异常")
            return
        end
        local status = tonumber(value.status) or 1
        -- status=2 时，value.summary 为制作完成的 APP 下载地址（兼容旧字段 link）
        local app_link = value.summary or value.link
        local result = {
            status = status,
            history = value.history,
            link = app_link,
            task_id = task_id,
        }
        sys.publish("FACTORY_MAKE_STATUS", result)
        -- status 2/3：任务结束，不再轮询
        if status == 2 or status == 3 then
            log.info("factory_rec", "make_app 任务结束 status:", status,
                     "link:", app_link and type(app_link) == "table" and table.concat(app_link, ";") or tostring(app_link or ""))
            return
        end
        -- 运行中：等待 interval 秒后下一轮（等待已在循环开头统一处理）
    end
    log.warn("factory_rec", "make_app 轮询达到上限，停止")
    sys.publish("FACTORY_MAKE_ERROR", "生成超时，请稍后重试")
end

-- 安装已生成的 APP（服务端返回链接，点击即可安装）
local function make_install(link)
    if not link then
        sys.publish("FACTORY_MAKE_ERROR", "安装链接为空")
        return
    end
    -- link 可能为字符串或 table（多链接时取第一个）
    local link_txt = ""
    if type(link) == "table" then
        link_txt = link[1] or ""
    else
        link_txt = tostring(link)
    end
    if link_txt == "" then
        sys.publish("FACTORY_MAKE_ERROR", "安装链接为空")
        return
    end
    if not exapp or not exapp.install_remote_app then
        sys.publish("FACTORY_MAKE_ERROR", "安装模块不可用")
        return
    end
    -- 确保 exapp 网络就绪（install_remote_app 依赖 network_ready 标志）
    if exapp.wait_network_ready then
        exapp.wait_network_ready(5000)
    end
    local aid = "make_app_" .. os.time()
    -- category/sort 为通用值，exapp.install_remote_app 需要 aid/url/name
    exapp.install_remote_app(aid, link_txt, "生成应用", "工具", "recommend")
end

-- ==================== 事件订阅 ====================

sys.subscribe("FACTORY_REC_SETUP", function()
    sys.taskInit(rec_setup)
end)

sys.subscribe("FACTORY_REC_START", function()
    sys.taskInit(rec_start)
end)

sys.subscribe("FACTORY_REC_STOP", function()
    sys.taskInit(rec_stop)
end)

sys.subscribe("FACTORY_REC_RESET", function()
    sys.taskInit(rec_reset)
end)

sys.subscribe("FACTORY_MAKE_SEND", function()
    sys.taskInit(make_send)
end)

sys.subscribe("FACTORY_MAKE_INSTALL", function(link)
    sys.taskInit(make_install, link)
end)
