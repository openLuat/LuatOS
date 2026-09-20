--[[
@module exaudio
@summary exaudio扩展库
@version 3.8
@date    2026.9.20
@author  拓毅恒
@description
本库负责音频硬件初始化、播放、录音和电源控制，可配合 exsip 使用普通 SIP 通话或 CC<->SIP 语音流桥接。
启用 exsip.init({cc_sip_bridge=true, ...}) 后，CC 下行语音经固件桥接送往 SIP 对端，
SIP 对端语音经固件桥接送入 CC 上行；需要固件同时具备 CC、VoIP PCM 桥接和对应音频后端支持。
该模式的通话音频由 CC 底层管理，exsip 不调用本库的 sip_voip_start()，也不在启动 SIP 媒体前停止本地音频驱动。
本库的 sip_voip_start()/sip_voip_stop() 用于普通 SIP 的本地 MIC/扬声器与 VoIP PCM 适配，
并非 CC<->SIP 桥接开关；不要在 CC<->SIP 桥接通话中额外启动该本地 speech 请求。
CC 与 SIP 两侧的拨号、接听、挂断联动由业务层控制，音频硬件参数仍按实际板型调用 setup() 配置。
@updates
    v3.8 2026.9.20
        1. 新增Air1103提示音播放接口 exaudio.play_ringback()/exaudio.play_hangup()，可用于SIP通话前后状态反馈。
    v3.7 2026.9.18
        1. 修复 DAC 模式下设置MIC音量导致 Air1601 死机问题。
    v3.6 2026.9.16
        1. 修复 air1103 模式在 Air1601 上 exaudio.setup 死机：
           Air1601 跳过该 I2S 配置——其 Air1103 走 UART 录音/播放不需要 I2S 参数,
           780EHM 等需要 cc 通话下行的型号仍正常配置 I2S。
        2. air1103 模式下 exaudio.sip_voip_start/stop 跳过 audio_v2 的 SIP 桥接并直接返回成功:
           Air1103 的 SIP 通话音频由业务层通过 voip.pcmIn/pcmOut 与 UART 自行桥接;
           若此处返回 false, exsip 会判定桥接失败并执行 voip.stop(), 导致通话没有音频。
    v3.5 2026.9.9
        1. 新增 DAC模式麦克风增益设置：model="dac" 时 exaudio.mic_vol(vol[, ana_vol])数字/模拟增益均由客户按 0-100 传入。
           并在 REQUEST_DRIVER_START 与 pm(RESUME) 时自动重新应用，修复 Air8101 等纯DAC模组无法调节麦克风音量的问题。
    v3.4 2026.9.4
        1. 修复 air1103 使用新框架进行VOLTE通话时无声问题。
    v3.3 2026.9.1
        1. 修复Air1602开发板调用exaudio.play_stop()后exaudio.pm(exaudio.SHUTDOWN)会关闭I2C1、导致LCD触摸失效的问题。
        2. 新增 air1103 支持：audio_setup_param 设置 model="air1103" 后，通过 UART1(可选) 驱动 Air1103 播放与录音。
           播放：exaudio.play_start({type=2, ...}) 启动后，用 exaudio.play_stream_write() 流式喂入 16kHz/16bit/单声道 PCM；
           录音：exaudio.record_start() 接收 Air1103 MIC 上行(16kHz/16bit/单声道, 512B/帧)，通过 path 回调逐段落盘。
    v3.2 2026.8.27
        1. 音频框架选择同时依据模组默认偏好和固件实际提供的audio/audio_v2库，
           修复未启用LUAT_USE_AUDIO_V2时仍误选新音频框架的问题。
        2. 显式audio_mode选择增加库能力校验，并保持Air8101、Air160X等模组优先使用Audio V2的原有约束。
    v3.1 2026.8.25
        1. 修复旧音频框架多音频连续播放报错的问题，同步更新 exaudio.play 两处调用，旧框架多音频播放恢复正常。
        2. 修复部分固件跑sip功能时，会出现死机或通话无声的问题。
    v3.0 2026.8.19
        1. 修复PCM流式录音停止后不触发录音完成回调的问题
        2. 修复exaudio.pm(exaudio.RESUME)恢复ES8311时未传递codec_voltage参数，
           避免1.8V板型(Air8201H等)休眠恢复后ES8311电平被重置为3.3V。
    v2.9 2026.8.14
        1. 修复codec_voltage参数无效问题：setup时audio_setup_param.codec_voltage始终为默认值1(3.3V)，
           现加入optional_params，外部设置codec_voltage=0(1.8V)可正确生效
    v2.8 2026.8.11
        1. 新增默认驱动切换支持：audio_setup_param新增tx_bus_type/tx_bus_id/rx_bus_type/rx_bus_id，
           当板子上有多种音频驱动、需播放和录音使用不同驱动时设置（如Air1602_V1.2开发板DAC0输出+I2S2录音）。
           默认nil不启用，不设置的客户使用BSP默认驱动，无需理解此功能。
        2. 切换默认驱动成功后，对dac_ctrl引脚做一次"拉低→等待→拉高"复位脉冲重启ES8311
           （驱动切换会重新配置I2S总线，dac_ctrl需从确定状态启动才能正常I2C通信）；
           未切换驱动时dac_ctrl仅拉高保持供电，行为与原有逻辑一致
        3. read_es8311_id()增加框架判断：audio_v2用i2c.readReg读取0xFD寄存器(0x83)校验，
           audio旧框架用i2c.send+i2c.recv读取CHIP_ID_REG，保持原有逻辑
        4. audio_v2_callback修复录音请求误报日志
    v2.7 2026.8.7
        1. 新增休眠控制宏exaudio.RESUME/exaudio.SHUTDOWN，解决Air1602等无audio库固件播放报错
        2. 所有exaudio.pm()调用统一改为exaudio.pm(exaudio.RESUME)/exaudio.pm(exaudio.SHUTDOWN)
    v2.6 2026.8.6
        1. 新音频框架play_start()播放前主动exaudio.pm(audio.RESUME)恢复ES8311工作模式
        2. 新音频框架play_stop()手动停止时exaudio.pm(audio.SHUTDOWN)下电ES8311省电
        3. exaudio.vol()同步更新voice_vol变量，修复CC铃声无法设置问题
        4. 通话自动唤醒：固件含cc库时自动订阅CC_IND事件，每次通话PLAY时自动RESUME唤醒，
    v2.5 2026.8.3
        1. play_start()文件播放新增文件头损坏预检：对mp3/amr/wav格式，播放前先解析文件头，
           文件不存在或文件头损坏时停止播放并提示"播放文件损坏，请更换文件播放"
    v2.4 2026.7.17
        1. 重构exaudio.parse_audio_info()，支持文件路径和缓冲数据两种方式输入
    v2.3 2026.7.16
        1. 移除新音频框架初始化audio_v2_setup中的make_probe_id+set_default_driver操作
           （各BSP有默认驱动，无需手动设置，特殊情况可通过exaudio.set_default_driver接口设置）
    v2.2 2026.7.14
        1. 新增codec_voltage参数控制ES8311电平 codec_voltage=1(默认3.3V)，codec_voltage=0(1.8V，适配Air8201等特殊板型)
    v2.1 2026.7.8
        1. 移除exaudio.shutdown()，合并到exaudio.pm()中
        2. exaudio.pm()新增新音频框架支持
        3. 新增exaudio.parse_audio_info()函数，用于从音频文件解析播放信息
        4. 新增Air700/Air1780系列模组检测
    v2.0 2026.7.3
        1. 修复流式播放偶尔播放不完整的问题
    v1.9 2026.7.1
        1. 调整音频框架默认选择：780EXX系列、8000系列默认旧框架
        2. 新增audio_mode参数，支持在setup中强制切换音频框架（"new"/"old"）
        3. 默认使用新音频框架的型号：Air8101、Air1601、Air1602
    v1.8 2026.5.11
        1. 新增TM8211音频编解码器支持，支持"es8311"、"tm8211"(I2S+外部Codec)和"dac"(内置DAC)两种类型
    v1.7 2026.4.22
        1. 新增多文件播放时的音频参数一致性检查，连续播放多个音频时添加限制，避免格式不同导致播放异常
    v1.6 2026.4.16
        1. 新增DAC模式支持，适配Air8101等使用内置DAC的模组，支持"es8311"(I2S+外部Codec)和"dac"(内置DAC)两种类型
        2. 优化参数检查逻辑，根据model自动选择初始化方式
        3. 流式播放统一使用队列+回调机制，通过audio.MORE_DATA事件驱动数据写入
    v1.5 2026.3.10
        1. 修改录音缓冲区使用逻辑，每次写完数据都清空缓冲区数据，释放内存，避免最后一段录音数据异常
    v1.4 2026.2.14
        1. 重构初始化i2s的逻辑，将接口给出让有录音或流式播放等需求的客户来自定义。
        3. 增大流式录音到文件缓冲区大小至48000，防止录音不完整。
    v1.3 2026.2.5
        1. 新增exaudio.pm()函数，可以在逻辑层直接调用exaudio.pm()来修改audio休眠模式。
        2. 重构exaudio.play_start()函数处理播放优先级逻辑，目前插入不同优先级的音频文件，会自动按照从高到底的顺序播放打断或播放。
        3. 重构exaudio.play_stop()函数，目前可以使用本函数来停止流式播放。
    v1.2 2026.1.6
        1. 新增双声道播放支持，exaudio.setup增加一个声道的配置参数
        2. 录音时间设置成0,会一直录音是正常的,api库已说明，这里再增加log打印提示
        3. 使用exaudio.record_stop()停止录音时，会有一小部分结尾的数据因为没有进入audio.on中的audio.RECORD_DATA事件而丢失，解决方案：
            在调用exaudio.record_stop()后，检查两个PCM缓冲区，确保所有数据都被处理
        4. exaudio.play_stream_write(data),流式音频数据,单次写入的长度修改为根据每秒播放数据量来确定
        5. 低功耗自动控制，exaudio.setup默认SHUTDOWN模式,exaudio.play_start和exaudio.record_start会自动切换到RESUME模式,播放完成或录音完成，会自动切换到SHUTDOWN模式
@usage

-- 版本更新说明
-- 版本号：202609201726
-- 1、更新时间：2026-09-20 17:26
--    新增Air1103提示音播放接口 exaudio.play_ringback()/exaudio.play_hangup()，
--    可用于SIP通话前后状态反馈。
-- 版本号：202609181400
-- 1、更新时间：2026-09-18 14:00
--    修复 DAC 模式下设置MIC音量导致 Air1601 死机问题。
-- 版本号：202609161747
-- 1、更新时间：2026-09-16 17:47
--    修复 air1103 模式在 Air1601 上 exaudio.setup 死机：
--       Air1601 跳过该 I2S 配置——其 Air1103 走 UART 录音/播放不需要 I2S 参数,
--       780EHM 等需要 cc 通话下行的型号仍正常配置 I2S。
-- 2、air1103 模式下 exaudio.sip_voip_start/stop 跳过 audio_v2 的 SIP 桥接并直接返回成功:
--    Air1103 的 SIP 通话音频由业务层通过 voip.pcmIn/pcmOut 与 UART 自行桥接;
--    若此处返回 false, exsip 会判定桥接失败并执行 voip.stop(), 导致通话没有音频。
-- 版本号：202609091419
-- 1、更新时间：2026-09-09 14:19
--    新增 DAC模式麦克风增益设置：model="dac" 时 exaudio.mic_vol(vol[, ana_vol])数字/模拟增益均由客户按 0-100 传入。
--    并在 REQUEST_DRIVER_START 与 pm(RESUME) 时自动重新应用，修复 Air8101 等纯DAC模组无法调节麦克风音量的问题。
-- 版本号：202609041030
-- 1、更新时间：2026-09-04 10:30
--    修复 air1103 使用新框架进行VOLTE通话时无声问题。
-- 版本号：202609011550
-- 1、更新时间：2026-09-01 15:50
--    修复Air1602开发板exaudio.pm(exaudio.SHUTDOWN)会关闭I2C1导致LCD触摸失效的问题。
-- 2、修复 air1103 模式(exaudio.setup({model="air1103"}))：原 air1103 分支在初始化 Air1103 芯片后
--    直接 return true，导致跳过 audio_v2_setup()，audio_v2.config(I2S参数) 从未执行，cc 通话下行
--    record 数据源节奏异常→下行数据断流、喇叭仅静音帧杂音。现已补上 audio_v2_setup 的 air1103 分支
--    (配置I2S 16k/16bit/LSB/RIGHT 并跳过 audio_v2.shutdown 低功耗休眠)，与 air1103 模式行为一致；
--    exaudio.pm 对 air1103/air1103 直接跳过电源控制。
-- 版本号：202608272002
-- 1、更新时间：2026-08-27 20:02
--    音频框架选择同时依据模组默认偏好和固件实际提供的audio/audio_v2库，修复未启用LUAT_USE_AUDIO_V2时仍误选新音频框架的问题。
--    显式audio_mode选择增加库能力校验，并保持Air8101、Air160X等模组优先使用Audio V2的原有约束。
-- 版本号：202608251813
-- 1、更新时间：2026-08-25 18:13
--    修复旧音频框架多音频连续播放报错的问题，同步更新 exaudio.play 两处调用，旧框架多音频播放恢复正常。
--    修复部分固件跑sip功能时，会出现死机或通话无声的问题。
-- 版本号：202608192010
-- 1、更新时间：2026-08-19 20:10
--    修复PCM流式录音手动停止后不触发录音完成回调的问题。
--    修复exaudio.pm(exaudio.RESUME)恢复ES8311时未传递codec_voltage参数，避免1.8V板型(Air8201H等)休眠恢复后ES8311电平被重置为3.3V。
-- 版本号：202608141949
-- 1、更新时间：2026-08-14 19:49
--    修复codec_voltage参数无效问题：setup时audio_setup_param.codec_voltage始终为默认值1(3.3V)，现加入optional_params，外部设置codec_voltage=0(1.8V)可正确生效
-- 版本号：202608111818
-- 1、更新时间：2026-08-11 18:18
--    新增默认驱动切换支持：audio_setup_param新增tx_bus_type/tx_bus_id/rx_bus_type/rx_bus_id，当板子上有多种音频驱动、需播放和录音使用不同驱动时设置默认nil不启用
--    切换默认驱动成功后，对dac_ctrl引脚做一次"拉低→等待→拉高"复位脉冲重启ES8311（驱动切换会重新配置I2S总线，dac_ctrl需从确定状态启动才能正常I2C通信）
--    read_es8311_id()增加框架判断：audio_v2用i2c.readReg读取0xFD寄存器(0x83)校验，audio旧框架用i2c.send+i2c.recv读取CHIP_ID_REG，保持原有逻辑
--    audio_v2_callback修复录音请求误报日志
-- 版本号：202608071000
-- 1、更新时间：2026-08-07 10:29
--    新增休眠控制宏exaudio.RESUME/exaudio.SHUTDOWN，解决Air1602等无audio库固件报错
--    所有exaudio.pm()调用统一改为exaudio.pm(exaudio.RESUME)/exaudio.pm(exaudio.SHUTDOWN)
-- 版本号：202608061100
-- 1、更新时间：2026-08-06 11:00
--    新音频框架play_start()播放前主动exaudio.pm(audio.RESUME)恢复ES8311工作模式
--    新音频框架play_stop()手动停止时exaudio.pm(audio.SHUTDOWN)下电ES8311省电
--    同时exaudio.vol()同步更新voice_vol变量，修复CC铃声无法设置问题
-- 版本号：202608031526
-- 1、更新时间：2026-08-03 15:26
--    play_start()文件播放新增文件头损坏预检功能
--    对mp3/amr/wav格式，播放前先解析文件头，文件不存在或头损坏时停止播放并提示"播放文件损坏，请更换文件播放"
-- 版本号：202607171800
-- 1、更新时间：2026-07-17 18:00
--    改造parse_audio_info，支持文件路径和缓冲数据两种方式输入
-- 版本号：202607161030
-- 1、更新时间：2026-07-16 10:30
--    移除新音频框架初始化audio_v2_setup中的make_probe_id+set_default_driver操作
--    各BSP有默认驱动，无需手动设置，特殊情况可通过exaudio.set_default_driver接口设置
-- 版本号：202607141800
-- 1、更新时间：2026-07-14 18:00
--    新增codec_voltage参数控制ES8311电平
--    codec_voltage=1(默认3.3V)，codec_voltage=0(1.8V，适配Air8201等特殊板型)
-- 版本号：202607081647
-- 1、更新时间：2026-07-08 16:47
--    移除exaudio.shutdown()，统一合并到exaudio.pm()中
--    exaudio.pm()新增新音频框架支持
--    新增exaudio.make_probe_id()函数，用于合成音频驱动ID
--    新增Air700/Air1780系列模组检测
-- 版本号：202607021200
-- 1、更新时间：2026-07-02 12:00
-- 2、更新内容
--    新增exaudio.version()接口
--    支持exaudio库文件版本号管理功能，版本号的格式为：yyyymmddhhmm，表示yyyy年mm月dd日hh时mm分发布的版本
]]
local exaudio = {}

