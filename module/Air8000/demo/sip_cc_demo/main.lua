--[[
@module  main
@summary Air8000 SIP-CC 桥接 Demo
@version 1.0
@date    2026.07.20
@author  蒋骞
@description
SIP 功能封装在 sip_main.lua，CC 功能封装在 cc_main.lua，bridge.lua 负责桥接协调。
main.lua 只加载 sip_main 和 cc_main（bridge 由 sip_main 自动引入）。

烧录前请在 config.lua 中修改 SIP 账号、密码、目标手机号、远程 SIP URI。
]]

PROJECT = "SIP_CC_DEMO"
VERSION = "1.0.0"
PRODUCT_KEY = "SIP_CC_DEMO"

-- LuatOS 基础库
require "sys"
require "sysplus"

log.info("main", PROJECT, VERSION)

-- 网络与音频
require "netdrv_device"
local audio_drv = require "audio_drv"

-- 核心模块：sip_main 会自动加载 bridge.lua
local sip_main = require "sip_main"
local cc_main = require "cc_main"

-- ==================== 启动任务 ====================

local function on_heartbeat()
    log.info(PROJECT, "心跳",
        "SIP=" .. sip_main.get_state(),
        "CC=" .. cc_main.get_state(),
        "SIP注册=" .. (sip_main.is_registered() and "Y" or "N"),
        "CC就绪=" .. (cc_main.is_ready() and "Y" or "N")
    )
end

local function main_task()
    -- 等待网络就绪
    while not socket or not socket.dft or not socket.adapter(socket.dft()) do
        log.warn("main", "等待 IP_READY ...")
        sys.waitUntil("IP_READY", 1000)
    end
    log.info("main", "网络已就绪", "adapter=" .. socket.dft())

    log.info(PROJECT, string.rep("=", 50))
    log.info(PROJECT, "Air8000 SIP-CC 桥接 Demo 启动中...")
    log.info(PROJECT, string.rep("=", 50))

    -- 初始化音频
    if audio_drv and audio_drv.init then
        local audio_ok = audio_drv.init()
        if audio_ok then
            log.info(PROJECT, "音频初始化成功")
        else
            log.warn(PROJECT, "音频初始化失败或跳过")
        end
    end

    -- 初始化 SIP 和 CC
    local sip_ok = sip_main.init()
    if not sip_ok then
        log.error(PROJECT, "SIP 初始化失败")
    end

    local cc_ok = cc_main.init()
    if not cc_ok then
        log.error(PROJECT, "CC 初始化失败")
    end

    log.info(PROJECT, "Demo 初始化流程完成")
    log.info(PROJECT, string.rep("=", 50))

    -- 10 秒心跳
    sys.timerLoopStart(on_heartbeat, 10000)
end

sys.taskInit(main_task)

-- 监听系统网络事件

local function on_ip_ready(ip, adapter)
    log.info(PROJECT, "网络已就绪", "adapter=" .. (adapter or "?"), "ip=" .. (ip or "?"))
end

local function on_ip_lose(adapter)
    log.warn(PROJECT, "网络已断开", "adapter=" .. (adapter or "?"))
end

sys.subscribe("IP_READY", on_ip_ready)
sys.subscribe("IP_LOSE", on_ip_lose)

-- ==================== 程序入口 ====================
sys.run()
-- sys.run() 之后不要添加任何语句
