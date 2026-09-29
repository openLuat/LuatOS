--[[
@module  app_main
@summary Air8784 出厂固件业务模式编排（产测完成后的正常模式）
@version 1.0
@date    2026.09.27
@author  王世豪
@usage
本文件为业务模式编排模块，核心业务逻辑为：
1、加载网络驱动（4G），等待 IP_READY；
2、加载 SIP 业务（sip_app_main）：内部自行完成音频初始化、SIP 注册与通话状态机；
3、加载按键（key_app）：SOS 呼出、UP 短按接听 / 长按挂断；
4、网络灯（GPIO27）跟随联网状态；
5、10 秒心跳打印 SIP 状态与音频就绪状态，便于客户与售后观察设备是否可用；

产测模式不加载本模块（main.lua 按 fskv test_done 分流），产线半成品不会注册 SIP、不产生流量。

本文件没有对外接口，在 main.lua 中 require "app_main" 即可加载运行；
]]

local config = require "config"
local TAG = config.log_tag
local audio_drv = require "audio_drv"

-- ==================== 网络驱动 ====================
require "netdrv_device"

-- ==================== SIP 与按键业务 ====================
require "sip_app_main"
require "key_app"
-- 留言播放：订阅 MSG_PLAY_REQ（UP 短按）与 SIP_APP_STATE（空闲判断 / 来电打断）。
-- config.message.enabled = false 时完全不加载（留言整体停用，UP 短按也就没有动作）。
if config.message and config.message.enabled then
    require "msg_player"
end
-- 注：AirCloud 上报与云端下行（aircloud_data）由 main.lua 统一加载，
-- 这样 SIP 与 CC 两种业务模式都能上报，不必各写一份

-- ==================== 状态灯与心跳 ====================
local leds = config.leds

local function on_ip_ready(ip, adapter)
    if adapter == config.adapter then
        log.info(TAG, "IP_READY", ip)
        gpio.setup(leds.net_pin, 1)
    end
end

local function on_ip_lose(adapter)
    if adapter == config.adapter then
        log.warn(TAG, "IP_LOSE")
        gpio.setup(leds.net_pin, 0)
    end
end

sys.subscribe("IP_READY", on_ip_ready)
sys.subscribe("IP_LOSE", on_ip_lose)

-- 通话中点亮主灯，空闲熄灭（客户可据此判断设备在通话）
local sip_state = "INIT"
sys.subscribe("SIP_APP_STATE", function(state)
    sip_state = state
    log.info(TAG, "SIP 状态", state)
    if state == "CONNECTED" or state == "DIALING" or state == "ANSWERING" or state == "INCOMING" then
        gpio.setup(leds.main_pin, 1)
    else
        gpio.setup(leds.main_pin, 0)
    end
end)

sys.taskInit(function()
    sys.waitUntil("IP_READY", 15000)
    log.info(TAG, "业务模式启动完成")
    log.info(TAG, "本机 SIP 账号", config.sip.sip_username)
    log.info(TAG, "SOS 键默认呼叫", config.dial_number)
    while true do
        log.info(TAG, "心跳", "SIP状态=", sip_state, "音频就绪=", audio_drv.is_ready())
        sys.wait(10000)
    end
end)