-- ==================== 模组检测 ====================
-- 获取当前模组型号
local function get_module_type()
    local model = hmeta and hmeta.model and hmeta.model()
    if model then
        local model_lower = model:lower()
        if model_lower:find("air1601") then
            return "air1601"
        elseif model_lower:find("air1602") then
            return "air1602"
        elseif model_lower:find("air8101") then
            return "air8101"
        elseif model_lower:find("air780e") then
            return "air780e"       -- 780EXX系列
        elseif model_lower:find("air8000") then
            return "air8000"      -- 8000系列
        elseif model_lower:find("air700") then
            return "air700"       -- Air700系列
        elseif model_lower:find("air1780") then
            return "air1780"      -- Air1780系列
        end
    end
    return "other"
end

-- 当前模组型号
local MODULE_TYPE = get_module_type()

-- 判断使用audio_v2还是audio。模组型号只决定默认偏好，实际选择必须受固件
-- 已编译的Lua库约束，避免无LUAT_USE_AUDIO_V2的固件误报为新音频框架。
local AUDIO_V2_AVAILABLE = audio_v2 ~= nil
local AUDIO_LEGACY_AVAILABLE = audio ~= nil
local PREFER_AUDIO_V2 = (MODULE_TYPE ~= "air780e" and MODULE_TYPE ~= "air8000" and
    MODULE_TYPE ~= "air700" and MODULE_TYPE ~= "air1780")
local USE_AUDIO_V2 = AUDIO_V2_AVAILABLE and (PREFER_AUDIO_V2 or not AUDIO_LEGACY_AVAILABLE)

-- ==================== 常量定义 ====================
local I2S_ID = 0
local MULTIMEDIA_ID = 0
local EX_MSG_PLAY_DONE = "playDone"
local ES8311_ADDR = 0x18    -- 7位地址
local CHIP_ID_REG = 0x00    -- 芯片ID寄存器地址
local PCM_BUFFER_DURATION_MS = 50  -- 每个缓冲区的时长（毫秒）

-- audio_v2相关常量
local AUDIO_V2_DRIVER_ID = nil  -- audio_v2驱动ID，初始化时设置

-- 模块常量
exaudio.PLAY_DONE = 1         --   音频播放完毕的事件之一
exaudio.RECORD_DONE = 1       --   音频录音完毕的事件之一  
exaudio.AMR_NB = 0
exaudio.AMR_WB = 1
exaudio.PCM_8000 = 2
exaudio.PCM_16000 = 3 
exaudio.PCM_24000 = 4
exaudio.PCM_32000 = 5
exaudio.PCM_48000 = 6

-- 休眠控制模式宏
exaudio.RESUME = 0      -- 工作模式
exaudio.SHUTDOWN = 2    -- 关断模式

-- ==================== 版本自适应 ====================
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

-- ==================== 配置参数 ====================
local audio_setup_param = {
    model = "es8311",    -- 编解码器类型: "es8311"、"tm8211" 或 "dac"(内置DAC)
    i2c_id = 0,               -- i2c_id: 0,1
    pa_ctrl = 0,              -- 音频放大器电源控制管脚
    dac_ctrl = 0,             -- 音频编解码芯片电源控制管脚
        
    -- 【注意：固件版本＜V2026，这里单位为1ms，这里填600，否则可能第一个字播不出来】
    dac_delay = set_dac_delay,            -- DAC启动前冗余时间
    
    pa_delay = 10,           -- DAC启动后延迟打开PA的时间(ms)
    dac_time_delay = 600,      -- 播放完毕后PA与DAC关闭间隔(ms)
    pa_on_level = 1,          -- PA打开电平 1:高 0:低       
    channels = 1,             -- 声道数: 1:单声道 2:双声道
    
    -- I2S硬件配置参数
    i2s_mode = 0,                -- I2S模式: 0:主机 1:从机
    i2s_sample = 16000,     -- I2S采样率
    bits_per_sample = 16,     -- I2S采样位深
    i2s_comm_format = i2s and i2s.MODE_LSB or 0, -- I2S通信格式: MODE_I2S, MODE_LSB, MODE_MSB
    i2s_framebit = 16,       -- I2S通道位宽

    -- 默认驱动切换参数（默认nil不启用，仅当板子上有多种音频驱动且需要播放和录音使用不同驱动时设置）
    -- 设置后setup内部自动执行exaudio.make_probe_id + set_default_driver，
    -- 并在切换成功后对dac_ctrl引脚做一次"拉低→等待→拉高"复位脉冲重启ES8311。
    -- 不设置时使用BSP默认驱动
    tx_bus_type = nil,        -- 发送(播放)总线类型，见audio_v2.DRIVER_TYPE_*常量，如DRIVER_TYPE_DAC
    tx_bus_id = nil,          -- 发送总线ID
    rx_bus_type = nil,        -- 接收(录音)总线类型，见audio_v2.DRIVER_TYPE_*常量，如DRIVER_TYPE_I2S
    rx_bus_id = nil,          -- 接收总线ID

    -- DAC硬件配置参数
    dac_ch = 0,               -- DAC通道号
    dac_chl = 0,              -- DAC通道选择: 0=AUD_LN, 1=AUD_LP, 2=双通道

    codec_voltage = 1,        -- ES8311编解码器电平: 1=3.3V(默认), 0=1.8V(Air8201H等特殊板型)
}

local audio_play_param = {
    type = 0,                  -- 0:文件 1:TTS 2:流式
    content = nil,             -- 播放内容
    cbfnc = nil,               -- 播放完毕回调
    priority = 0,              -- 优先级(数值越大越高)
    sampling_rate = 16000,     -- 采样率(仅流式)
    sampling_depth = 16,       -- 采样位深(仅流式)
    signed_or_unsigned = true, -- PCM是否有符号(仅流式)
    channels = 1,              -- 声道数 1:单声道 2:双声道（将使用setup中的配置）
    stream_buffer_size = 0,    -- 流式缓冲区大小(字节)
}

local audio_record_param = {
    format = 0,               -- 录制格式，支持exaudio.AMR_NB，exaudio.AMR_WB,exaudio.PCM_8000,exaudio.PCM_16000,exaudio.PCM_24000,exaudio.PCM_32000,exaudio.PCM_48000
    time = 5,                 -- 录制时间(秒)
    path = nil,               -- 文件路径或流式回调
    cbfnc = nil               -- 录音完毕回调
}

-- ==================== 内部变量 ====================
local pcm_buff0 = nil
local pcm_buff1 = nil
local voice_vol = 70
local mic_vol = 80
local dac_mic_dig_gain = 60   -- DAC(内置ADC)麦克风数字增益默认值(0~100)，仅model="dac"生效
local dac_mic_ana_gain = 50   -- DAC(内置ADC)麦克风模拟增益默认值(0~100)，仅model="dac"生效

-- 定义全局队列表
local audio_play_queue = {
    requests = {},       -- 存储播放请求的数组，按优先级从高到低排序
    current_priority = 0 -- 当前播放的优先级
}

-- 定义全局流式数据队列
local audio_stream_queue = {
    data = {},           -- 存储字符串的数组
    sequenceIndex = 1    -- 用于跟踪插入顺序的索引
}

-- audio_v2相关变量
local cc_auto_pm_enabled = false      -- 通话自动唤醒是否已开启（防止重复订阅CC_IND）
local audio_v2_request_index = nil  -- 当前播放请求的索引
local audio_v2_record_request_index = nil  -- 当前录音请求的索引
local audio_v2_stream_file_fp = nil  -- 流式播放文件句柄(audio_v2模式)
local audio_v2_stream_codec_id = nil  -- 流式播放codec_id(audio_v2模式)
local audio_v2_stream_data_start = nil  -- 流式播放数据起始位置(audio_v2模式)
local audio_v2_record_zbuff = nil  -- 录音zbuff（audio_v2回调模式）
-- 普通 SIP 本地音频适配资源；CC<->SIP 桥接使用 CC 底层资源，不使用本组请求和定时器。
local sip_v2_request_index, sip_v2_source_index, sip_v2_record_zbuff, sip_v2_timer
local audio_v2_stream_end_marked = false  -- 标记流式结束（队列模式）
local audio_v2_es8311_drv = nil  -- ES8311驱动引用（audio_v2模式）

-- ==================== 工具函数 ====================
-- 参数检查
local function check_param(param, expected_type, name)
    if type(param) ~= expected_type then
        log.error(string.format("参数错误: %s 应为 %s 类型", name, expected_type))
        return false
    end
    return true
end

-- 计算缓冲区大小, 公式：采样率 * 声道数 * 采样位数/8 * 缓冲区时长(秒)
local function calculate_buffer_size(sampling_rate, sampling_depth, channels)
    local bytes_per_sample = sampling_depth / 8
    local bytes_per_channel_per_second = sampling_rate * bytes_per_sample
    local bytes_per_buffer = bytes_per_channel_per_second * channels * (PCM_BUFFER_DURATION_MS / 1000)
    return math.floor(bytes_per_buffer / 4) * 4  -- 对齐到4字节
end

-- ==================== 队列操作函数 ====================
-- 向播放请求队列中添加请求（按优先级排序）
local function audio_play_queue_push_request(request)
    if type(request) == "table" and request.priority then
        -- 按优先级从高到低插入队列
        local inserted = false
        for i, existing_request in ipairs(audio_play_queue.requests) do
            if request.priority > existing_request.priority then
                table.insert(audio_play_queue.requests, i, request)
                inserted = true
                break
            end
        end
        
        if not inserted then
            table.insert(audio_play_queue.requests, request)
        end
        return true
    end
    return false
end

-- 从播放请求队列中取出最高优先级的请求
local function audio_play_queue_pop_request()
    if #audio_play_queue.requests > 0 then
        -- 取出并移除最高优先级的请求（队列第一个元素）
        local request = table.remove(audio_play_queue.requests, 1)
        audio_play_queue.current_priority = request.priority
        return request
    end
    audio_play_queue.current_priority = 0
    return nil
end

-- 向流式数据队列中添加字符串（按调用顺序插入）
local function audio_stream_queue_push(str)
    if type(str) == "string" then
        -- 存储格式: {index = 顺序索引, value = 字符串值}
        table.insert(audio_stream_queue.data, {
            index = audio_stream_queue.sequenceIndex,
            value = str
        })
        audio_stream_queue.sequenceIndex = audio_stream_queue.sequenceIndex + 1
        return true
    end
    return false
end

-- 从流式数据队列中取出最早插入的字符串（按顺序取出）
local function audio_stream_queue_pop()
    if #audio_stream_queue.data > 0 then
        -- 取出并移除第一个元素
        local item = table.remove(audio_stream_queue.data, 1)
        return item.value  -- 返回值
    end
    return nil
end

-- 清空所有队列数据
local function audio_queue_clear()
    -- 清空播放请求队列
    audio_play_queue.requests = {}
    audio_play_queue.current_priority = 0
    
    -- 清空流式数据队列
    audio_stream_queue.data = {}
    audio_stream_queue.sequenceIndex = 1
    return true
end

