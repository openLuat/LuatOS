--[[
@module  app_main
@summary 8784 + Air1103 的 SIP<->VoLTE(CC) 桥接启动流程
@version 1.0
@date    2026.09.23
@author  蒋骞
@usage
本文件为项目启动流程模块，核心业务逻辑为：
1、等待网络就绪(最长 10 秒)，打印当前默认网卡和启动信息；
2、调用 audio_drv.init() 初始化音频设备(Air1103 模式，拉起 audio_v2 新框架)；
3、调用 sip_main.init() 初始化 SIP，必须在 CC/SIP 音频启动前完成
   (exsip.init 里 cc_sip_bridge = true 会同步选择 CC 桥接路由)；
4、调用 cc_main.init() 初始化 VoLTE(cc.init(0))；
5、启动 10 秒循环心跳，打印 SIP/CC 两侧状态和注册情况；

SIP<->CC 的音频桥接由固件完成(cc_sip_bridge)，Lua 只负责两侧通话的状态联动；
本文件没有对外接口，直接在其他功能模块中require "app_main"就可以加载运行；
]]

local audio_drv = require "audio_drv"
local sip_main = require "sip_main"
local cc_main = require "cc_main"
local config = require "config"

local PROJECT = "AIR8784_1103_SIP_CC"

-- 心跳: 打印 SIP/CC 两侧状态, 便于观察长时间运行
local function on_heartbeat()
    log.info(PROJECT, "心跳",
        "SIP=" .. sip_main.get_state(),
        "CC=" .. cc_main.get_state(),
        "SIP注册=" .. (sip_main.is_registered() and "Y" or "N"),
        "CC就绪=" .. (cc_main.is_ready() and "Y" or "N"))
end

local function app_main_task()
    -- 1. 等待网络就绪
    sys.waitUntil("IP_READY", 10000)
    log.info(PROJECT, "网络等待结束", "adapter=" .. tostring(socket.dft()))

    log.info(PROJECT, string.rep("=", 50))
    log.info(PROJECT, "8784 + Air1103 SIP-CC 桥接 Demo 启动中...")
    log.info(PROJECT, string.rep("=", 50))

    -- 2. 初始化音频设备(Air1103 模式)
    if not audio_drv.init() then
        log.error(PROJECT, "音频初始化失败, 继续尝试启动 SIP/CC")
    end

    -- 3. 初始化 SIP(必须在 CC/SIP 音频启动前完成 cc_sip_bridge 配置)
    if not sip_main.init() then
        log.error(PROJECT, "SIP 初始化失败")
    end

    -- 4. 初始化 CC(VoLTE)
    if not cc_main.init() then
        log.error(PROJECT, "CC 初始化失败")
    end

    log.info(PROJECT, "SIP 呼入将拨打手机号:", tostring(config.target_phone_number))
    log.info(PROJECT, "手机呼入将呼叫 SIP:", tostring(config.remote_sip_uri))
    log.info(PROJECT, "Demo 初始化流程完成")
    log.info(PROJECT, string.rep("=", 50))

    -- 5. 10 秒心跳
    sys.timerLoopStart(on_heartbeat, 10000)
end

sys.taskInit(app_main_task)