-- ==================== audio_v2 回调处理 ====================
local function audio_v2_callback(request_index, event, param)
    if event == audio_v2.REQUEST_START then
        -- REQUEST_START对播放和录音请求都会触发，需区分打印
        if audio_v2_record_request_index == request_index then
            log.info("exaudio", "录音开始", request_index)
        else
            audio_v2_request_index = request_index
            log.info("exaudio", "播放开始", request_index)
        end
    elseif event == audio_v2.REQUEST_DRIVER_START then
        -- ES8311 每次启动请求时恢复 DAC、音量和 PA。
        if audio_setup_param.model == "es8311" and audio_v2_es8311_drv then
            audio_v2_es8311_drv.resume(audio_setup_param.i2c_id)
            audio_v2_es8311_drv.set_mute(audio_setup_param.i2c_id, false)
            audio_v2_es8311_drv.set_voice_vol(audio_setup_param.i2c_id, voice_vol)
            audio_v2_es8311_drv.set_mic_vol(audio_setup_param.i2c_id, mic_vol)
            if audio_setup_param.pa_ctrl and audio_setup_param.pa_ctrl > 0 then
                gpio.setup(audio_setup_param.pa_ctrl, audio_setup_param.pa_on_level)
            end
            log.info("exaudio", "audio_v2 driver start: ES8311 DAC/PA resumed")
        elseif audio_setup_param.model == "dac" and MODULE_TYPE == "air8101" then
            -- Air8101每次启动请求时重新应用麦克风增益
            apply_dac_mic_gain()
        end
    elseif event == audio_v2.REQUEST_NEED_NEW_DATA then
        -- 流式播放需要更多数据
        -- 先调用input()检查FIFO剩余空间
        -- 优先使用文件句柄方式
        if audio_v2_stream_file_fp and request_index == audio_v2_request_index then
            -- 文件流模式：先获取FIFO剩余空间，再循环写入
            local result, write_len, free_len = audio_v2.input(request_index)
            if result and free_len then
                while free_len > 0 do
                    -- 每次读取不超过FIFO剩余空间，避免partial write导致数据丢失
                    local read_size = free_len > 4096 and 4096 or free_len
                    local data = audio_v2_stream_file_fp:read(read_size)
                    if data then
                        local is_end = #data < read_size
                        result, write_len, free_len = audio_v2.input(request_index, data, is_end)
                        if not result then break end
                        -- 处理partial write：把未写入部分回退到文件，下次NEED_NEW_DATA继续读取
                        if write_len and write_len < #data then
                            local current_pos = audio_v2_stream_file_fp:seek("cur", 0)
                            audio_v2_stream_file_fp:seek("set", current_pos - (#data - write_len))
                            break
                        end
                        if is_end then
                            break
                        end
                    else
                        audio_v2.input(request_index, nil, true)
                        break
                    end
                end
            end
        else
            -- 队列模式：用户通过play_stream_write写入数据，循环填充直到FIFO满或队列空
            local result, write_len, free_len = audio_v2.input(request_index)
            if result and free_len then
                while free_len > 0 do
                    local data = audio_stream_queue_pop()
                    if data then
                        result, write_len, free_len = audio_v2.input(request_index, data, false)
                        if not result then break end
                        -- 处理partial write：audio_v2.input()只写入free_len能容纳的部分，剩余放回队列
                        if write_len and write_len < #data then
                            local remaining = data:sub(write_len + 1)
                            table.insert(audio_stream_queue.data, 1, {index = 0, value = remaining})
                            break
                        end
                    else
                        break
                    end
                end
            end
            -- while循环可能因partial write/FIFO满等原因退出而不走else分支，
            -- 所以此处统一检查：只有队列真正空了才发结束标记
            if audio_v2_stream_end_marked and #audio_stream_queue.data == 0 then
                audio_v2.input(request_index, "", true)
                audio_v2_stream_end_marked = false
            end
        end
    elseif event == audio_v2.REQUEST_GET_NEW_DATA then
        -- 普通 SIP 上行：本地 MIC 的 8 kHz/16 bit/单声道 PCM -> VoIP 编码并发送 RTP。
        -- CC<->SIP 模式的上行来源是 CC 对端语音，由固件直接转送，不经过此录音回调。
        if request_index == sip_v2_request_index and sip_v2_record_zbuff and voip then
            local used = sip_v2_record_zbuff:used()
            if used > 0 and type(voip.pcmIn) == "function" then
                voip.pcmIn(sip_v2_record_zbuff:query(0, used))
                sip_v2_record_zbuff:del()
            end
            return
        end
        -- 录音数据
        if type(audio_record_param.path) == "function" and audio_v2_record_zbuff then
            local total = audio_v2_record_zbuff:used()
            if total > 0 then
                audio_record_param.path(audio_v2_record_zbuff, total)
                audio_v2_record_zbuff:del()
            end
        end
    elseif event == audio_v2.REQUEST_END then
        -- 判断是录音结束还是播放结束
        if audio_v2_record_request_index == request_index then
            -- 录音结束
            audio_v2_record_request_index = nil
            audio_v2_record_zbuff = nil
            log.info("exaudio", "录音完毕", request_index)
            if type(audio_record_param.cbfnc) == "function" then
                audio_record_param.cbfnc(exaudio.RECORD_DONE)
            end
            -- 录音不发布EX_MSG_PLAY_DONE
        elseif audio_v2_request_index == request_index then
            -- 播放结束
            log.info("exaudio", "播放完毕", request_index)
            -- 关闭文件句柄
            if audio_v2_stream_file_fp then
                audio_v2_stream_file_fp:close()
                audio_v2_stream_file_fp = nil
            end
            
            if type(audio_play_param.cbfnc) == "function" then
                audio_play_param.cbfnc(exaudio.PLAY_DONE)
            end
            
            -- audio_v2 自带优先级管理，下一个请求会自动播放
            audio_v2_request_index = nil
            audio_v2_stream_codec_id = nil
            audio_v2_stream_data_start = nil
            audio_v2_stream_end_marked = false
            audio_play_queue.current_priority = 0
            
            sys.publish(EX_MSG_PLAY_DONE)
        end
    end
end

-- ==================== 播放控制 ====================
-- audio模式开始播放
local function start_next_play()
    local request = audio_play_queue_pop_request()
    if not request then
        return false
    end
    
    local playConfigs = request.configs
    audio_play_param.priority = request.priority
    
    -- 处理不同播放类型
    local play_type = playConfigs.type
    if play_type == 0 then  -- 文件播放
        if not playConfigs.content then
            log.error("文件播放需要指定content(文件路径或路径表)")
            return false
        end

        local content_type = type(playConfigs.content)
        if content_type == "table" then
            for _, path in ipairs(playConfigs.content) do
                if type(path) ~= "string" then
                    log.error("播放列表元素必须为字符串路径")
                    return false
                end
            end
            -- 多文件播放时检查音频参数一致性
            if #playConfigs.content > 1 then
                -- 根据文件扩展名获取codec类型
                local function get_codec_type(file_path)
                    local ext = file_path:match("%.([^.]+)$")
                    if ext then
                        ext = ext:lower()
                        if ext == "mp3" then
                            return codec.MP3
                        elseif ext == "amr" then
                            return codec.AMR
                        end
                    end
                    return nil
                end
                
                local codec_type = get_codec_type(playConfigs.content[1])
                if not codec_type then
                    log.error("无法识别第一个音频文件格式:", playConfigs.content[1])
                    return false
                end
                
                -- 创建临时decoder用于获取音频信息
                local coder = codec.create(codec_type, true)
                if not coder then
                    log.error("无法创建codec decoder, 类型:", codec_type)
                    return false
                end
                local result, audio_format, num_channels, sample_rate, bits_per_sample, is_signed = codec.info(coder, playConfigs.content[1])
                if not result then
                    log.error("无法获取第一个音频文件信息:", playConfigs.content[1])
                    codec.release(coder)
                    return false
                end
                for i = 2, #playConfigs.content do
                    local codec_type2 = get_codec_type(playConfigs.content[i])
                    if codec_type2 ~= codec_type then
                        log.error("多文件播放要求格式一致，文件", playConfigs.content[i], 
                            "格式与第一个文件格式不同")
                        codec.release(coder)
                        return false
                    end
                    local result2, audio_format2, num_channels2, sample_rate2, bits_per_sample2, is_signed2 = codec.info(coder, playConfigs.content[i])
                    if not result2 then
                        log.error("无法获取音频文件信息:", playConfigs.content[i])
                        codec.release(coder)
                        return false
                    end
                    if sample_rate2 ~= sample_rate then
                        log.error("多文件播放要求采样率一致，文件", playConfigs.content[i], 
                            "采样率", sample_rate2, "与第一个文件采样率", sample_rate, "不同")
                        codec.release(coder)
                        return false
                    end
                    if num_channels2 ~= num_channels then
                        log.error("多文件播放要求声道数一致，文件", playConfigs.content[i],
                            "声道数", num_channels2, "与第一个文件声道数", num_channels, "不同")
                        codec.release(coder)
                        return false
                    end
                    if bits_per_sample2 ~= bits_per_sample then
                        log.error("多文件播放要求采样位深一致，文件", playConfigs.content[i],
                            "位深", bits_per_sample2, "与第一个文件位深", bits_per_sample, "不同")
                        codec.release(coder)
                        return false
                    end
                end
                codec.release(coder)
                log.info("多文件播放参数检查通过，采样率:", sample_rate,
                    "声道数:", num_channels, "位深:", bits_per_sample)
            end
        elseif content_type ~= "string" then
            log.error("文件播放content必须为字符串或路径表")
            return false
        end

        audio_play_param.content = playConfigs.content
        if audio.play(MULTIMEDIA_ID, audio_play_param.content) ~= true then
            return false
        end

    elseif play_type == 1 then  -- TTS播放
        if not audio.tts then
            log.error("本固件不支持TTS,请更换支持TTS 的固件")
            return false
        end
        if not check_param(playConfigs.content, "string", "content") then
            log.error("TTS播放content必须为字符串")
            return false
        end
        audio_play_param.content = playConfigs.content
        if audio.tts(MULTIMEDIA_ID, audio_play_param.content)  ~= true  then
            return false
        end

    elseif play_type == 2 then  -- 流式播放
        if not check_param(playConfigs.sampling_rate, "number", "sampling_rate") then
            return false
        end
        if not check_param(playConfigs.sampling_depth, "number", "sampling_depth") then
            return false
        end

        audio_play_param.content = playConfigs.content
        audio_play_param.sampling_rate = playConfigs.sampling_rate
        audio_play_param.sampling_depth = playConfigs.sampling_depth
        audio_play_param.channels = audio_setup_param.channels or 1

        -- 计算每个缓冲区的大小（字节数）
        audio_play_param.stream_buffer_size = calculate_buffer_size(
            audio_play_param.sampling_rate,
            audio_play_param.sampling_depth,
            audio_play_param.channels
        )

        if playConfigs.signed_or_unsigned ~= nil then
            audio_play_param.signed_or_unsigned = playConfigs.signed_or_unsigned
        end

        audio.start(
            MULTIMEDIA_ID, 
            audio.PCM, 
            audio_play_param.channels, 
            playConfigs.sampling_rate, 
            playConfigs.sampling_depth, 
            audio_play_param.signed_or_unsigned
        )

        -- 发送初始数据（使用计算出的缓冲区大小）
        if audio.write(MULTIMEDIA_ID, string.rep("\0", audio_play_param.stream_buffer_size)) ~= true then
            return false
        end
    end                        

    -- 处理回调函数
    if playConfigs.cbfnc ~= nil then
        if check_param(playConfigs.cbfnc, "function", "cbfnc") then
            audio_play_param.cbfnc = playConfigs.cbfnc
        else
            return false
        end
    else
        audio_play_param.cbfnc = nil
    end
    
    return true
end

-- ==================== audio 回调处理 ====================
local function audio_callback(id, event, point)
    if event == audio.MORE_DATA then
        -- 从队列取出数据并写入
        local data = audio_stream_queue_pop()
        if data then
            audio.write(MULTIMEDIA_ID, data)
        end
    elseif event == audio.DONE then
        if type(audio_play_param.cbfnc) == "function" then
            audio_play_param.cbfnc(exaudio.PLAY_DONE)
        end
        
        -- 检查是否有下一个播放请求
        if #audio_play_queue.requests > 0 then
            -- 播放下一个请求
            start_next_play()
        else
            -- 没有更多请求，清空流式播放数据队列并进入休眠
            audio_stream_queue.data = {}
            audio_stream_queue.sequenceIndex = 1
            audio.pm(MULTIMEDIA_ID, exaudio.SHUTDOWN) -- 关断模式
            audio_play_queue.current_priority = 0
        end
        
        sys.publish(EX_MSG_PLAY_DONE)
        
    elseif event == audio.RECORD_DATA then
        if type(audio_record_param.path) == "function" then
            local buff, len = point == 0 and pcm_buff0 or pcm_buff1,
                             point == 0 and pcm_buff0:used() or pcm_buff1:used()
            audio_record_param.path(buff, len)
            -- 清空缓冲区数据，释放内存
            if buff and buff.del then
                buff:del()
            end
        end
        
    elseif event == audio.RECORD_DONE then
        if type(audio_record_param.cbfnc) == "function" then
            audio_record_param.cbfnc(exaudio.RECORD_DONE)
        end

        audio.pm(MULTIMEDIA_ID, exaudio.SHUTDOWN) -- 关断模式
    end
end

-- ==================== 硬件初始化 ====================
-- 读取ES8311芯片ID
-- audio_v2框架：使用i2c.readReg读取寄存器
-- audio旧框架：使用i2c.send+i2c.recv读取CHIP_ID_REG寄存器，保持原有逻辑
local function read_es8311_id()
    if USE_AUDIO_V2 then
        local data = i2c.readReg(audio_setup_param.i2c_id, ES8311_ADDR, 0xFD, 1)
        if data and #data == 1 and data:byte(1) == 0x83 then
            return true
        end
    else
        -- audio旧框架，读取芯片ID
        local send_ok = i2c.send(audio_setup_param.i2c_id, ES8311_ADDR, CHIP_ID_REG)
        if not send_ok then
            log.error("发送芯片ID读取请求失败")
            return false
        end
        local data = i2c.recv(audio_setup_param.i2c_id, ES8311_ADDR, 1)
        if data and #data == 1 then
            return true
        end
    end

    log.error("读取ES8311芯片ID失败")
    return false
end

-- audio_v2模式初始化
local function audio_v2_setup()
    -- 切换默认驱动
    -- 仅当板子上有多种音频驱动、播放和录音需使用不同驱动时，才需设置tx_bus_type/rx_bus_type。
    -- 例如DAC输出+I2S录音的板型，设置后本函数自动执行exaudio.make_probe_id+set_default_driver。
    -- 不设置时使用BSP默认驱动。
    local switch_default_driver = false
    if audio_setup_param.tx_bus_type and audio_setup_param.rx_bus_type then
        local pid = exaudio.make_probe_id(
            audio_setup_param.tx_bus_type, audio_setup_param.tx_bus_id or 0,
            audio_setup_param.rx_bus_type, audio_setup_param.rx_bus_id or 0)
        if pid then
            local ok = audio_v2.set_default_driver(pid)
            if ok then
                AUDIO_V2_DRIVER_ID = pid
                switch_default_driver = true
                log.info("exaudio.setup", "默认驱动已切换", "tx_bus_type:", audio_setup_param.tx_bus_type,
                    "rx_bus_type:", audio_setup_param.rx_bus_type)
            else
                log.error("exaudio.setup", "set_default_driver失败，将使用BSP默认驱动")
            end
        else
            log.error("exaudio.setup", "make_probe_id失败，将使用BSP默认驱动")
        end
    elseif audio_setup_param.tx_bus_type or audio_setup_param.rx_bus_type then
        -- 只设置了其中一个，参数不完整，继续使用BSP默认驱动
        log.warn("exaudio.setup", "tx_bus_type和rx_bus_type必须同时设置才能切换默认驱动，本次忽略，使用BSP默认驱动")
    end

    -- 根据model进行不同的初始化
    if audio_setup_param.model == "dac" then
        -- DAC模式（Air1601等使用内置DAC的模组）
        log.info("exaudio.setup", "audio_v2 DAC模式初始化")
    elseif audio_setup_param.model == "es8311" then
        -- ES8311 I2S模式（Air780EHM等使用ES8311的模组）
        log.info("exaudio.setup", "audio_v2 ES8311模式初始化")

        -- I2C配置
        if not i2c.setup(audio_setup_param.i2c_id) then
            log.error("I2C初始化失败")
            return false
        end

        -- 切换默认驱动后，对音频编解码芯片做复位重启（dac_ctrl引脚拉低→等待→拉高）
        -- 仅切换驱动时需要：驱动切换会重新配置I2S总线，ES8311需从确定状态启动才能正常I2C通信。
        -- 使用默认I2S无需此操作。
        if switch_default_driver and audio_setup_param.dac_ctrl and audio_setup_param.dac_ctrl > 0 then
            gpio.setup(audio_setup_param.dac_ctrl, 0)
            sys.wait(100)
            gpio.set(audio_setup_param.dac_ctrl, 1)
            sys.wait(100)
            log.info("exaudio.setup", "ES8311已重启", "dac_ctrl:", audio_setup_param.dac_ctrl)
        end
    elseif audio_setup_param.model == "air1103" then
        -- Air1103外置语音芯片模式(780EHM等无本地音频硬件): 只初始化新音频框架,
        -- 不做I2C/PA/CODEC任何硬件操作, 后续在I2S参数段统一配置audio_v2并跳过低功耗休眠
        log.info("exaudio.setup", "audio_v2 Air1103模式初始化")
    else
        log.error("audio_v2不支持的model:", audio_setup_param.model)
        return false
    end
    
    -- 注册audio_v2事件回调
    audio_v2.on(audio_v2_callback)
    
    -- 配置PA电源控制
    if audio_setup_param.model ~= "air1103" and audio_setup_param.pa_ctrl and audio_setup_param.pa_ctrl > 0 then
        audio_v2.config_pa_power_ctrl(
            true,  -- 使能PA电源控制
            audio_setup_param.pa_ctrl,  -- PA控制引脚
            audio_setup_param.pa_on_level,  -- PA使能电平
            audio_setup_param.pa_delay or 200  -- 延时
        )
    end
    
    -- ES8311模式下：Codec电源由手动GPIO控制，防止断电后ES8311寄存器丢失
    if audio_setup_param.model == "es8311" then
        -- 手动打开CODEC电源并保持常开
        if audio_setup_param.dac_ctrl and audio_setup_param.dac_ctrl > 0 then
            gpio.setup(audio_setup_param.dac_ctrl, 1)
        end
        
        -- 配置audio_v2 I2S参数
        -- 切换默认驱动后由BSP默认驱动提供I2S参数，无需在此配置
        if not switch_default_driver then
            audio_v2.config(audio_v2.CFG_PARAM_I2S_MODE, audio_v2.CFG_VALUE_I2S_MODE_LSB)
            audio_v2.config(audio_v2.CFG_PARAM_I2S_FRAME_BITS, audio_setup_param.i2s_framebit or 16, audio_setup_param.i2s_framebit or 16)
            audio_v2.config(audio_v2.CFG_PARAM_I2S_CHANNEL_TYPE, audio_v2.CFG_VALUE_I2S_CHANNEL_TYPE_RIGHT)
        else
            log.info("exaudio.setup", "已切换默认驱动，I2S参数使用默认配置")
        end
        
        -- 初始化ES8311编解码器
        local es8311_ok
        es8311_ok, audio_v2_es8311_drv = pcall(require, "es8311")
        if es8311_ok and audio_v2_es8311_drv then
            sys.wait(10)
            
            -- 检查ES8311芯片连接
            if not read_es8311_id() then
                log.error("ES8311通讯失败，请检查硬件")
                return false
            end
            
            local init_ok
            if audio_setup_param.codec_voltage == 0 then
                init_ok = audio_v2_es8311_drv.init(audio_setup_param.i2c_id, 0x01) -- 1.8V电平（Air8201H等特殊板型 ES8311电平为1.8V）
            else
                init_ok = audio_v2_es8311_drv.init(audio_setup_param.i2c_id) -- 默认3.3V
            end

            if init_ok then
                audio_v2_es8311_drv.set_sample_rate(audio_setup_param.i2c_id, audio_setup_param.i2s_sample or 16000, 256)
                audio_v2_es8311_drv.set_data_bits(audio_setup_param.i2c_id, audio_setup_param.bits_per_sample or 16)
                audio_v2_es8311_drv.set_format(audio_setup_param.i2c_id)
                audio_v2_es8311_drv.resume(audio_setup_param.i2c_id)
                audio_v2_es8311_drv.set_voice_vol(audio_setup_param.i2c_id, voice_vol)
                audio_v2_es8311_drv.set_mic_vol(audio_setup_param.i2c_id, mic_vol)
                log.info("exaudio.setup", "ES8311初始化完成")
            else
                log.error("ES8311芯片初始化失败")
                return false
            end
        else
            log.warn("exaudio.setup", "未找到es8311驱动模块")
        end

        -- ES8311模式下初始化完成后进入低功耗休眠（只关PA，不关Codec电源，防止配置丢失）
        audio_v2.shutdown(false, false, true)
    elseif audio_setup_param.model == "air1103" then
        -- I2S参数配置: 供cc通话下行record数据源使用(780EHM等)。
        -- 注意: 实测 Air1601/Air1602 调用 audio_v2.config 会触发底层 UsageFault(pc=0)死机,
        --       且其 Air1103 UART 录音/播放场景不需要 I2S 参数, 故 Air1601/Air1602 跳过配置。
        if MODULE_TYPE ~= "air1601" and MODULE_TYPE ~= "air1602" then
            audio_v2.config(audio_v2.CFG_PARAM_I2S_MODE, audio_v2.CFG_VALUE_I2S_MODE_LSB)
            audio_v2.config(audio_v2.CFG_PARAM_I2S_FRAME_BITS, 16, 16)
            audio_v2.config(audio_v2.CFG_PARAM_I2S_CHANNEL_TYPE, audio_v2.CFG_VALUE_I2S_CHANNEL_TYPE_RIGHT)
        end
        log.info("exaudio.setup", "audio_v2 Air1103模式初始化")
    else
        -- DAC等其他模式下初始化完成后进入低功耗休眠
        audio_v2.shutdown(false, true, true)
    end
    -- 同步旧音频框架的 bus_type，确保 voip 能正确识别音频后端为 I2S
    if audio_setup_param.model == "es8311" and audio and audio.setBus then
        pcall(audio.setBus, MULTIMEDIA_ID, audio.BUS_I2S, {
            chip = "es8311",
            i2cid = audio_setup_param.i2c_id,
            i2sid = I2S_ID
        })
    end
    log.info("exaudio.setup", "audio_v2初始化完成")
    return true
end

-- audio模式初始化
local function audio_setup()
    -- Air1103走UART串口, 旧音频框架无需硬件初始化。
    if audio_setup_param.model == "air1103" then
        log.info("exaudio.setup", "audio旧框架 Air1103模式: 无需本地音频硬件初始化")
        return true
    end

    -- 根据model选择初始化方式
    if audio_setup_param.model == "dac" then
        -- DAC模式初始化
        log.info("exaudio.setup", "使用DAC模式初始化")
        
        -- 配置音频通道
        audio.config(
            MULTIMEDIA_ID, 
            audio_setup_param.pa_ctrl,      -- PA控制引脚
            audio_setup_param.pa_on_level,  -- PA打开电平
            0,                              -- dac_delay: 固定为0
            audio_setup_param.pa_delay      -- PA延时
        )
        
        -- 设置总线为DAC模式
        audio.setBus(
            MULTIMEDIA_ID, 
            audio.BUS_DAC,
            {
                dacid = audio_setup_param.dac_ch
            }
        )
        
        log.info("exaudio.setup", "DAC通道已设置为:"..audio_setup_param.dac_ch)
    elseif audio_setup_param.model == "tm8211" then
        -- TM8211模式初始化 (I2S，无需I2C)
        log.info("exaudio.setup", "使用TM8211模式初始化")
        
        -- 初始化I2S
        local I2S_channel_format = audio_setup_param.channels == 2 and i2s.STEREO or i2s.MONO_R

        local result, data = i2s.setup(
            I2S_ID,  -- I2S的通道号
            audio_setup_param.i2s_mode,  -- I2S主从模式
            audio_setup_param.i2s_sample,  -- I2S采样率
            audio_setup_param.bits_per_sample,  -- I2S采样位深
            I2S_channel_format, -- 声道
            audio_setup_param.i2s_comm_format, -- I2S通讯格式
            audio_setup_param.i2s_framebit  -- I2S通道位宽
        )

        if not result then
            log.error("I2S设置失败")
            return false
        end
        -- 配置音频通道
        audio.config(
            MULTIMEDIA_ID, 
            audio_setup_param.pa_ctrl, 
            audio_setup_param.pa_on_level, 
            audio_setup_param.dac_delay, 
            audio_setup_param.pa_delay, 
            audio_setup_param.dac_ctrl, 
            1,  -- power_on_level
            audio_setup_param.dac_time_delay
        )
        -- 设置总线
        audio.setBus(
            MULTIMEDIA_ID, 
            audio.BUS_I2S,
            {
                chip = audio_setup_param.model,
                i2sid = I2S_ID
                -- voltage = audio.VOLTAGE_1800
            }
        )
        -- TM8211无需I2C芯片ID检查
    else
        -- ES8311 I2S模式初始化
        log.info("exaudio.setup", "使用ES8311 I2S模式初始化")
        
        -- I2C配置
        if not i2c.setup(audio_setup_param.i2c_id, i2c.FAST) then
            log.error("I2C初始化失败")
            return false
        end
        -- 初始化I2S
        local I2S_channel_format = audio_setup_param.channels == 2 and i2s.STEREO or i2s.MONO_R

        local result, data = i2s.setup(
            I2S_ID,  -- I2S的通道号
            audio_setup_param.i2s_mode,  -- I2S主从模式
            audio_setup_param.i2s_sample,  -- I2S采样率
            audio_setup_param.bits_per_sample,  -- I2S采样位深
            I2S_channel_format, -- 声道
            audio_setup_param.i2s_comm_format, -- I2S通讯格式
            audio_setup_param.i2s_framebit  -- I2S通道位宽
        )

        if not result then
            log.error("I2S设置失败")
            return false
        end
        -- 配置音频通道
        audio.config(
            MULTIMEDIA_ID, 
            audio_setup_param.pa_ctrl, 
            audio_setup_param.pa_on_level, 
            audio_setup_param.dac_delay, 
            audio_setup_param.pa_delay, 
            audio_setup_param.dac_ctrl, 
            1,  -- power_on_level
            audio_setup_param.dac_time_delay
        )
        -- 设置总线
        audio.setBus(
            MULTIMEDIA_ID, 
            audio.BUS_I2S,
            {
                chip = audio_setup_param.model,
                i2cid = audio_setup_param.i2c_id,
                i2sid = I2S_ID
                -- voltage = audio.VOLTAGE_1800
            }
        )

        -- 检查芯片连接
        if audio_setup_param.model == "es8311" and not read_es8311_id() then
            log.error("ES8311通讯失败，请检查硬件")
            return false
        end
    end

    -- 设置音量
    audio.vol(MULTIMEDIA_ID, voice_vol)
    if audio.micVol then
        audio.micVol(MULTIMEDIA_ID, mic_vol)
    end

    -- 注册回调
    audio.on(MULTIMEDIA_ID, audio_callback)
    
    audio.pm(MULTIMEDIA_ID, exaudio.SHUTDOWN) -- 关断模式
    log.info("exaudio.setup", "声道数已设置为:"..audio_setup_param.channels.."(1=单声道,2=双声道)")
    return true
end

-- ==================== 模块接口 ====================
-- 获取推荐的流式缓冲区大小
function exaudio.get_stream_buffer_size()
    if audio_setup_param.model == "air1103" then
        return 3200
    end
    if USE_AUDIO_V2 then
        -- audio_v2模式下返回推荐值
        local default_channels = audio_setup_param.channels or 1 
        local default_rate = audio_setup_param.i2s_sample 
        local default_depth = audio_setup_param.bits_per_sample 
        return calculate_buffer_size(default_rate, default_depth, default_channels)
    end
    
    if audio_play_param.stream_buffer_size > 0 then
        return audio_play_param.stream_buffer_size
    end

    -- 如果没有开始流式播放，返回一个基于默认参数的推荐值 
    local default_channels = audio_setup_param.channels or 1 
    local default_rate = audio_setup_param.i2s_sample 
    local default_depth = audio_setup_param.bits_per_sample 
    return calculate_buffer_size(default_rate, default_depth, default_channels)
end

-- ==================== air1103 (Air1103 语音芯片) 支持 ====================
-- 通过 UART 驱动 Air1103 播放 PCM 流式音频。
local air1103             = nil     -- require 得到的 air1103 模块引用，setup 时赋值
local air1103_playing     = false   -- air1103 是否正在播放
local air1103_vol         = 31      -- air1103 当前音量(0~31)
local air1103_end_marked  = false   -- 已收到"结束"标记(数据喂完)，等待缓冲排空
local air1103_drain_timer = nil     -- 缓冲排空轮询定时器
local air1103_recording    = false -- air1103 是否正在录音(MIC上行)
local air1103_record_param = nil   -- air1103 录音配置(含 path/cbfnc/time)
local air1103_record_timer = nil   -- air1103 录音自动停止定时器
local air1103_record_queue = {}    -- air1103 录音帧队列(512B string), UART回调入队/写任务出队
local air1103_record_wtask = nil   -- air1103 录音写文件任务
local air1103_record_out   = nil   -- air1103 录音攒批输出 zbuff
local air1103_mic_vol      = 31    -- air1103 麦克风音量(协议暂不支持调节, 仅记录)

-- air1103 播放结束统一处理：停流 + 置状态 + 触发播放完成回调
local function air1103_audio_done()
    if not air1103 then return end
    air1103_end_marked = false
    if air1103_drain_timer then
        sys.timerStop(air1103_drain_timer)
        air1103_drain_timer = nil
    end
    air1103.play_stream_stop()
    air1103_playing = false
    if audio_play_param and audio_play_param.cbfnc then
        audio_play_param.cbfnc(exaudio.PLAY_DONE)
    end
    sys.publish(EX_MSG_PLAY_DONE)
end

-- 缓冲排空轮询：收到结束标记后，待全部 PCM 发到 Air1103 再真正停止，避免尾音被清空截断
local function air1103_check_drain()
    if not air1103_end_marked then
        if air1103_drain_timer then
            sys.timerStop(air1103_drain_timer)
            air1103_drain_timer = nil
        end
        return
    end
    if not air1103 or not air1103.is_running() or air1103.get_pending() <= 0 then
        air1103_audio_done()
    end
end

-- 标记结束并启动排空：若已无待发数据则立即结束，否则轮询至缓冲排空后再停止
local function air1103_mark_end()
    if not air1103 or not air1103_playing then return end
    air1103_end_marked = true
    if not air1103.is_running() or air1103.get_pending() <= 0 then
        air1103_audio_done()
    elseif not air1103_drain_timer then
        air1103_drain_timer = sys.timerLoopStart(air1103_check_drain, 10)
    end
end

-- air1103 上行 MIC 为 16kHz/16bit/单声道(512B/帧, 32KB/s, 见芯片资料 XLS),
-- 原样写入文件即可, 不需要任何降采样/下混处理。
-- air1103 上行 MIC 数据回调：仅把每帧 512B PCM 入队
-- 队列上限: 防止写任务跟不上时无限积压(内存与停止后排空时间都不可控)
local Air1103_RECORD_QUEUE_MAX = 512   -- 帧数上限
local function air1103_audio_data_cb(data)
    if not air1103_recording or not air1103_record_param then return end
    if not data or #data == 0 then return end
    if #air1103_record_queue >= Air1103_RECORD_QUEUE_MAX then
        table.remove(air1103_record_queue, 1)  -- 丢最旧帧, 保持队列有界
    end
    air1103_record_queue[#air1103_record_queue + 1] = data
end

-- air1103 录音写文件任务：从队列取帧攒批(4KB)后投递给上层 path
local function air1103_record_writer()
    local drain_budget = nil  -- 停止录音后的剩余排空批次数
    while true do
        if #air1103_record_queue == 0 then
            if not air1103_recording then
                -- 触发完成回调
                if air1103_record_param and type(air1103_record_param.cbfnc) == "function" then
                    air1103_record_param.cbfnc(exaudio.RECORD_DONE)
                end
                log.info("exaudio", "air1103录音已停止")
                break
            end
            sys.wait(5)
        else
            local path = air1103_record_param and air1103_record_param.path
            if type(path) == "function" then
                if not air1103_record_out then
                    air1103_record_out = zbuff.create(8192)
                end
                air1103_record_out:clear(0)
                -- 关键: zbuff clear() 只 memset 不重置 used(), 必须手动 used(0);
                -- 否则 used 从上一批累积, 批次越攒越大, 之后 used>=4096 不再消费新帧, 反复写同一段数据
                air1103_record_out:used(0)
                while #air1103_record_queue > 0 and air1103_record_out:used() < 4096 do
                    local frame = table.remove(air1103_record_queue, 1)
                    if frame and #frame > 0 then
                        air1103_record_out:copy(nil, frame)  -- 16kHz/16bit/单声道, 原样写入
                    end
                end
                if air1103_record_out:used() > 0 then
                    path(air1103_record_out, air1103_record_out:used())
                end
            elseif type(path) == "string" then
                local f = io.open(path, "ab")
                if f then
                    while #air1103_record_queue > 0 do
                        local frame = table.remove(air1103_record_queue, 1)
                        if frame and #frame > 0 then f:write(frame) end
                    end
                    f:close()
                else
                    air1103_record_queue = {}
                end
            else
                air1103_record_queue = {}
            end
            -- 停止录音后限批排空: 最多再落盘 N 批, 之后丢弃剩余队列, 保证必触发 RECORD_DONE
            if not air1103_recording then
                if not drain_budget then
                    drain_budget = 40  -- 最多再落盘 40 批(≈160KB), 避免停止后还倒很久
                elseif drain_budget <= 0 then
                    log.warn("exaudio", "air1103录音停止后排空超时, 丢弃剩余队列")
                    air1103_record_queue = {}
                else
                    drain_budget = drain_budget - 1
                end
            end
            sys.wait(2)
        end
    end
    air1103_record_wtask = nil
end

-- air1103 停止录音：停 MIC 上行
local function air1103_record_stop()
    if not air1103 or not air1103_recording then return false end
    air1103_recording = false
    if air1103_record_timer then
        sys.timerStop(air1103_record_timer)
        air1103_record_timer = nil
    end
    air1103.stop_audio()          -- 02 01 停止上行 MIC 音频
    air1103.set_rx_enable(false)  -- 从源头丢弃 Air1103 上行数据, 彻底切断 cb 入队
    -- RECORD_DONE 由 air1103_record_writer 在队列后触发;
    -- 若写任务未运行(异常), 此处兜底触发, 避免回调丢失
    if not air1103_record_wtask then
        if air1103_record_param and type(air1103_record_param.cbfnc) == "function" then
            air1103_record_param.cbfnc(exaudio.RECORD_DONE)
        end
        log.info("exaudio", "air1103录音已停止")
    end
    return true
end

-- 初始化
-- audioConfigs.audio_mode="new"/"old" 选择本地音频框架，与 exsip.init 的 audio_mode（VoIP 路由）不同。
-- CC<->SIP 桥接由 exsip.init({cc_sip_bridge=true, ...}) 选择；本接口仍按板型配置音频硬件，
-- 不负责开启桥接或建立 CC/SIP 呼叫。i2s_sample、bits_per_sample、channels 是硬件配置，
-- 不改变 SIP 的 SDP 编解码协商，也不改变 sip_voip_start() 使用的 8 kHz/16 bit/单声道 PCM 格式。
function exaudio.setup(audioConfigs)
    if not audioConfigs or type(audioConfigs) ~= "table" then
        log.error("配置参数必须为table类型")
        return false
    end

    -- audio_mode参数处理。显式选择必须以对应Lua库实际存在为前提；
    -- auto/nil沿用基于模组偏好和固件能力计算出的默认值。
    if audioConfigs.audio_mode == "new" then
        if not AUDIO_V2_AVAILABLE then
            log.error("audio_mode=new，但固件未启用audio_v2库")
            return false
        end
        USE_AUDIO_V2 = true
        log.info("exaudio.setup", "audio_mode=new，切换到新音频框架")
    elseif audioConfigs.audio_mode == "old" then
        if not AUDIO_LEGACY_AVAILABLE then
            log.error("audio_mode=old，但固件未启用audio库")
            return false
        end
        if PREFER_AUDIO_V2 and AUDIO_V2_AVAILABLE then
            -- 保持8101、160X等原有约束：新框架可用时不允许强制切到旧框架。
            log.warn("exaudio.setup", "当前模组仅支持新音频框架，audio_mode=old不生效")
        else
            USE_AUDIO_V2 = false
            log.info("exaudio.setup", "audio_mode=old，切换到旧音频框架")
        end
    end

    log.info("exaudio.setup", "当前使用" .. (USE_AUDIO_V2 and "新" or "旧") .. "音频框架")

    -- 检查必要参数（air1103 走 UART，跳过此检查）
    if audioConfigs.model ~= "air1103" then
        if USE_AUDIO_V2 then
            if not audio_v2 then
                log.error("不支持audio_v2 库,请选择支持audio_v2 的core")
                return false
            end
        else
            if not audio then
                log.error("不支持audio 库,请选择支持audio 的core")
                return false
            end
        end
    end

    -- 检查编解码器型号
    if audioConfigs.model then
        if audioConfigs.model ~= "es8311" and audioConfigs.model ~= "dac" and audioConfigs.model ~= "tm8211" and audioConfigs.model ~= "air1103" then
            log.error("请指定正确的model: es8311、tm8211、dac 或 air1103")
            return false
        end
        audio_setup_param.model = audioConfigs.model
    end
    
    -- 根据model进行参数检查
    if audio_setup_param.model == "dac" then
        -- DAC模式
        if audioConfigs.dac_ch ~= nil then
            audio_setup_param.dac_ch = audioConfigs.dac_ch
        end
        if audioConfigs.dac_chl ~= nil then
            audio_setup_param.dac_chl = audioConfigs.dac_chl
        end
        log.info("exaudio.setup", "DAC模式 - 通道:"..audio_setup_param.dac_ch..", 声道:"..audio_setup_param.channels)
    elseif audio_setup_param.model == "tm8211" then
        -- TM8211模式 (I2S，无需I2C)
        log.info("exaudio.setup", "TM8211模式 - 声道:"..audio_setup_param.channels)
        
        -- TM8211 默认使用 MODE_MSB 格式
        if audioConfigs.i2s_comm_format == nil then
            audio_setup_param.i2s_comm_format = i2s and i2s.MODE_MSB or 0
            log.info("exaudio.setup", "TM8211使用默认MODE_MSB格式")
        end
        
        -- 检查功率放大器控制管脚
        if audioConfigs.dac_ctrl == nil then
            log.warn("dac_ctrl(音频编解码控制管脚)是控制pop 音的重要管脚,建议硬件设计加上")
        end
        audio_setup_param.dac_ctrl = audioConfigs.dac_ctrl
    elseif audio_setup_param.model == "air1103" then
        audio_setup_param.uart_id = audioConfigs.uart_id or 1
        air1103 = require "air1103"
        air1103.init(audio_setup_param.uart_id, 2000000)
        log.info("exaudio.setup", "Air1103 芯片初始化完成")
    else
        -- ES8311 I2S模式
        if not audio_setup_param.model or (audio_setup_param.model ~= "es8311") then
            log.error("请指定正确的model(es8311)")
            return false
        end
        -- 针对ES8311的特殊检查
        if not check_param(audioConfigs.i2c_id, "number", "i2c_id") then
            return false
        end
        audio_setup_param.i2c_id = audioConfigs.i2c_id

        -- 检查功率放大器控制管脚
        if audioConfigs.dac_ctrl == nil then
            log.warn("dac_ctrl(音频编解码控制管脚)是控制pop 音的重要管脚,建议硬件设计加上")
        end
        audio_setup_param.dac_ctrl = audioConfigs.dac_ctrl
    end

    -- 检查功率放大器控制管脚
    if audioConfigs.pa_ctrl == nil then
        log.warn("pa_ctrl(功率放大器控制管脚)是控制pop 音的重要管脚,建议硬件设计加上")
    end
    audio_setup_param.pa_ctrl = audioConfigs.pa_ctrl

    -- 处理可选参数
    local optional_params = {
        {name = "dac_delay", type = "number"},
        {name = "pa_delay", type = "number"},
        {name = "dac_time_delay", type = "number"},
        {name = "bits_per_sample", type = "number"},
        {name = "pa_on_level", type = "number"},
        {name = "channels", type = "number"},
        {name = "i2s_sample", type = "number"},      -- I2S采样率
        {name = "i2s_framebit", type = "number"},     -- I2S通道位宽
        {name = "i2s_mode", type = "number"},         -- I2S模式
        {name = "i2s_comm_format", type = "number"},  -- I2S通信格式
        {name = "dac_ch", type = "number"},           -- DAC通道
        {name = "dac_chl", type = "number"},          -- DAC通道选择
        {name = "tx_bus_type", type = "number"},      -- 发送总线类型(默认驱动切换)
        {name = "tx_bus_id", type = "number"},        -- 发送总线ID
        {name = "rx_bus_type", type = "number"},      -- 接收总线类型(默认驱动切换)
        {name = "rx_bus_id", type = "number"},        -- 接收总线ID
        {name = "codec_voltage", type = "number"},    -- ES8311电平: 1=3.3V(默认), 0=1.8V(Air8201H等特殊板型)
    }

    -- 校验默认驱动切换参数：tx/rx总线类型必须成对出现
    if (audioConfigs.tx_bus_type ~= nil) ~= (audioConfigs.rx_bus_type ~= nil) then
        log.error("tx_bus_type 和 rx_bus_type 必须同时设置")
        return false
    end

    for _, param in ipairs(optional_params) do
        if audioConfigs[param.name] ~= nil then
            if check_param(audioConfigs[param.name], param.type, param.name) then
                -- 对channels参数进行验证，确保只能是1或2
                if param.name == "channels" then
                    if audioConfigs[param.name] == 1 or audioConfigs[param.name] == 2 then
                        audio_setup_param[param.name] = audioConfigs[param.name]
                    else
                        log.error("声道数必须为1(单声道)或2(双声道)")
                        return false
                    end
                else
                    audio_setup_param[param.name] = audioConfigs[param.name]
                end
            else
                return false
            end
        end
    end

    -- 确保采样位数和声道数有默认值
    audio_setup_param.bits_per_sample = audio_setup_param.bits_per_sample or 16
    audio_setup_param.channels = audio_setup_param.channels or 1

    -- 通话自动唤醒
    -- 自动订阅CC_IND事件，每次通话PLAY（开始有音频输出）时自动exaudio.pm(exaudio.RESUME)唤醒ES8311，
    -- 通话结束后的休眠由业务脚本控制（demo内exaudio.pm(exaudio.SHUTDOWN)）
    -- 此订阅仅管理本地硬件唤醒，不建立 CC<->SIP 语音路由，也不联动两侧呼叫状态。
    if type(cc) == "userdata" and not cc_auto_pm_enabled then
        cc_auto_pm_enabled = true
        sys.subscribe("CC_IND", function(status)
            if status == "PLAY" then
                -- 通话建立/开始有音频输出：确保ES8311处于工作状态
                exaudio.pm(exaudio.RESUME)
            end
        end)
        log.info("exaudio.setup", "cc auto resume enabled")
    end

    -- 根据模式选择初始化方式
    if USE_AUDIO_V2 then
        return audio_v2_setup()
    else
        return audio_setup()
    end
end

-- 开始播放
function exaudio.play_start(playConfigs)
    -- Air1103 模式: 仅支持 PCM 流式播放(type=2)
    if audio_setup_param.model == "air1103" then
        if not air1103 then
            log.error("air1103未初始化，请先调用exaudio.setup")
            return false
        end
        if not playConfigs or type(playConfigs) ~= "table" then
            log.error("播放配置必须为table类型")
            return false
        end
        if not check_param(playConfigs.type, "number", "type") then
            log.error("type必须为数值(0:文件,1:TTS,2:流式)")
            return false
        end
        if playConfigs.type ~= 2 then
            log.error("air1103仅支持播放pcm流式音频，请更换播放的音频文件")
            return false
        end
        audio_play_param = playConfigs
        air1103.play_stream_start(air1103_vol)
        air1103_playing = true
        air1103_end_marked = false
        log.info("exaudio", "air1103流式播放已启动，等待play_stream_write喂数据")
        return true
    end
    if USE_AUDIO_V2 then
        -- audio_v2模式播放
        if not playConfigs or type(playConfigs) ~= "table" then
            log.error("播放配置必须为table类型")
            return false
        end

        -- audio_v2 setup 后恢复 ES8311 与 PA，保证 TTS 有模拟输出。
        if not exaudio.pm(exaudio.RESUME) then
            log.error("audio_v2恢复播放设备失败")
            return false
        end

        -- 检查播放类型
        if not check_param(playConfigs.type, "number", "type") then
            log.error("type必须为数值(0:文件,1:TTS,2:流式)")
            return false
        end

        -- 设置默认优先级
        playConfigs.priority = playConfigs.priority or 0
        
        -- 恢复RESUME工作模式
        exaudio.pm(exaudio.RESUME)

        -- audio_v2播放
        local play_type = playConfigs.type
        local ok, req_id = false, nil
        
        if play_type == 0 then  -- 文件播放
            if not playConfigs.content then
                log.error("文件播放需要指定content(文件路径或路径表)")
                return false
            end

            -- 文件头损坏预检：对 mp3/amr/wav 等带格式头的文件，播放前先解析文件头，
            local check_content = playConfigs.content
            if type(check_content) == "string" then
                -- 扩展名 -> codec_id 映射
                local ext = check_content:match("%.([^%.]+)$")
                local ext_codec = nil
                if ext then
                    ext = ext:lower()
                    if ext == "mp3" then
                        ext_codec = 5
                    elseif ext == "wav" then
                        ext_codec = 1
                    elseif ext == "amr" then
                        ext_codec = 2
                    end
                end
                local info_codec = playConfigs.codec_id or ext_codec
                if info_codec then
                    -- 先确认文件存在且可读
                    local fp_check = io.open(check_content, "rb")
                    if not fp_check then
                        log.error("播放文件不存在或无法打开，请更换文件播放:", check_content)
                        return false
                    end
                    fp_check:close()
                    local info = exaudio.parse_audio_info(check_content, info_codec)
                    if not info or not info.sample_rate or info.sample_rate == 0 then
                        log.error("播放文件损坏，请更换文件播放:", check_content)
                        return false
                    end
                end
            end

            -- 使用audio_v2.play播放文件
            ok, req_id = audio_v2.play(
                playConfigs.content, 
                playConfigs.err_stop ~= false,  -- 默认true
                playConfigs.priority,
                playConfigs.driver_probe_id,
                playConfigs.codec_id
            )
            if ok then
                audio_v2_request_index = req_id
                audio_play_param.cbfnc = playConfigs.cbfnc
            end
            return ok
            
        elseif play_type == 1 then  -- TTS播放
            if not check_param(playConfigs.content, "string", "content") then
                log.error("TTS播放content必须为字符串")
                return false
            end
            
            ok, req_id = audio_v2.tts(
                playConfigs.content, 
                playConfigs.priority,
                playConfigs.driver_probe_id
            )
            if ok then
                audio_v2_request_index = req_id
                audio_play_param.cbfnc = playConfigs.cbfnc
            end
            return ok
            
        elseif play_type == 2 then  -- 流式播放
            -- audio_v2流式播放
            -- 未指定codec_id时默认0(RAW/PCM)
            if not playConfigs.codec_id then
                --流式播放未指定codec_id时默认RAW/PCM
                playConfigs.codec_id = 0
            end
            
            -- 兼容旧版参数名
            local sample_rate = playConfigs.sample_rate or playConfigs.sampling_rate
            local data_bits = playConfigs.data_bits or playConfigs.sampling_depth or 16
            local is_signed
            if playConfigs.is_signed ~= nil then
                is_signed = playConfigs.is_signed  -- 保持boolean不变，直接传给stream
            elseif playConfigs.signed_or_unsigned ~= nil then
                is_signed = playConfigs.signed_or_unsigned
            else
                is_signed = true  -- 默认有符号
            end
            local channel_nums = playConfigs.channel_nums or playConfigs.channels or 1
            local priority = playConfigs.priority or 0
            local driver_probe_id = playConfigs.driver_probe_id or AUDIO_V2_DRIVER_ID
            
            -- 对于MP3/AMR/WAV格式，从文件解析真实采样率
            local file_path = playConfigs.file_path
            if file_path and (playConfigs.codec_id == 5 or playConfigs.codec_id == 2 or playConfigs.codec_id == 3 or playConfigs.codec_id == 1) then
                local fp = io.open(file_path, "rb")
                if fp then
                    local file_data = fp:read(12)
                    if file_data and #file_data > 0 then
                        local no_error, next_pos, need_len, parsed_sample_rate, parsed_data_bits, parsed_channel_nums, parsed_is_signed = 
                            audio_v2.get_play_info(file_data, playConfigs.codec_id, 0)
                        if no_error then
                            if parsed_sample_rate and parsed_sample_rate > 0 then
                                sample_rate = parsed_sample_rate
                                data_bits = parsed_data_bits or data_bits
                                channel_nums = parsed_channel_nums or channel_nums
                                if parsed_is_signed ~= nil then
                                    is_signed = parsed_is_signed  -- 保持boolean
                                end
                                log.info("exaudio", "从文件解析到采样率:", sample_rate, "bits:", data_bits, 
                                         "ch:", channel_nums, "signed:", is_signed)
                            else
                                -- sample_rate为0，重试
                                local retry_count = 0
                                while retry_count < 6 and no_error and (not parsed_sample_rate or parsed_sample_rate == 0) do
                                    log.info("exaudio", "seek", next_pos, "need", need_len)
                                    fp:seek("set", next_pos)
                                    file_data = fp:read(need_len)
                                    if file_data then
                                        no_error, next_pos, need_len, parsed_sample_rate, parsed_data_bits, parsed_channel_nums, parsed_is_signed = 
                                            audio_v2.get_play_info(file_data, playConfigs.codec_id, next_pos)
                                        retry_count = retry_count + 1
                                    else
                                        break
                                    end
                                end
                                if no_error and parsed_sample_rate and parsed_sample_rate > 0 then
                                    sample_rate = parsed_sample_rate
                                    data_bits = parsed_data_bits or data_bits
                                    channel_nums = parsed_channel_nums or channel_nums
                                    if parsed_is_signed ~= nil then
                                        is_signed = parsed_is_signed  -- 保持boolean
                                    end
                                    log.info("exaudio", "从文件解析到采样率:", sample_rate, "bits:", data_bits, 
                                             "ch:", channel_nums, "signed:", is_signed, "retries:", retry_count)
                                else
                                    log.warn("exaudio", "无法从文件解析采样率，使用默认值", "retries:", retry_count)
                                end
                            end
                        else
                            log.warn("exaudio", "get_play_info解析失败，使用默认值")
                        end
                    end
                    fp:close()
                end
            end
            
            -- 默认采样率
            if not sample_rate or sample_rate <= 0 then
                if playConfigs.codec_id == 0 then
                    sample_rate = 16000
                elseif playConfigs.codec_id == 1 then
                    sample_rate = 44100
                elseif playConfigs.codec_id == 2 then
                    sample_rate = 8000
                elseif playConfigs.codec_id == 3 then
                    sample_rate = 16000
                elseif playConfigs.codec_id == 5 then
                    sample_rate = 44100
                else
                    sample_rate = 16000
                end
                log.info("exaudio", "codec_id", playConfigs.codec_id, "使用默认采样率:", sample_rate)
            end
            
            log.info("exaudio", "调用stream: cid=", playConfigs.codec_id, "sr=", sample_rate, 
                     "bits=", data_bits, "ch=", channel_nums, "sig=", is_signed, "pri=", priority)
            ok, req_id = audio_v2.stream(
                playConfigs.codec_id,
                sample_rate,
                data_bits,
                channel_nums,
                is_signed,
                priority
            )
            log.info("exaudio", "stream返回: ok=", ok, "req_id=", req_id)
            
            if ok then
                audio_v2_request_index = req_id
                audio_v2_stream_codec_id = playConfigs.codec_id
                audio_play_param.cbfnc = playConfigs.cbfnc
                
                -- 如果有file_path，打开文件用于回调中循环读取
                if file_path then
                    local fp = io.open(file_path, "rb")
                    if fp then
                        -- 跳转到数据起始位置
                        local data_start = playConfigs.data_start or 0
                        if data_start > 0 then
                            fp:seek("set", data_start)
                        end
                        audio_v2_stream_file_fp = fp
                        audio_v2_stream_data_start = data_start
                        log.info("exaudio", "流式播放文件已打开:", file_path, "data_start:", data_start)
                    else
                        log.warn("exaudio", "无法打开流式播放文件:", file_path)
                    end
                end
                
                log.info("exaudio", "流式播放启动成功, request_index:", req_id, 
                         "采样率:", sample_rate, "codec_id:", playConfigs.codec_id)
            else
                log.error("exaudio", "流式播放启动失败")
            end
            return ok
        end
        
        return false
    else
        -- audio模式播放
        -- 恢复RESUME工作模式
        audio.pm(MULTIMEDIA_ID, exaudio.RESUME)
        if not playConfigs or type(playConfigs) ~= "table" then
            log.error("播放配置必须为table类型")
            return false
        end

        -- 检查播放类型
        if not check_param(playConfigs.type, "number", "type") then
            log.error("type必须为数值(0:文件,1:TTS,2:流式)")
            return false
        end

        -- 设置默认优先级
        playConfigs.priority = playConfigs.priority or 0
        
        -- 创建播放请求
        local request = {
            priority = playConfigs.priority,
            configs = playConfigs
        }
        
        -- 检查是否正在播放
        if not audio.isEnd(MULTIMEDIA_ID) then
            -- 如果新请求的优先级更高，则打断当前播放
            if playConfigs.priority > audio_play_queue.current_priority then
                -- 停止当前播放
                if audio.play(MULTIMEDIA_ID) ~= true then
                    return false
                end
                sys.waitUntil(EX_MSG_PLAY_DONE)
                
                -- 将新请求加入队列并立即播放
                audio_play_queue_push_request(request)
                return start_next_play()
            else
                -- 优先级不够高，将请求加入队列等待
                audio_play_queue_push_request(request)
                return true
            end
        else
            -- 没有正在播放，将请求加入队列并立即播放
            audio_play_queue_push_request(request)
            return start_next_play()
        end
    end
end

function exaudio.is_audio_v2()
    return USE_AUDIO_V2
end

--[[
启动普通 SIP 通话的本地 Audio V2 PCM 适配，由 exsip 在选用该路由且 voip.start() 成功后调用。
@api exaudio.sip_voip_start()
@return boolean 成功返回 true，当前音频框架不支持或请求创建失败返回 false；Air1103 模式直接返回 true
@usage
-- 通常由 exsip 管理，无需业务层手动调用：
-- 本地 MIC -> Audio V2 speech -> voip.pcmIn() -> SIP RTP 上行；
-- SIP RTP 下行 -> voip.pcmOut() -> Audio V2 extern_source -> 本地扬声器。
-- PCM 固定为 8 kHz、16 bit、单声道；下行每 20 ms 取 160 个采样点（320 字节）。
-- CC<->SIP 桥接由固件转送 CC 下行和 SIP 下行，exsip 在 cc_sip_bridge=true 时跳过本接口。
-- Air1103 模式不创建 Audio V2 请求；返回 true 仅表示跳过，UART 与 VoIP 的 PCM 搬运由业务层完成。
-- 成功创建的本地适配需与 sip_voip_stop() 配对释放；本接口不调用 voip.start() 或管理 CC 呼叫。
]]
function exaudio.sip_voip_start()
    -- Air1103(UART外置语音芯片)不需要audio_v2桥接: SIP通话音频由业务层通过 voip.pcmIn/pcmOut 与 UART 自行桥接。
    -- 这里必须返回 true, 否则 exsip 会认为桥接失败并执行 voip.stop(), 导致通话没有音频。
    if audio_setup_param.model == "air1103" then
        log.info("exaudio", "air1103模式: 跳过audio_v2 SIP桥接, 由上层用voip.pcmIn/pcmOut与UART桥接")
        return true
    end
    if not USE_AUDIO_V2 or not audio_v2 or not voip or not sys then return false end
    if type(voip.pcmOut) ~= "function" or type(voip.pcmIn) ~= "function" then
        log.warn("exaudio", "voip bridge not supported in this firmware")
        return false
    end
    local codec = audio_v2.DATA_CODEC_TYPE_VOIP_PCM
    sip_v2_record_zbuff = zbuff.create(4096)
    local ok, request_id = audio_v2.speech(codec, sip_v2_record_zbuff, 1,
        codec, 8000, 16, 1)
    if not ok then sip_v2_record_zbuff = nil return false end
    local source_ok, source_id = audio_v2.extern_source(request_id, true, false,
        codec, true, 8000, 16, 1, true)
    if not source_ok then audio_v2.stop(request_id) sip_v2_record_zbuff = nil return false end
    sip_v2_request_index, sip_v2_source_index = request_id, source_id
    sip_v2_timer = sys.timerLoopStart(function()
        if not sip_v2_source_index or not voip.isRunning() then return end
        if type(voip.pcmOut) ~= "function" then return end
        -- 普通 SIP 下行送到本地扬声器；暂时无 PCM 时补一帧静音，保持 20 ms 播放节奏。
        local pcm = voip.pcmOut(160) or string.rep("\0", 320)
        audio_v2.input(sip_v2_source_index, pcm, false)
    end, 20)
    log.info("exaudio", "SIP audio_v2 bridge started", request_id)
    return true
end

--[[
释放普通 SIP 本地音频适配的定时器、Audio V2 请求和录音缓冲，由 exsip 在停止媒体时调用。
@api exaudio.sip_voip_stop()
@return nil 无返回值
@usage
-- 仅清理 sip_voip_start() 创建的资源；VoIP 引擎停止由 exsip/voip.stop() 负责。
-- CC<->SIP 固件桥接资源随 CC 媒体生命周期管理；此接口不挂断 CC，也不关闭 CC 桥接配置。
-- Air1103 模式直接返回，业务层自行停止 UART PCM 搬运。
]]
function exaudio.sip_voip_stop()
    -- air1103模式没有建立audio_v2桥接(见sip_voip_start), 无需停止
    if audio_setup_param.model == "air1103" then return end
    if sip_v2_timer then sys.timerStop(sip_v2_timer) sip_v2_timer = nil end
    if sip_v2_request_index then audio_v2.stop(sip_v2_request_index) end
    sip_v2_request_index, sip_v2_source_index, sip_v2_record_zbuff = nil, nil, nil
end

--[[
Air1103 播放来电振铃提示音，可在sip来电接通前调用。
@api exaudio.play_ringback([callback])
@function callback 可选，播放完成回调；Air1103 模式下整段提示音播完时触发
@return boolean 成功返回 true，模型未内置提示音或 Air1103 未初始化返回 false
@usage
-- 来电接通前先响铃，播放完成后接听：
local function on_ringback_done()
    log.info("sip", "振铃结束，开始接听")
    -- 接听当前等待中的来电
    exsip.accept()
end

exaudio.play_ringback(on_ringback_done)

-- 调用后 Air1103 播放来电提示音（两段嘟嘟声）；
-- 播完由 Air1103 自行复位并恢复上行；
-- 注意：提示音占用 Air1103 下行，通话桥接期间不要调用。
]]
function exaudio.play_ringback(callback)
    if audio_setup_param.model == "air1103" then
        if not air1103 or type(air1103.play_busy) ~= "function" then
            log.warn("exaudio", "play_ringback: air1103 未初始化")
            return false
        end
        return air1103.play_busy(callback)
    end
    log.warn("exaudio", "play_ringback: 当前模型未内置提示音", audio_setup_param.model)
    return false
end

--[[
Air1103 播放挂断提示音，需在对端sip通话挂断后调用。
@api exaudio.play_hangup([callback])
@function callback 可选，播放完成回调；整段提示音播完时触发
@return boolean 成功返回 true，模型未内置提示音或 Air1103 未初始化返回 false
@usage
-- 对端挂断后播提示音
local function on_hangup_done()
    log.info("sip", "提示音播放结束")
end

exaudio.play_hangup(on_hangup_done)

-- 调用后 Air1103 播放挂断提示音（三段短嘟声）；
-- 注意：需在对端sip通话挂断后调用；
-- 播完由 Air1103 自行复位并恢复上行；提示音占用 Air1103 下行，通话桥接期间不要调用。
]]
function exaudio.play_hangup(callback)
    if audio_setup_param.model == "air1103" then
        if not air1103 or type(air1103.play_hangup) ~= "function" then
            log.warn("exaudio", "play_hangup: air1103 未初始化")
            return false
        end
        return air1103.play_hangup(callback)
    end
    log.warn("exaudio", "play_hangup: 当前模型未内置提示音", audio_setup_param.model)
    return false
end

-- 流式播放数据写入
-- @param data 音频数据(string/zbuff)
-- @param is_end 是否为最后一帧数据，true表示播放结束(仅audio_v2模式支持)
-- @return ok 是否成功
-- @return written 实际写入的字节数(audio_v2)
-- @return free_len FIFO剩余空间(audio_v2)
function exaudio.play_stream_write(data, is_end)
    if audio_setup_param.model == "air1103" then
        if not air1103 then return false end
        if not data or #data == 0 then return false end
        air1103.play_stream_write(data)
        if is_end then
            air1103_mark_end()
        end
        return true
    end
    if USE_AUDIO_V2 then
        -- audio_v2模式：入队列，由NEED_NEW_DATA回调批量写入FIFO
        if not audio_v2_request_index then
            log.error("audio_v2流式播放未启动")
            return false
        end
        
        -- 如果有文件句柄，由回调自动处理，忽略用户的手动写入
        if audio_v2_stream_file_fp then
            log.info("exaudio", "文件流模式，忽略手动写入")
            return true
        end
        
        -- 数据入队列，由audio_v2回调（NEED_NEW_DATA）统一写入FIFO。
        -- 注意：不在HTTP/网络回调里直接调用audio_v2.input()，避免总线错误/解码异常。
        audio_stream_queue_push(data)
        if is_end then
            -- is_end=true标记在队列数据被回调消耗完后生效
            audio_v2_stream_end_marked = true
        end
        
        return true
    end
    
    -- audio模式：插入队列，由audio.MORE_DATA回调处理
    audio_stream_queue_push(data)
    return true
end

-- 停止播放
function exaudio.play_stop(stopConfigs)
    if audio_setup_param.model == "air1103" then
        if not air1103 then return false end
        if air1103_playing then
            air1103_audio_done()
        end
        return true
    end
    if USE_AUDIO_V2 then
        -- audio_v2停止播放
        if audio_v2_request_index then
            -- 关闭文件句柄
            if audio_v2_stream_file_fp then
                audio_v2_stream_file_fp:close()
                audio_v2_stream_file_fp = nil
            end
            
            audio_v2.stop(audio_v2_request_index)
            audio_v2_request_index = nil
            audio_v2_stream_codec_id = nil
            audio_v2_stream_data_start = nil
            audio_play_queue.current_priority = 0
            exaudio.pm(exaudio.SHUTDOWN)
            return true
        end
        return false
    end

    -- 强制要求传入配置表参数
    if not stopConfigs or type(stopConfigs) ~= "table" then
        log.error("停止播放必须传入配置表参数，格式: {type = 0|1|2}")
        log.error("type参数说明: 0=文件播放, 1=TTS播放, 2=流式播放")
        return false
    end

    -- 检查播放类型参数
    if not check_param(stopConfigs.type, "number", "type") then
        log.error("停止播放需要指定type参数(0:文件,1:TTS,2:流式)")
        return false
    end
    
    -- 检查播放类型参数
    if not check_param(stopConfigs.type, "number", "type") then
        log.error("停止播放需要指定type参数(0:文件,1:TTS,2:流式)")
        return false
    end
    
    local stop_type = stopConfigs.type
    
    -- 根据播放类型使用不同的停止方法
    if stop_type == 2 then  -- 流式播放
        -- 流式播放使用audio.stop()停止
        local result = audio.stop(MULTIMEDIA_ID)
        if result then
            -- 清空流式数据队列
            audio_stream_queue.data = {}
            audio_stream_queue.sequenceIndex = 1
            audio_play_queue.current_priority = 0
            audio.pm(MULTIMEDIA_ID, exaudio.SHUTDOWN)
        end
        return result
    else  -- 文件播放或TTS播放
        -- 文件播放和TTS播放使用audio.play()停止
        local result = audio.play(MULTIMEDIA_ID)
        if result then
            -- 只有当停止的是当前播放类型时才清空状态
            audio_play_queue.current_priority = 0
            audio.pm(MULTIMEDIA_ID, exaudio.SHUTDOWN)
        end
        return result
    end
end

-- 检查播放是否结束
function exaudio.is_end()
    if audio_setup_param.model == "air1103" then
        return not air1103_playing
    end
    if USE_AUDIO_V2 then
        -- audio_v2使用is_all_done判断是否所有请求结束
        return audio_v2.is_all_done()
    end
    return audio.isEnd(MULTIMEDIA_ID)
end

-- 获取错误信息
function exaudio.get_error()
    if USE_AUDIO_V2 then
        -- audio_v2暂无错误获取接口
        return nil
    end
    return audio.getError(MULTIMEDIA_ID)
end

-- audio_v2录音格式转码表
local audio_v2_record_codec_map = {
    [exaudio.AMR_NB]   = { codec_id = audio_v2 and audio_v2.DATA_CODEC_TYPE_AMR_NB or 2, sr = 8000,  bits = 16 },
    [exaudio.AMR_WB]   = { codec_id = audio_v2 and audio_v2.DATA_CODEC_TYPE_AMR_WB or 3, sr = 16000, bits = 16 },
    [exaudio.PCM_8000]  = { codec_id = audio_v2 and audio_v2.DATA_CODEC_TYPE_RAW or 0,    sr = 8000,  bits = 16 },
    [exaudio.PCM_16000] = { codec_id = audio_v2 and audio_v2.DATA_CODEC_TYPE_RAW or 0,    sr = 16000, bits = 16 },
    [exaudio.PCM_24000] = { codec_id = audio_v2 and audio_v2.DATA_CODEC_TYPE_RAW or 0,    sr = 24000, bits = 16 },
    [exaudio.PCM_32000] = { codec_id = audio_v2 and audio_v2.DATA_CODEC_TYPE_RAW or 0,    sr = 32000, bits = 16 },
    [exaudio.PCM_48000] = { codec_id = audio_v2 and audio_v2.DATA_CODEC_TYPE_RAW or 0,    sr = 48000, bits = 16 },
}

-- 开始录音
function exaudio.record_start(recodConfigs)
    if not recodConfigs or type(recodConfigs) ~= "table" then
        log.error("录音配置必须为table类型")
        return false
    end
    -- 检查录音格式
    if recodConfigs.format == nil or type(recodConfigs.format) ~= "number" or recodConfigs.format > 6 then
        log.error("请指定正确的录音格式")
        return false
    end
    audio_record_param.format = recodConfigs.format

    -- 处理录音时间
    if recodConfigs.time ~= nil then
        if recodConfigs.time == 0 then
            audio_record_param.time = 0
            log.warn("exaudio.record_start", "录音时间设置为0，将无限录音")
            log.warn("exaudio.record_start", "提示：请调用exaudio.record_stop()手动停止录音")
        elseif recodConfigs.time < 0 then
            log.error("录音时间不能为负数")
            return false
        else
            audio_record_param.time = recodConfigs.time
            log.info("exaudio.record_start", string.format("将录音%d秒", audio_record_param.time))
        end
    else
        audio_record_param.time = 0
        log.warn("exaudio.record_start", "未指定录音时间，将无限录音")
        log.warn("exaudio.record_start", "提示：请调用exaudio.record_stop()手动停止录音")
    end

    -- 处理存储路径/回调
    if not recodConfigs.path then
        log.error("必须指定录音路径或流式回调函数")
        return false
    end
    audio_record_param.path = recodConfigs.path

    -- 处理回调函数
    if recodConfigs.cbfnc ~= nil then
        if type(recodConfigs.cbfnc) ~= "function" then
            log.error("cbfnc必须为函数类型")
            return false
        end
        audio_record_param.cbfnc = recodConfigs.cbfnc
    else
        audio_record_param.cbfnc = nil
    end

    -- air1103: 通过 UART MIC 上行录音(16kHz/16bit/单声道, 512B/帧)
    if audio_setup_param.model == "air1103" then
        if not air1103 then
            log.error("air1103未初始化，请先调用exaudio.setup")
            return false
        end
        if audio_record_param.format ~= exaudio.PCM_16000 then
            log.warn("air1103仅支持16kHz/16bit/单声道PCM录音，已按16k处理")
        end
        if type(audio_record_param.path) ~= "function" and type(audio_record_param.path) ~= "string" then
            log.error("air1103录音必须指定流式回调或文件路径")
            return false
        end
        air1103_record_param = audio_record_param
        air1103_recording = true
        air1103_record_queue = {}
        air1103.set_rx_enable(true)  -- 恢复解析 Air1103 上行数据(上一次停止时已关闭)
        air1103.on_audio_data(air1103_audio_data_cb)
        if not air1103_record_wtask then
            air1103_record_wtask = sys.taskInit(air1103_record_writer)
        end
        if air1103_record_timer then sys.timerStop(air1103_record_timer); air1103_record_timer = nil end
        if audio_record_param.time and audio_record_param.time > 0 then
            air1103_record_timer = sys.timerStart(function()
                air1103_record_timer = nil
                air1103_record_stop()
            end, audio_record_param.time * 1000)
        end
        -- 复位 Air1103 以(重新)启动 MIC 上行(复位后自动恢复上行音频)
        air1103.reset()
        log.info("exaudio", "air1103录音已开始(MIC上行)")
        return true
    end

    if USE_AUDIO_V2 then
        local fmt = audio_v2_record_codec_map[audio_record_param.format]
        if not fmt then
            log.error("不支持的录音格式")
            return false
        end
        
        local path_type = type(audio_record_param.path)
        local ok, req_id
        
        if path_type == "string" then
            ok, req_id = audio_v2.record(
                audio_record_param.path,  -- 文件路径
                audio_record_param.time,  -- 录制时长（秒）
                fmt.codec_id,             -- 编解码器ID
                0,                        -- priority
                fmt.sr,                   -- 采样率
                fmt.bits,                 -- 位深
                audio_setup_param.channels or 1  -- 声道数
            )
        elseif path_type == "function" then
            -- 创建录音zbuff
            audio_v2_record_zbuff = zbuff.create(48000)
            ok, req_id = audio_v2.record(
                audio_v2_record_zbuff,    -- zbuff缓冲区
                audio_record_param.time,  -- 录制时长（秒）
                fmt.codec_id,             -- 编解码器ID
                0,                        -- priority
                fmt.sr,                   -- 采样率
                fmt.bits,                 -- 位深
                audio_setup_param.channels or 1  -- 声道数
            )
        else
            log.error("录音路径必须为字符串或函数")
            return false
        end
        
        if ok then
            audio_v2_record_request_index = req_id
            log.info("exaudio", "录音已开始, req_id:", req_id)
        else
            audio_v2_record_zbuff = nil
            log.error("exaudio", "录音启动失败")
        end
        return ok
    end
    
    -- ========== audio模式录音 ==========
    -- 恢复RESUME工作模式
    audio.pm(MULTIMEDIA_ID, exaudio.RESUME)

    -- 转换录音格式
    local recod_format, amr_quailty
    if audio_record_param.format == exaudio.AMR_NB then
        recod_format = audio.AMR_NB
        amr_quailty = 7
    elseif audio_record_param.format == exaudio.AMR_WB then
        recod_format = audio.AMR_WB
        amr_quailty = 8
    elseif audio_record_param.format == exaudio.PCM_8000 then
        recod_format = 8000
    elseif audio_record_param.format == exaudio.PCM_16000 then
        recod_format = 16000
    elseif audio_record_param.format == exaudio.PCM_24000 then
        recod_format = 24000
    elseif audio_record_param.format == exaudio.PCM_32000 then
        recod_format = 32000
    elseif audio_record_param.format == exaudio.PCM_48000 then
        recod_format = 48000
    end

    local path_type = type(audio_record_param.path)
    if path_type == "string" then
        return audio.record(
            MULTIMEDIA_ID, 
            recod_format, 
            audio_record_param.time, 
            amr_quailty, 
            audio_record_param.path
        )
    elseif path_type == "function" then
        -- 初始化缓冲区
        if not pcm_buff0 or not pcm_buff1 then
            pcm_buff0 = zbuff.create(48000)
            pcm_buff1 = zbuff.create(48000)
        end
        return audio.record(
            MULTIMEDIA_ID, 
            recod_format, 
            audio_record_param.time, 
            amr_quailty, 
            nil, 
            3,
            pcm_buff0,
            pcm_buff1
        )
    end
    log.error("录音路径必须为字符串或函数")
    return false
end

-- 停止录音
function exaudio.record_stop()
    if audio_setup_param.model == "air1103" then
        return air1103_record_stop()
    end
    if USE_AUDIO_V2 then
        if audio_v2_record_request_index then
            -- 停止录音前，如果有回调模式，处理zbuff中剩余数据
            if type(audio_record_param.path) == "function" and audio_v2_record_zbuff then
                local left = audio_v2_record_zbuff:used()
                if left > 0 then
                    audio_record_param.path(audio_v2_record_zbuff, left)
                    audio_v2_record_zbuff:del()
                end
                -- zbuff模式必须调stop让C层停止
                audio_v2.stop(audio_v2_record_request_index)
                audio_v2_record_request_index = nil
                audio_v2_record_zbuff = nil
                -- audio_v2.stop()强制停止后，C层不会再触发REQUEST_END事件，
                -- 且上面的request_index已清空，即使C层补发REQUEST_END也无法匹配到录音分支。
                -- 因此这里必须手动触发录音完成回调，否则上层（如录音完成后自动播放）永远不会执行。
                if type(audio_record_param.cbfnc) == "function" then
                    audio_record_param.cbfnc(exaudio.RECORD_DONE)
                end
                return true
            end
            -- 文件录音：不调stop，让C层自然结束（timeout到期后自动回收REQUEST_END）。
            -- 不清空audio_v2_record_request_index，等待REQUEST_END回调来清空。
            -- 调stop会导致文件未保存/REQUEST_END不触发，只轮询is_all_done从不主动stop录音。
            return true
        end
        return false
    end
    
    local result = audio.recordStop(MULTIMEDIA_ID)
    -- 处理剩余的录音数据
    if type(audio_record_param.path) == "function" then
        -- 检查两个PCM缓冲区
        local buffers = {pcm_buff0, pcm_buff1}
        for i, buff in ipairs(buffers) do
            if buff and buff:used() > 0 then
                log.info("exaudio.record_stop", string.format("处理缓冲区%d的剩余数据: %d字节", i, buff:used()))
                audio_record_param.path(buff, buff:used())
            end
        end
    end
    return result
end

-- 设置音量
-- @param play_volume 音量值
-- @param driver_probe_id 驱动ID(可选,audio_v2模式支持)
-- @return 是否成功
function exaudio.vol(play_volume, driver_probe_id)
    if audio_setup_param.model == "air1103" then
        if not air1103 then return false end
        if check_param(play_volume, "number", "音量值") then
            local v = math.floor(play_volume * 31 / 100)
            if v > 31 then v = 31 elseif v < 0 then v = 0 end
            air1103.set_volume(v)
            air1103_vol = v
            return true
        end
        return false
    end
    if USE_AUDIO_V2 then
        -- 仅ES8311模式下才加载es8311驱动（DAC/TM8211模式无ES8311芯片，i2c不存在）
        if not audio_v2_es8311_drv and audio_setup_param.model == "es8311" then
            local ok
            ok, audio_v2_es8311_drv = pcall(require, "es8311")
        end
        if audio_v2_es8311_drv then
            -- audio_v2音量设置使用soft_volume
            if check_param(play_volume, "number", "音量值") then
                audio_v2_es8311_drv.set_voice_vol(audio_setup_param.i2c_id or 0, play_volume)
                audio_v2.soft_volume(play_volume, driver_probe_id)
                voice_vol = play_volume  -- 同步更新，exaudio.pm(RESUME)恢复ES8311时使用最新音量
                return true
            end
        else
            -- DAC/TM8211模式：无硬件音量寄存器，仅设置soft_volume
            if check_param(play_volume, "number", "音量值") then
                audio_v2.soft_volume(play_volume, driver_probe_id)
                voice_vol = play_volume
                return true
            end
        end
        return false
    end
    
    if check_param(play_volume, "number", "音量值") then
        return audio.vol(MULTIMEDIA_ID, play_volume)
    end
    return false
end

-- 应用DAC(内置ADC)麦克风增益
-- 两个参数均由客户按 0-100 传入，由本函数线性映射到硬件范围：
--   数字增益 dac_mic_dig_gain(0-100) -> 0-0x3f，默认 60
--   模拟增益 dac_mic_ana_gain(0-100) -> 0-0x0f，默认 50
-- 仅 model=="dac" 生效，固件未提供该接口(CFG_PARAM_ADC_DIG_GAIN为nil)时自动跳过
local function apply_dac_mic_gain()
    if audio_setup_param.model ~= "dac" or not audio_v2 then return end
    if not audio_v2.CFG_PARAM_ADC_DIG_GAIN then return end
    local dig = math.floor((dac_mic_dig_gain or 0) * 0x3f / 100)
    if dig > 0x3f then dig = 0x3f elseif dig < 0 then dig = 0 end
    local ok, err = pcall(audio_v2.config, audio_v2.CFG_PARAM_ADC_DIG_GAIN, dig)
    if not ok then log.warn("exaudio", "设置DAC数字增益失败:", err) end
    if dac_mic_ana_gain and dac_mic_ana_gain > 0 then
        local ana = math.floor(dac_mic_ana_gain * 0x0f / 100)
        if ana > 0x0f then ana = 0x0f elseif ana < 0 then ana = 0 end
        ok = pcall(audio_v2.config, audio_v2.CFG_PARAM_ADC_ANA_GAIN, ana)
        if not ok then log.warn("exaudio", "设置DAC模拟增益失败") end
    end
end

-- 设置麦克风音量
-- @param record_volume 麦克风音量值(0-100)，DAC模式下作为数字增益映射为 0-0x3f（默认 60）
-- @param dac_ana_gain 可选，DAC模式专用模拟增益(0-100)，线性映射为 0-0x0f，不传则为默认 50
-- @return 是否成功
function exaudio.mic_vol(record_volume, dac_ana_gain)
    if audio_setup_param.model == "air1103" then
        log.info("exaudio", "air1103不支持调节麦克风音量")
        return false
    end
    if USE_AUDIO_V2 then
        -- 仅ES8311模式下才加载es8311驱动（DAC/TM8211模式无ES8311芯片，i2c不存在）
        if not audio_v2_es8311_drv and audio_setup_param.model == "es8311" then
            local ok
            ok, audio_v2_es8311_drv = pcall(require, "es8311")
        end
        if audio_v2_es8311_drv then
            audio_v2_es8311_drv.set_mic_vol(audio_setup_param.i2c_id or 0, record_volume)
            mic_vol = record_volume
            return true
        end
        if audio_setup_param.model == "dac" and MODULE_TYPE == "air8101" then
            -- DAC模式：通过驱动配置设置麦克风数字/模拟增益
            if not check_param(record_volume, "number", "麦克风音量值") then
                return false
            end
            dac_mic_dig_gain = record_volume
            if dac_ana_gain ~= nil then
                dac_mic_ana_gain = dac_ana_gain
            end
            apply_dac_mic_gain()
            return true
        end
        -- TM8211模式：板载无MIC硬件，不支持调节麦克风音量
        log.info("exaudio", "tm8211不支持调节麦克风音量")
        return false
    end
    
    if check_param(record_volume, "number", "麦克风音量值") then
        return audio.micVol(MULTIMEDIA_ID, record_volume)  
    end
    return false
end

-- 获取当前声道数
function exaudio.get_channels()
    return audio_setup_param.channels
end

-- 写入最后一块数据后，通知多媒体通道已经没有更多数据需要播放了
-- audio_v2模式下，此函数用于标记流式播放结束
-- @param data 最后一帧数据(可选,audio_v2流式播放)
-- @return 是否成功
function exaudio.finish(data)
    if audio_setup_param.model == "air1103" then
        if not air1103 then return false end
        if data then
            air1103.play_stream_write(data)
        end
        if air1103_playing then
            air1103_mark_end()
        end
        return true
    end
    if USE_AUDIO_V2 then
        -- audio_v2流式播放结束
        if audio_v2_request_index then
            -- 如果有文件句柄，由回调自动处理结束，这里不干预
            if audio_v2_stream_file_fp then
                log.info("exaudio", "文件流模式，等待回调自动处理结束")
                return true
            end
            
            -- 队列模式：入队列后标记结束，由NEED_NEW_DATA回调在队列清空后发结束信号
            if data then
                audio_stream_queue_push(data)
            end
            audio_v2_stream_end_marked = true
            return true
        end
        return false
    end
    
    if audio.finish then
        return audio.finish(MULTIMEDIA_ID)
    end
    return false
end

-- 休眠控制
-- @param pm_mode 休眠模式: exaudio.SHUTDOWN/exaudio.RESUME
-- @return 是否成功
-- @usage
-- exaudio.pm(exaudio.SHUTDOWN)
-- exaudio.pm(exaudio.RESUME)
function exaudio.pm(pm_mode)
    -- air1103无需通过音频休眠控制
    if audio_setup_param.model == "air1103" then
        return true
    end

    if USE_AUDIO_V2 then
        -- 新框架：使用audio_v2.shutdown + es8311操作进入休眠
        if not audio_v2 then
            log.error("exaudio.pm", "audio_v2模块未加载")
            return false
        end
        -- 仅ES8311模式下才操作es8311驱动（DAC/TM8211模式无ES8311芯片，i2c不存在）
        local es8311_ok, es8311_drv = false, nil
        if audio_setup_param.model == "es8311" then
            es8311_ok, es8311_drv = pcall(require, "es8311")
        end
        if pm_mode == exaudio.SHUTDOWN then
            -- 1602开发板I2C1同时被audio(ES8311)与LCD触摸共用：
            -- audio_v2.shutdown(driver_power_off, codec_power_off, pa_power_off) 的
            -- driver_power_off=true 会停驱动并 deactivate，副作用是关闭其管理的 I2C1，导致 LCD 触摸失效。
            -- 故 1602 下电时保留 audio 驱动(driver_power_off=false)，I2C 保持打开供触摸使用；
            -- 非 1602 保持原逻辑彻底下电(driver_power_off=true)。
            if get_module_type() == "air1602" then
                audio_v2.shutdown(false, false, true)
            else
                -- SHUTDOWN：下电ES8311，关闭PA，保持驱动和CODEC以备快速恢复
                if es8311_ok and es8311_drv then
                    es8311_drv.power_down(audio_setup_param.i2c_id or 0)
                end

                audio_v2.shutdown(true, false, true)
            end
            return true
        elseif pm_mode == exaudio.RESUME then
            -- RESUME：恢复ES8311，确保所有模块处于工作状态
            if es8311_ok and es8311_drv then
                -- codec_voltage=0时按1.8V电平初始化(0x01)，否则默认3.3V(0x00)
                local voltage = audio_setup_param.codec_voltage == 0 and 0x01 or 0x00
                es8311_drv.init(audio_setup_param.i2c_id or 0, voltage)
                es8311_drv.resume(audio_setup_param.i2c_id or 0)
                es8311_drv.set_mute(audio_setup_param.i2c_id or 0, false)
                es8311_drv.set_voice_vol(audio_setup_param.i2c_id or 0, voice_vol)
                es8311_drv.set_mic_vol(audio_setup_param.i2c_id or 0, mic_vol)
            elseif audio_setup_param.model == "dac" and MODULE_TYPE == "air8101" then
                -- Air8101唤醒后重新应用麦克风增益
                apply_dac_mic_gain()
            end
            -- 恢复外部 PA。
            if audio_setup_param.pa_ctrl and audio_setup_param.pa_ctrl > 0 then
                gpio.setup(audio_setup_param.pa_ctrl, audio_setup_param.pa_on_level)
            end
            audio_v2.shutdown(false, false, false)
            return true
        end
        log.warn("exaudio.pm", "不支持的模式:", pm_mode)
        return false
    end

    -- 旧框架：直接调用audio.pm（pm_mode为数值宏，与audio.RESUME/audio.SHUTDOWN一致）
    if audio and audio.pm then
        return audio.pm(MULTIMEDIA_ID, pm_mode)
    end
    return false
end

-- 获取当前使用的音频模式
function exaudio.get_audio_mode()
    return USE_AUDIO_V2 and "audio_v2" or "audio"
end

-- 合成音频驱动ID（仅audio_v2模式支持）
-- 用于在不使用默认驱动时，指定driver_probe_id参数
-- @api exaudio.make_probe_id(tx_bus_type, tx_bus_id, rx_bus_type, rx_bus_id)
-- @int tx_bus_type 发送总线类型，见audio_v2.DRIVER_TYPE_xxx常量(DRIVER_TYPE_NONE/I2S/DAC/ADC/USB)
-- @int tx_bus_id 发送总线id
-- @int rx_bus_type 接收总线类型，见audio_v2.DRIVER_TYPE_xxx常量
-- @int rx_bus_id 接收总线id
-- @return int 驱动ID，传入其他audio_v2函数的driver_probe_id参数；audio模式下返回nil
-- @usage
-- -- I2S0双工驱动（可同时播放和录音）
-- local pid = exaudio.make_probe_id(audio_v2.DRIVER_TYPE_I2S, 0, audio_v2.DRIVER_TYPE_I2S, 0)
-- -- DAC0单工驱动（仅播放）
-- local pid = exaudio.make_probe_id(audio_v2.DRIVER_TYPE_DAC, 0, audio_v2.DRIVER_TYPE_NONE, 0)
-- -- 使用合成的驱动ID进行下电操作
-- exaudio.shutdown(true, true, true, pid)
function exaudio.make_probe_id(tx_bus_type, tx_bus_id, rx_bus_type, rx_bus_id)
    if not USE_AUDIO_V2 then
        log.warn("exaudio.make_probe_id", "仅新音频框架支持")
        return nil
    end

    if not audio_v2 then
        log.error("exaudio.make_probe_id", "新音频框架未加载")
        return nil
    end

    return audio_v2.make_probe_id(tx_bus_type, tx_bus_id, rx_bus_type, rx_bus_id)
end

-- ==================== 流式播放辅助函数（仅audio_v2模式支持） ====================

--[[
@description 从音频文件或缓冲数据解析播放信息（采样率、位宽、声道数等）
@api exaudio.parse_audio_info(input, codec_id[, pos])
@string/zbuff input 音频文件路径（string）或二进制数据（string/zbuff）
@number codec_id 编解码器ID (0=PCM, 1=WAV, 2=AMR_NB, 3=AMR_WB, 5=MP3)
@number pos 可选，数据偏移位置（字节），仅传入二进制数据时有效，默认0
@return table 成功返回包含音频信息的table，失败返回nil
@usage
-- 方式1：传入文件路径
local info = exaudio.parse_audio_info("/luadb/test.mp3", 5)
if info then
    log.info("采样率:", info.sample_rate)
    log.info("位宽:", info.data_bits)
    log.info("声道数:", info.channel_nums)
end

-- 方式2：传入缓冲数据
local info = exaudio.parse_audio_info(buff_data, 5)
if info then
    log.info("采样率:", info.sample_rate)
end
注意：此函数仅在audio_v2模式下可用
]]
function exaudio.parse_audio_info(input, codec_id, pos)
    if not input then
        log.error("parse_audio_info: input must not be nil")
        return nil
    end
    
    if not codec_id or type(codec_id) ~= "number" then
        log.error("parse_audio_info: codec_id must be number")
        return nil
    end
    
    -- PCM格式是原始音频数据，没有文件头，直接返回默认值
    if codec_id == 0 then
        log.info("parse_audio_info: PCM format, use default values")
        return {sample_rate = 16000, data_bits = 16, channel_nums = 1, is_signed = true, data_start = 0}
    end
    
    local file_data
    local need_close_fp = false
    local fp
    
    -- 判断传入的是文件路径还是缓冲数据
    if type(input) == "string" then
        -- 尝试打开文件
        fp = io.open(input, "rb")
        if fp then
            need_close_fp = true
            -- 先读取12字节进行初始解析
            file_data = fp:read(12)
            if not file_data or #file_data == 0 then
                log.error("parse_audio_info: file read failed", input)
                fp:close()
                return nil
            end
        else
            -- 不是文件路径，当作二进制数据直接使用
            file_data = input
        end
    else
        -- zbuff或其他类型，直接作为数据使用
        file_data = input
    end
    
    local start_pos = pos or 0
    
    -- 使用audio_v2.get_play_info解析文件头
    local no_error, next_pos, need_len, sample_rate, data_bits, channel_nums, is_signed = 
        audio_v2.get_play_info(file_data, codec_id, start_pos)
    
    log.info("parse_audio_info", "get_play_info result:", no_error, "sample_rate:", sample_rate, "next_pos:", next_pos, "need_len:", need_len)
    
    if no_error then
        if sample_rate and sample_rate > 0 then
            -- 解析成功
            if need_close_fp then
                log.info("exaudio.parse_audio_info", input, "sample_rate:", sample_rate, 
                         "bits:", data_bits, "channels:", channel_nums)
                fp:close()
            end
            return {
                sample_rate = sample_rate,
                data_bits = data_bits or 16,
                channel_nums = channel_nums or 1,
                is_signed = (is_signed ~= false),
                data_start = next_pos
            }
        else
            -- sample_rate为0或nil，需要读取更多数据重试
            if need_close_fp then
                -- 文件模式：从文件继续读取
                log.info("parse_audio_info", "sample_rate is", sample_rate, "need retry")
                local retry_count = 0
                while retry_count < 6 and no_error and (not sample_rate or sample_rate == 0) do
                    log.info("parse_audio_info", "seek", next_pos, "need", need_len)
                    fp:seek("set", next_pos)
                    file_data = fp:read(need_len)
                    if file_data then
                        log.info("parse_audio_info", "read", #file_data)
                        no_error, next_pos, need_len, sample_rate, data_bits, channel_nums, is_signed = 
                            audio_v2.get_play_info(file_data, codec_id, next_pos)
                        retry_count = retry_count + 1
                    else
                        break
                    end
                end
                
                if no_error and sample_rate and sample_rate > 0 then
                    log.info("exaudio.parse_audio_info", input, "sample_rate:", sample_rate, 
                             "bits:", data_bits, "channels:", channel_nums, "retries:", retry_count)
                    fp:close()
                    return {
                        sample_rate = sample_rate,
                        data_bits = data_bits or 16,
                        channel_nums = channel_nums or 1,
                        is_signed = is_signed ~= false,
                        data_start = next_pos
                    }
                else
                    log.warn("parse_audio_info: retry failed", input, "retries:", retry_count)
                end
            else
                -- 缓冲数据模式：返回当前解析结果，由调用方自行重试
                log.info("parse_audio_info", "buffer mode, sample_rate is", sample_rate, "need more data, next_pos:", next_pos, "need_len:", need_len)
                return {
                    sample_rate = sample_rate or 0,
                    data_bits = data_bits or 16,
                    channel_nums = channel_nums or 1,
                    is_signed = (is_signed ~= false),
                    data_start = next_pos,
                    need_len = need_len
                }
            end
        end
    else
        log.warn("parse_audio_info: get_play_info error", input)
    end
    
    if need_close_fp then
        fp:close()
    end
    return nil
end

--[[
获取库版本信息
@return string 年月日时分，例如： "202606300102"
@usage
exaudio.version()
]]
function exaudio.version()
    return "202609201726"
end

log.debug("exaudio", "version -> " .. exaudio.version())

return exaudio
